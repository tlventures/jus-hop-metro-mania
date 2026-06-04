import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_service.dart';
import '../app/router.dart' as router_module;

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _cityTopicKey = 'fcm_city_topic';

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'metrosafar_general',
    'MetroSafar updates',
    description: 'Trip, reward, and metro service updates.',
    importance: Importance.defaultImportance,
  );

  Future<void> init({BackendService? backendService}) async {
    if (_initialized) return;
    _initialized = true;

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) _navigate(payload);
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[NotificationService] permission denied');
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await uploadToken(token, backendService: backendService);
      }
      _messaging.onTokenRefresh.listen(
        (token) => uploadToken(token, backendService: backendService),
      );
    } catch (error) {
      debugPrint('[NotificationService] token registration failed: $error');
    }

    // Subscribe to the broadcast topic so admin "All Users" pushes are
    // delivered. (Topic messages only reach subscribed devices.)
    try {
      await _messaging.subscribeToTopic('all_users');
      // Re-subscribe to the last known city topic on launch.
      final prefs = await SharedPreferences.getInstance();
      final lastCity = prefs.getString(_cityTopicKey);
      if (lastCity != null && lastCity.isNotEmpty) {
        await _messaging.subscribeToTopic('city_$lastCity');
      }
    } catch (error) {
      debugPrint('[NotificationService] topic subscribe failed: $error');
    }

    FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;
      await showLocal(
        title: notification?.title ?? 'MetroSafar',
        body: notification?.body ?? 'You have a new update.',
        payload: routeFromData(message.data),
      );
    });

    // App opened by tapping a notification (background → foreground).
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _navigate(routeFromData(m.data)));
    // App launched from terminated state by a notification.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _navigate(routeFromData(initial.data));
  }

  /// Resolve an in-app route from an FCM data payload.
  /// Conventions: { screen: 'my_redemptions' } or { screen: 'game', gameId: 'trivia' }.
  String routeFromData(Map<String, dynamic> data) {
    final screen = data['screen']?.toString();
    // Game deep-link needs the gameId param.
    if (screen == 'game' && data['gameId'] != null) return '/game/${data['gameId']}';
    // Map any known screen token to its route. Keeps the payload contract
    // simple (snake_case tokens) while covering every reachable destination.
    const screenRoutes = <String, String>{
      'my_redemptions': '/my-redemptions',
      'notifications': '/notifications-inbox',
      'notifications_inbox': '/notifications-inbox',
      'settings': '/settings',
      'home': '/home',
      'ride': '/ride',
      'play': '/play',
      'wallet': '/wallet',
      'profile': '/profile',
      'learn': '/learn',
      'stamps': '/stamps',
      'audio': '/audio',
      'events': '/events',
      'journey_planner': '/journey-planner',
      'friends': '/friends',
      'referral': '/referral',
      'booking': '/booking',
    };
    if (screen != null && screenRoutes.containsKey(screen)) {
      return screenRoutes[screen]!;
    }
    // Explicit raw deeplink wins as a last resort.
    if (data['deeplink'] != null) return data['deeplink'].toString();
    return '/home';
  }

  void _navigate(String route) {
    try {
      router_module.appRouter.go(route);
    } catch (e) {
      debugPrint('[NotificationService] navigation failed: $e');
    }
  }

  /// Subscribe to the active city's FCM topic so admin "by city" broadcasts
  /// land. Unsubscribes from the previously-subscribed city first. Safe to
  /// call repeatedly; no-ops when the city is unchanged.
  Future<void> subscribeToCity(String? cityId) async {
    if (cityId == null || cityId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getString(_cityTopicKey);
      if (previous == cityId) return; // already subscribed
      if (previous != null && previous.isNotEmpty) {
        await _messaging.unsubscribeFromTopic('city_$previous');
      }
      await _messaging.subscribeToTopic('city_$cityId');
      await prefs.setString(_cityTopicKey, cityId);
      debugPrint('[NotificationService] subscribed to city_$cityId');
    } catch (e) {
      debugPrint('[NotificationService] city topic subscribe failed: $e');
    }
  }

  Future<void> uploadToken(
    String token, {
    BackendService? backendService,
  }) async {
    await (backendService ?? BackendService()).registerDeviceToken(
      token: token,
      platform: _platformName,
    );
  }

  Future<void> showLocal({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'metrosafar_general',
          'MetroSafar updates',
          channelDescription: 'Trip, reward, and metro service updates.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  Future<void> scheduleStreakReminder() async {
    await _localNotifications.periodicallyShow(
      1001,
      'Keep your MetroSafar streak alive',
      'Open MetroSafar today to keep earning commute rewards.',
      RepeatInterval.daily,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'metrosafar_general',
          'MetroSafar updates',
          channelDescription: 'Trip, reward, and metro service updates.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'unknown';
    }
  }
}
