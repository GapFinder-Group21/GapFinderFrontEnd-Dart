import 'dart:collection';

// Cache in memory that keeps at most maxEntries values and removes the least recently used one.
//
// Structure: a LinkedHashMap, which is a hash map that also remembers the insertion order.
// The first entry is always the one used the longest time ago and the last one the most recent.
// - Looking up a key is O(1) because of the hash table.
// - "Marking as recently used" is remove + insert at the end, also O(1).
// - Removing the oldest is removing the first entry, O(1).
// A plain Map or a List would need O(n) to know which entry is the oldest.
// If ttl is given, a value also expires that long after it was saved.
class LruCache<K, V> {
  final int maxEntries;
  final Duration? ttl;

  final LinkedHashMap<K, _Entry<V>> _entries = LinkedHashMap<K, _Entry<V>>();
  int _hits = 0;
  int _misses = 0;

  LruCache({required this.maxEntries, this.ttl}) : assert(maxEntries > 0);

  int get length => _entries.length;
  int get hits => _hits;
  int get misses => _misses;

  // The value, or null if it is not there or it expired (a miss). A hit makes it the most recent.
  V? get(K key) {
    final entry = _entries.remove(key);

    if (entry == null) {
      _misses++;
      return null;
    }

    final maxAge = ttl;
    if (maxAge != null && DateTime.now().difference(entry.savedAt) > maxAge) {
      _misses++; // expired: it was already removed above
      return null;
    }

    _entries[key] = entry; // back at the end: now it is the most recent
    _hits++;
    return entry.value;
  }

  // Saves the value as the most recent; if there are too many, removes the least recently used
  void put(K key, V value) {
    _entries.remove(key);
    _entries[key] = _Entry(value, DateTime.now());

    if (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(K key) => _entries.remove(key);

  void clear() => _entries.clear();
}

class _Entry<V> {
  final V value;
  final DateTime savedAt;
  _Entry(this.value, this.savedAt);
}
