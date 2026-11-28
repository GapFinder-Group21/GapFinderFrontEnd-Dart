import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/chat_message.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/chat_service.dart';
import 'package:gapfinderfrontend_dart/services/friendship_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_reminder_service.dart';

// What the inbox knows about the chat with one friend
class ChatInboxEntry {
  // Newest server id already counted (only newer messages are asked from the back)
  int lastId;
  // Messages from the friend that the user has not read
  int unread;
  // When the newest message of the chat (sent or received) was written
  DateTime? lastAt;
  // Text of the newest message
  String? preview;

  ChatInboxEntry({this.lastId = 0, this.unread = 0, this.lastAt, this.preview});

  Map<String, dynamic> toJson() => {
        'lastId': lastId,
        'unread': unread,
        'lastAt': lastAt?.toIso8601String(),
        'preview': preview,
      };

  factory ChatInboxEntry.fromJson(Map<String, dynamic> json) => ChatInboxEntry(
        lastId: (json['lastId'] as num?)?.toInt() ?? 0,
        unread: (json['unread'] as num?)?.toInt() ?? 0,
        lastAt: json['lastAt'] == null ? null : DateTime.tryParse(json['lastAt'] as String),
        preview: json['preview'] as String?,
      );
}

// Shows the notification of a new message (replaced in tests)
typedef ChatNotifier = Future<void> Function(int friendId, String title, String body);

// New chat messages and unread counter.
// Looks for new messages of every friend every 10 s while the app is open (the back has no push and no
// "unread" endpoint, so it asks each chat only for the messages newer than the last one it knows: afterId).
// For each new message of a friend it counts it as unread and shows a notification, unless that chat is
// open. The counters and the time of the last message are saved per user, and the Friends tab uses them to
// put the friends with the most recent messages first and to show the number of unread messages.
// In the background the polling stops (same rule as the other pollers): when the app comes back it checks
// at once, so the messages that arrived meanwhile are notified then.
class ChatInboxService extends ChangeNotifier {
  static final ChatInboxService instance = ChatInboxService();

  static const pollEvery = Duration(seconds: 10);
  static const _friendsRefreshEvery = Duration(minutes: 2);
  static const _prefsPrefix = 'chat_inbox_v1:';
  // A chat has at most this many pages of 50 messages read when it is first seen (guards a loop)
  static const _maxBaselinePages = 40;

  final ChatService _chat;
  final FriendshipService _friendships;
  final ConnectivityService _connectivity;
  final Future<int?> Function() _readUserId;
  final ChatNotifier _notifier;
  final Future<List<User>> Function(int userId)? _loadFriends;

  ChatInboxService({
    ChatService? chat,
    FriendshipService? friendships,
    ConnectivityService? connectivity,
    Future<int?> Function()? readUserId,
    ChatNotifier? notifier,
    this._loadFriends,
  })  : _chat = chat ?? ChatService(),
        _friendships = friendships ?? FriendshipService(),
        _connectivity = connectivity ?? ConnectivityService.instance,
        _readUserId = readUserId ?? TokenStorage.getUserId,
        _notifier = notifier ?? _showNotification;

  static Future<void> _showNotification(int friendId, String title, String body) =>
      GapReminderService().showChatMessage(friendId, title, body);

  final Map<int, ChatInboxEntry> _entries = {};
  List<User> _friendList = [];
  DateTime? _friendsLoadedAt;
  int? _userId;
  int? _activeChat;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _started = false;
  bool _paused = false;
  bool _polling = false;
  bool _disposed = false;

  // ─── What the screens read ───────────────────────────────────────────────

  int unreadFor(int friendId) => _entries[friendId]?.unread ?? 0;
  DateTime? lastMessageAt(int friendId) => _entries[friendId]?.lastAt;
  String? previewFor(int friendId) => _entries[friendId]?.preview;
  int get totalUnread => _entries.values.fold(0, (sum, e) => sum + e.unread);
  bool get isStarted => _started;

