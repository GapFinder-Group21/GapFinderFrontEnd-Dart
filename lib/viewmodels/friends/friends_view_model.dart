import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/cache/expiry_policy.dart';
import 'package:gapfinderfrontend_dart/core/cache/lru_cache.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/outbox_keys.dart';
import 'package:gapfinderfrontend_dart/models/friendship.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/friendship_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';

// A friend together with their current free gap (if any)
class FriendWithGap {
  final User user;
  final Gap? gap;
  FriendWithGap(this.user, this.gap);
}

// A friend request received, with the user who sent it
class PendingFriendRequest {
  final int friendshipId;
  final User user;
  PendingFriendRequest(this.friendshipId, this.user);
}

// Everything the screen shows: free friends, friends in class and pending requests
class FriendsData {
  final List<FriendWithGap> freeNow;
  final List<User> inClass;
  final List<PendingFriendRequest> pendingRequests;
  // True when it was read from the device: the gaps of the friends are not saved, so
  // without connection every friend goes in inClass and nobody is shown as free now
  final bool fromCache;
  FriendsData({
    required this.freeNow,
    required this.inClass,
    required this.pendingRequests,
    this.fromCache = false,
  });
}

// State and logic of the friends tab.
// Network falling back to cache: it asks the back and, if there is no connection (or it fails),
// shows what SQLite has saved. Send, accept and reject without connection go to the outbox.
class FriendsViewModel extends ChangeNotifier {
  final FriendshipService _friendshipService;
  final GapService _gapService;
  final UserService _userService;
  final JoelLocalCache _localCache;
  final ConnectivityService _connectivity;
  final OutboxService _outbox;

  // The screen never waits longer than this for the back
  static const loadTimeout = Duration(seconds: 20);

  // Results of the user search, in memory. It is static so it survives while the app is open,
  // even if the screen (and this ViewModel) is rebuilt.
  // - maxEntries 15: every search text is one entry, and while typing "a", "an", "ana" each prefix
  //   is a different one. 15 covers a few searches and their back and forth, and each entry is
  //   only a short list of users, so the memory used is tiny.
  // - 3 minutes with results: long enough for the user to type, delete and type again without asking
  //   the back every time, short enough that a new user or a changed name shows up soon.
  // - 30 seconds with no results: a new user can show up soon, so "nobody found" is not kept long.
  static final LruCache<String, List<User>> _searchCache = LruCache<String, List<User>>(
    maxEntries: 15,
    name: 'busqueda amigos',
    expiryPolicy: ValueBasedExpiry<String, List<User>>(searchExpiry),
  );

  // How long a search is kept: less when nobody was found
  @visibleForTesting
  static Duration? searchExpiry(String key, List<User> results) =>
      results.isEmpty ? const Duration(seconds: 30) : const Duration(minutes: 3);

  // Empties the search cache (for tests)
  @visibleForTesting
  static void clearSearchCache() => _searchCache.clear();

  // Same text with other capitals or extra spaces is the same search
  static String _searchKey(String query) => query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  FriendsViewModel({
    FriendshipService? friendshipService,
    GapService? gapService,
    UserService? userService,
    JoelLocalCache? localCache,
    ConnectivityService? connectivity,
    OutboxService? outbox,
  })  : _friendshipService = friendshipService ?? FriendshipService(),
        _gapService = gapService ?? GapService(),
        _userService = userService ?? UserService(),
        _localCache = localCache ?? JoelLocalCache.instance,
        _connectivity = connectivity ?? ConnectivityService.instance,
        _outbox = outbox ?? OutboxService.instance;

  FriendsData? _data;
  bool _isLoading = true;
  bool _hasError = false;
  List<User> _searchResults = [];
  bool _isSearching = false;
  String? _errorMessage;
  bool _disposed = false;

  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<Set<String>>? _pendingSub;
  bool _isOffline = false;
  DateTime? _lastUpdated;
  Set<String> _pendingKeys = {};
  bool _lastActionQueued = false;
  int _loadId = 0;

  // Last loaded data (kept while reloading, like the old FutureBuilder)
  FriendsData? get data => _data;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  List<User> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;
  bool get isOffline => _isOffline;
  // When the friends on screen were last updated (the network answer or the saved copy)
  DateTime? get lastUpdated => _lastUpdated;
  // True if the last send/accept/reject was queued instead of sent
  bool get lastActionQueued => _lastActionQueued;

  // True if a friend request to this user is waiting in the outbox
  bool isSendPending(int targetUserId) => _pendingKeys.contains(OutboxKeys.friendRequestSend(targetUserId));

  // True if a decision (accept or reject) on this request is waiting in the outbox
  bool isDecisionPending(int friendshipId) => _pendingKeys.contains(OutboxKeys.friendRequestDecision(friendshipId));

  // All the friends, used by the header
  List<User> get allFriends => [
        ...?_data?.freeNow.map((f) => f.user),
        ...?_data?.inClass,
      ];

