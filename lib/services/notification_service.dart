import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'backend_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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
    } catch (error) {
      debugPrint('[NotificationService] topic subscribe failed: $error');
    }

    FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;
      await showLocal(
        title: notification?.title ?? 'MetroSafar',
        body: notification?.body ?? 'You have a new update.',
        payload: message.data['deeplink'] as String?,
      );
    });
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
