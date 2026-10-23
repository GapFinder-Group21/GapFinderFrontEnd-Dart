// Decides how long a cache entry lives. It is asked every time an entry is created, updated or read,
// so the lifetime can depend on the moment and on the value itself.
// Every method returns the time to live from now; null means the entry never expires.
// "remaining" is the time the entry had left before the call (null if it had no expiry).
abstract class ExpiryPolicy<K, V> {
  // A new key is saved
  Duration? afterCreate(K key, V value);

  // A key that already existed is saved again
  Duration? afterUpdate(K key, V value, Duration? remaining);

  // A valid entry is read
  Duration? afterRead(K key, V value, Duration? remaining);
}

// Every entry lives the same time after it is saved; reading it changes nothing.
// This is the same rule the cache had with a plain ttl.
class FixedExpiry<K, V> extends ExpiryPolicy<K, V> {
  final Duration ttl;

  FixedExpiry(this.ttl);

  @override
  Duration? afterCreate(K key, V value) => ttl;

  @override
  Duration? afterUpdate(K key, V value, Duration? remaining) => ttl;

  @override
  Duration? afterRead(K key, V value, Duration? remaining) => remaining;
}

// An entry expires after being idle: every read starts the time again.
class SlidingExpiry<K, V> extends ExpiryPolicy<K, V> {
  final Duration idle;

  SlidingExpiry(this.idle);

  @override
  Duration? afterCreate(K key, V value) => idle;

  @override
  Duration? afterUpdate(K key, V value, Duration? remaining) => idle;

  @override
  Duration? afterRead(K key, V value, Duration? remaining) => idle;
}

// The lifetime is calculated from the key and the value when the entry is saved; reading it changes nothing.
class ValueBasedExpiry<K, V> extends ExpiryPolicy<K, V> {
  final Duration? Function(K key, V value) duration;

  ValueBasedExpiry(this.duration);

  @override
  Duration? afterCreate(K key, V value) => duration(key, value);

  @override
  Duration? afterUpdate(K key, V value, Duration? remaining) => duration(key, value);

  @override
  Duration? afterRead(K key, V value, Duration? remaining) => remaining;
}
