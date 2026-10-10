import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/insight_model.dart';
import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../services/quote_storage.dart';
import '../services/sleep_wake_storage.dart';
import '../screens/home/widgets/sleep_wake_dialogs.dart';
import '../services/notification_service.dart';
import 'package:uuid/uuid.dart';

/// Single source of truth for the entire app.
class ZenState extends ChangeNotifier with WidgetsBindingObserver {
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
    refreshSleepWakeData();
    ensureQuoteLoaded(date);
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

  // ── Saved Meals & Quick Actions (Module 4) ─────────────────────────────
  List<Map<String, dynamic>> savedMeals = [];
  List<Map<String, dynamic>> savedMealSuggestions = [];
  bool isLoadingSavedMeals = false;

  // ── Global loading ────────────────────────────────────────────────────────
  bool isLoading = false;
  String? errorMessage;

  // ── Sleep & Wake state ────────────────────────────────────────────────────
  DateTime? _wakeTime;
  DateTime? _sleepTime;
  Duration? _sleepDuration;
  bool _isSleepPending = false;

  DateTime? get wakeTime => _wakeTime;
  DateTime? get sleepTime => _sleepTime;
  Duration? get sleepDuration => _sleepDuration;
  bool get isSleepPending => _isSleepPending;
  String get formattedSleepDuration => SleepWakeStorage.formatDuration(_sleepDuration);

  // ── 24-Hour Quotes State ───────────────────────────────────────────────────
  final Map<String, DailyQuote> _quotesCache = {};
  DailyQuote? get currentDailyQuote => _quotesCache[_selectedDate];
  DailyQuote? getQuoteForDate(String date) => _quotesCache[date];

  Future<DailyQuote> ensureQuoteLoaded(String date) async {
    if (_quotesCache.containsKey(date)) {
      return _quotesCache[date]!;
    }

    // 1. Check Phone Local Cache (Offline First: SharedPreferences zen_quote_YYYY-MM-DD)
    final local = await QuoteStorage.getLocalQuote(date);
    if (local != null) {
      _quotesCache[date] = local;
      notifyListeners();
      return local;
    }

    // 2. Fetch from backend (DB Cache -> RapidAPI -> Fallback pool)
    final quote = await QuoteStorage.getOrFetchQuote(
      date,
      fetchRemote: (d) => _api.getDailyQuote(d),
    );
    _quotesCache[date] = quote;
    notifyListeners();
    return quote;
  }

  // ── Init (called after token is set) ─────────────────────────────────────
  Future<void> init() async {
    isLoading = true;
    notifyListeners();

    // 1. Restore cached user profile immediately if present
    final cachedUserMap = await AuthStorage.getCachedUser();
    if (cachedUserMap != null) {
      user = UserModel.fromJson(cachedUserMap);
      logicalToday = cachedUserMap['logical_today'] as String? ?? _todayLocal();
      _selectedDate = logicalToday!;
    }

    // 2. Fetch authoritative user from server
    try {
      final me = await _api.getMe();
      if (me != null) {
        logicalToday = me['logical_today'] as String?;
        if (logicalToday != null) _selectedDate = logicalToday!;
        user = _userFromMe(me);
        await AuthStorage.saveCachedUser(me);
      }
    } catch (_) {}

    // 3. Load day view, sleep/wake cycle, quote, and saved meals
    await loadDayView(_selectedDate);
    await refreshSleepWakeData();
    ensureQuoteLoaded(_selectedDate);
    loadSavedMeals();
    loadSavedMealSuggestions();
    NotificationService().syncToken();

    WidgetsBinding.instance.addObserver(this);

    isLoading = false;
    notifyListeners();
  }

