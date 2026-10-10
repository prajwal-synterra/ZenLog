import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for background isolate handling
  await Firebase.initializeApp();
  if (kDebugMode) {
    print('Handling background notification: ${message.messageId} - ${message.notification?.title}');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  Future<void> init() async {
    try {
      await Firebase.initializeApp();

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request user permissions
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (kDebugMode) {
        print('Notification permission status: ${settings.authorizationStatus}');
      }

      // Fetch FCM Token
      _fcmToken = await messaging.getToken();
      if (kDebugMode) {
        print('========================================');
        print('FIREBASE FCM TOKEN: $_fcmToken');
        print('========================================');
      }

      // Listen for token refreshes
      messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (kDebugMode) {
          print('FCM Token Refreshed: $newToken');
        }
      });

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('Received foreground notification: ${message.notification?.title}: ${message.notification?.body}');
        }
      });

      // When user taps a notification while app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('User opened notification from background: ${message.data}');
        }
      });

      // Check if app was opened from terminated state
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && kDebugMode) {
        print('App opened from terminated state by notification: ${initialMessage.data}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('NotificationService init error: $e');
      }
    }
  }
}
