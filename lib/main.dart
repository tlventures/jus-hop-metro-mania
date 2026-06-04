import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'l10n/app_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/router.dart' as router_module;
import 'core/city/city_theme_provider.dart';
import 'core/city/current_city_provider.dart';
import 'design_system/theme.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'core/compliance/minor_status.dart';
import 'services/analytics_service.dart';
import 'services/backend_service.dart';
import 'services/connectivity_watcher.dart';
import 'services/localization_service.dart';
import 'services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (_) => const _ProductionErrorFallback();
  // Draw under the system bars so branded backgrounds are full-bleed
  // (eliminates the white band above the navigation bar).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Run immediately so the animated splash shows on the first frame; all
  // heavy initialisation runs inside BootstrapApp while the splash is visible.
  runApp(const BootstrapApp());
}

/// Performs all async startup work (Firebase, services, ads, router) while an
/// animated [SplashScreen] is shown, then swaps in the real app. Keeps launch
/// responsive on slower/older devices instead of a frozen white screen.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (mounted) setState(() => _error = null);
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      await initializeServices();
      // Hydrate minor-status cache BEFORE AdMob init and analytics wiring
      // so all gates have the correct value on the very first frame.
      await MinorStatus.hydrate();
      _wireAuthBoundServices();
      await router_module.initializeRouter();
      ConnectivityWatcher.instance.start(BackendService());
      unawaited(MobileAds.instance.initialize());
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      if (mounted) setState(() => _ready = true);
    } catch (e, st) {
      debugPrint('Bootstrap failed: $e\n$st');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: SplashScreen(
          error: _error,
          onRetry: _error != null ? _boot : null,
        ),
      );
    }
    return ProviderScope(child: const MetroSafarApp());
  }
}

class _ProductionErrorFallback extends StatelessWidget {
  const _ProductionErrorFallback();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F7FA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.error_outline, size: 36, color: Color(0xFF4F46E5)),
              SizedBox(height: 12),
              Text(
                'Something went wrong',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF252334),
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Please reopen MetroSafar. We have logged this safely.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF5B5868)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void _wireAuthBoundServices() {
  FirebaseAuth.instance.authStateChanges().listen((user) {
    // DPDPA §9 — no behavioural analytics for under-18 users.
    if (!MinorStatus.isMinorCached) {
      unawaited(AnalyticsService.setUserId(user?.uid));
    }
    if (user != null) {
      unawaited(NotificationService.instance.init());
    }
  });
}

Future<void> initializeServices() async {
  await SharedPreferences.getInstance();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

class MetroSafarApp extends ConsumerStatefulWidget {
  const MetroSafarApp({super.key});

  @override
  ConsumerState<MetroSafarApp> createState() => _MetroSafarAppState();
}

class _MetroSafarAppState extends ConsumerState<MetroSafarApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(localeProvider.notifier).initialize();
      // Initialize city from saved preference / geo — non-blocking.
      // Onboarding will reinitialize if the user hasn't set a city yet.
      ref.read(currentCityProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final cityLight = ref.watch(cityLightThemeProvider);
    final cityDark = ref.watch(cityDarkThemeProvider);

    // Keep the FCM city-topic subscription in sync with the active city so
    // admin "by city" broadcasts are delivered.
    ref.listen(activeCityProvider, (prev, next) {
      if (next != null && next.id != prev?.id) {
        NotificationService.instance.subscribeToCity(next.id);
      }
    });

    return MaterialApp.router(
      title: 'MetroSafar',
      theme: cityLight,
      darkTheme: cityDark,
      themeMode: ThemeMode.system,
      routerConfig: router_module.appRouter,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales:
          LocalizationService.supportedLanguageCodes
              .map(LocalizationService.localeFromCode)
              .toList(),
    );
  }
}
