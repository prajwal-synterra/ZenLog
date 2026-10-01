import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/api_service.dart';
import '../../services/auth_storage.dart';
import '../main_scaffold.dart';

class DayReadyLoadingScreen extends StatefulWidget {
  const DayReadyLoadingScreen({super.key});

  @override
  State<DayReadyLoadingScreen> createState() => _DayReadyLoadingScreenState();
}

class _DayReadyLoadingScreenState extends State<DayReadyLoadingScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  double _progress = 0.20;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _startSyncProcess();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startSyncProcess() async {
    // Step 1: Token validation
    setState(() => _progress = 0.3);
    final token = await AuthStorage.getToken();
    if (token != null && token.isNotEmpty) {
      _api.setToken(token);
    }

    // Step 2: Validate token with server (rolling refresh happens here)
    setState(() => _progress = 0.5);
    final me = await _api.getMe();
    if (me == null) {
      // Token invalid: clear and redirect to login
      await AuthStorage.clearToken();
      _api.clearToken();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    // Step 3: Token valid, proceed to app
    setState(() => _progress = 0.8);
    await Future.delayed(const Duration(milliseconds: 200));

    // Step 4: Finalize
    setState(() => _progress = 1.0);
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => const MainScaffold(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated ring
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1.0 + (_pulseController.value * 0.06);
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t.surfaceAlt,
                          border: Border.all(color: t.line, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            'ZL',
                            style: GoogleFonts.fraunces(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 36),

                Text(
                  'Setting things up…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Loading your journal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: t.inkMuted,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 32),

                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    width: 160,
                    height: 4,
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: t.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation<Color>(t.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

