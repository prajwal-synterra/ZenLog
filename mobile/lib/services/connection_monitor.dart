import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';


enum ConnectionStateEnum {
  unknown,
  connected,
  disconnected,
  authRequired,
}

enum ReasonCode {
  noNetwork,
  timeout,
  unreachable,
  sslError,
  serverError,
  serverRestarting,
  dbDown,
  rateLimited,
  authExpired,
  unknown,
}

class ConnectionSnapshot {
  final ConnectionStateEnum state;
  final ReasonCode? reason;
  final int? httpStatus;
  final String message;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;
  final int? clockSkewMin;

  const ConnectionSnapshot({
    required this.state,
    this.reason,
    this.httpStatus,
    this.message = 'Checking connection…',
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.clockSkewMin,
  });

  String get debugString {
    final codeStr = reason?.name.toUpperCase() ?? 'NONE';
    final statusStr = httpStatus != null ? '$httpStatus' : 'NO_HTTP';
    final timeStr = DateTime.now().toIso8601String();
    return '$codeStr · $statusStr · $timeStr';
  }
}

/// Connection Monitor implementing Section 6 of ZenLog Offline-First Spec.
class ConnectionMonitor {
  static final ConnectionMonitor _instance = ConnectionMonitor._internal();
  factory ConnectionMonitor() => _instance;
  ConnectionMonitor._internal();

  ConnectionSnapshot _current = const ConnectionSnapshot(state: ConnectionStateEnum.unknown);
  ConnectionSnapshot get current => _current;

  final _streamController = StreamController<ConnectionSnapshot>.broadcast();
  Stream<ConnectionSnapshot> get stream => _streamController.stream;

  Timer? _probeTimer;
  int _consecutiveFailures = 0;
  DateTime? _firstFailureTime;
  int _probeIntervalSec = 15;
  bool _isProbing = false;

  /// Called when the connection transitions from disconnected/unknown → connected.
  /// ZenState subscribes to this to trigger runSync('connectivity') automatically.
  VoidCallback? onConnectivityRegained;

  void init() {
    probeNow();
  }

  void _emit(ConnectionSnapshot snapshot) {
    _current = snapshot;
    _streamController.add(snapshot);
  }

  // ─── Classification (Section 6.3) ──────────────────────────────────────────

  ({ReasonCode code, String message, bool retryable, bool connectivity}) classify({
    dynamic error,
    http.Response? response,
    Map<String, dynamic>? healthBody,
  }) {
    // 1. SocketException / DNS / Offline
    if (error is SocketException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('failed host lookup') || msg.contains('network is unreachable')) {
        return (
          code: ReasonCode.noNetwork,
          message: 'No internet connection.',
          retryable: true,
          connectivity: true,
        );
      }
      return (
        code: ReasonCode.unreachable,
        message: "Can't reach the server.",
        retryable: true,
        connectivity: true,
      );
    }

    // 2. Timeout
    if (error is TimeoutException) {
      return (
        code: ReasonCode.timeout,
        message: 'Server took too long to respond.',
        retryable: true,
        connectivity: true,
      );
    }

    // 3. Handshake / TLS / SSL
    if (error is HandshakeException || error.toString().toLowerCase().contains('ssl')) {
      return (
        code: ReasonCode.sslError,
        message: 'Secure connection failed.',
        retryable: true,
        connectivity: true,
      );
    }

    // 4. HTTP Responses
    if (response != null) {
      final status = response.statusCode;

      // 401 Session Expired (check JSON header/body)
      if (status == 401) {
        final contentType = response.headers['content-type'] ?? '';
        final isJson = contentType.contains('application/json');
        if (isJson) {
          return (
            code: ReasonCode.authExpired,
            message: 'Session ended. Log in again.',
            retryable: false,
            connectivity: false,
          );
        }
        // Captive portal 401 HTML
        return (
          code: ReasonCode.unreachable,
          message: "Can't reach the server.",
          retryable: true,
          connectivity: true,
        );
      }

      // Database down check
      if (healthBody != null && healthBody['database'] != 'connected') {
        return (
          code: ReasonCode.dbDown,
          message: 'Server is up, but its database is down.',
          retryable: true,
          connectivity: true,
        );
      }

      if (status == 429) {
        return (
          code: ReasonCode.rateLimited,
          message: 'Too many requests. Waiting a moment.',
          retryable: true,
          connectivity: true,
        );
      }

      if (status == 502 || status == 503 || status == 504) {
        return (
          code: ReasonCode.serverRestarting,
          message: 'Server is restarting ($status).',
          retryable: true,
          connectivity: true,
        );
      }

      if (status >= 500) {
        return (
          code: ReasonCode.serverError,
          message: 'Server error ($status).',
          retryable: true,
          connectivity: true,
        );
      }

      // 4xx Validation errors are NOT connectivity failures!
      if (status >= 400) {
        return (
          code: ReasonCode.unknown,
          message: 'Request rejected ($status).',
          retryable: false,
          connectivity: false,
        );
      }
    }

