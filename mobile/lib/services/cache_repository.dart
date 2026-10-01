import 'api_service.dart';
import 'connection_monitor.dart';
import 'offline_storage.dart';

/// Cache Repository implementing Section 5 of ZenLog Offline-First Spec.
/// Handles stale-while-revalidate, local overlays, and prefetching.
class CacheRepository {
  static final CacheRepository _instance = CacheRepository._internal();
  factory CacheRepository() => _instance;
  CacheRepository._internal();

  final OfflineStorage _storage = OfflineStorage();
  final ApiService _api = ApiService();

  static const List<Map<String, String>> defaultMotivation = [
    {
      'headline': 'A fresh page.',
      'message': 'Log what you actually do. Small, honest entries beat perfect ones.',
      'tone': 'steady',
    },
    {
      'headline': 'Show up tomorrow.',
      'message': 'Write your first meal and your first glass of water early.',
      'tone': 'steady',
    },
    {
      'headline': 'Keep it simple.',
      'message': 'Protein at every meal, water through the day, one workout when planned.',
      'tone': 'steady',
    },
    {
      'headline': 'Rhythm over intensity.',
      'message': 'A normal day, logged, is worth more than a perfect day skipped.',
      'tone': 'steady',
    },
  ];

  // ─── Day View with Stale-While-Revalidate and Local Overlay (§5.1 & §5.6) ──