  // The same list with the friends that have the most recent messages first (the others keep their order)
  List<T> sortByRecent<T>(List<T> items, int Function(T item) friendIdOf) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final x = lastMessageAt(friendIdOf(a));
      final y = lastMessageAt(friendIdOf(b));
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return sorted;
  }

  // ─── Life of the service ─────────────────────────────────────────────────

  // Starts looking for new messages (safe to call many times). Needs a session.
  Future<void> start() async {
    if (_started || _disposed) return;
    final userId = await _readUserId();
    if (userId == null || _started || _disposed) return;

    _started = true;
    _paused = false;
    if (_userId != userId) {
      _entries.clear();
      _friendList = [];
      _friendsLoadedAt = null;
      _userId = userId;
    }
    await _load(userId);
    _watchAppLifecycle();
    _timer = Timer.periodic(pollEvery, (_) => pollOnce());
    unawaited(pollOnce());
  }

  // Stops the polling (the main screen was closed)
  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  // Logout: forget everything of the user that leaves, in memory and on the phone
  Future<void> reset() async {
    final userId = _userId;
    stop();
    _entries.clear();
    _friendList = [];
    _friendsLoadedAt = null;
    _activeChat = null;
    _userId = null;
    if (userId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('$_prefsPrefix$userId');
      } catch (e) {
        debugPrint('Could not clear the chat inbox: $e');
      }
    }
    _notify();
  }

  void _watchAppLifecycle() {
    if (_lifecycle != null) return;
    try {
      _lifecycle = AppLifecycleListener(onStateChange: handleAppLifecycle);
    } catch (_) {
      // Without a Flutter binding (plain unit tests) there is no listener
    }
  }

  @visibleForTesting
  void handleAppLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _paused = true;
    } else if (state == AppLifecycleState.resumed && _paused) {
      _paused = false;
      unawaited(pollOnce()); // the messages that arrived meanwhile, at once
    }
  }

  // ─── Called by the chat screen ───────────────────────────────────────────

  // The chat with this friend is on screen: its messages are read and no notification is needed
  void openChat(int friendId) {
    _activeChat = friendId;
    final entry = _entries[friendId];
    if (entry != null && entry.unread > 0) {
      entry.unread = 0;
      _save();
      _notify();
    }
    GapReminderService().cancelChatMessage(friendId).catchError((Object _) {});
  }

  void closeChat(int friendId) {
    if (_activeChat == friendId) _activeChat = null;
  }

  // The chat screen has these messages: they are read, so they never count as unread
  void chatSeen(int friendId, List<ChatMessage> messages) {
    final entry = _entries.putIfAbsent(friendId, ChatInboxEntry.new);
    var changed = false;
    for (final m in messages) {
      final id = m.serverId;
      if (id != null && id > entry.lastId) {
        entry.lastId = id;
        changed = true;
      }
      if (entry.lastAt == null || m.createdAt.isAfter(entry.lastAt!)) {
        entry.lastAt = m.createdAt;
        entry.preview = m.content;
        changed = true;
      }
    }
    if (entry.unread != 0) {
      entry.unread = 0;
      changed = true;
    }
    if (changed) {
      _save();
      _notify();
    }
  }

  // The user wrote to a friend: that chat goes up in the list at once
  void touch(int friendId, DateTime at, String content) {
    final entry = _entries.putIfAbsent(friendId, ChatInboxEntry.new);
    if (entry.lastAt == null || at.isAfter(entry.lastAt!)) {
      entry.lastAt = at;
      entry.preview = content;
    }
    _save();
    _notify();
  }

  // ─── Polling ─────────────────────────────────────────────────────────────

  // One round: asks every friend's chat for what is new. Public so tests (and resume) can run it.
  Future<void> pollOnce() async {
    final userId = _userId;
    if (userId == null || _polling || _paused || _disposed || !_connectivity.isOnline) return;
    _polling = true;
    try {
      await _refreshFriendsIfNeeded(userId);
      await Future.wait(_friendList.map((f) => _checkFriend(userId, f)));
    } catch (e) {
      debugPrint('Chat inbox round failed: $e');
    } finally {
      _polling = false;
    }
  }

  Future<void> _refreshFriendsIfNeeded(int userId) async {
    final loadedAt = _friendsLoadedAt;
    if (loadedAt != null && DateTime.now().difference(loadedAt) < _friendsRefreshEvery) return;
    try {
      _friendList = await (_loadFriends ?? _friendships.getFriendsByUser)(userId)
          .timeout(const Duration(seconds: 10));
      _friendsLoadedAt = DateTime.now();
    } catch (e) {
      debugPrint('Chat inbox could not load the friends: $e');
      if (_friendList.isEmpty) {
        try {
          _friendList = await JoelLocalCache.instance.friends.getAllForUser(userId);
        } catch (_) {}
      }
    }
  }

  Future<void> _checkFriend(int userId, User friend) async {
    try {
      final entry = _entries[friend.id];
      if (entry == null) {
        await _baseline(userId, friend);
        return;
      }

      final body = await _chat
          .getConversationBody(userId, friend.id, afterId: entry.lastId)
          .timeout(const Duration(seconds: 10));
      if (body.trim().isEmpty || body.trim() == '[]') return;
      _apply(userId, friend, _parse(body));
    } catch (e) {
      debugPrint('Chat inbox could not check ${friend.name}: $e');
    }
  }

  // First time this chat is seen: what is already there counts as read (no notification for old messages)
  Future<void> _baseline(int userId, User friend) async {
    final entry = ChatInboxEntry();
    for (var page = 0; page < _maxBaselinePages; page++) {
      final body = await _chat
          .getConversationBody(userId, friend.id, afterId: entry.lastId)
          .timeout(const Duration(seconds: 10));
      if (body.trim().isEmpty || body.trim() == '[]') break;
      final messages = _parse(body);
      if (messages.isEmpty) break;
      for (final m in messages) {
        final id = m.serverId ?? 0;
        if (id > entry.lastId) entry.lastId = id;
        if (entry.lastAt == null || m.createdAt.isAfter(entry.lastAt!)) {
          entry.lastAt = m.createdAt;
          entry.preview = m.content;
        }
      }
    }
    // The chat screen may have registered this friend while the pages were loading
    final current = _entries[friend.id];
    if (current == null) {
      _entries[friend.id] = entry;
    } else if (entry.lastId > current.lastId) {
      current.lastId = entry.lastId;
    }
    _save();
    _notify();
  }

  List<ChatMessage> _parse(String body) {
    final list = jsonDecode(body) as List;
    return list.map((m) => ChatMessage.fromServer(m as Map<String, dynamic>)).toList();
  }

  // Counts the new messages of one friend and notifies the ones that came from them
  void _apply(int userId, User friend, List<ChatMessage> messages) {
    final entry = _entries.putIfAbsent(friend.id, ChatInboxEntry.new);
    // The chat screen may have seen some of these while the request was in the air
    final fresh = messages.where((m) => (m.serverId ?? 0) > entry.lastId).toList();
    if (fresh.isEmpty) return;

    var incoming = 0;
    ChatMessage? lastIncoming;
    for (final m in fresh) {
      final id = m.serverId ?? 0;
      if (id > entry.lastId) entry.lastId = id;
      if (entry.lastAt == null || m.createdAt.isAfter(entry.lastAt!)) {
        entry.lastAt = m.createdAt;
        entry.preview = m.content;
      }
      if (m.senderId != userId) {
        incoming++;
        lastIncoming = m;
      }
    }

    final shouldNotify = incoming > 0 && _activeChat != friend.id;
    if (shouldNotify) entry.unread += incoming;
    _save();
    _notify();

    if (shouldNotify) {
      final body = incoming == 1 ? lastIncoming!.content : '$incoming mensajes nuevos';
      _notifier(friend.id, friend.name, body).catchError((Object e) {
        debugPrint('Could not show the chat notification: $e');
      });
    }
  }

  // ─── Saved copy (so the counters survive closing the app) ────────────────

  Future<void> _load(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$userId');
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _entries
        ..clear()
        ..addAll(map.map((k, v) => MapEntry(int.parse(k), ChatInboxEntry.fromJson(v as Map<String, dynamic>))));
      _notify();
    } catch (e) {
      debugPrint('Could not read the chat inbox: $e');
    }
  }

  void _save() {
    final userId = _userId;
    if (userId == null) return;
    final raw = jsonEncode(_entries.map((k, v) => MapEntry(k.toString(), v.toJson())));
    SharedPreferences.getInstance().then((prefs) => prefs.setString('$_prefsPrefix$userId', raw)).catchError((Object e) {
      debugPrint('Could not save the chat inbox: $e');
      return false;
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
