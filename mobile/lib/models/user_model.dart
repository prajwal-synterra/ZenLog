class UserModel {
  final String userId;
  final String username;
  final String name;
  final String goal;
  final double bodyWeightKg;
  final double dailyProteinTargetG;
  final double? dailyCalorieTarget;
  final double? dailyWaterTargetMl;
  final int? weeklyWorkoutTarget;
  final bool hasPin;

  UserModel({
    required this.userId,
    required this.username,
    required this.name,
    required this.goal,
    required this.bodyWeightKg,
    required this.dailyProteinTargetG,
    this.dailyCalorieTarget,
    this.dailyWaterTargetMl,
    this.weeklyWorkoutTarget,
    this.hasPin = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['user_id'] ?? '',
      username: json['username'] ?? '',
      name: json['name'] ?? '',
      goal: json['goal'] ?? 'muscle_gain',
      bodyWeightKg: (json['body_weight_kg'] as num?)?.toDouble() ?? 70.0,
      dailyProteinTargetG:
          (json['daily_protein_target_g'] as num?)?.toDouble() ?? 126.0,
      dailyCalorieTarget: (json['daily_calorie_target'] as num?)?.toDouble(),
      dailyWaterTargetMl: (json['daily_water_target_ml'] as num?)?.toDouble() ?? 3000.0,
      weeklyWorkoutTarget: (json['weekly_workout_target'] as num?)?.toInt() ?? 3,
      hasPin: json['has_pin'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'username': username,
      'name': name,
      'goal': goal,
      'body_weight_kg': bodyWeightKg,
      'daily_protein_target_g': dailyProteinTargetG,
      'daily_calorie_target': dailyCalorieTarget,
      'daily_water_target_ml': dailyWaterTargetMl,
      'weekly_workout_target': weeklyWorkoutTarget,
      'has_pin': hasPin,
    };
  }

  UserModel copyWith({
    String? userId,
    String? username,
    String? name,
    String? goal,
    double? bodyWeightKg,
    double? dailyProteinTargetG,
    double? dailyCalorieTarget,
    double? dailyWaterTargetMl,
    int? weeklyWorkoutTarget,
    bool? hasPin,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      name: name ?? this.name,
      goal: goal ?? this.goal,
      bodyWeightKg: bodyWeightKg ?? this.bodyWeightKg,
      dailyProteinTargetG: dailyProteinTargetG ?? this.dailyProteinTargetG,
      dailyCalorieTarget: dailyCalorieTarget ?? this.dailyCalorieTarget,
      dailyWaterTargetMl: dailyWaterTargetMl ?? this.dailyWaterTargetMl,
      weeklyWorkoutTarget: weeklyWorkoutTarget ?? this.weeklyWorkoutTarget,
      hasPin: hasPin ?? this.hasPin,
    );
  }
}
