import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;
import 'package:gapfinderfrontend_dart/core/cache/expiry_policy.dart';
import 'package:gapfinderfrontend_dart/core/cache/lru_cache.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/core/utils/client_id.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/chat_message_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/outbox_keys.dart';
import 'package:gapfinderfrontend_dart/models/chat_message.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/chat_inbox_service.dart';
import 'package:gapfinderfrontend_dart/services/chat_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/chat_processing.dart';
import 'package:gapfinderfrontend_dart/core/perf/perf_log.dart';

// Runs mergeChatMessages somewhere (an isolate in the app; replaced in tests if needed)
typedef ChatMerger = Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> payload);

// EVENTUAL CONNECTIVITY JOEL: SQLite + outbox queue (chat with a friend)
// State and logic of the chat with one friend: read and send messages, also without internet
class ChatViewModel extends ChangeNotifier {
  // CACHING JOEL: LRU with sliding expiry (10 chats, 5 min)
  // Estrategia: LRU cache. One entry per friend (key = friend id) with the whole chat in memory, so
  // opening a chat again shows it at once, without reading SQLite or the network.
  // - maxEntries 10: a student talks with a few friends at a time.
  // - SlidingExpiry 5 min: every read starts the time again, so an open chat stays; one not read
  //   for 5 min is dropped (the polling keeps the open one fresh anyway).
  static final LruCache<int, List<ChatMessage>> _cache = LruCache<int, List<ChatMessage>>(
    maxEntries: 10,
    name: 'chats',
    expiryPolicy: SlidingExpiry<int, List<ChatMessage>>(const Duration(minutes: 5)),
  );

  // Empties the chats in memory (logout and tests)
  static void clearChatCache() => _cache.clear();

  static const maxLength = 500;
  static const offlineMessage = 'Sin conexión · tus mensajes se enviarán cuando vuelva';
  static const queuedNotice = 'Sin conexión: tu mensaje se enviará cuando vuelva el internet';

  final User friend;
  final ChatService _chatService;
  final ChatMessageDao _dao;
  final ConnectivityService _connectivity;
  final OutboxService _outbox;
  final Future<int?> Function() _readUserId;
  final ChatMerger _merge;
  final ChatInboxService _inbox;
  final Duration pollEvery;

  ChatViewModel(
    this.friend, {
    ChatService? chatService,
    ChatMessageDao? dao,
    ConnectivityService? connectivity,
    OutboxService? outbox,
    Future<int?> Function()? readUserId,
    ChatMerger? merge,
    ChatInboxService? inbox,
    this.pollEvery = const Duration(seconds: 5),
  })  : _chatService = chatService ?? ChatService(),
        _dao = dao ?? ChatMessageDao(),
        _connectivity = connectivity ?? ConnectivityService.instance,
        _outbox = outbox ?? OutboxService.instance,
        _readUserId = readUserId ?? TokenStorage.getUserId,
        _inbox = inbox ?? ChatInboxService.instance,
        // MULTITHREADING JOEL: Isolate (merge in compute)
        _merge = merge ?? ((payload) => compute(mergeChatMessages, payload));

  List<ChatMessage> _messages = [];
  int? _userId;
  bool _isLoading = true;
  bool _isOffline = false;
  bool _fetching = false;
  bool _disposed = false;
  // Why the back refused each failed message (by clientId)
  final Map<String, String> _failReasons = {};
  Set<String> _pendingKeys = {};
  Timer? _pollTimer;
  AppLifecycleListener? _lifecycle;
  // True while the app is in the background: no polling
  bool _inBackground = false;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<Set<String>>? _pendingSub;

  List<ChatMessage> get messages => _messages;
  int? get userId => _userId;
  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  bool get isPolling => _pollTimer != null;
  String? failReason(String clientId) => _failReasons[clientId];

  // Opens the chat: memory → SQLite → network, then keeps it fresh while it is open
  Future<void> init() async {
    _userId = await _readUserId();
    if (_disposed || _userId == null) return;

    _isOffline = !_connectivity.isOnline;
    _connectivitySub = _connectivity.onStatusChange.listen(_onConnectivityChanged);
    _watchAppLifecycle();

    final cached = _cache.get(friend.id);
    if (cached != null) {
      debugPrint('HIT chat ${friend.id} ${_cache.describe()}');
      _messages = cached;
    } else {
      debugPrint('MISS chat ${friend.id} ${_cache.describe()}');
      try {
        _messages = await _dao.getConversation(_userId!, friend.id);
      } catch (e) {
        debugPrint('Could not read the saved chat: $e');
      }
    }
    _isLoading = false;
    // This chat is open: its messages are read (no unread number, no notification for this friend)
    _inbox.openChat(friend.id);
    _inbox.chatSeen(friend.id, _messages);
    _notify();

    // Watched after the chat is loaded, so pending messages saved before (even before a restart)
    // are checked against the queue
    _pendingSub = _outbox.pendingKeys.listen(_onPendingKeysChanged, onError: (Object e) {
      debugPrint('Error watching the outbox: $e');
    });

    if (!_isOffline) {
      await fetchNew();
      _startPolling();
    }
  }

