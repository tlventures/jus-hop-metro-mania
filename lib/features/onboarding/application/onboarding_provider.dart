import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingState {
  final int currentStep;
  final bool hasCompletedOnboarding;
  final bool locationPermissionGranted;
  final bool notificationPermissionGranted;

  OnboardingState({
    required this.currentStep,
    required this.hasCompletedOnboarding,
    this.locationPermissionGranted = false,
    this.notificationPermissionGranted = false,
  });

  OnboardingState copyWith({
    int? currentStep,
    bool? hasCompletedOnboarding,
    bool? locationPermissionGranted,
    bool? notificationPermissionGranted,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      locationPermissionGranted: locationPermissionGranted ?? this.locationPermissionGranted,
      notificationPermissionGranted: notificationPermissionGranted ?? this.notificationPermissionGranted,
    );
  }
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier()
      : super(
          OnboardingState(
            currentStep: 0,
            hasCompletedOnboarding: false,
          ),
        );

  // 9 pages: welcome(0), ageGate(1), parentalConsent(2), games(3), learn(4),
  // rewards(5), permissions(6), cityConfirm(7), privacyConsent(8)
  static const int _totalSteps = 8;

  void nextStep() {
    if (state.currentStep < _totalSteps) {
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }

  void goToStep(int step) {
    if (step >= 0 && step <= _totalSteps) {
      state = state.copyWith(currentStep: step);
    }
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasCompletedOnboarding', true);
    state = state.copyWith(hasCompletedOnboarding: true);
  }

  void setLocationPermission(bool granted) {
    state = state.copyWith(locationPermissionGranted: granted);
  }

  void setNotificationPermission(bool granted) {
    state = state.copyWith(notificationPermissionGranted: granted);
  }

  Future<bool> checkOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('hasCompletedOnboarding') ?? false;
    state = state.copyWith(hasCompletedOnboarding: completed);
    return completed;
  }
}

final onboardingProvider = StateNotifierProvider<OnboardingNotifier, OnboardingState>((ref) {
  return OnboardingNotifier();
});
