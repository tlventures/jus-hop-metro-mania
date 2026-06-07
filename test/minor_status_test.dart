import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metrosafar/core/compliance/minor_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory stand-in for the flutter_secure_storage platform channel so the
  // DPDPA minor-status logic can be exercised without a real Keystore.
  final secureStore = <String, String>{};

  setUp(() {
    secureStore.clear();
    SharedPreferences.setMockInitialValues({});
    MinorStatus.isMinorCached = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'read':
            return secureStore[call.arguments['key'] as String];
          case 'write':
            secureStore[call.arguments['key'] as String] =
                call.arguments['value'] as String;
            return null;
          case 'delete':
            secureStore.remove(call.arguments['key'] as String);
            return null;
          case 'readAll':
            return Map<String, String>.from(secureStore);
          case 'deleteAll':
            secureStore.clear();
            return null;
          case 'containsKey':
            return secureStore.containsKey(call.arguments['key'] as String);
        }
        return null;
      },
    );
  });

  group('MinorStatus', () {
    test('a DOB under 18 classifies as minor and caches the flag', () async {
      final dob = DateTime.now().subtract(const Duration(days: 365 * 15));
      await MinorStatus.setDob(dob);
      expect(MinorStatus.isMinorCached, isTrue);
      expect(await MinorStatus.age, inInclusiveRange(14, 16));
    });

    test('a DOB over 18 classifies as adult', () async {
      final dob = DateTime.now().subtract(const Duration(days: 365 * 30));
      await MinorStatus.setDob(dob);
      expect(MinorStatus.isMinorCached, isFalse);
    });

    test('hydrate restores the cached minor flag from secure storage', () async {
      final dob = DateTime.now().subtract(const Duration(days: 365 * 12));
      await MinorStatus.setDob(dob);
      MinorStatus.isMinorCached = false; // simulate cold start
      await MinorStatus.hydrate();
      expect(MinorStatus.isMinorCached, isTrue);
    });

    test('migrates legacy SharedPreferences minor flag on hydrate', () async {
      // Legacy install: flag lived in plaintext SharedPreferences.
      SharedPreferences.setMockInitialValues({'user_is_minor': true});
      await MinorStatus.hydrate();
      expect(MinorStatus.isMinorCached, isTrue);
      // Legacy key should be cleared after migration.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('user_is_minor'), isNull);
    });
  });
}