  // Asks the back only for the messages newer than the last one we have (afterId), then merges them
  // in an isolate. Used when the chat opens and by the polling every 5 s.
  Future<void> fetchNew() async {
    final userId = _userId;
    // Micro-optimización (lifecycle): no requests to the back while the app is in the background
    if (userId == null || _fetching || _isOffline || _disposed || _inBackground) return;
    _fetching = true;
    try {
      PerfStats.chatPoll(_lastServerId());
      final body = await _chatService
          .getConversationBody(userId, friend.id, afterId: _lastServerId())
          .timeout(const Duration(seconds: 10));
      if (_disposed) return;
      if (body.trim() == '[]' || body.trim().isEmpty) return; // nothing new

      final merged = await _merge({
        'local': _messages.map((m) => m.toMap()).toList(),
        'remote': body,
      });
      if (_disposed) return;

      _messages = merged.map(ChatMessage.fromMap).toList();
      for (final m in _messages) {
        if (m.status == ChatMessageStatus.sent) _failReasons.remove(m.clientId);
      }
      _saveChat();
      _inbox.chatSeen(friend.id, _messages);
      _notify();
    } catch (e) {
      debugPrint('Could not load new chat messages: $e');
    } finally {
      _fetching = false;
    }
  }

  // Sends a message. Returns an error text when it cannot be sent at all, otherwise null.
  // It shows at once as pending; online it is sent now, offline it goes to the outbox.
  String? send(String text) {
    final content = text.trim();
    final userId = _userId;
    if (userId == null) return 'No hay una sesión activa';
    if (content.isEmpty) return 'Escribe un mensaje';
    if (content.length > maxLength) return 'El mensaje no puede tener más de $maxLength caracteres';

    final message = ChatMessage(
      clientId: newClientId(),
      senderId: userId,
      receiverId: friend.id,
      content: content,
      createdAt: DateTime.now(),
      status: ChatMessageStatus.pending,
    );
    _put(message);
    _inbox.touch(friend.id, message.createdAt, content); // this friend goes up in the Friends list
    _deliver(message);
    return null;
  }

  // Tries a failed message again with the same clientId (the back never stores it twice)
  void retry(String clientId) {
    final index = _messages.indexWhere((m) => m.clientId == clientId);
    if (index < 0) return;
    _failReasons.remove(clientId);
    final message = _messages[index].copyWith(status: ChatMessageStatus.pending);
    _put(message);
    _deliver(message);
  }

  void _deliver(ChatMessage message) {
    // In flight until it is sent or saved in the queue: the queue watcher must not count it as sent
    _sendingNow.add(message.clientId);
    if (_isOffline) {
      _queue(message).whenComplete(() => _sendingNow.remove(message.clientId));
      return;
    }

    // MULTITHREADING JOEL: Future with handler (send a chat message)
    // Estrategia: Future con handler. The send is not awaited: .then marks it sent, .catchError decides
    // between the outbox (no network) and failed (the back refused it), and .whenComplete refreshes
    // the screen. The UI never waits for the network.
    _chatService
        .send(friend.id, message.content, message.clientId)
        .then((stored) => _onSent(message, stored))
        .catchError((Object e) => _onSendError(message, e))
        .whenComplete(() {
          _sendingNow.remove(message.clientId);
          _notify();
        });
  }

  void _onSent(ChatMessage message, ChatMessage? stored) {
    // null means 409: the back already had it, so it counts as sent
    _put(stored ?? message.copyWith(status: ChatMessageStatus.sent));
  }

  Future<void> _onSendError(ChatMessage message, Object error) async {
    if (isNetworkError(error)) {
      await _queue(message);
      return;
    }
    // The back refused it (not friends, empty, too long): its reason is shown under the message
    final reason = error is ChatRefusedException
        ? error.message
        : userMessage(error, network: 'No se pudo enviar el mensaje');
    _markFailed(message.clientId, reason);
  }

