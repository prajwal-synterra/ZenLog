import 'package:flutter/material.dart';
import '../core/theme/zen_colors.dart';
import 'main_scaffold.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _leafController;

  @override
  void initState() {
    super.initState();
    _leafController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _leafController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: ZenColors2.sageBg,
      body: SafeArea(
        child: Stack(
          children: [
            // Decorative background vertical lines like the reference UI
            Positioned(
              right: 48,
              top: 80,
              bottom: 120,
              child: Row(
                children: [
                  Container(
                    width: 1,
                    color: ZenColors2.forestMedium.withOpacity(0.08),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    color: ZenColors2.forestMedium.withOpacity(0.12),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 1,
                    color: ZenColors2.forestMedium.withOpacity(0.06),
                  ),
                ],
              ),
            ),

            // Main Content Layout
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Social Proof & Menu Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Social Proof Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: ZenColors2.forestDark.withOpacity(0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: ZenColors2.forestDark.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Overlapping mini avatars
                            SizedBox(
                              width: 38,
                              height: 20,
                              child: Stack(
                                children: [
                                  _buildMiniAvatar(0, Colors.teal.shade200),
                                  _buildMiniAvatar(10, Colors.green.shade300),
                                  _buildMiniAvatar(20, Colors.teal.shade400),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Loved by',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: ZenColors2.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '10k+ Mindful Humans',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: ZenColors2.forestDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Settings / Dots indicator
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ZenColors2.forestDark.withOpacity(0.08),
                          ),
                        ),
                        child: const Icon(
                          Icons.eco_rounded,
                          size: 18,
                          color: ZenColors2.forestMedium,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // High-impact Two-tone Headline
                  Text(
                    'Mindful',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: ZenColors2.forestDark,
                      height: 1.05,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'Daily Flow',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: ZenColors2.forestMedium,
                      height: 1.05,
                      letterSpacing: -1,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Subtitle
                  Row(
                    children: [
                      const Text('🌱 ', style: TextStyle(fontSize: 14)),
                      Text(
                        'AI journal & nutrition intelligence on the go',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ZenColors2.textMuted,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Hero Plant Asset with subtle floating leaves animation
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Soft botanical glow ring
                        Container(
                          width: size.width * 0.75,
                          height: size.width * 0.75,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                ZenColors2.mintGlow.withOpacity(0.4),
                                ZenColors2.sageBg.withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),

                        // Hero 3D Render Image
                        ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: SizedBox(
                            width: size.width * 0.78,
                            height: 280,
                            child: Image.asset(
                              'assets/images/onboarding_hero.jpg',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),

                        // Animated Floating Leaf
                        AnimatedBuilder(
                          animation: _leafController,
                          builder: (context, child) {
                            return Positioned(
                              top: 20 + (_leafController.value * 12),
                              right: 15,
                              child: Transform.rotate(
                                angle: 0.2 + (_leafController.value * 0.1),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.85),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: ZenColors2.forestDark.withOpacity(0.06),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.spa_rounded,
                                    size: 16,
                                    color: ZenColors2.emeraldAccent,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Bottom Action Pill Button (matches the reference design)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const MainScaffold(),
                          transitionsBuilder: (_, animation, __, child) =>
                              FadeTransition(opacity: animation, child: child),
                          transitionDuration:
                              const Duration(milliseconds: 400),
                        ),
                      );
                    },
                    child: Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: ZenColors2.forestDark,
                        borderRadius: BorderRadius.circular(100),
                        boxShadow: [
                          BoxShadow(
                            color: ZenColors2.forestDark.withOpacity(0.25),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 8.0),
                            child: Text(
                              'Begin Journey',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          // Circular arrow button
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: ZenColors2.forestMedium,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Already have an account link
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const MainScaffold()),
                        );
                      },
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            color: ZenColors2.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                          children: const [
                            TextSpan(text: 'Already have an account? '),
                            TextSpan(
                              text: 'Sign in',
                              style: TextStyle(
                                color: ZenColors2.forestDark,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniAvatar(double left, Color color) {
    return Positioned(
      left: left,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      ),
    );
  }
}

