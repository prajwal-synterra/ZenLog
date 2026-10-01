import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'connection_monitor.dart';
import 'offline_storage.dart';

/// Single-flight mutex for sync operations
class SingleFlightMutex {
  bool _isLocked = false;
  bool get isLocked => _isLocked;

  bool tryAcquire() {
    if (_isLocked) return false;
    _isLocked = true;
    return true;
  }

  void release() {
    _isLocked = false;
  }
}

/// Sync Engine implementing Section 7 of ZenLog Offline-First Spec.
class SyncEngine extends ChangeNotifier {
  static final SyncEngine _instance = SyncEngine._internal();
  factory SyncEngine() => _instance;
  SyncEngine._internal();

  final SingleFlightMutex _mutex = SingleFlightMutex();
  final OfflineStorage _storage = OfflineStorage();
  final ApiService _api = ApiService();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  int _queuedCount = 0;
  int get queuedCount => _queuedCount;

  Timer? _scheduledTimer;
  String? _currentUserId;

  VoidCallback? onPostSyncRefresh;

  void setUserId(String? userId) {
    _currentUserId = userId;
    refreshQueuedCount();
  }

  Future<void> refreshQueuedCount() async {
    if (_currentUserId == null) {
      _queuedCount = 0;
    } else {
      _queuedCount = await _storage.getQueuedCount(_currentUserId!);
    }
    notifyListeners();
  }

  // ─── Exponential Backoff with Jitter (Section 7.7) ─────────────────────────

  Duration calculateBackoff(int attempts) {
    // 2s * 2^(attempts-1) capped at 5 minutes ± 20% jitter
    final baseSeconds = min(300, (2 * pow(2, attempts - 1)).toInt());
    final jitterFactor = 0.8 + (Random().nextDouble() * 0.4); // 0.8 - 1.2
    final jitteredSeconds = (baseSeconds * jitterFactor).round().clamp(2, 300);
    return Duration(seconds: jitteredSeconds);
  }

  // ─── Run Sync (Section 7.6) ────────────────────────────────────────────────

