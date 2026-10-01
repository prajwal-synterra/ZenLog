import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../state/zen_state.dart';
import 'sleep_wake_storage.dart';
import '../screens/home/widgets/sleep_wake_dialogs.dart';

/// Orchestrates Feature 1: Morning prompt protocol.
///
/// Evaluated on app launch AND app resume.
/// 1. If wakePromptShown == true -> do nothing.
/// 2. If last night's sleepTime is null AND today's sleepPromptShown == false:
///    -> Show Pop-up 1 ("What time did you sleep last night?").
///    -> Save sleepTime to previous day's record, sleepPending = false, sleepPromptShown = true.
/// 3. If wakePromptShown == false:
///    -> Show Pop-up 2 ("What time did you wake up this morning?").
///    -> Save wakeTime, wakePromptShown = true.
///    -> Start morning walk countdown from wakeTime.
class MorningFlowService {
  static bool _isEvaluating = false;

  /// Main evaluation entry point called on launch and resume.
  static Future<void> evaluate(BuildContext context, ZenState state) async {
    if (_isEvaluating) return;
    _isEvaluating = true;

    try {
      if (!context.mounted) return;

      final today = state.logicalToday ?? _todayDateString();
      final yesterday = _yesterdayDateString(today);

      // Step 1: If wakePromptShown == true -> do nothing.
      final wakeShown = await SleepWakeStorage.isWakePromptShown(today);
      if (wakeShown) {
        return;
      }

      // Step 2: Check last night's sleepTime
      var lastNightSleep = await SleepWakeStorage.getSleepTime(yesterday);
      final sleepShown = await SleepWakeStorage.isSleepPromptShown(today);

      if (lastNightSleep == null && !sleepShown) {
        if (!context.mounted) return;

        // Show Pop-up 1: Non-dismissible
        final pickedTime = await SleepWakeTimeDialog.show(
          context: context,
          title: 'What time did you sleep last night?',
          subtitle: 'ZenLog links your sleep to last night so today starts with clear circadian data.',
          initialTime: const TimeOfDay(hour: 23, minute: 0),
          confirmLabel: 'Save Bedtime',
          validator: (time) {
            final now = DateTime.now();
            final candidate = SleepWakeStorage.resolveRecentPastTime(
              hour: time.hour,
              minute: time.minute,
              anchorTime: now,
            );
            final diff = now.difference(candidate);
            if (diff.inMinutes <= 0) {
              return 'Bedtime must be in the past.';
            }
            if (diff.inHours > 24) {
              return 'Bedtime must be within the last 24 hours.';
            }
            return null;
          },
        );

        if (pickedTime != null) {
          final now = DateTime.now();
          final candidateSleep = SleepWakeStorage.resolveRecentPastTime(
            hour: pickedTime.hour,
            minute: pickedTime.minute,
            anchorTime: now,
          );

          // Atomic write: save sleepTime, sleepPending = false, sleepPromptShown = true
          await SleepWakeStorage.saveYesterdaySleep(
            todayDate: today,
            yesterdayDate: yesterday,
            sleepTime: candidateSleep,
          );
          lastNightSleep = candidateSleep;

          // Sync with backend & reload previous day
          final formattedSleepTime =
              '${candidateSleep.hour.toString().padLeft(2, '0')}:${candidateSleep.minute.toString().padLeft(2, '0')}';
          state.syncSleepTime(formattedSleepTime, day: yesterday);
        }
      }

      // Step 3: If wakePromptShown == false -> Show Pop-up 2
      final stillWakeShown = await SleepWakeStorage.isWakePromptShown(today);
      if (!stillWakeShown) {
        if (!context.mounted) return;

        final defaultWake = TimeOfDay.now();

        final pickedWake = await SleepWakeTimeDialog.show(
          context: context,
          title: 'What time did you wake up this morning?',
          subtitle: 'Used to calculate your active hours and anchor your morning sunlight walk.',
          initialTime: defaultWake,
          confirmLabel: 'Save Wake Time',
          validator: (time) {
            final now = DateTime.now();
            var candidateWake = DateTime(
              now.year,
              now.month,
              now.day,
              time.hour,
              time.minute,
            );
            if (candidateWake.isAfter(now.add(const Duration(minutes: 10)))) {
              return 'Wake time cannot be in the future.';
            }

            if (lastNightSleep != null) {
              final duration = candidateWake.difference(lastNightSleep);
              if (duration.inMinutes <= 0) {
                final sleepStr = DateFormat('hh:mm a').format(lastNightSleep);
                return 'Wake time cannot be earlier than bedtime ($sleepStr).';
              }
              if (duration.inHours > 16) {
                return 'Sleep duration cannot exceed 16 hours. Please check times.';
              }
            }
            return null;
          },
        );

        if (pickedWake != null) {
          final now = DateTime.now();
          final candidateWake = DateTime(
            now.year,
            now.month,
            now.day,
            pickedWake.hour,
            pickedWake.minute,
          );

          // Atomic write: save wakeTime, wakePromptShown = true
          await SleepWakeStorage.saveTodayWake(
            todayDate: today,
            wakeTime: candidateWake,
          );

          // Sync with backend
          final formattedWakeTime =
              '${candidateWake.hour.toString().padLeft(2, '0')}:${candidateWake.minute.toString().padLeft(2, '0')}';
          await state.submitWakeTime(formattedWakeTime, day: today);

          // Update state so UI reactively shows sleep & morning walk countdown
          await state.refreshSleepWakeData();
        }
      }
    } finally {
      _isEvaluating = false;
    }
  }

  static String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _yesterdayDateString(String today) {
    final parsed = DateTime.tryParse(today) ?? DateTime.now();
    final y = parsed.subtract(const Duration(days: 1));
    return '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
  }
}
