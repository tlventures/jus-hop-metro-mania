import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart' show setOnboardingComplete;
import '../../../core/city/current_city_provider.dart';
import '../application/onboarding_provider.dart';
import 'screens/age_gate_screen.dart';
import 'screens/city_confirm_screen.dart';
import 'screens/games_feature_screen.dart';
import 'screens/learn_feature_screen.dart';
import 'screens/age_restricted_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/privacy_consent_screen.dart';
import 'screens/rewards_feature_screen.dart';
import 'screens/welcome_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final PageController _pageController;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    ref.read(onboardingProvider.notifier).nextStep();
    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _previousStep() {
    ref.read(onboardingProvider.notifier).previousStep();
    _pageController.previousPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _skipOnboarding() async {
    await ref.read(onboardingProvider.notifier).completeOnboarding();
    await setOnboardingComplete();
    if (mounted) context.go('/login');
  }

  void _completeOnboarding() async {
    await ref.read(onboardingProvider.notifier).completeOnboarding();
    await setOnboardingComplete();
    if (mounted) context.go('/login');
  }

  /// Called when the CityConfirmScreen finishes — city is now set, proceed to login.
  void _onCityConfirmed() {
    _completeOnboarding();
  }

  /// Under-18 users stop here. Shown as a full-screen modal (not a PageView
  /// page) so it can't be swiped past, and so the age gate remains underneath
  /// if the user needs to correct a mistyped birthday. There is no "continue" —
  /// MetroSafar is 18+ and does not process children's data (DPDPA §9).
  void _showAgeRestrictedModal(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AgeRestrictedScreen(
          onChangeDob: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Kick off city initialization early so it's ready by the time the
    // city confirm screen is shown.
    Future.microtask(() =>
        ref.read(currentCityProvider.notifier).initialize());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // Page 0 – Welcome
            WelcomeScreen(
              onNext: _nextStep,
              onSkip: _skipOnboarding,
            ),
            // Page 1 – Age gate (DPDPA §9)
            // Adults advance the PageView. Under-18s hit a terminal 18+ screen
            // as a modal and cannot continue — no guardian data is collected.
            Builder(builder: (ctx) => AgeGateScreen(
              onAdult: _nextStep,
              onMinor: () => _showAgeRestrictedModal(ctx),
              onBack: _previousStep,
            )),
            // Page 2 – Play features
            GamesFeatureScreen(
              onNext: _nextStep,
              onBack: _previousStep,
            ),
            // Page 3 – Learn features
            LearnFeatureScreen(
              onNext: _nextStep,
              onBack: _previousStep,
            ),
            // Page 4 – Rewards
            RewardsFeatureScreen(
              onNext: _nextStep,
              onBack: _previousStep,
            ),
            // Page 5 – Location & notification permissions
            PermissionsScreen(
              onComplete: _nextStep,
              onBack: _previousStep,
            ),
            // Page 6 – City detection & confirmation
            CityConfirmScreen(
              onCityConfirmed: _onCityConfirmed,
              onBack: _previousStep,
            ),
            // Page 7 – Privacy consent
            PrivacyConsentScreen(
              onAccept: _completeOnboarding,
              onDecline: _completeOnboarding,
            ),
          ],
        ),
      ),
    );
  }
}

