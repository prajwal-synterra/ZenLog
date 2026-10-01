import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/api_service.dart';
import '../../services/sleep_wake_storage.dart';
import '../../models/day_record_model.dart';

class SleepScannerScreen extends StatefulWidget {
  const SleepScannerScreen({super.key});

  @override
  State<SleepScannerScreen> createState() => _SleepScannerScreenState();
}

class _SleepScannerScreenState extends State<SleepScannerScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late AnimationController _pulseController;

  String _sleepTime = DateFormat('HH:mm').format(DateTime.now());
  bool _isProcessing = false;
  DailyRecordModel? _resultRecord;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _processDay() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final record = await _api.submitSleep(_sleepTime);
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await SleepWakeStorage.saveNightSleepNow(todayDate: todayStr, sleepTime: now);
      setState(() {
        _resultRecord = record;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZenColors2.forestDark,
      body: SafeArea(
        child: Stack(
          children: [
            // Top Navigation Bar
            Positioned(
              top: 12,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const Text(
                    'AI Daily Scanner',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: ZenColors2.mintGlow,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),

            // Middle Viewfinder Image (Matches the Monstera Scan in reference)
            Positioned.fill(
              top: 70,
              bottom: 240,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/images/scan_visual.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),

                      // Animated Glowing Scanner Reticle
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = 0.95 + (_pulseController.value * 0.05);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 240,
                              height: 240,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: ZenColors2.mintGlow.withOpacity(
                                      0.6 + (_pulseController.value * 0.4)),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: ZenColors2.mintGlow.withOpacity(0.2),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      // Floating tag overlay
                      Positioned(
                        bottom: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.radar_rounded,
                                  color: ZenColors2.mintGlow, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'AI Fact Parser Active',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Sliding Sheet (Matches the reference bottom sheet)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 30,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle Pill
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: ZenColors2.textSubtle.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _resultRecord != null
                                  ? 'Synthesized...'
                                  : 'Sleep & Nightly Close',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: ZenColors2.textMuted,
                              ),
                            ),
                            const Text(
                              'AI Macro Extraction',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: ZenColors2.forestDark,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ],
                        ),
                        // Match tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: ZenColors2.mintSoft,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Text(
                            '100% Parsed',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ZenColors2.forestDark,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _isProcessing ? null : 1.0,
                        minHeight: 6,
                        backgroundColor: ZenColors2.pillBg,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            ZenColors2.emeraldAccent),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Sleep Time Input Pill
                    Row(
                      children: [
                        const Icon(Icons.bedtime_rounded,
                            size: 18, color: ZenColors2.forestMedium),
                        const SizedBox(width: 8),
                        Text(
                          'Sleep Time:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ZenColors2.forestDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: ZenColors2.pillBg,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            _sleepTime,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ZenColors2.forestDark,
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_errorMessage != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],

                    // CTA Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _processDay,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZenColors2.forestDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                          elevation: 0,
                        ),
                        child: _isProcessing
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Gemini AI Extracting...',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            )
                          : Text(
                              _resultRecord != null
                                  ? 'Done! Return to Journal ✓'
                                  : 'Run Extraction & Sleep 🌙',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