  // Eventual connectivity: the message waits in the SQLite outbox and is sent when the network is back.
  // The dedupe key (user + clientId) keeps one row per message, however many times it is retried.
  Future<void> _queue(ChatMessage message) async {
    final key = OutboxKeys.chatMessage(message.senderId, message.clientId);
    try {
      await _outbox.enqueue(
        type: OutboxTypes.chatMessage,
        method: 'POST',
        endpoint: '/chats/messages',
        body: {'receiverId': friend.id, 'content': message.content, 'clientId': message.clientId},
        dedupeKey: key,
        label: friend.name,
      );
      _pendingKeys = {..._pendingKeys, key};
    } catch (e) {
      debugPrint('Could not queue the chat message: $e');
      _markFailed(message.clientId, 'No se pudo guardar el mensaje');
    }
  }

  // A chat key left the outbox: it was sent, unless the back refused it or it ran out of attempts
  Future<void> _onPendingKeysChanged(Set<String> keys) async {
    final userId = _userId;
    if (userId == null) return;
    final mine = keys.where((k) => OutboxKeys.isChatKey(k, userId)).toSet();
    _pendingKeys = mine;

    // Pending messages of this chat that are not in the queue anymore (also after the app restarts)
    final left = _messages
        .where((m) => m.status == ChatMessageStatus.pending && m.isMine(userId))
        .where((m) => !mine.contains(OutboxKeys.chatMessage(userId, m.clientId)))
        .where((m) => !_isSendingNow(m))
        .toList();
    if (left.isEmpty) return;

    for (final m in left) {
      final key = OutboxKeys.chatMessage(userId, m.clientId);
      final refusal = await _safe(() => _outbox.lastRefusalFor(key));
      if (refusal != null) {
        _markFailed(m.clientId, refusal.message);
      } else if (await _safe(() => _outbox.isExhausted(key)) == true) {
        _markFailed(m.clientId, 'No se pudo enviar el mensaje');
      } else {
        _put(m.copyWith(status: ChatMessageStatus.sent));
      }
    }
    _notify();
    fetchNew(); // brings the server ids of the messages just sent
  }

  // A message being sent online right now is pending but not queued: it is not "lost"
  final Set<String> _sendingNow = {};
  bool _isSendingNow(ChatMessage m) => _sendingNow.contains(m.clientId);

  void _onConnectivityChanged(bool online) {
    _isOffline = !online;
    _notify();
    // In the background the polling waits: it starts again when the app comes back
    if (online && !_inBackground) {
      fetchNew();
      _startPolling();
    } else {
      _stopPolling(); // no requests without internet: they would only fail
    }
  }

  // Polling is part of the feature (new messages every 5 s while the chat is open and online).
  // A Timer runs on the same isolate, so it is not a multithreading strategy.
  void _startPolling() {
    if (_pollTimer != null || _disposed || _inBackground) return;
    _pollTimer = Timer.periodic(pollEvery, (_) => fetchNew());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // Without a Flutter binding (plain unit tests) there is no listener: tests call handleAppLifecycle
  void _watchAppLifecycle() {
    if (_lifecycle != null) return;
    try {
      _lifecycle = AppLifecycleListener(onStateChange: handleAppLifecycle);
    } catch (_) {}
  }

  // Micro-optimización (lifecycle): the 5 s polling stops while the app is in the background
  @visibleForTesting
  void handleAppLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _inBackground = true;
      _stopPolling();
    } else if (state == AppLifecycleState.resumed && _inBackground) {
      _inBackground = false;
      if (!_isOffline) {
        fetchNew(); // new messages at once
        _startPolling();
      }
    }
  }

  int _lastServerId() {
    var last = 0;
    for (final m in _messages) {
      final id = m.serverId;
      if (id != null && id > last) last = id;
    }
    return last;
  }

  // Puts or replaces a message (by clientId), saves it and updates the cache
  void _put(ChatMessage message) {
    final index = _messages.indexWhere((m) => m.clientId == message.clientId);
    final list = [..._messages];
    if (index >= 0) {
      list[index] = message;
    } else {
      list.add(message);
    }
    _messages = list;
    final userId = _userId;
    if (userId != null) {
      _dao.upsert(userId, friend.id, message).catchError((Object e) {
        debugPrint('Could not save the chat message: $e');
      });
    }
    _cache.put(friend.id, _messages);
    _notify();
  }

  void _markFailed(String clientId, String reason) {
    final index = _messages.indexWhere((m) => m.clientId == clientId);
    if (index < 0) return;
    _failReasons[clientId] = reason;
    _put(_messages[index].copyWith(status: ChatMessageStatus.failed));
  }

  // Saves the whole chat after a network answer (SQLite + memory)
  void _saveChat() {
    final userId = _userId;
    if (userId == null) return;
    _cache.put(friend.id, _messages);
    _dao.upsertAll(userId, friend.id, _messages).catchError((Object e) {
      debugPrint('Could not save the chat: $e');
    });
  }

  Future<T?> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (_) {
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _inbox.closeChat(friend.id);
    _stopPolling();
    _connectivitySub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }
}
