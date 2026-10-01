import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/services/sleep_wake_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Feature 1 & Feature 3: Sleep & Wake Storage & Calculations', () {
    test('Test Case 1: First open of the day - saves yesterday sleep and today wake atomically', () async {
      const today = '2026-10-02';
      const yesterday = '2026-10-01';

      // Initially flags are false
      expect(await SleepWakeStorage.isSleepPromptShown(today), isFalse);
      expect(await SleepWakeStorage.isWakePromptShown(today), isFalse);
      expect(await SleepWakeStorage.getSleepTime(yesterday), isNull);
      expect(await SleepWakeStorage.getWakeTime(today), isNull);

      // Answer Pop-up 1 (Bedtime 11:30 PM on Oct 1)
      final sleepTime = DateTime(2026, 10, 1, 23, 30);
      await SleepWakeStorage.saveYesterdaySleep(
        todayDate: today,
        yesterdayDate: yesterday,
        sleepTime: sleepTime,
      );

      // Verify Pop-up 1 atomic write
      expect(await SleepWakeStorage.isSleepPromptShown(today), isTrue);
      expect(await SleepWakeStorage.isSleepPending(yesterday), isFalse);
      expect(await SleepWakeStorage.getSleepTime(yesterday), equals(sleepTime));

      // Pop-up 2 is still not shown
      expect(await SleepWakeStorage.isWakePromptShown(today), isFalse);

      // Answer Pop-up 2 (Wake time 07:00 AM on Oct 2)
      final wakeTime = DateTime(2026, 10, 2, 7, 0);
      await SleepWakeStorage.saveTodayWake(
        todayDate: today,
        wakeTime: wakeTime,
      );

      // Verify Pop-up 2 atomic write
      expect(await SleepWakeStorage.isWakePromptShown(today), isTrue);
      expect(await SleepWakeStorage.getWakeTime(today), equals(wakeTime));

      // Verify derived duration on read
      final duration = await SleepWakeStorage.calculateSleepDuration(
        wakeDate: today,
        nightDate: yesterday,
      );
      expect(duration, isNotNull);
      expect(duration!.inHours, equals(7));
      expect(duration.inMinutes.remainder(60), equals(30));
      expect(SleepWakeStorage.formatDuration(duration), equals('7h 30m'));
    });

    test('Test Case 2: Reopening 5 times after answering - flags remain true, no popups', () async {
      const today = '2026-10-02';
      final wakeTime = DateTime(2026, 10, 2, 7, 0);
      await SleepWakeStorage.saveTodayWake(todayDate: today, wakeTime: wakeTime);

      for (int i = 0; i < 5; i++) {
        final wakeShown = await SleepWakeStorage.isWakePromptShown(today);
        expect(wakeShown, isTrue, reason: 'Reopen #$i must return true and show zero popups');
      }
    });

    test('Test Case 3: App killed between Pop-up 1 and Pop-up 2', () async {
      const today = '2026-10-02';
      const yesterday = '2026-10-01';

      // Answer Pop-up 1
      final sleepTime = DateTime(2026, 10, 1, 23, 0);
      await SleepWakeStorage.saveYesterdaySleep(
        todayDate: today,
        yesterdayDate: yesterday,
        sleepTime: sleepTime,
      );

      // User kills app and restarts
      // Check state on restart:
      final sleepShown = await SleepWakeStorage.isSleepPromptShown(today);
      final wakeShown = await SleepWakeStorage.isWakePromptShown(today);

      // Pop-up 1 is NOT re-prompted because sleepPromptShown == true
      expect(sleepShown, isTrue);
      // Pop-up 2 resumes immediately because wakePromptShown == false
      expect(wakeShown, isFalse);

      // Now user answers Pop-up 2
      final wakeTime = DateTime(2026, 10, 2, 6, 45);
      await SleepWakeStorage.saveTodayWake(todayDate: today, wakeTime: wakeTime);

      expect(await SleepWakeStorage.isWakePromptShown(today), isTrue);
      final duration = await SleepWakeStorage.calculateSleepDuration(
        wakeDate: today,
        nightDate: yesterday,
      );
      expect(SleepWakeStorage.formatDuration(duration), equals('7h 45m'));
    });

    test('Test Case 4: Sleep after midnight (1:30 AM bedtime, 8:00 AM wake)', () {
      final wakeTime = DateTime(2026, 10, 2, 8, 0);

      // User inputs 1:30 AM
      final resolvedBedtime = SleepWakeStorage.resolveRecentPastTime(
        hour: 1,
        minute: 30,
        anchorTime: wakeTime,
      );

      // Candidate is on the same calendar day (Oct 2 at 01:30 AM), 6.5h prior to 08:00 AM
      expect(resolvedBedtime, equals(DateTime(2026, 10, 2, 1, 30)));
      final duration = wakeTime.difference(resolvedBedtime);
      expect(duration.inHours, equals(6));
      expect(duration.inMinutes.remainder(60), equals(30));
      expect(duration.inMinutes > 0, isTrue);
      expect(duration.inHours <= 16, isTrue);
      expect(SleepWakeStorage.formatDuration(duration), equals('6h 30m'));
    });

    test('Test Case 4b: Sleep before midnight (11:30 PM bedtime, 7:00 AM wake)', () {
      final wakeTime = DateTime(2026, 10, 2, 7, 0);

      // User inputs 11:30 PM (23:30)
      final resolvedBedtime = SleepWakeStorage.resolveRecentPastTime(
        hour: 23,
        minute: 30,
        anchorTime: wakeTime,
      );

      // Candidate is on yesterday (Oct 1 at 23:30 PM), 7.5h prior to 07:00 AM
      expect(resolvedBedtime, equals(DateTime(2026, 10, 1, 23, 30)));
      final duration = wakeTime.difference(resolvedBedtime);
      expect(duration.inHours, equals(7));
      expect(duration.inMinutes.remainder(60), equals(30));
      expect(duration.inMinutes > 0, isTrue);
      expect(duration.inHours <= 16, isTrue);
      expect(SleepWakeStorage.formatDuration(duration), equals('7h 30m'));
    });

    test('Test Case 5: Ask me tomorrow path & Feature 2 Night submit', () async {
      const today = '2026-10-01';
      const nextDay = '2026-10-02';

      // User taps Submit Report at night and chooses "No, ask me tomorrow morning"
      await SleepWakeStorage.saveNightAskTomorrow(todayDate: today);

      // Verify night prompt was shown for today
      expect(await SleepWakeStorage.isNightPromptShown(today), isTrue);
      expect(await SleepWakeStorage.isSleepPending(today), isTrue);
      expect(await SleepWakeStorage.getSleepTime(today), isNull);

      // Next morning (Oct 2), last night's sleep is null and sleepPromptShown is false
      expect(await SleepWakeStorage.getSleepTime(today), isNull);
      expect(await SleepWakeStorage.isSleepPromptShown(nextDay), isFalse);
      // This correctly triggers Pop-up 1 on next morning!
    });

    test('Test Case 6: Submitting report twice on the same night', () async {
      const today = '2026-10-01';

      // First submit: user selects "Yes, I'm going to sleep now"
      final now = DateTime(2026, 10, 1, 23, 15);
      await SleepWakeStorage.saveNightSleepNow(todayDate: today, sleepTime: now);

      expect(await SleepWakeStorage.isNightPromptShown(today), isTrue);
      expect(await SleepWakeStorage.getSleepTime(today), equals(now));

      // Second submit later that night: nightPromptShown is already true -> bypassed
      final alreadyShown = await SleepWakeStorage.isNightPromptShown(today);
      expect(alreadyShown, isTrue);
    });

    test('Test Case 7: Multiple missed days', () async {
      const today = '2026-10-05'; // Monday
      const yesterday = '2026-10-04'; // Sunday
      const friday = '2026-10-02';

      // Friday has no sleep or wake data
      final fridayDuration = await SleepWakeStorage.calculateSleepDuration(
        wakeDate: friday,
        nightDate: '2026-10-01',
      );
      // Older missing days stay "—" / no data, never 0h
      expect(SleepWakeStorage.formatDuration(fridayDuration), equals('—'));

      // On Monday, Pop-up 1 asks for yesterday (Sunday night Oct 4)
      final sleepTime = DateTime(2026, 10, 4, 23, 0);
      await SleepWakeStorage.saveYesterdaySleep(
        todayDate: today,
        yesterdayDate: yesterday,
        sleepTime: sleepTime,
      );

      final wakeTime = DateTime(2026, 10, 5, 7, 0);
      await SleepWakeStorage.saveTodayWake(
        todayDate: today,
        wakeTime: wakeTime,
      );

      final mondayDuration = await SleepWakeStorage.calculateSleepDuration(
        wakeDate: today,
        nightDate: yesterday,
      );
      expect(SleepWakeStorage.formatDuration(mondayDuration), equals('8h'));
    });

    test('Duration format edge cases: never 0h', () {
      expect(SleepWakeStorage.formatDuration(null), equals('—'));
      expect(SleepWakeStorage.formatDuration(Duration.zero), equals('—'));
      expect(SleepWakeStorage.formatDuration(const Duration(minutes: -10)), equals('—'));
      expect(SleepWakeStorage.formatDuration(const Duration(hours: 7, minutes: 20)), equals('7h 20m'));
      expect(SleepWakeStorage.formatDuration(const Duration(hours: 8, minutes: 0)), equals('8h'));
    });
  });
}
