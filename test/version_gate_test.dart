import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:metrosafar/services/version_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VersionGate.resetForTest();
    PackageInfo.setMockInitialValues(
      appName: 'MetroSafar',
      packageName: 'com.tlventures.metrosafar',
      version: '1.0.24',
      buildNumber: '24',
      buildSignature: '',
    );
  });

  Future<void> pumpAndEnforce(
    WidgetTester tester,
    Map<String, dynamic> appConfig,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => VersionGate.enforce(context, appConfig),
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('blocks when build is below minSupportedBuild', (tester) async {
    await pumpAndEnforce(tester, {'minSupportedBuild': 25});
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('does not block when build meets the floor', (tester) async {
    await pumpAndEnforce(tester, {'minSupportedBuild': 24});
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('fails open when appConfig has no floor', (tester) async {
    await pumpAndEnforce(tester, {});
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('the update dialog is not dismissible by back', (tester) async {
    await pumpAndEnforce(tester, {'minSupportedBuild': 99});
    expect(find.text('Update required'), findsOneWidget);
    // Simulate a system back; PopScope(canPop:false) should keep it up.
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsOneWidget);
  });
}
