import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';
import 'auth_storage.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
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

  final _foregroundStreamController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onForegroundMessage => _foregroundStreamController.stream;

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

      await syncToken();

      // Listen for token refreshes
      messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (kDebugMode) {
          print('FCM Token Refreshed: $newToken');
        }
        syncToken();
      });

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          print('Received foreground notification: ${message.notification?.title}: ${message.notification?.body}');
        }
        _foregroundStreamController.add(message);
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

  /// Registers token with ZenLog backend if user has an active session.
  Future<void> syncToken() async {
    if (_fcmToken == null || _fcmToken!.isEmpty) return;
    try {
      final token = await AuthStorage.getToken();
      if (token != null && token.isNotEmpty) {
        final deviceId = await AuthStorage.getOrCreateDeviceId();
        await ApiService().registerFcmToken(_fcmToken!, deviceId: deviceId);
      }
    } catch (_) {}
  }
}
