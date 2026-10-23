import 'dart:collection';
import 'package:gapfinderfrontend_dart/core/cache/expiry_policy.dart';

// Cache in memory that keeps at most maxEntries values and removes the least recently used one.
//
// Structure: a LinkedHashMap, which is a hash map that also remembers the insertion order.
// The first entry is always the one used the longest time ago and the last one the most recent.
// - Looking up a key is O(1) because of the hash table.
// - "Marking as recently used" is remove + insert at the end, also O(1).
// - Removing the oldest is removing the first entry, O(1).
// A plain Map or a List would need O(n) to know which entry is the oldest.
//
// Expiry: every entry keeps the moment it expires (or null if it never does). An ExpiryPolicy decides
// that moment when the entry is created, updated or read. Passing only a ttl is the same as
// FixedExpiry(ttl), so a cache built with a ttl behaves as it always did.
class LruCache<K, V> {
  final int maxEntries;
  final Duration? ttl;
  final String name;

  final LinkedHashMap<K, _Entry<V>> _entries = LinkedHashMap<K, _Entry<V>>();
  late final ExpiryPolicy<K, V>? _policy;
  int _hits = 0;
  int _misses = 0;
  int _expired = 0;
  int _evictedByCapacity = 0;
  int _removed = 0;

  LruCache({
    required this.maxEntries,
    this.ttl,
    ExpiryPolicy<K, V>? expiryPolicy,
    this.name = 'cache',
  }) : assert(maxEntries > 0),
       assert(ttl == null || expiryPolicy == null, 'Use a ttl or an expiryPolicy, not both') {
    final fixed = ttl;
    _policy = expiryPolicy ?? (fixed != null ? FixedExpiry<K, V>(fixed) : null);
  }

  int get length => _entries.length;
  int get hits => _hits;
  int get misses => _misses;

  // A snapshot of the counters
  CacheStats get stats => CacheStats(
        hits: _hits,
        misses: _misses,
        expired: _expired,
        evictedByCapacity: _evictedByCapacity,
        removed: _removed,
      );

  // The value, or null if it is not there or it expired (a miss). A hit makes it the most recent.
  V? get(K key) {
    final entry = _entries.remove(key);

    if (entry == null) {
      _misses++;
      return null;
    }

    final now = DateTime.now();
    if (entry.isExpiredAt(now)) {
      _misses++; // expired: it was already removed above
      _expired++;
      return null;
    }

    // The policy can give the entry a new lifetime (for example a sliding one)
    final policy = _policy;
    if (policy != null) {
      final lifetime = policy.afterRead(key, entry.value, entry.remainingAt(now));
      entry.expiresAt = lifetime == null ? null : now.add(lifetime);
    }

    _entries[key] = entry; // back at the end: now it is the most recent
    _hits++;
    return entry.value;
  }

  // Saves the value as the most recent; if there are too many, removes the least recently used
  void put(K key, V value) {
    final now = DateTime.now();
    final existing = _entries.remove(key);

    // An entry that already expired counts as a new one
    final previous = existing != null && !existing.isExpiredAt(now) ? existing : null;
    final policy = _policy;
    Duration? lifetime;
    if (policy != null) {
      lifetime = previous == null
          ? policy.afterCreate(key, value)
          : policy.afterUpdate(key, value, previous.remainingAt(now));
    }

    _entries[key] = _Entry(value, lifetime == null ? null : now.add(lifetime));

    if (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
      _evictedByCapacity++;
    }
  }

  void remove(K key) {
    if (_entries.remove(key) != null) _removed++;
  }

  void clear() => _entries.clear();

  // One line with the state of the cache, ready for debugPrint
  String describe() =>
      '[LRU $name] hits=$_hits misses=$_misses size=$length/$maxEntries '
      'expired=$_expired evicted=$_evictedByCapacity removed=$_removed';
}

// Counters of a cache at one moment
class CacheStats {
  final int hits;
  final int misses;
  final int expired;
  final int evictedByCapacity;
  final int removed;

  const CacheStats({
    required this.hits,
    required this.misses,
    required this.expired,
    required this.evictedByCapacity,
    required this.removed,
  });
}

class _Entry<V> {
  final V value;
  DateTime? expiresAt; // null: it never expires

  _Entry(this.value, this.expiresAt);

  bool isExpiredAt(DateTime now) {
    final limit = expiresAt;
    return limit != null && now.isAfter(limit);
  }

  Duration? remainingAt(DateTime now) => expiresAt?.difference(now);
}
