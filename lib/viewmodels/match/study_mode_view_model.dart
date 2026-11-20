import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/core/utils/client_id.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_outbox.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_period_dao.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/study_mode_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_periods_cache.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_plan_processing.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// Runs buildStudyPlan somewhere (another isolate in the app; called directly in tests)
typedef StudyPlanner = Future<StudyPlan> Function(StudyPlanPayload payload);

// State and logic of the study mode screen: turn it on for a while ("Estoy estudiando ahora"), hide a gap of
// the week and remove the periods. Everything also works without internet.
class StudyModeViewModel extends ChangeNotifier with OfflineAwareMixin {
  static const queuedNotice = 'Se sincronizará al volver la conexión';
  static const noSessionMessage = 'No hay una sesión activa';
  static const loadFailedMessage = 'No pudimos cargar tu modo estudio';
  static const saveFailedMessage = 'No se pudo guardar el modo estudio. Intenta de nuevo.';
  static const removeFailedMessage = 'No se pudo quitar el periodo. Intenta de nuevo.';
  static const noGapMessage = 'Ahora no estás en un gap';
  static const gapEndedMessage = 'Este gap ya terminó';

  // How far ahead the gaps of the week are listed
  static const _gapsAhead = Duration(days: 7);

  final StudyModeService _service;
  final GapService _gapService;
  final StudyPeriodDao _dao;
  final StudyModePrefs _prefs;
  final JoelLocalCache _localCache;
  final OutboxService _outbox;
  final ConnectivityService _connectivity;
  final Future<int?> Function() _readUserId;
  final StudyPlanner _plan;
  final DateTime Function() _clock;

  StudyModeViewModel({
    StudyModeService? service,
    GapService? gapService,
    StudyPeriodDao? dao,
    StudyModePrefs? prefs,
    JoelLocalCache? localCache,
    OutboxService? outbox,
    ConnectivityService? connectivity,
    Future<int?> Function()? readUserId,
    StudyPlanner? plan,
    DateTime Function()? clock,
  })  : _service = service ?? StudyModeService(),
        _gapService = gapService ?? GapService(),
        _dao = dao ?? StudyPeriodDao(),
        _prefs = prefs ?? StudyModePrefs(),
        _localCache = localCache ?? JoelLocalCache.instance,
        _outbox = outbox ?? OutboxService.instance,
        _connectivity = connectivity ?? ConnectivityService.instance,
        _readUserId = readUserId ?? TokenStorage.getUserId,
        _plan = plan ?? buildStudyPlanInIsolate,
        _clock = clock ?? DateTime.now;

  int? _userId;
  // The periods that have not ended (active now or later), the earliest first
  List<StudyPeriod> _periods = [];
  // The gaps of the week that have not ended
  List<Gap> _gaps = [];
  StudyPlan _studyPlan = StudyPlan.empty;
  StudyDuration _duration = StudyDuration.oneHour;
  bool _isLoading = true;
  String? _error;
  String? _notice;
  bool _disposed = false;
  int _loadSeq = 0;
  int _planSeq = 0;
  StreamSubscription<Set<String>>? _pendingSub;
  // Keys of my study periods that wait in the outbox
  Set<String> _pendingKeys = {};
  // Periods this ViewModel is adding or removing right now: the outbox watcher must not judge them yet
  final Set<String> _busy = {};
  // Outbox keys that left while their period was busy: they are judged when the action ends
  final Set<String> _deferred = {};

  // The connection the ViewModel was given (the singleton in the app, a fake in tests)
  @override
  bool get hasConnection => _connectivity.isOnline;

  int? get userId => _userId;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // The periods that have not ended, the earliest first
  List<StudyPeriod> get periods => _periods.where((p) => !p.hasEndedAt(_clock())).toList();

  // The gaps of the week that have not ended, the earliest first
  List<Gap> get gaps => _gaps;

  List<Gap> get todayGaps {
    final now = _clock();
    return _gaps.where((g) => _sameDay(g.startTime, now)).toList();
  }

  List<Gap> get laterGaps {
    final now = _clock();
    return _gaps.where((g) => !_sameDay(g.startTime, now)).toList();
  }

  // The gap the user is in right now (null if there is none)
  Gap? get currentGap {
    final now = _clock();
    for (final gap in _gaps) {
      if (!gap.startTime.isAfter(now) && gap.endTime.isAfter(now)) return gap;
    }
    return null;
  }