  // ── App lifecycle ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadDayView(_selectedDate, silent: true);
      refreshSleepWakeData();
    }
  }

  Future<void> loadDayView(String date, {bool silent = false}) async {
    if (_dayViewLoading[date] == true) return;
    _dayViewLoading[date] = true;
    if (!silent) notifyListeners();

    try {
      final fresh = await _api.getDayView(date);
      if (fresh != null) {
        _dayViewCache[date] = fresh;
        _dayViewError[date] = null;
        final qRaw = fresh['quote'];
        if (qRaw is Map) {
          final qMap = qRaw.map((k, v) => MapEntry(k.toString(), v));
          if (qMap['quote'] != null) {
            final dq = DailyQuote.fromJson(qMap, defaultDate: date);
            _quotesCache[date] = dq;
            QuoteStorage.saveLocalQuote(dq);
          }
        }
        _startPollingIfNeeded(fresh, date);
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

  // ── Log actions (Direct Online API) ───────────────────────────────────────

  static const _uuid = Uuid();

  Future<bool> addLog(String text, {DateTime? loggedAt}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    try {
      final clientId = _uuid.v4();
      final effectiveLoggedAt = loggedAt ?? _effectiveDateTimeForSelectedDate();
      final created = await _api.createLog(
        trimmed,
        date: _selectedDate,
        loggedAt: effectiveLoggedAt,
        clientId: clientId,
      );
      if (created != null) {
        _dayViewCache.remove(_selectedDate);
        if (created.date.isNotEmpty && created.date != _selectedDate) {
          _dayViewCache.remove(created.date);
        }
        await loadDayView(_selectedDate);
        return true;
      }
      errorMessage = "Couldn't save log. Please try again.";
      notifyListeners();
      return false;
    } catch (e) {
      errorMessage = "Error saving log: $e";
      notifyListeners();
      return false;
    }
  }

  DateTime _effectiveDateTimeForSelectedDate() {
    final today = logicalToday ?? _todayLocal();
    if (_selectedDate == today) {
      return DateTime.now();
    }
    // Past date: construct a DateTime for the selected date at 13:00 (Lunch) by default
    final parts = _selectedDate.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
      final m = int.tryParse(parts[1]) ?? DateTime.now().month;
      final d = int.tryParse(parts[2]) ?? DateTime.now().day;
      return DateTime(y, m, d, 13, 0);
    }
    return DateTime.now();
  }

  Future<bool> repeatLog(String logId, {DateTime? loggedAt}) async {
    try {
      final clientId = _uuid.v4();
      final created = await _api.repeatLog(
        logId,
        loggedAt: loggedAt,
        clientId: clientId,
      );
      if (created != null) {
        final today = logicalToday ?? _todayLocal();
        _dayViewCache.remove(today);
        _dayViewCache.remove(_selectedDate);
        if (created.date.isNotEmpty) {
          _dayViewCache.remove(created.date);
        }
        await loadDayView(_selectedDate);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> moveLogTime(String logId, DateTime newLoggedAt) async {
    try {
      final updated = await _api.updateLog(logId, null, loggedAt: newLoggedAt);
      if (updated != null) {
        _dayViewCache.clear();
        await loadDayView(_selectedDate);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> editLog(String logId, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return false;

    try {
      final updated = await _api.updateLog(logId, trimmed);
      if (updated != null) {
        _dayViewCache.remove(_selectedDate);
        await loadDayView(_selectedDate);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteLog(String logId) async {
    try {
      final success = await _api.deleteLog(logId);
      if (success) {
        _dayViewCache.remove(_selectedDate);
        await loadDayView(_selectedDate);
      }
      return success;
    } catch (_) {
      return false;
    }
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

  Future<bool> addStructuredLog({
    required String text,
    required Map<String, dynamic> extracted,
    String source = 'structured',
    Map<String, dynamic>? meta,
    DateTime? loggedAt,
  }) async {
    try {
      final clientId = _uuid.v4();
      final effectiveLoggedAt = loggedAt ?? _effectiveDateTimeForSelectedDate();
      final created = await _api.createStructuredLog(
        text: text,
        extracted: extracted,
        source: source,
        meta: meta,
        loggedAt: effectiveLoggedAt,
        clientId: clientId,
      );
      if (created != null) {
        _dayViewCache.remove(_selectedDate);
        if (created.date.isNotEmpty && created.date != _selectedDate) {
          _dayViewCache.remove(created.date);
        }
        await loadDayView(_selectedDate);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> logFoodScan(String scanId, {double? servings, double? grams, DateTime? loggedAt}) async {
    try {
      final clientId = _uuid.v4();
      final effectiveLoggedAt = loggedAt ?? _effectiveDateTimeForSelectedDate();
      final created = await _api.logFoodScan(
        scanId,
        servings: servings,
        grams: grams,
        loggedAt: effectiveLoggedAt,
        clientId: clientId,
      );
      if (created != null) {
        _dayViewCache.remove(_selectedDate);
        if (created.date.isNotEmpty && created.date != _selectedDate) {
          _dayViewCache.remove(created.date);
        }
        await loadDayView(_selectedDate);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> logProduct(String productId, {double? servings, double? grams, DateTime? loggedAt}) async {
    try {
      final clientId = _uuid.v4();
      final effectiveLoggedAt = loggedAt ?? _effectiveDateTimeForSelectedDate();
      final created = await _api.logProduct(
        productId,
        servings: servings,
        grams: grams,
        loggedAt: effectiveLoggedAt,
        clientId: clientId,
      );
      if (created != null) {
        _dayViewCache.remove(_selectedDate);
        if (created.date.isNotEmpty && created.date != _selectedDate) {
          _dayViewCache.remove(created.date);
        }
        await loadDayView(_selectedDate);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
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

  // ── Sleep & Wake actions ──────────────────────────────────────────────────

  Future<void> refreshSleepWakeData() async {
    final current = _selectedDate;
    final d = DateTime.tryParse(current) ?? DateTime.now();
    final prev = d.subtract(const Duration(days: 1));
    final prevDate =
        '${prev.year}-${prev.month.toString().padLeft(2, '0')}-${prev.day.toString().padLeft(2, '0')}';

    _wakeTime = await SleepWakeStorage.getWakeTime(current);
    _sleepTime = await SleepWakeStorage.getSleepTime(prevDate);
    _isSleepPending = await SleepWakeStorage.isSleepPending(prevDate);

    // If storage doesn't have wakeTime yet, check current dayView
    if (_wakeTime == null && currentDayView != null) {
      final wakeMap = currentDayView?['wake'] as Map<String, dynamic>?;
      final wakeStr = wakeMap?['wake_time'] as String? ?? (currentDayView?['wake_time'] as String?);
      if (wakeStr != null) {
        final parts = wakeStr.split(':');
        if (parts.length == 2) {
          final h = int.tryParse(parts[0]) ?? 0;
          final m = int.tryParse(parts[1]) ?? 0;
          _wakeTime = DateTime(d.year, d.month, d.day, h, m);
        }
      }
    }

    if (_wakeTime != null && _sleepTime != null) {
      final diff = _wakeTime!.difference(_sleepTime!);
      if (!diff.isNegative && diff.inMinutes > 0 && diff.inHours <= 16) {
        _sleepDuration = diff;
      } else {
        _sleepDuration = null;
      }
    } else {
      _sleepDuration = null;
    }
    notifyListeners();
  }

  Future<void> syncSleepTime(String sleepTime, {String? day}) async {
    await _api.submitSleep(sleepTime, day: day);
    if (day != null) {
      _dayViewCache.remove(day);
    }
    await refreshSleepWakeData();
    notifyListeners();
  }

  Future<void> handleNightSubmit(BuildContext context) async {
    final today = logicalToday ?? _todayLocal();
    final alreadyShown = await SleepWakeStorage.isNightPromptShown(today);

    if (!alreadyShown && context.mounted) {
      final sleepNow = await NightConfirmationModal.show(context);
      if (sleepNow == true) {
        final now = DateTime.now();
        await SleepWakeStorage.saveNightSleepNow(todayDate: today, sleepTime: now);
        final formatted =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        await _api.submitSleep(formatted, day: today);
      } else if (sleepNow == false) {
        await SleepWakeStorage.saveNightAskTomorrow(todayDate: today);
      }
      await refreshSleepWakeData();
    }

    // Always run analysis as part of day submit
    await analyzeDay(today);
  }

  Future<bool> submitWakeTime(String wakeTime, {String? day}) async {
    final ok = await _api.recordWake(wakeTime, day: day);
    await refreshSleepWakeData();
    return ok;
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

  // ── Saved Meals & Quick Actions (Module 4) ─────────────────────────────

  Future<void> loadSavedMeals() async {
    try {
      isLoadingSavedMeals = true;
      notifyListeners();
      savedMeals = await _api.getSavedMeals();
    } catch (_) {
    } finally {
      isLoadingSavedMeals = false;
      notifyListeners();
    }
  }

  Future<void> loadSavedMealSuggestions() async {
    try {
      savedMealSuggestions = await _api.getSavedMealSuggestions();
      notifyListeners();
    } catch (_) {}
  }

  void dismissSuggestion(String rawText) {
    savedMealSuggestions.removeWhere((s) => s['raw_text'] == rawText);
    notifyListeners();
  }

  /// Optimistically adds water and sends structured log (Module 4).
  /// Returns created log ID so undo can immediately delete it.
  Future<String?> logQuickWater(int amountMl) async {
    final effectiveLoggedAt = _effectiveDateTimeForSelectedDate();
    final clientId = _uuid.v4();

    // Optimistic local update on currentDayView
    if (_dayViewCache.containsKey(_selectedDate)) {
      final cached = Map<String, dynamic>.from(_dayViewCache[_selectedDate]!);
      final totals = Map<String, dynamic>.from((cached['totals'] as Map?) ?? {});
      final currentHydration = (totals['hydration_ml'] as num?)?.toDouble() ?? 0.0;
      totals['hydration_ml'] = currentHydration + amountMl;
      cached['totals'] = totals;
      _dayViewCache[_selectedDate] = cached;
      notifyListeners();
    }

    try {
      final res = await _api.createStructuredLog(
        text: '$amountMl ml water',
        extracted: {
          'hydration_ml': amountMl,
          'water_ml': amountMl,
        },
        source: 'water_quick',
        loggedAt: effectiveLoggedAt,
        clientId: clientId,
      );

      if (res != null) {
        _dayViewCache.remove(_selectedDate);
        await loadDayView(_selectedDate, silent: true);
        return res.id;
      }
    } catch (_) {}

    // Rollback if failed
    await loadDayView(_selectedDate, silent: true);
    return null;
  }

  Future<bool> logSavedMeal(String mealId, {double portion = 1.0}) async {
    final effectiveLoggedAt = _effectiveDateTimeForSelectedDate();
    final clientId = _uuid.v4();
    try {
      final res = await _api.logSavedMeal(
        mealId,
        portion: portion,
        loggedAt: effectiveLoggedAt,
        clientId: clientId,
      );
      if (res != null) {
        _dayViewCache.remove(_selectedDate);
        await loadDayView(_selectedDate);
        await loadSavedMeals();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> saveMealFromLog(String logId, {String? name}) async {
    try {
      final res = await _api.createSavedMeal(logId: logId, name: name);
      if (res != null) {
        await loadSavedMeals();
        await loadSavedMealSuggestions();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> createSavedMealManual({
    required String name,
    required Map<String, dynamic> extracted,
    String? rawText,
    bool pinned = false,
  }) async {
    try {
      final res = await _api.createSavedMeal(
        name: name,
        extracted: extracted,
        rawText: rawText,
        pinned: pinned,
      );
      if (res != null) {
        await loadSavedMeals();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> updateSavedMeal(
    String id, {
    String? name,
    String? rawText,
    Map<String, dynamic>? extracted,
    bool? pinned,
  }) async {
    try {
      final res = await _api.updateSavedMeal(
        id,
        name: name,
        rawText: rawText,
        extracted: extracted,
        pinned: pinned,
      );
      if (res != null) {
        await loadSavedMeals();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> deleteSavedMeal(String id) async {
    try {
      final ok = await _api.deleteSavedMeal(id);
      if (ok) {
        savedMeals.removeWhere((m) => m['id'] == id);
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _todayLocal() {
    final shifted = DateTime.now().subtract(const Duration(hours: 4));
    return '${shifted.year}-${shifted.month.toString().padLeft(2, '0')}-${shifted.day.toString().padLeft(2, '0')}';
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
      hasPin: me['has_pin'] == true,
    );
  }

  Future<({bool ok, String? error})> setPin({
    required String pin,
    String? currentPin,
  }) async {
    final res = await _api.setPin(pin: pin, currentPin: currentPin);
    if (res.ok) {
      if (user != null) {
        user = user!.copyWith(hasPin: true);
        notifyListeners();
      }
    }
    return res;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }
}
