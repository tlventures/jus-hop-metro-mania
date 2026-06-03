import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design_system/components/ad_banner.dart';
import '../design_system/components/offline_banner.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/wallet/presentation/wallet_screen.dart';
import '../features/wallet/presentation/my_redemptions_screen.dart';
import '../features/notifications/presentation/notifications_inbox_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/play/presentation/play_hub_screen.dart';
import '../features/play/games/daily_spin_screen.dart';
import '../features/play/games/trivia_screen.dart';
import '../features/play/games/sudoku_screen.dart';
import '../features/play/games/word_puzzle_screen.dart';
import '../features/play/games/city_explorer_screen.dart';
import '../features/learn/presentation/learn_hub_screen.dart';
import '../features/booking/presentation/booking_coming_soon_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/audio/presentation/audio_stories_screen.dart';
import '../features/events/presentation/events_screen.dart';
import '../features/intelligence/presentation/journey_planner_screen.dart';
import '../features/phase56/presentation/feature_gate.dart';
import '../features/referral/presentation/referral_screen.dart';
import '../features/social/presentation/friends_screen.dart';
import '../features/stamps/presentation/stamps_screen.dart';
import '../features/trip/presentation/trip_mode_screen.dart';

Future<void> initializeRouter() async {
  await SharedPreferences.getInstance();
}

Future<void> setOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('hasCompletedOnboarding', true);
}

Future<void> clearOnboardingFlag() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('hasCompletedOnboarding');
}

Future<String?> _redirect(BuildContext context, GoRouterState state) async {
  final prefs = await SharedPreferences.getInstance();
  final doneOnboarding = prefs.getBool('hasCompletedOnboarding') ?? false;
  final path = state.uri.path;

  // Not onboarded yet → force to onboarding (allow /onboarding itself)
  if (!doneOnboarding && path != '/onboarding') return '/onboarding';

  // Onboarded but not signed in → force to login (allow /login itself)
  final user = FirebaseAuth.instance.currentUser;
  if (doneOnboarding && user == null && path != '/login') return '/login';
  if (doneOnboarding && user != null && path == '/login') return '/home';

  return null;
}

/// Global navigator key — lets non-widget code (e.g. notification taps)
/// drive navigation via [appRouter].
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Maps a game id to its screen — shared by the Play hub and deep links.
Widget gameScreenFor(String gameId) {
  switch (gameId) {
    case 'trivia':
      return const TriviaScreen();
    case 'sudoku':
      return const SudokuScreen();
    case 'word_puzzle':
      return const WordPuzzleScreen();
    case 'city_explorer':
      return const CityExplorerScreen();
    case 'daily_spin':
    default:
      return const DailySpinScreen();
  }
}

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/home',
  redirect: _redirect,
  routes: [
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    ShellRoute(
      builder: (context, state, child) {
        final selectedIndex = _getSelectedIndex(state.fullPath ?? '/home');
        return _NavShell(selectedIndex: selectedIndex, child: child);
      },
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/ride',
          builder:
              (context, state) => FeatureGate(
                featureName: 'Ride Mode',
                enabled: (flags) => flags.tripMode,
                child: const TripModeScreen(),
              ),
        ),
        GoRoute(
          path: '/play',
          builder: (context, state) => const PlayHubScreen(),
        ),
        GoRoute(
          path: '/wallet',
          builder: (context, state) => const WalletScreen(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/learn',
      builder: (context, state) => const LearnHubScreen(),
    ),
    GoRoute(
      path: '/my-redemptions',
      builder: (context, state) => const MyRedemptionsScreen(),
    ),
    GoRoute(
      path: '/notifications-inbox',
      builder: (context, state) => const NotificationsInboxScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    // Deep link straight into a specific game (e.g. /game/trivia).
    GoRoute(
      path: '/game/:gameId',
      builder: (context, state) => gameScreenFor(state.pathParameters['gameId'] ?? 'daily_spin'),
    ),
    GoRoute(
      path: '/booking',
      builder: (context, state) => const BookingComingSoonScreen(),
    ),
    GoRoute(
      path: '/friends',
      builder: (context, state) => const FriendsScreen(),
    ),
    GoRoute(
      path: '/referral',
      builder: (context, state) => const ReferralScreen(),
    ),
    GoRoute(
      path: '/journey-planner',
      builder:
          (context, state) => FeatureGate(
            featureName: 'Journey Planner',
            enabled: (flags) => flags.liveEtas,
            child: const JourneyPlannerScreen(),
          ),
    ),
    GoRoute(
      path: '/stamps',
      builder:
          (context, state) => FeatureGate(
            featureName: 'Station Stamps',
            enabled: (flags) => flags.stamps,
            child: const StampsScreen(),
          ),
    ),
    GoRoute(
      path: '/audio',
      builder:
          (context, state) => FeatureGate(
            featureName: 'Audio Stories',
            enabled: (flags) => flags.audioStories,
            child: const AudioStoriesScreen(),
          ),
    ),
    GoRoute(
      path: '/events',
      builder:
          (context, state) => FeatureGate(
            featureName: 'Live Events',
            enabled: (flags) => flags.liveEvents,
            child: const EventsScreen(),
          ),
    ),
  ],
);

int _getSelectedIndex(String location) {
  if (location.startsWith('/home')) return 0;
  if (location.startsWith('/ride')) return 1;
  if (location.startsWith('/play')) return 2;
  if (location.startsWith('/wallet')) return 3;
  if (location.startsWith('/profile')) return 4;
  return 0;
}

class _NavShell extends StatelessWidget {
  final Widget child;
  final int selectedIndex;

  const _NavShell({required this.child, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [const OfflineBanner(), Expanded(child: child)]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ad lives in its own clearly-separated slot: top divider + solid
          // background + gap below, so it never blends into the nav bar
          // (prevents accidental taps and satisfies AdMob placement policy).
          Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              return Container(
                width: double.infinity,
                color: scheme.surface,
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    const MetroSafarAdBanner(),
                  ],
                ),
              );
            },
          ),
          NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => _navigateToTab(context, index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
                tooltip: '',
              ),
              NavigationDestination(
                icon: Icon(Icons.train_outlined),
                selectedIcon: Icon(Icons.train),
                label: 'Ride',
                tooltip: '',
              ),
              NavigationDestination(
                icon: Icon(Icons.sports_esports_outlined),
                selectedIcon: Icon(Icons.sports_esports),
                label: 'Play',
                tooltip: '',
              ),
              NavigationDestination(
                icon: Icon(Icons.wallet_outlined),
                selectedIcon: Icon(Icons.wallet),
                label: 'Wallet',
                tooltip: '',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
                tooltip: '',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _navigateToTab(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/ride');
      case 2:
        context.go('/play');
      case 3:
        context.go('/wallet');
      case 4:
        context.go('/profile');
    }
  }
}