    return (
      code: ReasonCode.unknown,
      message: 'Unexpected error.',
      retryable: true,
      connectivity: true,
    );
  }

  // ─── Reporting outcomes from API client ────────────────────────────────────

  void reportSuccess({DateTime? serverTime}) {
    final wasDisconnected = _current.state == ConnectionStateEnum.disconnected ||
        _current.state == ConnectionStateEnum.unknown;

    _consecutiveFailures = 0;
    _firstFailureTime = null;
    _probeIntervalSec = 15;
    _stopProbeTimer();

    int? skewMin;
    if (serverTime != null) {
      final diff = DateTime.now().toUtc().difference(serverTime).inMinutes.abs();
      if (diff >= 5) skewMin = diff;
    }

    _emit(ConnectionSnapshot(
      state: ConnectionStateEnum.connected,
      message: 'Connected to server',
      lastSuccessAt: DateTime.now(),
      lastAttemptAt: DateTime.now(),
      clockSkewMin: skewMin,
    ));

    // §7.8 — trigger sync when connection regains
    if (wasDisconnected) {
      onConnectivityRegained?.call();
    }
  }

  void reportFailure({dynamic error, http.Response? response}) {
    final c = classify(error: error, response: response);

    if (c.code == ReasonCode.authExpired) {
      _emit(ConnectionSnapshot(
        state: ConnectionStateEnum.authRequired,
        reason: c.code,
        httpStatus: response?.statusCode,
        message: c.message,
        lastAttemptAt: DateTime.now(),
      ));
      return;
    }

    // If it's a 4xx validation rejection, do NOT mark disconnected!
    if (!c.connectivity) {
      return;
    }

    final now = DateTime.now();
    _consecutiveFailures++;
    _firstFailureTime ??= now;

    // Two consecutive failures within 30s -> mark DISCONNECTED immediately
    if (_consecutiveFailures >= 2 && now.difference(_firstFailureTime!).inSeconds <= 30) {
      _setDisconnected(c.code, c.message, response?.statusCode);
    } else {
      // Confirm with a /health probe
      _probeHealth();
    }
  }

  void _setDisconnected(ReasonCode code, String message, int? status) {
    _emit(ConnectionSnapshot(
      state: ConnectionStateEnum.disconnected,
      reason: code,
      httpStatus: status,
      message: message,
      lastAttemptAt: DateTime.now(),
      lastSuccessAt: _current.lastSuccessAt,
      clockSkewMin: _current.clockSkewMin,
    ));

    _scheduleNextProbe();
  }

  // ─── Probing (Section 6.2) ────────────────────────────────────────────────

  Future<void> probeNow() async {
    await _probeHealth();
  }

  Future<void> _probeHealth() async {
    if (_isProbing) return;
    _isProbing = true;

    try {
      final res = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/health'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      ).timeout(const Duration(seconds: 5));

      DateTime? sTime;
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>?;
        if (body?['server_time'] != null) {
          sTime = DateTime.tryParse(body!['server_time'] as String);
        }
      } catch (_) {}

      if (res.statusCode == 200 && body?['database'] == 'connected') {
        reportSuccess(serverTime: sTime);
      } else {
        final c = classify(response: res, healthBody: body);
        _setDisconnected(c.code, c.message, res.statusCode);
      }
    } catch (e) {
      final c = classify(error: e);
      _setDisconnected(c.code, c.message, null);
    } finally {
      _isProbing = false;
    }
  }

  void _scheduleNextProbe() {
    _stopProbeTimer();
    _probeTimer = Timer(Duration(seconds: _probeIntervalSec), () async {
      await _probeHealth();
      // Backoff up to 2 minutes
      if (_current.state == ConnectionStateEnum.disconnected) {
        _probeIntervalSec = (_probeIntervalSec * 1.5).round().clamp(15, 120);
        _scheduleNextProbe();
      }
    });
  }

  void _stopProbeTimer() {
    _probeTimer?.cancel();
    _probeTimer = null;
  }
}
