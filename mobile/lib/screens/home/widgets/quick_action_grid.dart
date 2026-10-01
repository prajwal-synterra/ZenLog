import 'package:flutter/material.dart';
import '../../../../core/theme/zen_colors.dart';

class QuickActionGrid extends StatelessWidget {
  final VoidCallback? onNutritionTap;
  final VoidCallback? onWorkoutTap;
  final VoidCallback? onMindTap;
  final VoidCallback? onInsightsTap;

  const QuickActionGrid({
    super.key,
    this.onNutritionTap,
    this.onWorkoutTap,
    this.onMindTap,
    this.onInsightsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildActionItem(
          label: 'Nutrition',
          icon: Icons.eco_rounded,
          color: ZenColors2.forestMedium,
          bgColor: ZenColors2.mintSoft,
          onTap: onNutritionTap,
        ),
        _buildActionItem(
          label: 'Workouts',
          icon: Icons.bolt_rounded,
          color: ZenColors2.workoutPurple,
          bgColor: ZenColors2.workoutSoft,
          onTap: onWorkoutTap,
        ),
        _buildActionItem(
          label: 'Mind & Mood',
          icon: Icons.spa_rounded,
          color: ZenColors2.forestLight,
          bgColor: ZenColors2.pillBg,
          onTap: onMindTap,
        ),
        _buildActionItem(
          label: 'AI Insights',
          icon: Icons.auto_awesome_rounded,
          color: ZenColors2.accent,
          bgColor: ZenColors2.incompleteSoft,
          onTap: onInsightsTap,
        ),
      ],
    );
  }

  Widget _buildActionItem({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ZenColors2.forestDark.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: ZenColors2.forestDark.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: bgColor.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ZenColors2.forestDark,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


