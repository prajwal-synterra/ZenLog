import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';
import '../models/user_model.dart';
import '../models/log_model.dart';
import '../models/day_record_model.dart';
import '../models/insight_model.dart';
import '../models/prompt_status_model.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;
  bool get isAuthenticated => _token != null;
  void setToken(String token) => _token = token;
  void clearToken() => _token = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // ─────────────────────────────────────────────────────────────────────────
  // HEALTH
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> pingHealth() async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}/health'),
            headers: {'ngrok-skip-browser-warning': 'true'},
          )
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTH
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> login({
    required String username,
    required String phone,
    String? deviceId,
    String? deviceName,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.login}'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
            body: jsonEncode({
              'username': username,
              'phone_number': phone,
              if (deviceId != null) 'device_id': deviceId,
              if (deviceName != null) 'device_name': deviceName,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getMe() async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}/api/auth/me'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      if (res.statusCode == 401) return null;
    } catch (_) {}
    return null;
  }

  Future<void> logout() async {
    try {
      await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/api/auth/logout'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
    clearToken();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // USER
  // ─────────────────────────────────────────────────────────────────────────

  Future<UserModel?> getUserProfile() async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.userMe}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        return UserModel.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  Future<UserModel?> updateUserProfile({
    required String goal,
    required double bodyWeight,
    required double proteinTarget,
    double? calorieTarget,
    double? waterTargetMl,
    int? weeklyWorkoutTarget,
  }) async {
    try {
      final body = {
        'goal': goal,
        'body_weight_kg': bodyWeight,
        'daily_protein_target_g': proteinTarget,
        if (calorieTarget != null) 'daily_calorie_target': calorieTarget,
        if (waterTargetMl != null) 'daily_water_target_ml': waterTargetMl,
        if (weeklyWorkoutTarget != null) 'weekly_workout_target': weeklyWorkoutTarget,
      };
      final res = await http
          .put(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.userMe}'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        return UserModel.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // v2: DAY VIEW (the main new endpoint)
  // ─────────────────────────────────────────────────────────────────────────

  /// GET /api/days/{date}/view — returns mode, logs, totals, progress, score, verdict
  Future<Map<String, dynamic>?> getDayView(String date) async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}/api/days/$date/view'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// GET /api/quotes/{date} — returns 24h daily quote from DB cache or RapidAPI
  Future<Map<String, dynamic>?> getDailyQuote(String date) async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}/api/quotes/$date'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }


  /// POST /api/days/{date}/analyze — trigger on-demand Gemini verdict
  Future<({bool success, String? error, Map<String, dynamic>? data})> analyzeDay(String date) async {
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/api/days/$date/analyze'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        return (success: true, error: null, data: jsonDecode(res.body) as Map<String, dynamic>?);
      } else {
        String detail = 'Analysis failed (${res.statusCode})';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['detail'] != null) {
            detail = body['detail'].toString();
          }
        } catch (_) {}
        return (success: false, error: detail, data: null);
      }
    } catch (e) {
      return (success: false, error: 'Network timeout. Check connection and try again.', data: null);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGS
  // ─────────────────────────────────────────────────────────────────────────

  Future<LogEntryModel?> createLog(String text, {String? date}) async {
    try {
      final body = <String, dynamic>{'text': text};
      final res = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logs}'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 201) {
        return LogEntryModel.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  /// Used by SyncEngine: sends client_id for idempotency (§7.3 / C1) and the
  /// original timestamp so the server applies the 4 AM date rule correctly.
  Future<({bool ok, LogEntryModel? model, String? error})> createLogWithDetails(
    String text, {
    String? clientId,
    DateTime? timestamp,
  }) async {
    try {
      final body = <String, dynamic>{
        'text': text,
        if (clientId != null) 'client_id': clientId,
        if (timestamp != null) 'timestamp': timestamp.toIso8601String(),
      };
      final res = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logs}'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final model = LogEntryModel.fromJson(jsonDecode(res.body));
        return (ok: true, model: model, error: null);
      }
      // Extract error detail from body
      String detail = 'Server error (${res.statusCode})';
      try {
        final b = jsonDecode(res.body);
        if (b is Map && b['detail'] != null) detail = b['detail'].toString();
        if (b is Map && b['message'] != null) detail = b['message'].toString();
      } catch (_) {}
      return (ok: false, model: null, error: detail);
    } catch (e) {
      return (ok: false, model: null, error: e.toString());
    }
  }

  Future<LogEntryModel?> updateLog(String logId, String newText) async {
    try {
      final res = await http
          .put(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logs}/$logId'),
            headers: _headers,
            body: jsonEncode({'text': newText}),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return LogEntryModel.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> deleteLog(String logId) async {
    try {
      final res = await http
          .delete(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logs}/$logId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 204;
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>?> overrideLog(
    String logId, {
    double? proteinG,
    double? caloriesKcal,
    int? hydrationMl,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (proteinG != null) body['protein_g'] = proteinG;
      if (caloriesKcal != null) body['calories_kcal'] = caloriesKcal;
      if (hydrationMl != null) body['hydration_ml'] = hydrationMl;

      final res = await http
          .patch(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logs}/$logId/override'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> retryLogExtraction(String logId) async {
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.logs}/$logId/retry'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEGACY: Sleep / Wake / Prompt Status (kept for backward compat)
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> recordWake(String wakeTime, {String? day}) async {
    try {
      final endpoint = day != null
          ? '${ApiConstants.baseUrl}/api/days/$day/wake'
          : '${ApiConstants.baseUrl}${ApiConstants.wake}';
      final res = await http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: jsonEncode({'wake_time': wakeTime}),
          )
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  Future<DailyRecordModel?> submitSleep(String sleepTime, {String? day}) async {
    try {
      final endpoint = day != null
          ? '${ApiConstants.baseUrl}/api/days/$day/sleep'
          : '${ApiConstants.baseUrl}${ApiConstants.sleep}';
      final res = await http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: jsonEncode({'sleep_time': sleepTime}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 || res.statusCode == 201) {
        return DailyRecordModel.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  Future<DayPromptStatusModel?> getPromptStatus() async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.promptStatus}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        return DayPromptStatusModel.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CALENDAR
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCalendar(
      String from, String to) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/api/calendar')
          .replace(queryParameters: {'from': from, 'to': to});
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(res.body));
      }
    } catch (_) {}
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INSIGHTS
  // ─────────────────────────────────────────────────────────────────────────

  Future<InsightModel?> getWeeklyInsights() async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.insightsWeekly}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return InsightModel.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  Future<InsightModel?> getMonthlyInsights() async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.insightsMonthly}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return InsightModel.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }
}

extension DateHelper on DateTime {
  String toIsoformatDate() {
    return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }
}