  Future<Map<String, dynamic>?> getDayViewWithOverlay({
    required String userId,
    required String date,
    required Function(Map<String, dynamic> freshData) onBackgroundUpdate,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'dayView:$date';

    // 1. Check local cache
    final cached = await _storage.getCache(userId: userId, key: cacheKey);
    Map<String, dynamic>? baseData;
    int? cacheAgeMs;

    if (cached != null && cached.data is Map<String, dynamic>) {
      baseData = Map<String, dynamic>.from(cached.data as Map);
      cacheAgeMs = DateTime.now().millisecondsSinceEpoch - cached.fetchedAt;
    }

    // 2. Fetch remote if stale, not cached, today, or forced
    final isDisconnected = ConnectionMonitor().current.state == ConnectionStateEnum.disconnected;
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final isToday = date == todayStr;
    final shouldRefetch = (forceRefresh || isToday || cached == null || cached.isStale) && !isDisconnected;

    if (shouldRefetch) {
      _api.getDayView(date).then((fresh) async {
        if (fresh != null) {
          await _storage.putCache(userId: userId, key: cacheKey, data: fresh);
          final overlaid = await applyOverlay(userId: userId, date: date, baseData: fresh);
          onBackgroundUpdate(overlaid);
        }
      }).catchError((_) {});
    }

    // 3. Fallback for future day if completely offline and nothing cached (§5.5)
    if (baseData == null) {
      if (date.compareTo(todayStr) > 0) {
        baseData = _buildStaticMotivationFallback(userId, date);
      }
    }

    if (baseData == null) return null;

    // 4. Apply Local Overlay (Section 5.6)
    return await applyOverlay(
      userId: userId,
      date: date,
      baseData: baseData,
      cacheAgeMs: cacheAgeMs,
    );
  }

  /// Merges local unsynced entries into the day view payload (Section 5.6)
  Future<Map<String, dynamic>> applyOverlay({
    required String userId,
    required String date,
    required Map<String, dynamic> baseData,
    int? cacheAgeMs,
  }) async {
    final result = Map<String, dynamic>.from(baseData);
    if (cacheAgeMs != null) {
      result['_cache_age_ms'] = cacheAgeMs;
    }

    final localLogs = await _storage.getLocalLogsForDate(userId, date);
    if (localLogs.isEmpty) return result;

    final existingLogs = (result['logs'] as List?)?.cast<dynamic>() ?? [];
    final List<Map<String, dynamic>> merged = [];
    final Set<String> hiddenIds = {};
    final Map<String, String> editedText = {};

    for (final l in localLogs) {
      final clientId = l['client_id'] as String;
      final serverId = l['server_id'] as String?;
      final deletePending = (l['delete_pending'] as int?) == 1;
      final editPending = (l['edit_pending'] as int?) == 1;

      if (deletePending) {
        if (serverId != null) hiddenIds.add(serverId);
        hiddenIds.add(clientId);
        continue;
      }

      if (editPending) {
        if (serverId != null) editedText[serverId] = l['text'] as String;
        editedText[clientId] = l['text'] as String;
      }

      // Check if this log is already present in server cache
      final alreadyInServerCache = existingLogs.any((el) {
        if (el is Map) {
          final id = el['id']?.toString();
          final cId = el['client_id']?.toString();
          return (serverId != null && id == serverId) || (cId != null && cId == clientId) || (id == clientId);
        }
        return false;
      });

      // If not yet in server cache, keep showing from local_logs so it never disappears
      if (!alreadyInServerCache) {
        merged.add({
          'id': serverId ?? clientId,
          'client_id': clientId,
          'text': l['text'],
          'timestamp': l['timestamp'],
          'time_display': _formatTimeDisplay(l['timestamp'] as String),
          'sync_state': l['sync_state'],
          'edit_pending': editPending,
          'fail_reason': l['fail_reason'],
          'extraction_status': l['sync_state'] == 'synced' ? 'done' : 'queued',
          'overrides': {},
        });
      }
    }

    // Add existing server logs, omitting deleted ones and updating edited ones
    for (final el in existingLogs) {
      if (el is Map) {
        final elMap = el.map((k, v) => MapEntry(k.toString(), v));
        final id = elMap['id']?.toString() ?? '';
        final cId = elMap['client_id']?.toString() ?? '';

        if (hiddenIds.contains(id) || hiddenIds.contains(cId)) {
          continue;
        }

        final copy = Map<String, dynamic>.from(elMap);
        if (editedText.containsKey(id)) {
          copy['text'] = editedText[id];
          copy['edit_pending'] = true;
        } else if (editedText.containsKey(cId)) {
          copy['text'] = editedText[cId];
          copy['edit_pending'] = true;
        }
        merged.add(copy);
      }
    }

    // Sort by timestamp
    merged.sort((a, b) {
      final ta = a['timestamp']?.toString() ?? '';
      final tb = b['timestamp']?.toString() ?? '';
      return ta.compareTo(tb);
    });

    result['logs'] = merged;

    // Count queued entries that aren't counted in totals yet (§1.3)
    final queuedCount = localLogs.where((l) => l['sync_state'] != 'synced').length;
    result['queued_entries_count'] = queuedCount;

    return result;
  }

  Map<String, dynamic> _buildStaticMotivationFallback(String userId, String date) {
    int hash = 0;
    final combined = '$userId$date';
    for (int i = 0; i < combined.length; i++) {
      hash = (hash * 31 + combined.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final chosen = defaultMotivation[hash % defaultMotivation.length];

    return {
      'date': date,
      'mode': 'future',
      'is_closed': false,
      'pending_count': 0,
      'failed_count': 0,
      'logs': [],
      'totals': {'protein_g': 0, 'calories_kcal': 0, 'hydration_ml': 0, 'workout_done': false, 'workout_mins': 0},
      'targets': {},
      'progress': null,
      'score': null,
      'rating': null,
      'verdict': null,
      'verdict_status': 'none',
      'motivation': {
        'headline': chosen['headline'],
        'message': chosen['message'],
        'tone': chosen['tone'],
        'is_generic_fallback': true,
      },
    };
  }

  String _formatTimeDisplay(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $period';
    } catch (_) {
      return '';
    }
  }

  // ─── Prefetch Sequence (Section 5.3) ──────────────────────────────────────

  Future<void> runPrefetch(String userId) async {
    final monitor = ConnectionMonitor().current;
    if (monitor.state == ConnectionStateEnum.disconnected) return;

    final lastPrefetch = await _storage.getKv('last_full_refresh_at');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastPrefetch != null) {
      final lastMs = int.tryParse(lastPrefetch) ?? 0;
      if (now - lastMs < const Duration(hours: 24).inMilliseconds) {
        return; // Prefetched recently
      }
    }

    try {
      final today = DateTime.now();
      // 1. Previous 6 days + Today
      for (int i = 0; i <= 6; i++) {
        final d = today.subtract(Duration(days: i));
        final dateStr = d.toIso8601String().substring(0, 10);
        final dv = await _api.getDayView(dateStr);
        if (dv != null) {
          await _storage.putCache(userId: userId, key: 'dayView:$dateStr', data: dv);
        }
      }

      // 2. Next 3 days (future motivation)
      for (int i = 1; i <= 3; i++) {
        final d = today.add(Duration(days: i));
        final dateStr = d.toIso8601String().substring(0, 10);
        final dv = await _api.getDayView(dateStr);
        if (dv != null) {
          await _storage.putCache(userId: userId, key: 'dayView:$dateStr', data: dv);
        }
      }

      await _storage.setKv('last_full_refresh_at', now.toString());
    } catch (_) {}
  }
}
