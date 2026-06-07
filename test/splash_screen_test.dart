import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrosafar/features/onboarding/presentation/screens/welcome_screen.dart';

void main() {
  testWidgets('Welcome screen presents the rewards-first launch promise', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(onNext: () {}, onSkip: () {})),
    );

    expect(find.text('Ride. Earn. Own your city.'), findsOneWidget);
    expect(find.text('Start earning'), findsOneWidget);
    // The rewards-first promise pill and the primary CTA arrow.
    expect(find.byIcon(Icons.bolt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });
}