  // True when there are no friends and no requests
  bool get hasNoFriends =>
      _data != null &&
      _data!.freeNow.isEmpty &&
      _data!.inClass.isEmpty &&
      _data!.pendingRequests.isEmpty;

  // Load the friends when the screen opens and start listening to the connection and the outbox
  Future<void> init() {
    _isOffline = !_connectivity.isOnline;
    _connectivitySub ??= _connectivity.onStatusChange.listen(_onConnectivityChanged);
    // Estrategia: Stream. The outbox emits the set of pending keys every time it changes
    _pendingSub ??= _outbox.pendingKeys.listen(_onPendingKeysChanged);
    return refresh();
  }

  // Back online: reload by itself. Offline: keep what is on screen (the banner explains it)
  void _onConnectivityChanged(bool online) {
    _isOffline = !online;
    _notify();
    if (online) refresh(silent: true);
  }

  // When an action leaves the outbox (it was sent) the friends are reloaded
  void _onPendingKeysChanged(Set<String> keys) {
    final mine = keys.where(OutboxKeys.isFriendKey).toSet();
    final sent = _pendingKeys.difference(mine);
    _pendingKeys = mine;
    _notify();

    if (sent.isEmpty) return;
    if (sent.any((k) => k.startsWith('friend_request_send:'))) {
      _searchResults = [];
      _isSearching = false;
    }
    refresh(silent: true);
  }

  // Pull to refresh: checks the connection for real first, so it can notice it is back
  Future<void> pullToRefresh() async {
    await _connectivity.checkNow();
    _isOffline = !_connectivity.isOnline;
    await refresh();
  }

  // Reload everything (pull to refresh and when the tab opens again).
  // From the back if there is connection; if not, or if it fails, from SQLite.
  // silent: do not show the spinner (used when the connection comes back)
  Future<void> refresh({bool silent = false}) async {
    final loadId = ++_loadId;
    if (!silent) _isLoading = true;
    _hasError = false;
    _notify();

    FriendsData? data;
    DateTime? updated;
    try {
      if (_isOffline) throw const _OfflineException();
      data = await _loadFriends().timeout(loadTimeout);
      updated = DateTime.now();
    } catch (e) {
      if (e is! _OfflineException) debugPrint('Friends not loaded, using the saved ones: $e');
      final cached = await _loadFromCache();
      data = cached?.data;
      updated = cached?.savedAt;
    }

    // A newer reload already started, so this result is old
    if (loadId != _loadId) return;

    if (data != null) {
      _data = data;
      _lastUpdated = updated;
    } else if (!silent || _data == null) {
      _data = null;
      _hasError = true;
    }
    _isLoading = false;
    _notify();
  }

  // Friends and requests saved in SQLite; null if nothing was saved yet
  Future<({FriendsData data, DateTime? savedAt})?> _loadFromCache() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;

