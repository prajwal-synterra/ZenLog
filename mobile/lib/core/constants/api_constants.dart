class ApiConstants {
  // Toggle between Ngrok (local testing) and Render (production)
  static const bool useNgrok = false;
  static const String ngrokUrl = 'https://dawdlingly-pseudoinsane-pa.ngrok-free.dev';
  static const String renderUrl = 'https://zenlog-k0la.onrender.com';

  static String get baseUrl {
    const fromEnv = String.fromEnvironment('BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return useNgrok ? ngrokUrl : renderUrl;
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
  static const String photoAnalyze = '/api/logs/photo/analyze';
  static const String foodScan = '/api/foods/scan';
  static const String foodProducts = '/api/foods/products';
}
