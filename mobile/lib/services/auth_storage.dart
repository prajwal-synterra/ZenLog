import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists session tokens, device identity, and cached user profile.
/// Implements Section 4 (Persistent Login) of ZenLog Offline-First Spec.
class AuthStorage {
  static const String _keyToken = 'zenlog_token';
  static const String _keyPendingRevokeToken = 'zenlog_pending_revoke_token';
  static const String _keyUsername = 'zenlog_username';
  static const String _keyPhone = 'zenlog_phone';
  static const String _keyDeviceId = 'zenlog_device_id';
  static const String _keyCachedUser = 'zenlog_cached_user';

  // ─── Token ────────────────────────────────────────────────────────────────

  static Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyToken);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyToken, token);
    } catch (_) {}
  }

  static Future<void> clearToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyToken);
    } catch (_) {}
  }

  // ─── Pending Revoke Token (Section 4.3) ───────────────────────────────────

  static Future<String?> getPendingRevokeToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyPendingRevokeToken);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPendingRevokeToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPendingRevokeToken, token);
    } catch (_) {}
  }

  static Future<void> clearPendingRevokeToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyPendingRevokeToken);
    } catch (_) {}
  }

  // ─── Cached User Profile (Section 4.1 & 4.2) ──────────────────────────────

  static Future<void> saveCachedUser(Map<String, dynamic> userMap) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCachedUser, jsonEncode(userMap));
      if (userMap['username'] != null) {
        await prefs.setString(_keyUsername, userMap['username'] as String);
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_keyCachedUser);
      if (str != null && str.isNotEmpty) {
        return jsonDecode(str) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clearCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCachedUser);
    } catch (_) {}
  }

  // ─── Credentials (remembered for login pre-fill) ──────────────────────────

  static Future<void> saveCredentials({
    required String username,
    required String phone,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUsername, username);
      await prefs.setString(_keyPhone, phone);
    } catch (_) {}
  }

  static Future<String> getSavedUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyUsername) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> getSavedPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyPhone) ?? '';
    } catch (_) {
      return '';
    }
  }

  // ─── Device ID ────────────────────────────────────────────────────────────

  static Future<String> getOrCreateDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_keyDeviceId);
      if (id == null) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        id = 'zenlog-$ts-device';
        await prefs.setString(_keyDeviceId, id);
      }
      return id;
    } catch (_) {
      return 'zenlog-device-default';
    }
  }

  // ─── Logout Flow (Section 4.3) ────────────────────────────────────────────

  static Future<void> handleUserLogout() async {
    final active = await getToken();
    if (active != null) {
      await setPendingRevokeToken(active);
    }
    await clearToken();
    await clearCachedUser();
  }
}
