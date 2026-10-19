import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/cache/lru_cache.dart';

void main() {
  group('LruCache', () {
    test('removes the least recently used entry when it is over capacity', () {
      final cache = LruCache<String, int>(maxEntries: 2);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      expect(cache.length, 2);
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
    });

    test('get moves the entry to the end so it is not the next one removed', () {
      final cache = LruCache<String, int>(maxEntries: 2);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.get('a'); // now b is the least recently used
      cache.put('c', 3);

      expect(cache.get('a'), 1);
      expect(cache.get('b'), isNull);
      expect(cache.get('c'), 3);
    });

    test('put on an existing key updates it and makes it the most recent', () {
      final cache = LruCache<String, int>(maxEntries: 2);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('a', 10);
      cache.put('c', 3);

      expect(cache.get('a'), 10);
      expect(cache.get('b'), isNull);
    });

    test('entries expire after the ttl', () async {
      final cache = LruCache<String, int>(maxEntries: 5, ttl: const Duration(milliseconds: 50));

      cache.put('a', 1);
      expect(cache.get('a'), 1);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(cache.get('a'), isNull);
      expect(cache.length, 0); // the expired entry was removed
    });

    test('counts hits and misses', () {
      final cache = LruCache<String, int>(maxEntries: 2);

      cache.put('a', 1);
      cache.get('a');
      cache.get('a');
      cache.get('missing');

      expect(cache.hits, 2);
      expect(cache.misses, 1);
    });

    test('remove and clear delete entries', () {
      final cache = LruCache<String, int>(maxEntries: 5);
      cache.put('a', 1);
      cache.put('b', 2);

      cache.remove('a');
      expect(cache.length, 1);

      cache.clear();
      expect(cache.length, 0);
    });
  });
}
