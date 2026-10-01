import 'package:flutter/material.dart';
import '../../../../core/theme/zen_colors.dart';
import '../../../../models/day_record_model.dart';
import '../../scanner/sleep_scanner_screen.dart';

class HeroSleepCard extends StatelessWidget {
  final DailyRecordModel? record;
  final VoidCallback? onProcessComplete;

  const HeroSleepCard({
    super.key,
    this.record,
    this.onProcessComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = record?.status == 'COMPLETED';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: ZenColors2.forestDark.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: ZenColors2.forestDark.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background ambient gradient
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 140,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(26),
                  bottomRight: Radius.circular(26),
                ),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withOpacity(0.0),
                    ZenColors2.mintSoft.withOpacity(0.5),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left Column: Text & CTA Button
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? ZenColors2.mintSoft
                              : ZenColors2.pillBg,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          isCompleted
                              ? '✓ Day Synthesized'
                              : 'AI Daily Scan & Sleep',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCompleted
                                ? ZenColors2.forestDark
                                : ZenColors2.forestMedium,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      Text(
                        isCompleted ? 'Today\'s Macro Flow' : 'Close Day & Sleep',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ZenColors2.forestDark,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),

                      Text(
                        isCompleted
                            ? '${record?.totalProtein.toStringAsFixed(0)}g / ${record?.proteinTarget.toStringAsFixed(0)}g protein (${record?.targetPercentage.toStringAsFixed(0)}%)'
                            : 'Log sleep time to extract macros & synthesize journal.',
                        style: TextStyle(
                          fontSize: 12,
                          color: ZenColors2.textMuted,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // CTA Pill Button
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SleepScannerScreen(),
                            ),
                          ).then((_) {
                            onProcessComplete?.call();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: ZenColors2.forestDark,
                            borderRadius: BorderRadius.circular(100),
                            boxShadow: [
                              BoxShadow(
                                color: ZenColors2.forestDark.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isCompleted ? 'View Full AI Scan' : 'Process Day',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Right Image: 3D Plant Asset (matches the reference card)
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 115,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.8),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ZenColors2.forestDark.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/images/home_card_plant.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