  // The chip that is selected. "Hasta que termine el gap" needs a gap to end, so without one it is not
  // available and the 1 h chip is shown instead (the saved preference is not changed).
  StudyDuration get selectedDuration =>
      _duration == StudyDuration.untilGapEnds && currentGap == null ? StudyDuration.oneHour : _duration;

  bool get canUseGapDuration => currentGap != null;

  // When the study block the user is in right now ends (null if they are not studying now). It is read
  // against the clock every time, so it clears by itself when the period ends.
  DateTime? get activeUntil => activeStudyUntil(_periods, _clock());

  // The state of the "Estoy estudiando ahora" switch
  bool get isStudyingNow => activeUntil != null;

  // Until when the gap stays hidden (null if it is not hidden)
  DateTime? hiddenUntil(Gap gap) {
    final until = _studyPlan.hiddenUntil(gap.id);
    return until != null && until.isAfter(_clock()) ? until : null;
  }

  // The user can turn the gap's switch off only if the period that hides it was made for that gap.
  // A gap hidden by the study mode of "now" is turned off with the main switch.
  bool hasOwnPeriod(Gap gap) => periods.any((p) => p.gapId == gap.id);

  // The period waits in the outbox: it shows "Pendiente de enviar"
  bool isPending(StudyPeriod period) => !period.synced;

  // Message for a SnackBar (queued, refused). It is read once.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  // Loads the screen: what is saved first, then the back. It reloads by itself when the connection comes back.
  Future<void> init() async {
    listenToConnectivity(onRestored: refresh);
    try {
      _userId = await _readUserId();
    } catch (e) {
      debugPrint('No se pudo leer el usuario: $e');
    }

    final userId = _userId;
    if (userId == null) {
      _error = noSessionMessage;
      _isLoading = false;
      _notify();
      return;
    }

    _duration = await _safe<StudyDuration?>(() => _prefs.get(userId)) ?? StudyDuration.oneHour;
    return refresh();
  }

  // Pull to refresh: checks the connection for real first, so it can notice it is back
  Future<void> pullToRefresh() async {
    await _connectivity.checkNow();
    await refresh();
  }

  // Shows what is saved (memory → SQLite) at once and then, with connection, asks the back.
  // The last load to START wins: an answer that arrives after a newer load began is ignored.
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    final seq = ++_loadSeq;
    _error = null;

    await _showSaved(userId, seq);
    if (seq != _loadSeq) return;

    // Estrategia: Eventual connectivity. Without connection the periods saved in SQLite stay on screen
    // (the ones turned on offline included) with the offline banner.
    if (!hasConnection) {
      markFromCache(lastUpdated);
      _isLoading = false;
      _notify();
      return;
    }

