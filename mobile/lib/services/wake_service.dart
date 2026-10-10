import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';
import 'connection_monitor.dart';

enum WakeStatus {
  idle,
  waking,
  awake,
  unreachable,
}

/// Module 1: WakeService handles Render server cold-start detection,
/// pinging /ping with retry, dynamic request timeouts, and queue safety.
class WakeService extends ChangeNotifier {
  static final WakeService _instance = WakeService._internal();
  factory WakeService() => _instance;
  WakeService._internal();

  WakeStatus _status = WakeStatus.idle;
  WakeStatus get status => _status;

  bool get isWaking => _status == WakeStatus.waking;
  bool get isAwake => _status == WakeStatus.awake;
  bool get isUnreachable => _status == WakeStatus.unreachable;

  DateTime? _lastAwakeAt;
  DateTime? get lastAwakeAt => _lastAwakeAt;

  /// True if a successful server response occurred in the last 12 minutes (Render idle cutoff is 15m)
  bool get isWarm =>
      _lastAwakeAt != null &&
      DateTime.now().difference(_lastAwakeAt!).inMinutes < 12;

  /// Dynamic timeout: 65s on first request after idle/cold, 15s when warm
  Duration get dynamicTimeout =>
      isWarm ? const Duration(seconds: 15) : const Duration(seconds: 65);

  bool _isAttemptingWake = false;
  Future<bool>? _currentWakeFuture;

  /// Triggered on app launch and on AppLifecycleState.resumed
  Future<bool> wakeAndProbe({bool forceColdCheck = false}) {
    if (_isAttemptingWake && _currentWakeFuture != null) {
      return _currentWakeFuture!;
    }
    _currentWakeFuture = _performWake(forceColdCheck: forceColdCheck);
    return _currentWakeFuture!;
  }

  Future<bool> _performWake({bool forceColdCheck = false}) async {
    _isAttemptingWake = true;

    // If warm and not forcing cold check, verify quickly with a 5s check
    if (isWarm && !forceColdCheck) {
      final quickOk = await _quickPing(timeout: const Duration(seconds: 5));
      if (quickOk) {
        _status = WakeStatus.awake;
        _lastAwakeAt = DateTime.now();
        _isAttemptingWake = false;
        notifyListeners();
        return true;
      }
    }

    // Server is cold or quick ping failed: enter waking state
    _status = WakeStatus.waking;
    notifyListeners();

    // Up to 6 attempts with 5s spacing (covers 30-60s Render cold-start)
    const maxAttempts = 6;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final ok = await _quickPing(
        timeout: attempt == 1
            ? const Duration(seconds: 12)
            : const Duration(seconds: 8),
      );

      if (ok) {
        _status = WakeStatus.awake;
        _lastAwakeAt = DateTime.now();
        _isAttemptingWake = false;
        notifyListeners();
        ConnectionMonitor().reportSuccess();
        return true;
      }

      if (attempt < maxAttempts) {
        await Future.delayed(const Duration(seconds: 5));
      }
    }

    // All attempts exhausted
    _status = WakeStatus.unreachable;
    _isAttemptingWake = false;
    notifyListeners();
    return false;
  }

  Future<bool> _quickPing({required Duration timeout}) async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}/ping'),
            headers: {'ngrok-skip-browser-warning': 'true'},
          )
          .timeout(timeout);

      if (res.statusCode == 200) {
        try {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          if (data['ok'] == true) return true;
        } catch (_) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Mark server warm whenever any API call succeeds
  void markServerWarm({DateTime? serverTime}) {
    _lastAwakeAt = DateTime.now();
    if (_status != WakeStatus.awake) {
      _status = WakeStatus.awake;
      notifyListeners();
    }
  }

  String get timeSinceLastPingFormatted {
    if (_lastAwakeAt == null) return 'Never';
    final diff = DateTime.now().difference(_lastAwakeAt!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
