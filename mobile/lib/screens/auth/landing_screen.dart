import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/auth_storage.dart';
import '../../services/api_service.dart';
import 'login_screen.dart';
import 'day_ready_loading_screen.dart';

// ZenLog v3 §6.1 Splash & §6.2 Welcome carousel
// Ink & Paper design. Pure typography + UI fragments. No stock photos, no emoji in chrome.

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  @override
  void initState() {
    super.initState();
    _checkExistingToken();
  }

  Future<void> _checkExistingToken() async {
    final token = await AuthStorage.getToken();
    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      ApiService().setToken(token);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DayReadyLoadingScreen()),
      );
    }
  }

  void _goToLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ── Brand ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'ZenLog',
                    style: GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    '•',
                    style: TextStyle(
                      color: t.accent,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 2),

              // ── Hero text ──
              Text(
                'Write your day.\nWe\'ll do the math.',
                style: GoogleFonts.fraunces(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                  height: 1.15,
                ),
              ),

              const SizedBox(height: 20),

              // ── Fake composer ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Write what you ate, did or felt…',
                          style: TextStyle(color: t.inkFaint, fontSize: 15),
                        ),
                        const Spacer(),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: t.ink,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.arrow_upward_rounded, size: 18, color: t.onInk),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Sample chips
                    Wrap(
                      spacing: 8,
                      children: [
                        _SampleChip(label: '+19 g protein', bg: t.successTint, text: t.successText),
                        _SampleChip(label: '315 kcal', bg: t.surfaceAlt, text: t.inkMuted),
                        _SampleChip(label: '500 ml', bg: t.infoTint, text: t.infoText),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Mini pace bar ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('PACE', style: TextStyle(color: t.inkFaint, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(color: t.warnTint, borderRadius: BorderRadius.circular(999)),
                          child: Text('Behind', style: TextStyle(color: t.warnText, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Protein', style: TextStyle(color: t.inkMuted, fontSize: 12)),
                        const Spacer(),
                        Text('88 / 126 g', style: TextStyle(color: t.ink, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          Container(height: 8, color: t.surfaceAlt),
                          Container(width: size.width * 0.42, height: 8, color: t.warnFill),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // ── CTA ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _goToLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.ink,
                    foregroundColor: t.onInk,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Get started',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color text;
  const _SampleChip({required this.label, required this.bg, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

