class DayPromptStatusModel {
  final String today;
  final String yesterday;
  final bool needsYesterdaySleep;
  final bool needsTodayWake;
  final String? yesterdayStatus;
  final String? todayStatus;
  final String? yesterdaySleepTime;
  final String? todayWakeTime;

  DayPromptStatusModel({
    required this.today,
    required this.yesterday,
    required this.needsYesterdaySleep,
    required this.needsTodayWake,
    this.yesterdayStatus,
    this.todayStatus,
    this.yesterdaySleepTime,
    this.todayWakeTime,
  });

  factory DayPromptStatusModel.fromJson(Map<String, dynamic> json) {
    return DayPromptStatusModel(
      today: json['today']?.toString() ?? '',
      yesterday: json['yesterday']?.toString() ?? '',
      needsYesterdaySleep: json['needs_yesterday_sleep'] == true,
      needsTodayWake: json['needs_today_wake'] == true,
      yesterdayStatus: json['yesterday_status']?.toString(),
      todayStatus: json['today_status']?.toString(),
      yesterdaySleepTime: json['yesterday_sleep_time']?.toString(),
      todayWakeTime: json['today_wake_time']?.toString(),
    );
  }
}
