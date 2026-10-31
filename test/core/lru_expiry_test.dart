import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/cache/expiry_policy.dart';
import 'package:gapfinderfrontend_dart/core/cache/lru_cache.dart';

// Long enough that a slow machine does not make the waits below fall on the wrong side of the limit:
// "inside" waits are at most 300 ms (60 % of the time) and "after" waits are 600 ms (120 %)
const _short = Duration(milliseconds: 500);
const _long = Duration(milliseconds: 2000);

Future<void> _wait(int milliseconds) => Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  group('LruCache with a ttl (same as before)', () {
    test('a ttl is the same as FixedExpiry', () async {
      final withTtl = LruCache<String, int>(maxEntries: 5, ttl: _short);
      final withPolicy = LruCache<String, int>(maxEntries: 5, expiryPolicy: FixedExpiry<String, int>(_short));

      withTtl.put('a', 1);
      withPolicy.put('a', 1);
      expect(withTtl.get('a'), 1);
      expect(withPolicy.get('a'), 1);

      await _wait(600);

      expect(withTtl.get('a'), isNull);
      expect(withPolicy.get('a'), isNull);
    });

    test('with no ttl and no policy the entries never expire', () async {
      final cache = LruCache<String, int>(maxEntries: 5);
      cache.put('a', 1);

      await _wait(600);

      expect(cache.get('a'), 1);
    });

    test('a ttl and a policy at the same time is refused', () {
      expect(
        () => LruCache<String, int>(maxEntries: 2, ttl: _short, expiryPolicy: FixedExpiry<String, int>(_short)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('FixedExpiry', () {
    test('reading does not extend the life of the entry', () async {
      final cache = LruCache<String, int>(maxEntries: 5, expiryPolicy: FixedExpiry<String, int>(_short));

      cache.put('a', 1);
      await _wait(300);
      expect(cache.get('a'), 1); // still valid, but this read must not renew it
      await _wait(300);

      expect(cache.get('a'), isNull);
    });

    test('an expired read is a miss, removes the entry and counts as expired', () async {
      final cache = LruCache<String, int>(maxEntries: 5, expiryPolicy: FixedExpiry<String, int>(_short));

      cache.put('a', 1);
      await _wait(600);

      expect(cache.get('a'), isNull);
      expect(cache.length, 0);
      expect(cache.hits, 0);
      expect(cache.misses, 1);
      expect(cache.stats.expired, 1);
    });
  });

  group('SlidingExpiry', () {
    test('a read starts the time again', () async {
      final cache = LruCache<String, int>(maxEntries: 5, expiryPolicy: SlidingExpiry<String, int>(_short));

      cache.put('a', 1);
      await _wait(300);
      expect(cache.get('a'), 1); // renewed
      await _wait(300);
      expect(cache.get('a'), 1); // 80 ms after saving, but only 40 after the last read
      await _wait(600);

      expect(cache.get('a'), isNull); // idle for too long
    });
  });

  group('ValueBasedExpiry', () {
    test('two entries of the same cache can live different times', () async {
      final cache = LruCache<String, int>(
        maxEntries: 5,
        expiryPolicy: ValueBasedExpiry<String, int>(
          (key, value) => value > 10 ? _long : _short,
        ),
      );

      cache.put('short', 1);
      cache.put('long', 99);
      await _wait(600);

      expect(cache.get('short'), isNull);
      expect(cache.get('long'), 99);
    });

    test('a null duration means the entry never expires', () async {
      final cache = LruCache<String, int>(
        maxEntries: 5,
        expiryPolicy: ValueBasedExpiry<String, int>((key, value) => null),
      );

      cache.put('a', 1);
      await _wait(600);

      expect(cache.get('a'), 1);
    });

    test('the policy is asked again when a key is updated', () async {
      final cache = LruCache<String, int>(
        maxEntries: 5,
        expiryPolicy: ValueBasedExpiry<String, int>(
          (key, value) => value == 1 ? _short : _long,
        ),
      );

      cache.put('a', 1);
      cache.put('a', 2); // now it lives longer
      await _wait(600);

      expect(cache.get('a'), 2);
    });

    test('the policy receives the remaining time on update and read', () {
      final remainingOnUpdate = <Duration?>[];
      final remainingOnRead = <Duration?>[];
      final cache = LruCache<String, int>(maxEntries: 5, expiryPolicy: _Spy(remainingOnUpdate, remainingOnRead));

      cache.put('a', 1);
      cache.put('a', 2);
      cache.get('a');

      expect(remainingOnUpdate.single, isNotNull);
      expect(remainingOnUpdate.single!.inSeconds, greaterThan(0));
      expect(remainingOnRead.single, isNotNull);
    });
  });

  group('LRU behaviour with a policy', () {
    test('capacity still removes the least recently used entry', () {
      final cache = LruCache<String, int>(
        maxEntries: 2,
        expiryPolicy: FixedExpiry<String, int>(const Duration(minutes: 1)),
      );

      cache.put('a', 1);
      cache.put('b', 2);
      cache.get('a'); // b is now the least recently used
      cache.put('c', 3);

      expect(cache.get('a'), 1);
      expect(cache.get('b'), isNull);
      expect(cache.get('c'), 3);
    });
  });

  group('stats and describe', () {
    test('stats count expired, evicted by capacity and removed entries', () async {
      final cache = LruCache<String, int>(maxEntries: 2, expiryPolicy: FixedExpiry<String, int>(_short));

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3); // a is evicted by capacity
      cache.remove('b');
      cache.remove('missing'); // not there: it is not counted
      await _wait(600);
      cache.get('c'); // expired

      final stats = cache.stats;
      expect(stats.evictedByCapacity, 1);
      expect(stats.removed, 1);
      expect(stats.expired, 1);
      expect(stats.misses, 1);
      expect(stats.hits, 0);
    });

    test('describe gives one line with the state of the cache', () {
      final cache = LruCache<String, int>(maxEntries: 20, name: 'detalle mesa', ttl: const Duration(minutes: 5));

      cache.put('a', 1);
      cache.get('a');
      cache.get('a');
      cache.get('a');
      cache.get('missing');
      cache.put('b', 2);

      expect(cache.describe(), '[LRU detalle mesa] hits=3 misses=1 size=2/20 expired=0 evicted=0 removed=0');
    });
  });
}

// Records the remaining time the policy receives
class _Spy extends ExpiryPolicy<String, int> {
  final List<Duration?> remainingOnUpdate;
  final List<Duration?> remainingOnRead;

  _Spy(this.remainingOnUpdate, this.remainingOnRead);

  @override
  Duration? afterCreate(String key, int value) => const Duration(minutes: 1);

  @override
  Duration? afterUpdate(String key, int value, Duration? remaining) {
    remainingOnUpdate.add(remaining);
    return const Duration(minutes: 1);
  }

  @override
  Duration? afterRead(String key, int value, Duration? remaining) {
    remainingOnRead.add(remaining);
    return remaining;
  }
}
