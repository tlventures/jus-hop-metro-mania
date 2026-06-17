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
import 'screens/parental_consent_screen.dart';
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

  /// Declining optional analytics/marketing is a real, distinct choice — not a
  /// silent equivalent of Accept. Confirm what it means before proceeding so
  /// the Decline button doesn't behave identically to Accept.
  void _declinePrivacy() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Continue without analytics?'),
        content: const Text(
          'You can still use MetroSafar. We just won\'t collect optional '
          'analytics or marketing data. You can change this anytime in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed == true) _completeOnboarding();
  }

  /// Called when the CityConfirmScreen finishes — city is now set, proceed to login.
  void _onCityConfirmed() {
    _completeOnboarding();
  }

  /// For under-18 users: show the parental consent screen as a full-screen
  /// modal route (not a PageView page) to avoid the pre-build race condition.
  /// Advances to the next onboarding page after the modal is dismissed.
  void _showParentalConsentModal(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ParentalConsentScreen(
          onContinue: () {
            Navigator.of(context).pop();
            _nextStep();
          },
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
    const totalPages = 8;
    final step = ref.watch(onboardingProvider).currentStep;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Progress: tells the user how far through the 8-step flow they
              // are, instead of an open-ended sequence with no end in sight.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (step + 1) / totalPages,
                    minHeight: 6,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
            // Page 0 – Welcome
            WelcomeScreen(
              onNext: _nextStep,
              onSkip: _skipOnboarding,
            ),
            // Page 1 – Age gate (DPDPA §9)
            // For adults: onAdult → _nextStep advances the PageView.
            // For minors: onMinor → shows ParentalConsentScreen as a modal
            //   (not a PageView page, avoiding PageView pre-build race),
            //   then advances into the same next page when dismissed.
            Builder(builder: (ctx) => AgeGateScreen(
              onAdult: _nextStep,
              onMinor: () => _showParentalConsentModal(ctx),
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
              onDecline: _declinePrivacy,
            ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

