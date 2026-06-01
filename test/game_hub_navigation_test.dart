import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrosafar/features/play/presentation/play_hub_screen.dart';

void main() {
  testWidgets('Play hub exposes the word puzzle earning path', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PlayHubScreen())),
    );

    await tester.pump();

    expect(find.text('Play & Earn'), findsOneWidget);
    expect(find.text('Word Puzzle'), findsOneWidget);
  });
}
