import 'package:flutter/foundation.dart';

class ApiConstants {
  // Use 10.0.2.2 for Android emulator, 127.0.0.1 for Web and Windows desktop
  static String get baseUrl {
    return 'https://zenlog-zma5.onrender.com';
  }

  // Endpoints
  static const String login = '/api/auth/login';
  static const String logout = '/api/auth/logout';
  static const String userMe = '/api/users/me';
  static const String logs = '/api/logs';
  static const String todayLogs = '/api/logs/today';
  static const String sleep = '/api/days/sleep';
  static const String wake = '/api/days/wake';
  static const String promptStatus = '/api/days/prompt-status';
  static const String calendar = '/api/calendar';
  static const String statsDaily = '/api/stats/daily';
  static const String statsWeekly = '/api/stats/weekly';
  static const String statsMonthly = '/api/stats/monthly';
  static const String insightsWeekly = '/api/insights/weekly';
  static const String insightsMonthly = '/api/insights/monthly';
}
