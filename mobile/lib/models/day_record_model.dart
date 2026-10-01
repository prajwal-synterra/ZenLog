class DailyRecordModel {
  final String recordId;
  final String userId;
  final String date;
  final String status;
  final Map<String, dynamic> sleep;
  final Map<String, dynamic> wake;
  final Map<String, dynamic> nutrition;
  final Map<String, dynamic> fitness;
  final Map<String, dynamic> learning;
  final Map<String, dynamic> habits;
  final Map<String, dynamic> mood;
  final Map<String, dynamic> insights;
  final Map<String, dynamic> processing;

  DailyRecordModel({
    required this.recordId,
    required this.userId,
    required this.date,
    required this.status,
    this.sleep = const {},
    this.wake = const {},
    this.nutrition = const {},
    this.fitness = const {},
    this.learning = const {},
    this.habits = const {},
    this.mood = const {},
    this.insights = const {},
    this.processing = const {},
  });

  factory DailyRecordModel.fromJson(Map<String, dynamic> json) {
    return DailyRecordModel(
      recordId: json['record_id'] ?? json['id'] ?? '',
      userId: json['user_id'] ?? '',
      date: json['date'] ?? '',
      status: json['status'] ?? 'OPEN',
      sleep: json['sleep'] ?? {},
      wake: json['wake'] ?? {},
      nutrition: json['nutrition'] ?? {},
      fitness: json['fitness'] ?? {},
      learning: json['learning'] ?? {},
      habits: json['habits'] ?? {},
      mood: json['mood'] ?? {},
      insights: json['insights'] ?? {},
      processing: json['processing'] ?? {},
    );
  }

  // Wake & Sleep Getters
  String? get wakeTime => wake['wake_time'] as String?;
  String? get sleepTime => sleep['sleep_time'] as String?;

  // Helpers
  double get totalProtein =>
      (nutrition['daily_totals']?['protein_g'] as num?)?.toDouble() ?? 0.0;

  double get proteinTarget =>
      (nutrition['daily_totals']?['protein_target_g'] as num?)?.toDouble() ?? 126.0;

  double get targetPercentage =>
      (nutrition['daily_totals']?['target_percentage'] as num?)?.toDouble() ?? 0.0;

  double get remainingProtein =>
      (nutrition['daily_totals']?['remaining_protein_g'] as num?)?.toDouble() ?? 0.0;

  int get hydrationMl =>
      (nutrition['daily_totals']?['hydration_ml'] as num?)?.toInt() ?? 0;

  double get caloriesKcal =>
      (nutrition['daily_totals']?['calories_kcal'] as num?)?.toDouble() ?? 0.0;

  List<dynamic> get meals => nutrition['meals'] as List<dynamic>? ?? [];
  List<dynamic> get workouts => fitness['workouts'] as List<dynamic>? ?? [];
  List<dynamic> get learningActivities => learning['activities'] as List<dynamic>? ?? [];
  List<dynamic> get habitObservations => habits['observations'] as List<dynamic>? ?? [];
  List<dynamic> get moodObservations => mood['observations'] as List<dynamic>? ?? [];
}
