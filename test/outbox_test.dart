import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metrosafar/services/sync/outbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  PendingMutation mutation({
    String id = 'm1',
    int retryCount = 0,
    DateTime? createdAt,
  }) {
    return PendingMutation(
      id: id,
      method: 'POST',
      path: '/api/trips/start',
      headers: const {'Content-Type': 'application/json'},
      body: const {'startStationId': 's1'},
      createdAt: createdAt ?? DateTime.now(),
      retryCount: retryCount,
    );
  }

  group('Outbox', () {
    test('enqueue then count and all round-trips a mutation', () async {
      final outbox = Outbox();
      await outbox.enqueue(mutation());
      expect(await outbox.count(), 1);
      final all = await outbox.all();
      expect(all.single.path, '/api/trips/start');
      expect(all.single.body!['startStationId'], 's1');
    });

    test('enqueue dedupes by id', () async {
      final outbox = Outbox();
      await outbox.enqueue(mutation(id: 'dup'));
      await outbox.enqueue(mutation(id: 'dup', retryCount: 1));
      expect(await outbox.count(), 1);
      expect((await outbox.all()).single.retryCount, 1);
    });

    test('isDead is true past max retries', () {
      expect(mutation(retryCount: Outbox.maxRetries).isDead(), isTrue);
      expect(mutation(retryCount: Outbox.maxRetries - 1).isDead(), isFalse);
    });

    test('isDead is true past TTL', () {
      final old = DateTime.now().subtract(Outbox.ttl + const Duration(hours: 1));
      expect(mutation(createdAt: old).isDead(), isTrue);
    });

    test('purgeDead removes only dead entries and returns them', () async {
      final outbox = Outbox();
      await outbox.enqueue(mutation(id: 'live'));
      await outbox.enqueue(mutation(id: 'old', createdAt: DateTime(2000)));
      await outbox.enqueue(
        mutation(id: 'exhausted', retryCount: Outbox.maxRetries),
      );

      final dropped = await outbox.purgeDead();

      expect(dropped.map((m) => m.id).toSet(), {'old', 'exhausted'});
      final remaining = await outbox.all();
      expect(remaining.single.id, 'live');
    });
  });
}
