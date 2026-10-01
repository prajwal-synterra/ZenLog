import 'package:shared_preferences/shared_preferences.dart';

/// Persists the session token and credentials locally.
/// v2: Token is stored and checked on startup via /api/auth/me.
class AuthStorage {
  static const String _keyToken = 'zenlog_token';
  static const String _keyUsername = 'zenlog_username';
  static const String _keyPhone = 'zenlog_phone';
  static const String _keyDeviceId = 'zenlog_device_id';
  static const String _keyUserName = 'zenlog_user_name'; // display name
  static const String _keyGoal = 'zenlog_goal';

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

  // ─── Credentials (remembered for login pre-fill) ──────────────────────────

  static Future<void> saveCredentials({
    required String username,
    required String phone,
    String? displayName,
    String? goal,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUsername, username);
      await prefs.setString(_keyPhone, phone);
      if (displayName != null) await prefs.setString(_keyUserName, displayName);
      if (goal != null) await prefs.setString(_keyGoal, goal);
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

  // ─── Device ID (stable UUID for this device) ──────────────────────────────

  static Future<String> getOrCreateDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_keyDeviceId);
      if (id == null) {
        // Generate a simple stable UUID-like ID
        final ts = DateTime.now().millisecondsSinceEpoch;
        id = 'zenlog-$ts-flutter';
        await prefs.setString(_keyDeviceId, id);
      }
      return id;
    } catch (_) {
      return 'zenlog-device-default';
    }
  }

  // ─── Clear all ────────────────────────────────────────────────────────────

  static Future<void> clearLogin() async {
    await clearToken();
  }

  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyToken);
      // Keep username/phone for login pre-fill
    } catch (_) {}
  }
}
