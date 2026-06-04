import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router.dart' show setOnboardingComplete;
import '../../../core/city/current_city_provider.dart';
import '../../../core/compliance/minor_status.dart';
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

  /// Called when the CityConfirmScreen finishes — city is now set, proceed to login.
  void _onCityConfirmed() {
    _completeOnboarding();
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
            AgeGateScreen(
              onAdult: _nextStep,
              onMinor: _nextStep, // both advance; onMinor proceeds to parental-consent (page 2)
              onBack: _previousStep,
            ),
            // Page 2 – Parental consent (only reached by minors; adults skip via _nextStep)
            // Adults will land here but the screen detects isMinorCached=false and auto-advances.
            _ParentalConsentGate(
              onContinue: _nextStep,
              onBack: _previousStep,
            ),
            // Page 3 – Play features
            GamesFeatureScreen(
              onNext: _nextStep,
              onBack: _previousStep,
            ),
            // Page 4 – Learn features
            LearnFeatureScreen(
              onNext: _nextStep,
              onBack: _previousStep,
            ),
            // Page 5 – Rewards
            RewardsFeatureScreen(
              onNext: _nextStep,
              onBack: _previousStep,
            ),
            // Page 6 – Location & notification permissions
            PermissionsScreen(
              onComplete: _nextStep,
              onBack: _previousStep,
            ),
            // Page 7 – City detection & confirmation
            CityConfirmScreen(
              onCityConfirmed: _onCityConfirmed,
              onBack: _previousStep,
            ),
            // Page 8 – Privacy consent
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

/// Auto-skips for adults. Shows [ParentalConsentScreen] only for under-18 users.
class _ParentalConsentGate extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback? onBack;
  const _ParentalConsentGate({required this.onContinue, this.onBack});

  @override
  Widget build(BuildContext context) {
    if (!MinorStatus.isMinorCached) {
      // Adult — skip this page immediately on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => onContinue());
      return const SizedBox.shrink();
    }
    return ParentalConsentScreen(onContinue: onContinue, onBack: onBack);
  }
}
