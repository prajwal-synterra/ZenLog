import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/zen_colors.dart';

/// Morning Walk Countdown Card
/// Triggered right after wakeTime is recorded. Encourages circadian morning walk/sunlight.
/// Default window: 60 minutes from wake time, target: 20-30 min walk.
class MorningWalkCard extends StatefulWidget {
  final DateTime wakeTime;
  final int windowMinutes;
  final VoidCallback? onCompleted;

  const MorningWalkCard({
    super.key,
    required this.wakeTime,
    this.windowMinutes = 60,
    this.onCompleted,
  });

  @override
  State<MorningWalkCard> createState() => _MorningWalkCardState();
}

class _MorningWalkCardState extends State<MorningWalkCard> {
  Timer? _timer;
  late Duration _remaining;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _calculateRemaining());
  }

  void _calculateRemaining() {
    final now = DateTime.now();
    final deadline = widget.wakeTime.add(Duration(minutes: widget.windowMinutes));
    final diff = deadline.difference(now);

    if (diff.isNegative) {
      if (!_isExpired && mounted) {
        setState(() {
          _remaining = Duration.zero;
          _isExpired = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _remaining = diff;
          _isExpired = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    final mins = _remaining.inMinutes;
    final secs = _remaining.inSeconds.remainder(60);
    final timeStr =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          // Icon Circle
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _isExpired ? t.surfaceAlt : t.warnTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                Icons.directions_walk_rounded,
                color: _isExpired ? t.inkMuted : t.warnFill,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'MORNING CIRCADIAN WALK',
                      style: TextStyle(
                        color: t.inkFaint,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _isExpired
                      ? 'Morning window completed'
                      : 'Step outside for sunlight & movement',
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Countdown Timer Pill
          if (!_isExpired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.line),
              ),
              child: Text(
                timeStr,
                style: GoogleFonts.fraunces(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
