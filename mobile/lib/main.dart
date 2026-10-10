import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/zen_theme.dart';
import 'core/theme/zen_theme_controller.dart';
import 'screens/auth/landing_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ZenThemeController.instance.init();
  await NotificationService().init();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ZenLogApp());
}

class ZenLogApp extends StatelessWidget {
  const ZenLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ZenThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'ZenLog',
          debugShowCheckedModeBanner: false,
          theme: ZenTheme.lightTheme,
          darkTheme: ZenTheme.darkTheme,
          themeMode: ZenThemeController.instance.themeMode,
          home: const LandingScreen(),
          routes: {
            '/login': (_) => const LoginScreen(),
          },
        );
      },
    );
  }
}