    // Estrategia: Multithreading (Future with handler). The gaps of the week and the study periods are
    // asked to the back at the same time (Future.wait) and the answer is handled with .then / .catchError /
    // .whenComplete, so the screen never waits for the network. The cross of both lists runs in an isolate.
    return Future.wait<Object>([
      _gapService.getUserGaps(userId),
      _service.getPeriods(userId),
    ])
        .timeout(OfflineAwareMixin.loadTimeout)
        .then((results) => _onLoaded(seq, userId, results))
        .catchError((Object e) => _onError(seq, e))
        .whenComplete(() => _onDone(seq));
  }

  // Memory (LRU) → SQLite. The saved gaps of the week come from the Match tab's local copy.
  Future<void> _showSaved(int userId, int seq) async {
    final now = _clock();

    var periods = StudyPeriodsCache.read(userId);
    if (periods == null) {
      final saved = await _safe(() => _dao.getForUser(userId)) ?? <StudyPeriod>[];
      periods = saved.where((p) => !p.hasEndedAt(now)).toList();
      StudyPeriodsCache.write(userId, periods, notify: false);
    }

    if (_gaps.isEmpty) {
      final savedGaps = await _localCache.safeRead<List<Gap>>('gaps', () => _localCache.gaps.get(userId));
      if (savedGaps != null) _gaps = _upcoming(savedGaps, now);
    }
    if (seq != _loadSeq) return;

    _periods = List.of(periods);
    await _replan();
    if (seq != _loadSeq) return;

    // Something to show, or no way to get it: the spinner is not needed
    _isLoading = _periods.isEmpty && _gaps.isEmpty && hasConnection;
    _watchOutbox();
    _notify();
  }

  // The back answered: merge its periods with the ones waiting in the outbox, save them and cross them
  Future<void> _onLoaded(int seq, int userId, List<Object> results) async {
    if (seq != _loadSeq) return;
    final gaps = results[0] as List<Gap>;
    final server = results[1] as List<StudyPeriod>;
    final now = _clock();

    _localCache.saveGaps(userId, gaps);

    // The user is turning something on or off right now: this answer may not know it yet. The next load will.
    if (_busy.isNotEmpty) return;

    final pending = await _pendingKeysSnapshot();
    final local = await _safe(() => _dao.getForUser(userId)) ?? <StudyPeriod>[];
    final merged = mergeStudyPeriods(userId: userId, local: local, server: server, pendingKeys: pending, now: now);
    if (_busy.isNotEmpty) return;

    await _safe(() => _dao.replaceAllForUser(userId, merged));
    if (seq != _loadSeq) return;

    _periods = merged;
    _gaps = _upcoming(gaps, now);
    _publish(userId);
    await _replan();
    markFresh();
    _error = null;
  }

  // The load failed. No connection: the saved data stays and the banner says so. A real error of the
  // back is shown to the user.
  void _onError(int seq, Object error) {
    if (seq != _loadSeq) return;
    debugPrint('Error cargando el modo estudio: $error');
    if (isNetworkError(error)) {
      markFromCache(lastUpdated);
    } else {
      _error = userMessage(error, network: loadFailedMessage);
    }
  }

  void _onDone(int seq) {
    if (seq != _loadSeq) return;
    _isLoading = false;
    _notify();
  }

  // The chip of the duration; it is remembered for the next time (SharedPreferences)
  Future<void> selectDuration(StudyDuration duration) async {
    if (duration == StudyDuration.untilGapEnds && currentGap == null) return;
    _duration = duration;
    _notify();
    final userId = _userId;
    if (userId != null) await _safe(() => _prefs.set(userId, duration));
  }

  // Turns the study mode on from now for the selected duration.
  // Returns null when it was saved (see takeNotice if it is waiting for the connection), or the error message.
  Future<String?> startStudying() async {
    final userId = _userId;
    if (userId == null) return noSessionMessage;
    final now = _clock();
    if (activeStudyUntil(_periods, now) != null) return null; // the switch is already on

    final duration = selectedDuration;
    DateTime end;
    int? gapId;
    if (duration == StudyDuration.untilGapEnds) {
      final gap = currentGap;
      if (gap == null) return noGapMessage;
      end = gap.endTime;
      gapId = gap.id;
    } else {
      end = now.add(Duration(minutes: duration.minutes));
    }

    return _add(StudyPeriod(
      clientId: newClientId(),
      userId: userId,
      startTime: now,
      endTime: _clampEnd(now, end),
      gapId: gapId,
    ));
  }

  // Turns the study mode off: removes the periods that are going on right now
  Future<String?> stopStudying() async {
    final now = _clock();
    String? error;
    for (final period in _periods.where((p) => p.isActiveAt(now)).toList()) {
      error ??= await _remove(period);
    }
    return error;
  }

  // "Ocultar" a gap of the week: a period that covers the gap
  Future<String?> hideGap(Gap gap) async {
    final userId = _userId;
    if (userId == null) return noSessionMessage;
    if (!gap.endTime.isAfter(_clock())) return gapEndedMessage;
    if (hiddenUntil(gap) != null) return null;

    return _add(StudyPeriod(
      clientId: newClientId(),
      userId: userId,
      startTime: gap.startTime,
      endTime: _clampEnd(gap.startTime, gap.endTime),
      gapId: gap.id,
    ));
  }

  // The gap is visible again: removes the periods that were made to hide it
  Future<String?> showGap(Gap gap) async {
    String? error;
    for (final period in periods.where((p) => p.gapId == gap.id)) {
      error ??= await _remove(period);
    }
    return error;
  }

  // "Quitar" of the list of periods
  Future<String?> removePeriod(StudyPeriod period) => _remove(period);

  // The back never accepts more than 12 hours
  DateTime _clampEnd(DateTime start, DateTime end) {
    final longest = start.add(StudyPeriod.maxDuration);
    return end.isAfter(longest) ? longest : end;
  }

  // Estrategia: Eventual connectivity (optimistic). The period is saved in SQLite with synced = 0 and shown
  // at once; then it is queued in the outbox with the key study_mode:<userId>:<clientId> and sent by itself
  // (now if there is internet, when it comes back if not). Until then it shows "Pendiente de enviar".
  Future<String?> _add(StudyPeriod period) async {
    final userId = period.userId;
    final key = StudyModeOutbox.key(userId, period.clientId);
    _busy.add(period.clientId);
    try {
      await _dao.upsert(period);
      _periods = [..._periods, period]..sort((a, b) => a.startTime.compareTo(b.startTime));
      _publish(userId);
      await _replan();
      _notify();

      await StudyModeOutbox.enqueueAdd(period, outbox: _outbox);
      _pendingKeys = {..._pendingKeys, key};
      if (!hasConnection) _notice = queuedNotice;
      _notify();
      return null;
    } catch (e) {
      debugPrint('No se pudo guardar el periodo de estudio: $e');
      await _dropLocal(period);
      return saveFailedMessage;
    } finally {
      _busy.remove(period.clientId);
      if (_deferred.remove(key)) unawaited(_onKeysLeft(userId, {key}));
    }
  }

  // Estrategia: Eventual connectivity. A period that never reached the back is removed by cancelling its
  // pending POST and deleting the saved period (both are undone, nothing is sent). One the back already
  // has is removed from the screen at once and a DELETE waits in the outbox.
  Future<String?> _remove(StudyPeriod period) async {
    final userId = _userId;
    if (userId == null) return noSessionMessage;
    final key = StudyModeOutbox.key(userId, period.clientId);
    _busy.add(period.clientId);
    try {
      // The period as SQLite has it now: the outbox may have sent it since the screen read it
      final fresh = await _safe(() => _dao.find(period.clientId)) ?? period;

      if (!fresh.synced) {
        await _outbox.cancelPending(key);
      } else if (fresh.serverId != null) {
        await StudyModeOutbox.enqueueRemove(userId, fresh.clientId, fresh.serverId!, outbox: _outbox);
        _pendingKeys = {..._pendingKeys, key};
        if (!hasConnection) _notice = queuedNotice;
      }

      await _dropLocal(fresh);
      return null;
    } catch (e) {
      debugPrint('No se pudo quitar el periodo de estudio: $e');
      return removeFailedMessage;
    } finally {
      _busy.remove(period.clientId);
      if (_deferred.remove(key)) unawaited(_onKeysLeft(userId, {key}));
    }
  }

  // Removes the period from SQLite, from memory and from the shared cache
  Future<void> _dropLocal(StudyPeriod period) async {
    await _safe(() => _dao.delete(period.clientId));
    _periods = _periods.where((p) => p.clientId != period.clientId).toList();
    final userId = _userId;
    if (userId != null) _publish(userId);
    await _replan();
    _notify();
  }

  // The periods in memory are shared with the Match tab through the cache
  void _publish(int userId) => StudyPeriodsCache.write(userId, _periods);

  // Estrategia: Stream. The outbox tells which keys are still waiting: a key that leaves means the action
  // was sent (or refused). The screen reacts instead of asking all the time.
  void _watchOutbox() {
    if (_pendingSub != null) return;
    try {
      _pendingSub = _outbox.pendingKeys.listen((keys) {
        final userId = _userId;
        if (userId == null) return;
        final prefix = StudyModeOutbox.prefix(userId);
        final mine = keys.where((k) => k.startsWith(prefix)).toSet();

        // Keys that just left, plus the pending periods whose key is not in the queue (they were sent or
        // refused while the screen was closed)
        final left = _pendingKeys.difference(mine)
          ..addAll(_periods
              .where((p) => !p.synced && !mine.contains(StudyModeOutbox.key(userId, p.clientId)))
              .map((p) => StudyModeOutbox.key(userId, p.clientId)));
        _pendingKeys = mine;
        _notify();
        if (left.isNotEmpty) _onKeysLeft(userId, left);
      }, onError: (Object e) => debugPrint('Error vigilando la cola de envío: $e'));
    } catch (e) {
      debugPrint('No se pudo vigilar la cola de envío: $e');
    }
  }

  // A queued POST left the outbox: it was sent (the handler marked it in SQLite), unless the back refused
  // it (lastRefusalFor) or it ran out of attempts. A refused period is removed and the user is told why.
  Future<void> _onKeysLeft(int userId, Set<String> keys) async {
    var sent = false;

    for (final key in keys) {
      final clientId = StudyModeOutbox.clientIdOf(key, userId);
      if (clientId == null) continue;
      if (_busy.contains(clientId)) {
        _deferred.add(key);
        continue;
      }
      // An old emission of the stream can arrive late: only a key that is really gone counts
      if (await _safe(() => _outbox.isPending(key)) == true) continue;

      final index = _periods.indexWhere((p) => p.clientId == clientId);
      if (index < 0 || _periods[index].synced) continue; // a removal that was sent: nothing to show
      final period = _periods[index];

      final refusal = await _safe(() => _outbox.lastRefusalFor(key));
      if (refusal != null) {
        await _dropLocal(period);
        _notice = refusal.message == StudyModeOutbox.refusedMessage
            ? refusal.message
            : '${StudyModeOutbox.refusedMessage}: ${refusal.message}';
        _notify();
      } else if (await _safe(() => _outbox.isExhausted(key)) == true) {
        await _dropLocal(period);
        _notice = 'No se pudo sincronizar tu modo estudio. Intenta de nuevo.';
        _notify();
      } else {
        sent = true;
      }
    }

    if (sent) await _reloadLocal();
  }

  // The periods as SQLite has them now (the ended ones are removed). Used when the outbox sent something and
  // when a period ended.
  Future<void> _reloadLocal() async {
    final userId = _userId;
    if (userId == null) return;
    final now = _clock();
    await _safe(() => _dao.deleteEnded(userId, now));
    final saved = await _safe(() => _dao.getForUser(userId)) ?? <StudyPeriod>[];
    if (_disposed) return;
    _periods = saved.where((p) => !p.hasEndedAt(now)).toList();
    _publish(userId);
    await _replan();
    _notify();
  }

  // Estrategia: Caching. The mode expires with the cache: when the nearest end time passes, reading the
  // cache is a miss, so the periods are read again and the screen and the Match tab are told. The countdown
  // of the screen calls this when it reaches zero (the countdown itself is only UI).
  Future<void> refreshIfExpired() async {
    final userId = _userId;
    if (userId == null) return;
    final now = _clock();
    if (StudyPeriodsCache.read(userId) != null && _periods.every((p) => !p.hasEndedAt(now))) return;
    await _reloadLocal();
  }

  // Estrategia: Multithreading (Isolate). Joins the periods and crosses them with the gaps of the week in
  // another isolate (buildStudyPlan). An older plan that finishes late is ignored.
  Future<void> _replan() async {
    final seq = ++_planSeq;
    final payload = StudyPlanPayload(
      gaps: [
        for (final gap in _gaps)
          {
            'id': gap.id,
            'startMillis': gap.startTime.millisecondsSinceEpoch,
            'endMillis': gap.endTime.millisecondsSinceEpoch,
          },
      ],
      periods: [
        for (final period in _periods)
          {
            'startMillis': period.startTime.millisecondsSinceEpoch,
            'endMillis': period.endTime.millisecondsSinceEpoch,
          },
      ],
      nowMillis: _clock().millisecondsSinceEpoch,
    );

    try {
      final plan = await _plan(payload);
      if (_disposed || seq != _planSeq) return;
      _studyPlan = plan;
    } catch (e) {
      debugPrint('No se pudo calcular el plan de estudio: $e');
    }
  }

  // The keys of every action waiting in the outbox
  Future<Set<String>> _pendingKeysSnapshot() async {
    final actions = await _safe(() => _outbox.pendingActions()) ?? <PendingAction>[];
    return actions.map((a) => a.key).whereType<String>().toSet();
  }

  // The gaps that have not ended and start in the next days, the earliest first
  List<Gap> _upcoming(List<Gap> gaps, DateTime now) {
    final limit = now.add(_gapsAhead);
    return gaps.where((g) => g.endTime.isAfter(now) && g.startTime.isBefore(limit)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

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
    _pendingSub?.cancel();
    super.dispose();
  }
}
