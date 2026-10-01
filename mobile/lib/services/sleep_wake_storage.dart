import 'package:shared_preferences/shared_preferences.dart';

/// Persistent storage for sleep & wake timestamps and daily prompt protocol flags.
///
/// Every write operation writes the data and the corresponding flag together
/// in the same transaction so data and flags can never disagree.
/// Flags are date-keyed so each day's prompts are evaluated independently and
/// at most ONCE per day.
class SleepWakeStorage {
  static const String _prefixSleepTime = 'zen_sleep_time_';
  static const String _prefixWakeTime = 'zen_wake_time_';
  static const String _prefixSleepPending = 'zen_sleep_pending_';
  static const String _prefixSleepPromptShown = 'zen_sleep_prompt_shown_';
  static const String _prefixWakePromptShown = 'zen_wake_prompt_shown_';
  static const String _prefixNightPromptShown = 'zen_night_prompt_shown_';

  // ─── Atomic Writes ────────────────────────────────────────────────────────

  /// Saves Pop-up 1 answer: records sleepTime for yesterday's night,
  /// marks sleepPending = false, and marks today's sleepPromptShown = true.
  static Future<void> saveYesterdaySleep({
    required String todayDate,
    required String yesterdayDate,
    required DateTime sleepTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('$_prefixSleepTime$yesterdayDate', sleepTime.toIso8601String()),
      prefs.setBool('$_prefixSleepPending$yesterdayDate', false),
      prefs.setBool('$_prefixSleepPromptShown$todayDate', true),
    ]);
  }

  /// Saves Pop-up 2 answer: records wakeTime for today and marks
  /// today's wakePromptShown = true.
  static Future<void> saveTodayWake({
    required String todayDate,
    required DateTime wakeTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('$_prefixWakeTime$todayDate', wakeTime.toIso8601String()),
      prefs.setBool('$_prefixWakePromptShown$todayDate', true),
    ]);
  }

  /// Saves Night Option A ("Yes, I'm going to sleep now"):
  /// records sleepTime = now, sleepPending = false, and nightPromptShown = true.
  static Future<void> saveNightSleepNow({
    required String todayDate,
    required DateTime sleepTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('$_prefixSleepTime$todayDate', sleepTime.toIso8601String()),
      prefs.setBool('$_prefixSleepPending$todayDate', false),
      prefs.setBool('$_prefixNightPromptShown$todayDate', true),
    ]);
  }

  /// Saves Night Option B ("No, ask me tomorrow morning"):
  /// sleepTime = null, sleepPending = true, and nightPromptShown = true.
  static Future<void> saveNightAskTomorrow({
    required String todayDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove('$_prefixSleepTime$todayDate'),
      prefs.setBool('$_prefixSleepPending$todayDate', true),
      prefs.setBool('$_prefixNightPromptShown$todayDate', true),
    ]);
  }

  // ─── Reads ────────────────────────────────────────────────────────────────

  static Future<DateTime?> getSleepTime(String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString('$_prefixSleepTime$date');
      return val != null ? DateTime.tryParse(val) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> getWakeTime(String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString('$_prefixWakeTime$date');
      return val != null ? DateTime.tryParse(val) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isSleepPending(String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_prefixSleepPending$date') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isSleepPromptShown(String todayDate) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_prefixSleepPromptShown$todayDate') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isWakePromptShown(String todayDate) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_prefixWakePromptShown$todayDate') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isNightPromptShown(String todayDate) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_prefixNightPromptShown$todayDate') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ─── Derived Calculations ─────────────────────────────────────────────────

  /// Computes duration = wakeTime - sleepTime for a wake date [wakeDate],
  /// where the night belongs to [nightDate].
  /// Returns null if either timestamp is absent or duration <= 0.
  static Future<Duration?> calculateSleepDuration({
    required String wakeDate,
    required String nightDate,
  }) async {
    final wake = await getWakeTime(wakeDate);
    final sleep = await getSleepTime(nightDate);
    if (wake == null || sleep == null) return null;
    final diff = wake.difference(sleep);
    return diff.isNegative ? null : diff;
  }

  /// Formats duration to "7h 20m", or "—" if null. Never outputs "0h".
  static String formatDuration(Duration? duration) {
    if (duration == null || duration.inMinutes <= 0) return '—';
    final hours = duration.inHours;
    final mins = duration.inMinutes.remainder(60);
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  /// Resolves a time-of-day input (e.g. 23:30 or 01:30) to the most recent past
  /// DateTime within 24 hours strictly prior to [anchorTime].
  /// For instance, if anchorTime is 07:00 AM on Oct 2:
  /// - 11:30 PM resolves to Oct 1 11:30 PM (7.5h prior)
  /// - 01:30 AM resolves to Oct 2 01:30 AM (5.5h prior)
  static DateTime resolveRecentPastTime({
    required int hour,
    required int minute,
    required DateTime anchorTime,
  }) {
    var candidate = DateTime(
      anchorTime.year,
      anchorTime.month,
      anchorTime.day,
      hour,
      minute,
    );
    // If candidate is greater than or equal to anchorTime, it must have occurred yesterday
    if (!candidate.isBefore(anchorTime)) {
      candidate = candidate.subtract(const Duration(days: 1));
    }
    return candidate;
  }

  /// Computes average sleep duration across the given [daysCount] prior to [anchorDate].
  static Future<Duration?> getAverageSleepDuration({
    int daysCount = 7,
    DateTime? anchorDate,
  }) async {
    final anchor = anchorDate ?? DateTime.now();
    int totalMinutes = 0;
    int validDays = 0;

    for (int i = 0; i < daysCount; i++) {
      final date = anchor.subtract(Duration(days: i));
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final prevDate = date.subtract(const Duration(days: 1));
      final prevDateStr =
          '${prevDate.year}-${prevDate.month.toString().padLeft(2, '0')}-${prevDate.day.toString().padLeft(2, '0')}';

      final wake = await getWakeTime(dateStr);
      final sleep = await getSleepTime(prevDateStr);

      if (wake != null && sleep != null) {
        final diff = wake.difference(sleep);
        if (!diff.isNegative && diff.inMinutes > 0 && diff.inHours <= 16) {
          totalMinutes += diff.inMinutes;
          validDays++;
        }
      }
    }

    if (validDays == 0) return null;
    return Duration(minutes: (totalMinutes / validDays).round());
  }
}
