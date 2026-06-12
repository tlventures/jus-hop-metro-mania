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
    expect(find.text('Explore first'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });

  testWidgets('Welcome screen renders on small phones without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(onNext: () {}, onSkip: () {})),
    );

    // A RenderFlex overflow surfaces as an exception in widget tests.
    expect(tester.takeException(), isNull);

    // Content taller than the viewport must be reachable by scrolling.
    await tester.scrollUntilVisible(find.text('Start earning'), 200);
    expect(find.text('Start earning'), findsOneWidget);
  });
}