    return _localCache.safeRead('friends', () async {
      final friends = await _localCache.friends.getAllForUser(userId);
      final requests = await _localCache.friendRequests.getAllForUser(userId);
      final savedAt = await _localCache.friends.lastSavedAt(userId) ??
          await _localCache.friendRequests.lastSavedAt(userId);
      if (savedAt == null) return null;

      final pending = requests
          .where((r) => r.requester != null)
          .map((r) => PendingFriendRequest(r.id, r.requester!))
          .toList();
      final data = FriendsData(freeNow: [], inClass: friends, pendingRequests: pending, fromCache: true);
      return (data: data, savedAt: savedAt);
    });
  }

  // Searches users by name - GET /users/search?name=
  Future<void> search(String query) async {
    // Searching needs the back: the field is disabled without connection (clearing still works)
    if (_isOffline && query.trim().isNotEmpty) return;
    if (query.trim().isEmpty) {
      _searchResults = [];
      _isSearching = false;
      _notify();
      return;
    }
    _isSearching = true;
    _notify();
    try {
      final key = _searchKey(query);
      var results = _searchCache.get(key);
      if (results != null) {
        debugPrint('HIT "$key" ${_searchCache.describe()}');
      } else {
        debugPrint('MISS "$key" ${_searchCache.describe()}');
        results = await _userService.searchByName(query.trim());
        _searchCache.put(key, results);
      }
      final currentUserId = await TokenStorage.getUserId();
      _searchResults = results.where((u) => u.id != currentUserId).toList();
      _notify();
    } catch (e) {
      debugPrint('Error searching users: $e');
    }
  }

  // Sends a friend request - POST /friendships
  // Returns null if there is no session, true if it was sent (or queued, see lastActionQueued),
  // false on error (see errorMessage)
  Future<bool?> sendFriendRequest(int targetUserId) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;
    _lastActionQueued = false;

    Future<bool> queue() => _queue(
          OutboxTypes.friendRequestSend,
          'POST',
          '/friendships',
          OutboxKeys.friendRequestSend(targetUserId),
          body: {'requesterId': userId, 'receiverId': targetUserId},
        );

    // Without connection it goes to the outbox with one key per user
    if (_isOffline) return queue();

    // Estrategia: Future con handler. The answer is handled with .then (it worked) and
    // .catchError (it failed) instead of await + try/catch.
    return _friendshipService.sendRequest(userId, targetUserId).then<bool?>((_) {
      _searchResults = [];
      _isSearching = false;
      _notify();
      refresh();
      return true;
    }).catchError((Object e) async {
      if (isNetworkError(e)) return queue();
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    });
  }

  // Accepts a friend request - PATCH /friendships/{id}/accept
  // Same return values as sendFriendRequest
  Future<bool?> acceptRequest(int friendshipId) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;
    _lastActionQueued = false;

    final endpoint = '/friendships/$friendshipId/accept?userId=$userId';
    final key = OutboxKeys.friendRequestDecision(friendshipId);
    if (_isOffline) return _queue(OutboxTypes.friendRequestAccept, 'PATCH', endpoint, key);

    try {
      await _friendshipService.acceptRequest(friendshipId, userId);
      refresh();
      return true;
    } catch (e) {
      if (isNetworkError(e)) return _queue(OutboxTypes.friendRequestAccept, 'PATCH', endpoint, key);
      _errorMessage = 'Error accepting request: $e';
      return false;
    }
  }

  // Rejects a friend request - PATCH /friendships/{id}/reject
  // Same return values as sendFriendRequest
  Future<bool?> rejectRequest(int friendshipId) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;
    _lastActionQueued = false;

    final endpoint = '/friendships/$friendshipId/reject?userId=$userId';
    final key = OutboxKeys.friendRequestDecision(friendshipId);
    if (_isOffline) return _queue(OutboxTypes.friendRequestReject, 'PATCH', endpoint, key);

    try {
      await _friendshipService.rejectRequest(friendshipId, userId);
      refresh();
      return true;
    } catch (e) {
      if (isNetworkError(e)) return _queue(OutboxTypes.friendRequestReject, 'PATCH', endpoint, key);
      _errorMessage = 'Error rejecting request: $e';
      return false;
    }
  }

  // Saves the action in the outbox to send it when the connection comes back.
  // The dedupe key makes the outbox keep only one pending action per key, so tapping many
  // times leaves one (enqueue returns false and nothing is duplicated).
  Future<bool> _queue(String type, String method, String endpoint, String key, {Map<String, dynamic>? body}) async {
    try {
      await _outbox.enqueue(type: type, method: method, endpoint: endpoint, body: body, dedupeKey: key);
      _pendingKeys = {..._pendingKeys, key}; // the buttons change at once, the stream confirms it
      _lastActionQueued = true;
      _notify();
      return true;
    } catch (e) {
      debugPrint('Could not queue the action: $e');
      _errorMessage = 'No se pudo guardar la acción para enviarla después';
      return false;
    }
  }

  // Loads the friends (split into "with GAP now" and "in class") and the pending requests
  Future<FriendsData> _loadFriends() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return FriendsData(freeNow: [], inClass: [], pendingRequests: []);

    final friends = await _friendshipService.getFriendsByUser(userId);
    final pending = await _friendshipService.getPendingReceived(userId);

    final pendingRequests = <PendingFriendRequest>[];
    final savedRequests = <Friendship>[];
    for (final p in pending) {
      User? u = p.requester;
      if (u == null && p.requesterId != null) {
        try {
          u = await _userService.getUser(p.requesterId!);
        } catch (_) {}
      }
      if (u != null) {
        pendingRequests.add(PendingFriendRequest(p.id, u));
        savedRequests.add(Friendship(
          id: p.id,
          status: p.status,
          createdAt: p.createdAt,
          requesterId: p.requesterId ?? u.id,
          receiverId: p.receiverId,
          requester: u,
        ));
      }
    }

    // Cached on network response (never blocks the screen)
    _localCache.saveFriends(userId, friends, savedRequests);

    final now = DateTime.now();
    final freeNow = <FriendWithGap>[];
    final inClass = <User>[];

    final friendsGaps = await Future.wait(friends.map(_loadFriendGaps));

    for (var i = 0; i < friends.length; i++) {
      final u = friends[i];
      final current = friendsGaps[i]
          .where((g) => !now.isBefore(g.startTime) && now.isBefore(g.endTime))
          .firstOrNull;

      if (current != null) {
        freeNow.add(FriendWithGap(u, current));
      } else {
        inClass.add(u);
      }
    }

    return FriendsData(freeNow: freeNow, inClass: inClass, pendingRequests: pendingRequests);
  }

  // Gets a friend's gaps for this week - GET /gaps/user/{userId}
  // Only the friend can generate their own gaps (the back answers 403 otherwise),
  // so a friend without gaps is shown as "in class"
  Future<List<Gap>> _loadFriendGaps(User friend) async {
    try {
      return await _gapService.getUserGaps(friend.id);
    } catch (e) {
      debugPrint('No se pudieron cargar los gaps de ${friend.name}: $e');
      return [];
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivitySub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }
}

// Thrown inside refresh() to go straight to the saved data when there is no connection
class _OfflineException implements Exception {
  const _OfflineException();
}
