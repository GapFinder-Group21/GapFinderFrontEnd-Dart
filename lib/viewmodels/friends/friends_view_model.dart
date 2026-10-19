import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
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
  FriendsData({required this.freeNow, required this.inClass, required this.pendingRequests});
}

// State and logic of the friends tab
class FriendsViewModel extends ChangeNotifier {
  final FriendshipService _friendshipService;
  final GapService _gapService;
  final UserService _userService;
  final JoelLocalCache _localCache;

  FriendsViewModel({
    FriendshipService? friendshipService,
    GapService? gapService,
    UserService? userService,
    JoelLocalCache? localCache,
  })  : _friendshipService = friendshipService ?? FriendshipService(),
        _gapService = gapService ?? GapService(),
        _userService = userService ?? UserService(),
        _localCache = localCache ?? JoelLocalCache.instance;

  FriendsData? _data;
  bool _isLoading = true;
  bool _hasError = false;
  List<User> _searchResults = [];
  bool _isSearching = false;
  String? _errorMessage;
  bool _disposed = false;

  // Last loaded data (kept while reloading, like the old FutureBuilder)
  FriendsData? get data => _data;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  List<User> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;

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

  // Load the friends when the screen opens
  Future<void> init() => refresh();

  // Reload everything (pull to refresh and when the tab opens again)
  Future<void> refresh() async {
    _isLoading = true;
    _hasError = false;
    _notify();

    try {
      _data = await _loadFriends();
    } catch (e) {
      _data = null;
      _hasError = true;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // Searches users by name - GET /users/search?name=
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      _isSearching = false;
      _notify();
      return;
    }
    _isSearching = true;
    _notify();
    try {
      final results = await _userService.searchByName(query.trim());
      final currentUserId = await TokenStorage.getUserId();
      _searchResults = results.where((u) => u.id != currentUserId).toList();
      _notify();
    } catch (e) {
      debugPrint('Error searching users: $e');
    }
  }

  // Sends a friend request - POST /friendships
  // Returns null if there is no session, true if it was sent, false on error (see errorMessage)
  Future<bool?> sendFriendRequest(int targetUserId) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;
    try {
      await _friendshipService.sendRequest(userId, targetUserId);
      _searchResults = [];
      _isSearching = false;
      _notify();
      refresh();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    }
  }

  // Accepts a friend request - PATCH /friendships/{id}/accept
  // Same return values as sendFriendRequest
  Future<bool?> acceptRequest(int friendshipId) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;
    try {
      await _friendshipService.acceptRequest(friendshipId, userId);
      refresh();
      return true;
    } catch (e) {
      _errorMessage = 'Error accepting request: $e';
      return false;
    }
  }

  // Rejects a friend request - PATCH /friendships/{id}/reject
  // Same return values as sendFriendRequest
  Future<bool?> rejectRequest(int friendshipId) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;
    try {
      await _friendshipService.rejectRequest(friendshipId, userId);
      refresh();
      return true;
    } catch (e) {
      _errorMessage = 'Error rejecting request: $e';
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
    super.dispose();
  }
}
