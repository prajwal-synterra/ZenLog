import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/insight_model.dart';
import '../services/api_service.dart';

/// Single source of truth for the entire app.
///
/// Key v2 principle: selectedDate drives ALL data fetches.
/// The server's /api/days/{date}/view is the one endpoint for the home screen.
class ZenState extends ChangeNotifier {
  final ApiService _api = ApiService();

  // ── User ──────────────────────────────────────────────────────────────────
  UserModel? user;
  String? logicalToday; // "YYYY-MM-DD" from server (4 AM rule)

  // ── Selected date ─────────────────────────────────────────────────────────
  /// The currently viewed date. Drives everything.
  String _selectedDate = _todayLocal();
  String get selectedDate => _selectedDate;

  void setSelectedDate(String date) {
    if (_selectedDate == date) return;
    _selectedDate = date;
    _dayViewCache.remove(date); // Force fresh fetch for new date
    notifyListeners();
    loadDayView(date);
  }

  // ── DayView cache (keyed by date) ─────────────────────────────────────────
  final Map<String, Map<String, dynamic>> _dayViewCache = {};
  final Map<String, bool> _dayViewLoading = {};
  final Map<String, String?> _dayViewError = {};

  Map<String, dynamic>? get currentDayView => _dayViewCache[_selectedDate];
  bool get isDayViewLoading => _dayViewLoading[_selectedDate] == true;
  String? get dayViewError => _dayViewError[_selectedDate];

  // Polling for pending extractions
  Timer? _pollTimer;
  int _pollCount = 0;
  static const int _maxPollCount = 15; // 30s max (2s intervals)

  // ── Insights ──────────────────────────────────────────────────────────────
  InsightModel? weeklyInsight;
  InsightModel? monthlyInsight;

  // ── Global loading ────────────────────────────────────────────────────────
  bool isLoading = false;
  String? errorMessage;

  // ── Init (called after token is set) ─────────────────────────────────────
  Future<void> init() async {
    isLoading = true;
    notifyListeners();

    // Get logical today from server (authoritative 4 AM boundary)
    final me = await _api.getMe();
    if (me != null) {
      logicalToday = me['logical_today'] as String?;
      _selectedDate = logicalToday ?? _todayLocal();
      user = _userFromMe(me);
    }

    // Load the day view for today
    await loadDayView(_selectedDate);

    isLoading = false;
    notifyListeners();
  }

  Future<void> loadDayView(String date, {bool silent = false}) async {
    if (_dayViewLoading[date] == true) return;
    _dayViewLoading[date] = true;
    if (!silent) notifyListeners();

    try {
      final data = await _api.getDayView(date);
      if (data != null) {
        _dayViewCache[date] = data;
        _dayViewError[date] = null;
        _startPollingIfNeeded(data, date);
      } else {
        _dayViewError[date] = 'Could not load data for $date.';
      }
    } catch (e) {
      _dayViewError[date] = e.toString();
    }

    _dayViewLoading[date] = false;
    notifyListeners();
  }

  void _startPollingIfNeeded(Map<String, dynamic> data, String date) {
    final pendingCount = (data['pending_count'] as int?) ?? 0;
    final verdictStatus = (data['verdict_status'] as String?) ?? 'none';
    final needsPoll = pendingCount > 0 || verdictStatus == 'pending';

    if (needsPoll && date == _selectedDate) {
      _stopPolling();
      _pollCount = 0;
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        _pollCount++;
        if (_pollCount >= _maxPollCount) {
          _stopPolling();
          return;
        }
        final fresh = await _api.getDayView(date);
        if (fresh != null) {
          _dayViewCache[date] = fresh;
          notifyListeners();
          final newPending = (fresh['pending_count'] as int?) ?? 0;
          final newVerdict = (fresh['verdict_status'] as String?) ?? 'none';
          if (newPending == 0 && newVerdict != 'pending') {
            _stopPolling();
          }
        }
      });
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── Log actions ───────────────────────────────────────────────────────────

