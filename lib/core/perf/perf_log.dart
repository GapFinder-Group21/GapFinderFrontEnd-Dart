import 'dart:async';
import 'package:flutter/widgets.dart';

// Measurement logs for the micro-optimizations (only with --dart-define=PERF_LOGS=true)
// Every line: [PERF][<tag>] t=<ms since main> <message>
class PerfLog {
  static const enabled = bool.fromEnvironment('PERF_LOGS');
  static final Stopwatch _clock = Stopwatch();

  // Called on the first line of main(): t=0 is the real start of the app
  static void start() => _clock..reset()..start();

  static void log(String tag, String message) {
    if (!enabled) return;
    debugPrint('[PERF][$tag] t=${_clock.elapsedMilliseconds}ms $message');
  }

  // "resumed", "paused", "hidden", "inactive" or "detached"
  static String get appState => WidgetsBinding.instance.lifecycleState?.name ?? 'resumed';

  static AppLifecycleListener? _lifecycle;

  // Called right after runApp: first frame, 10 s summary, lifecycle and light sensor counters
  static void startAppMonitors() {
    if (!enabled) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      log('startup', 'first frame');
      Timer(const Duration(seconds: 10), () => log('startup', PerfStats.startupSummary()));
    });

    _lifecycle ??= AppLifecycleListener(onStateChange: (state) {
      log('lifecycle', state.name);
      if (state == AppLifecycleState.paused) PerfStats.startBackground();
      if (state == AppLifecycleState.resumed) PerfStats.endBackground();
    });

    Timer.periodic(const Duration(seconds: 60), (_) {
      log('sensor', 'lux events last 60s=${PerfStats.luxThisMinute} state=$appState');
      PerfStats.luxThisMinute = 0;
    });
  }
}

// Counters used by the summaries
class PerfStats {
  // Startup window (micro-optimization 1)
  static int requestsStarted = 0; // counted when the request goes out (pending ones included)
  static int requestsCompleted = 0; // counted when the answer (or the error) arrives
  static int bytesReceived = 0;
  static final List<String> tabsCreated = [];

  // Only these count as tabs in the 10 s summary (the location banner is logged apart)
  static const _tabNames = {'Schedule', 'Friends', 'Match', 'OpenTables', 'Recommendations'};

  // Background window (micro-optimization 2)
  static DateTime? backgroundSince;
  static int bgHttp = 0, bgGpsReads = 0, bgChatPolls = 0, bgLuxEvents = 0;

  // Light sensor events in the current minute
  static int luxThisMinute = 0;

  static bool get _inBackground => backgroundSince != null;

  static void tabCreated(String name) {
    if (!PerfLog.enabled) return;
    tabsCreated.add(name);
    PerfLog.log('tab', '$name created');
  }

  // Counts the request when it goes out and returns its number #n (no line here)
  static int httpStart() {
    if (!PerfLog.enabled) return 0;
    requestsStarted++;
    if (_inBackground) bgHttp++;
    return requestsStarted;
  }

  // One line per request, when the answer (or the error) arrives
  static void httpEnd(int n, String method, String path, String status, int ms, int bytes) {
    if (!PerfLog.enabled) return;
    requestsCompleted++;
    bytesReceived += bytes;
    PerfLog.log('http', '#$n $method $path $status ${ms}ms ${_kb(bytes)} state=${PerfLog.appState}');
  }

  static void gpsRead(int ms, int httpCalls) {
    if (!PerfLog.enabled) return;
    if (_inBackground) bgGpsReads++;
    PerfLog.log('location', 'tick gps=${ms}ms http=$httpCalls state=${PerfLog.appState}');
  }

  static void chatPoll(int afterId) {
    if (!PerfLog.enabled) return;
    if (_inBackground) bgChatPolls++;
    PerfLog.log('chat', 'poll afterId=$afterId state=${PerfLog.appState}');
  }

  // No line per reading: it only counts
  static void luxEvent() {
    if (!PerfLog.enabled) return;
    luxThisMinute++;
    if (_inBackground) bgLuxEvents++;
  }

  static void startBackground() {
    if (!PerfLog.enabled) return;
    backgroundSince = DateTime.now();
    bgHttp = 0;
    bgGpsReads = 0;
    bgChatPolls = 0;
    bgLuxEvents = 0;
  }

  static void endBackground() {
    final since = backgroundSince;
    if (!PerfLog.enabled || since == null) return;
    final seconds = DateTime.now().difference(since).inSeconds;
    PerfLog.log(
      'background',
      '${seconds}s in background: http=$bgHttp gpsReads=$bgGpsReads chatPolls=$bgChatPolls luxEvents=$bgLuxEvents',
    );
    backgroundSince = null;
  }

  static String startupSummary() {
    final tabs = tabsCreated.where(_tabNames.contains).toList();
    final pending = requestsStarted - requestsCompleted;
    return 'summary 10s: requests=$requestsStarted (completed=$requestsCompleted pending=$pending) '
        'bytes=${_size(bytesReceived)} tabs=${tabs.length} (${tabs.join(',')})';
  }

  static String _kb(int bytes) => '${(bytes / 1000).toStringAsFixed(1)}KB';

  static String _size(int bytes) =>
      bytes >= 1000000 ? '${(bytes / 1000000).toStringAsFixed(1)}MB' : _kb(bytes);
}

// Image logs (micro-optimization 3)
class PerfImages {
  // Labels already watched: build() runs many times, the image is measured only once
  static final Set<String> _watched = {};
  // Cache moments already logged
  static final Set<String> _cacheMoments = {};

  // Logs once the decoded size of an image: [PERF][images] <label> decoded WxH = X.XXMB (drawn WxH)
  // Safe to call from build(): at most ONE listener per label, removed right after
  static void watch(BuildContext context, ImageProvider provider, String label, Size drawn) {
    if (!PerfLog.enabled || !_watched.add(label)) return;

    // Same provider and configuration as the Image widget: it reads the same cached image
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        final w = info.image.width;
        final h = info.image.height;
        PerfLog.log(
          'images',
          '$label decoded ${w}x$h = ${(w * h * 4 / 1000000).toStringAsFixed(2)}MB '
              '(drawn ${drawn.width.round()}x${drawn.height.round()})',
        );
        info.dispose(); // the listener owns this handle to the image
      },
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  // Logs the image cache once per moment: [PERF][images] imageCache=X.XMB images=N live=N (<moment>)
  static void logCache(String moment) {
    if (!PerfLog.enabled || !_cacheMoments.add(moment)) return;
    final cache = PaintingBinding.instance.imageCache;
    PerfLog.log(
      'images',
      'imageCache=${(cache.currentSizeBytes / 1000000).toStringAsFixed(1)}MB '
          'images=${cache.currentSize} live=${cache.liveImageCount} ($moment)',
    );
  }
}