  Future<void> runSync(String trigger) async {
    final userId = _currentUserId;
    if (userId == null) return;
    if (!_mutex.tryAcquire()) return;

    final hasLock = await _storage.tryAcquireLock('sync_lock_$userId', const Duration(seconds: 60));
    if (!hasLock) {
      _mutex.release();
      return;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final monitor = ConnectionMonitor().current;
      if (monitor.state == ConnectionStateEnum.authRequired) {
        return;
      }
      if (monitor.state == ConnectionStateEnum.disconnected &&
          trigger != 'manual' &&
          trigger != 'connectivity') {
        return;
      }

      int syncedInThisRun = 0;

      while (true) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final op = await _storage.getNextRunnableOp(userId, now);
        if (op == null) break;

        final opId = op['op_id'] as String;
        final opType = op['type'] as String;
        final entityKey = op['entity_key'] as String?;
        final attempts = (op['attempts'] as int?) ?? 0;
        final payload = jsonDecode(op['payload'] as String) as Map<String, dynamic>;

        await _storage.setOpStatus(opId, 'sending');
        if (entityKey != null) {
          await _storage.markLogSyncing(entityKey);
        }

        final result = await _executeOp(opType, entityKey, payload);

        if (result.ok) {
          syncedInThisRun++;
          await _storage.removeOp(opId);
          if (opType == 'CREATE_LOG' && entityKey != null) {
            final serverId = result.serverId ?? opId;
            final serverDate = result.serverDate ?? DateTime.now().toIso8601String().substring(0, 10);
            await _storage.markLogSynced(
              clientId: entityKey,
              serverId: serverId,
              serverDate: serverDate,
            );
          } else if (opType == 'DELETE_LOG' && entityKey != null) {
            await _storage.deleteLocalLog(entityKey);
          }
          await refreshQueuedCount();
          continue;
        }

        // Handle failure classification (§7.6 & §7.9)
        final c = ConnectionMonitor().classify(
          error: result.error,
          response: result.response,
        );

        if (c.code == ReasonCode.authExpired) {
          await _storage.setOpStatus(opId, 'queued');
          break; // Stop, preserve queue
        }

        if (c.retryable) {
          final nextDelay = calculateBackoff(attempts + 1);
          final nextAttemptAt = DateTime.now().add(nextDelay).millisecondsSinceEpoch;
          await _storage.scheduleRetry(
            opId,
            nextAttemptAt,
            attempts + 1,
            code: c.code.name,
            msg: c.message,
          );
          _scheduleRetryTimer(nextDelay);
          break; // Stop sync run, preserve order
        } else {
          // Permanent failure (4xx / 422)
          final reasonMsg = result.errorMsg ?? c.message;
          await _storage.failPermanent(opId, code: c.code.name, msg: reasonMsg);
          if (entityKey != null) {
            await _storage.markLogFailed(clientId: entityKey, reason: reasonMsg);
          }
          await refreshQueuedCount();
          // Skip this op, continue with the rest of the queue
          continue;
        }
      }

      await refreshQueuedCount();

      if (_queuedCount == 0 && syncedInThisRun > 0) {
        onPostSyncRefresh?.call();
      }
    } finally {
      await _storage.releaseLock('sync_lock_$userId');
      _isSyncing = false;
      _mutex.release();
      notifyListeners();
    }
  }

  Future<({bool ok, dynamic error, dynamic response, String? serverId, String? serverDate, String? errorMsg})>
      _executeOp(String type, String? entityKey, Map<String, dynamic> payload) async {
    try {
      if (type == 'CREATE_LOG') {
        final text = payload['text'] as String;
        final clientId = payload['client_id'] as String?;
        final tsStr = payload['timestamp'] as String?;
        final ts = tsStr != null ? DateTime.tryParse(tsStr) : null;

        final res = await _api.createLogWithDetails(
          text,
          clientId: clientId,
          timestamp: ts,
        );

        if (res.ok) {
          return (
            ok: true,
            error: null,
            response: null,
            serverId: res.model?.id,
            serverDate: res.model?.date,
            errorMsg: null,
          );
        } else {
          return (
            ok: false,
            error: null,
            response: null,
            serverId: null,
            serverDate: null,
            errorMsg: res.error,
          );
        }
      }

      if (type == 'UPDATE_LOG') {
        if (entityKey == null) return (ok: true, error: null, response: null, serverId: null, serverDate: null, errorMsg: null);
        final local = await _storage.getLocalLogByClientId(entityKey);
        final serverId = local?['server_id'] as String? ?? entityKey;
        final newText = payload['text'] as String;

        final updated = await _api.updateLog(serverId, newText);
        if (updated != null) {
          return (ok: true, error: null, response: null, serverId: serverId, serverDate: null, errorMsg: null);
        }
        return (ok: false, error: Exception('Update failed'), response: null, serverId: null, serverDate: null, errorMsg: 'Update failed');
      }

      if (type == 'DELETE_LOG') {
        if (entityKey == null) return (ok: true, error: null, response: null, serverId: null, serverDate: null, errorMsg: null);
        final local = await _storage.getLocalLogByClientId(entityKey);
        final serverId = local?['server_id'] as String? ?? entityKey;

        final ok = await _api.deleteLog(serverId);
        return (ok: ok, error: ok ? null : Exception('Delete failed'), response: null, serverId: null, serverDate: null, errorMsg: null);
      }

      return (ok: true, error: null, response: null, serverId: null, serverDate: null, errorMsg: null);
    } catch (e) {
      return (ok: false, error: e, response: null, serverId: null, serverDate: null, errorMsg: e.toString());
    }
  }

  void _scheduleRetryTimer(Duration delay) {
    _scheduledTimer?.cancel();
    _scheduledTimer = Timer(delay, () {
      runSync('timer');
    });
  }

  void disposeEngine() {
    _scheduledTimer?.cancel();
  }
}