  Future<bool> addLog(String text) async {
    if (text.trim().isEmpty) return false;
    final created = await _api.createLog(text);
    if (created != null) {
      await loadDayView(_selectedDate);
      return true;
    }
    return false;
  }

  Future<bool> editLog(String logId, String newText) async {
    if (newText.trim().isEmpty) return false;
    final updated = await _api.updateLog(logId, newText);
    if (updated != null) {
      await loadDayView(_selectedDate);
      return true;
    }
    return false;
  }

  Future<bool> deleteLog(String logId) async {
    final success = await _api.deleteLog(logId);
    if (success) {
      await loadDayView(_selectedDate);
    }
    return success;
  }

  Future<bool> retryLog(String logId) async {
    final ok = await _api.retryLogExtraction(logId);
    if (ok) await loadDayView(_selectedDate, silent: true);
    return ok;
  }

  Future<bool> overrideLog(
    String logId, {
    double? proteinG,
    double? caloriesKcal,
    int? hydrationMl,
  }) async {
    final res = await _api.overrideLog(
      logId,
      proteinG: proteinG,
      caloriesKcal: caloriesKcal,
      hydrationMl: hydrationMl,
    );
    if (res != null) {
      await loadDayView(_selectedDate);
      return true;
    }
    return false;
  }

  // ── Analyze / Verdict ─────────────────────────────────────────────────────

  bool _isAnalyzing = false;
  bool get isAnalyzing => _isAnalyzing;

  Future<String?> analyzeDay(String date) async {
    _isAnalyzing = true;
    notifyListeners();
    try {
      final res = await _api.analyzeDay(date);
      if (!res.success) {
        return res.error ?? 'Analysis failed.';
      }
      await loadDayView(date, silent: true);
      // Start polling for verdict
      final data = _dayViewCache[date];
      if (data != null) _startPollingIfNeeded(data, date);
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  // ── Wake time ─────────────────────────────────────────────────────────────

  Future<bool> submitWakeTime(String wakeTime, {String? day}) async {
    return _api.recordWake(wakeTime, day: day);
  }

  // ── Health ping ────────────────────────────────────────────────────────────

  Future<bool> pingHealth() => _api.pingHealth();

  // ── Insights ──────────────────────────────────────────────────────────────

  Future<void> loadWeeklyInsight() async {
    weeklyInsight = await _api.getWeeklyInsights();
    notifyListeners();
  }

  Future<void> loadMonthlyInsight() async {
    monthlyInsight = await _api.getMonthlyInsights();
    notifyListeners();
  }

  // ── User profile ──────────────────────────────────────────────────────────

  Future<void> updateGoals({
    required String goal,
    required double bodyWeight,
    required double proteinTarget,
    double? calorieTarget,
    double? waterTargetMl,
    int? weeklyWorkoutTarget,
  }) async {
    final updated = await _api.updateUserProfile(
      goal: goal,
      bodyWeight: bodyWeight,
      proteinTarget: proteinTarget,
      calorieTarget: calorieTarget,
      waterTargetMl: waterTargetMl,
      weeklyWorkoutTarget: weeklyWorkoutTarget,
    );
    if (updated != null) {
      user = updated;
      // Invalidate cache so progress recalculates with new targets
      _dayViewCache.clear();
      await loadDayView(_selectedDate);
      notifyListeners();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _todayLocal() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  UserModel _userFromMe(Map<String, dynamic> me) {
    return UserModel(
      userId: me['user_id'] ?? '',
      username: me['username'] ?? '',
      name: me['name'] ?? '',
      goal: me['goal'] ?? 'muscle_gain',
      bodyWeightKg: (me['body_weight_kg'] as num?)?.toDouble() ?? 70.0,
      dailyProteinTargetG:
          (me['daily_protein_target_g'] as num?)?.toDouble() ?? 126.0,
      dailyCalorieTarget: (me['daily_calorie_target'] as num?)?.toDouble(),
      dailyWaterTargetMl: (me['daily_water_target_ml'] as num?)?.toDouble() ?? 3000.0,
      weeklyWorkoutTarget: (me['weekly_workout_target'] as num?)?.toInt() ?? 3,
    );
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
