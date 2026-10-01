import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Database service implementing Section 3 of ZenLog Offline-First Spec.
/// Durable SQLite tables for cache, local_logs, outbox, and kv store.
class OfflineStorage {
  static final OfflineStorage _instance = OfflineStorage._internal();
  factory OfflineStorage() => _instance;
  OfflineStorage._internal();

  Database? _db;
  static const int schemaVersion = 1;
  static const Duration defaultSoftTtl = Duration(hours: 24);
  static const Duration hardExpiry = Duration(days: 7);

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'zenlog_offline.db');

    return await openDatabase(
      path,
      version: schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cache (
            user_id TEXT NOT NULL,
            key TEXT NOT NULL,
            json TEXT NOT NULL,
            fetched_at INTEGER NOT NULL,
            soft_expires_at INTEGER NOT NULL,
            schema_v INTEGER NOT NULL,
            PRIMARY KEY (user_id, key)
          );
        ''');

        await db.execute('''
          CREATE TABLE local_logs (
            client_id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            server_id TEXT,
            text TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            provisional_date TEXT NOT NULL,
            sync_state TEXT NOT NULL,
            edit_pending INTEGER DEFAULT 0,
            delete_pending INTEGER DEFAULT 0,
            fail_reason TEXT,
            created_at INTEGER NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE outbox (
            op_id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            seq INTEGER NOT NULL,
            type TEXT NOT NULL,
            entity_key TEXT,
            payload TEXT NOT NULL,
            status TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER NOT NULL DEFAULT 0,
            last_error_code TEXT,
            last_error_msg TEXT,
            created_at INTEGER NOT NULL
          );
        ''');

        await db.execute('''
          CREATE INDEX outbox_user_seq ON outbox(user_id, seq);
        ''');

        await db.execute('''
          CREATE TABLE kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          );
        ''');
      },
    );
  }

  // ─── Cache Layer (Section 5) ───────────────────────────────────────────────

  Future<void> putCache({
    required String userId,
    required String key,
    required dynamic data,
    Duration softTtl = defaultSoftTtl,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final softExpiresAt = now + softTtl.inMilliseconds;
    final jsonStr = data is String ? data : jsonEncode(data);

    await db.insert(
      'cache',
      {
        'user_id': userId,
        'key': key,
        'json': jsonStr,
        'fetched_at': now,
        'soft_expires_at': softExpiresAt,
        'schema_v': schemaVersion,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({dynamic data, int fetchedAt, bool isStale})?> getCache({
    required String userId,
    required String key,
  }) async {
    final db = await database;
    final rows = await db.query(
      'cache',
      where: 'user_id = ? AND key = ?',
      whereArgs: [userId, key],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final row = rows.first;
    final now = DateTime.now().millisecondsSinceEpoch;
    final fetchedAt = row['fetched_at'] as int;
    final softExpiresAt = row['soft_expires_at'] as int;
    final isStale = now >= softExpiresAt;

    try {
      final decoded = jsonDecode(row['json'] as String);
      return (data: decoded, fetchedAt: fetchedAt, isStale: isStale);
    } catch (_) {
      return null;
    }
  }

  Future<void> invalidateCache({required String userId, required String keyPrefix}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'cache',
      {'soft_expires_at': now - 1},
      where: 'user_id = ? AND key LIKE ?',
      whereArgs: [userId, '$keyPrefix%'],
    );
  }

  Future<void> purgeOldCache(String userId) async {
    final db = await database;
    final hardThreshold = DateTime.now().subtract(hardExpiry).millisecondsSinceEpoch;
    await db.delete(
      'cache',
      where: 'user_id = ? AND fetched_at < ?',
      whereArgs: [userId, hardThreshold],
    );
  }

  // ─── Local Logs & Write-Ahead Save (Section 7.2 & 7.4) ────────────────────

  Future<void> saveLogWriteAhead({
    required String userId,
    required String clientId,
    required String text,
    required String timestamp,
    required String provisionalDate,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // 1. Check max 500 queued limit (Section 7.10)
      final countRow = await txn.rawQuery(
        "SELECT COUNT(*) as count FROM outbox WHERE user_id = ? AND status = 'queued'",
        [userId],
      );
      final currentQueue = (countRow.first['count'] as int?) ?? 0;
      if (currentQueue >= 500) {
        throw Exception('Too many unsynced changes. Connect to sync.');
      }

      // 2. Next seq strictly increasing
      final maxSeqRow = await txn.rawQuery(
        'SELECT MAX(seq) as max_seq FROM outbox WHERE user_id = ?',
        [userId],
      );
      final nextSeq = ((maxSeqRow.first['max_seq'] as int?) ?? 0) + 1;

      // 3. Insert local_logs row
      await txn.insert(
        'local_logs',
        {
          'client_id': clientId,
          'user_id': userId,
          'server_id': null,
          'text': text,
          'timestamp': timestamp,
          'provisional_date': provisionalDate,
          'sync_state': 'queued',
          'edit_pending': 0,
          'delete_pending': 0,
          'fail_reason': null,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 4. Insert outbox row
      final payloadJson = jsonEncode({
        'client_id': clientId,
        'text': text,
        'timestamp': timestamp,
      });

      await txn.insert(
        'outbox',
        {
          'op_id': clientId,
          'user_id': userId,
          'seq': nextSeq,
          'type': 'CREATE_LOG',
          'entity_key': clientId,
          'payload': payloadJson,
          'status': 'queued',
          'attempts': 0,
          'next_attempt_at': 0,
          'last_error_code': null,
          'last_error_msg': null,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> queueEditLog({
    required String userId,
    required String clientId,
    required String newText,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Coalescing check (§7.4)
      final existingCreate = await txn.query(
        'outbox',
        where: "user_id = ? AND entity_key = ? AND type = 'CREATE_LOG' AND status = 'queued'",
        whereArgs: [userId, clientId],
      );

      if (existingCreate.isNotEmpty) {
        // Just update CREATE_LOG payload!
        final oldPayload = jsonDecode(existingCreate.first['payload'] as String) as Map<String, dynamic>;
        oldPayload['text'] = newText;
        await txn.update(
          'outbox',
          {'payload': jsonEncode(oldPayload)},
          where: 'op_id = ?',
          whereArgs: [existingCreate.first['op_id']],
        );
        await txn.update(
          'local_logs',
          {'text': newText},
          where: 'client_id = ?',
          whereArgs: [clientId],
        );
        return;
      }

      // Check existing UPDATE_LOG
      final existingUpdate = await txn.query(
        'outbox',
        where: "user_id = ? AND entity_key = ? AND type = 'UPDATE_LOG' AND status = 'queued'",
        whereArgs: [userId, clientId],
      );
      if (existingUpdate.isNotEmpty) {
        final oldPayload = jsonDecode(existingUpdate.first['payload'] as String) as Map<String, dynamic>;
        oldPayload['text'] = newText;
        await txn.update(
          'outbox',
          {'payload': jsonEncode(oldPayload)},
          where: 'op_id = ?',
          whereArgs: [existingUpdate.first['op_id']],
        );
        await txn.update(
          'local_logs',
          {'text': newText, 'edit_pending': 1},
          where: 'client_id = ?',
          whereArgs: [clientId],
        );
        return;
      }

      // New UPDATE_LOG op
      final maxSeqRow = await txn.rawQuery('SELECT MAX(seq) as max_seq FROM outbox WHERE user_id = ?', [userId]);
      final nextSeq = ((maxSeqRow.first['max_seq'] as int?) ?? 0) + 1;

      await txn.update(
        'local_logs',
        {'text': newText, 'edit_pending': 1},
        where: 'client_id = ?',
        whereArgs: [clientId],
      );

      await txn.insert('outbox', {
        'op_id': 'op_${now}_$clientId',
        'user_id': userId,
        'seq': nextSeq,
        'type': 'UPDATE_LOG',
        'entity_key': clientId,
        'payload': jsonEncode({'text': newText}),
        'status': 'queued',
        'attempts': 0,
        'next_attempt_at': 0,
        'created_at': now,
      });
    });
  }

  Future<void> queueDeleteLog({
    required String userId,
    required String clientId,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Coalescing check (§7.4): If CREATE_LOG not yet sent, delete both ops and local row!
      final existingCreate = await txn.query(
        'outbox',
        where: "user_id = ? AND entity_key = ? AND type = 'CREATE_LOG' AND status = 'queued'",
        whereArgs: [userId, clientId],
      );

      if (existingCreate.isNotEmpty) {
        await txn.delete('outbox', where: 'entity_key = ? AND user_id = ?', whereArgs: [clientId, userId]);
        await txn.delete('local_logs', where: 'client_id = ?', whereArgs: [clientId]);
        return; // Zero network calls ever happen!
      }

      // Otherwise drop pending updates/overrides and enqueue DELETE_LOG
      await txn.delete(
        'outbox',
        where: "user_id = ? AND entity_key = ? AND type IN ('UPDATE_LOG', 'OVERRIDE_LOG')",
        whereArgs: [userId, clientId],
      );

      await txn.update(
        'local_logs',
        {'delete_pending': 1},
        where: 'client_id = ?',
        whereArgs: [clientId],
      );

      final maxSeqRow = await txn.rawQuery('SELECT MAX(seq) as max_seq FROM outbox WHERE user_id = ?', [userId]);
      final nextSeq = ((maxSeqRow.first['max_seq'] as int?) ?? 0) + 1;

      await txn.insert('outbox', {
        'op_id': 'op_${now}_$clientId',
        'user_id': userId,
        'seq': nextSeq,
        'type': 'DELETE_LOG',
        'entity_key': clientId,
        'payload': jsonEncode({}),
        'status': 'queued',
        'attempts': 0,
        'next_attempt_at': 0,
        'created_at': now,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getLocalLogsForDate(String userId, String date) async {
    final db = await database;
    final rows = await db.query(
      'local_logs',
      where: 'user_id = ? AND provisional_date = ?',
      whereArgs: [userId, date],
      orderBy: 'timestamp ASC',
    );
    return rows;
  }

  Future<Map<String, dynamic>?> getLocalLogByClientId(String clientId) async {
    final db = await database;
    final rows = await db.query(
      'local_logs',
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> deleteLocalLog(String clientId) async {
    final db = await database;
    await db.delete('local_logs', where: 'client_id = ?', whereArgs: [clientId]);
  }

  Future<void> markLogSynced({
    required String clientId,
    required String serverId,
    required String serverDate,
  }) async {
    final db = await database;
    await db.update(
      'local_logs',
      {
        'server_id': serverId,
        'provisional_date': serverDate,
        'sync_state': 'synced',
        'edit_pending': 0,
        'delete_pending': 0,
      },
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  Future<void> markLogSyncing(String clientId) async {
    final db = await database;
    await db.update(
      'local_logs',
      {'sync_state': 'syncing'},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  Future<void> markLogFailed({required String clientId, required String reason}) async {
    final db = await database;
    await db.update(
      'local_logs',
      {
        'sync_state': 'failed',
        'fail_reason': reason,
      },
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  // ─── Outbox Operations (Section 7.6) ──────────────────────────────────────

  Future<Map<String, dynamic>?> getNextRunnableOp(String userId, int nowEpochMs) async {
    final db = await database;
    final rows = await db.query(
      'outbox',
      where: "user_id = ? AND status = 'queued' AND next_attempt_at <= ?",
      whereArgs: [userId, nowEpochMs],
      orderBy: 'seq ASC',
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> getQueuedCount(String userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) as count FROM outbox WHERE user_id = ? AND status IN ('queued', 'sending')",
      [userId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getQueuedOps(String userId) async {
    final db = await database;
    return await db.query(
      'outbox',
      where: "user_id = ? AND status IN ('queued', 'sending')",
      orderBy: 'seq ASC',
    );
  }

  Future<void> setOpStatus(String opId, String status) async {
    final db = await database;
    await db.update('outbox', {'status': status}, where: 'op_id = ?', whereArgs: [opId]);
  }

  Future<void> scheduleRetry(String opId, int nextAttemptAt, int attempts, {String? code, String? msg}) async {
    final db = await database;
    await db.update(
      'outbox',
      {
        'status': 'queued',
        'attempts': attempts,
        'next_attempt_at': nextAttemptAt,
        'last_error_code': code,
        'last_error_msg': msg,
      },
      where: 'op_id = ?',
      whereArgs: [opId],
    );
  }

  Future<void> failPermanent(String opId, {String? code, String? msg}) async {
    final db = await database;
    await db.update(
      'outbox',
      {
        'status': 'failed_permanent',
        'last_error_code': code,
        'last_error_msg': msg,
      },
      where: 'op_id = ?',
      whereArgs: [opId],
    );
  }

  Future<void> removeOp(String opId) async {
    final db = await database;
    await db.delete('outbox', where: 'op_id = ?', whereArgs: [opId]);
  }

  Future<void> clearUserData(String userId) async {
    final db = await database;
    await db.delete('cache', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('local_logs', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('outbox', where: 'user_id = ?', whereArgs: [userId]);
  }

  // ─── KV Store (Section 3.2 & 7.8) ─────────────────────────────────────────

  Future<String?> getKv(String key) async {
    final db = await database;
    final rows = await db.query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isNotEmpty ? (rows.first['value'] as String?) : null;
  }

  Future<void> setKv(String key, String value) async {
    final db = await database;
    await db.insert(
      'kv',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Lock with TTL (Section 7.8)
  Future<bool> tryAcquireLock(String lockKey, Duration ttl) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lockVal = await getKv(lockKey);

    if (lockVal != null) {
      final expiresAt = int.tryParse(lockVal) ?? 0;
      if (now < expiresAt) return false; // Still held
    }

    await setKv(lockKey, (now + ttl.inMilliseconds).toString());
    return true;
  }

  Future<void> releaseLock(String lockKey) async {
    final db = await database;
    await db.delete('kv', where: 'key = ?', whereArgs: [lockKey]);
  }
}
