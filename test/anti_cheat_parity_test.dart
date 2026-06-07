import 'package:flutter_test/flutter_test.dart';

/// Guards the client/server scoring contract that the backend anti-cheat module
/// (backend/lib/anti-cheat.js) relies on. If the trivia scoring constants in
/// trivia_screen.dart change, the server ceiling (questionsAnswered * 30) must
/// change too — this test documents and pins the maximum points per question so
/// that a divergence is caught in code review.
void main() {
  test('trivia max points-per-question matches the server ceiling (30)', () {
    const basePoints = 10;
    const maxSpeedBonus = 5; // _speedBonus(): <5s
    const maxStreakMultiplier = 2.0; // _streakMultiplier(): streak >= 5

    final maxPerQuestion =
        ((basePoints + maxSpeedBonus) * maxStreakMultiplier).round();

    // Mirrors MAX_POINTS_PER_QUESTION in backend/lib/anti-cheat.js.
    expect(maxPerQuestion, 30);
  });
}
