import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Measures study time in the app and reports it to lookd for the activity
/// heatmap (docs/specs/0001-learning-activity-heatmap.md).
///
/// Surfaces start a [ActivityClock] while they are in use. Every [tick] the
/// tracker credits the time since the last check to running clocks whose
/// conditions hold, and every [flushEvery] it sends the totals.
class ActivityTracker with WidgetsBindingObserver {
  ActivityTracker(this.app, {this.now = DateTime.now, Future<dynamic> Function(Map<String, Object> report)? post})
      : _post = post ?? ((r) => app.api.post('/api/activity', r)),
        _testing = post != null {
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(tick, (_) => _check());
  }

  /// Set by main(); null in tests, where tracking is a no-op.
  static ActivityTracker? instance;

  static const tick = Duration(seconds: 10);
  static const flushEvery = Duration(seconds: 60);

  /// Reading and practice count only this long after the last interaction.
  static const idleAfter = Duration(minutes: 2);

  final AppState app;
  final DateTime Function() now;
  final Future<dynamic> Function(Map<String, Object> report) _post;

  /// A test seam for [_post]: sends even without a lookd connection.
  final bool _testing;
  late final Timer _ticker;
  final _clocks = <ActivityClock>{};
  final _pending = <(String, String, String), _Bucket>{}; // (kind, lecture, local day)
  AppLifecycleState _life = AppLifecycleState.resumed;
  DateTime? _lastFlush;
  var _flushing = false;

  bool get _visible => _life == AppLifecycleState.resumed || _life == AppLifecycleState.inactive;
  bool get _focused => _life == AppLifecycleState.resumed;

  /// A clock for one surface. [interactive] clocks (reading, practice) need
  /// window focus and recent interaction; others (watching) need visibility.
  ActivityClock clock(String kind, {String lectureId = '', bool interactive = false}) =>
      ActivityClock._(this, kind, lectureId, interactive);

  /// Count a discrete event, such as a question to the assistant.
  void count(String kind, {String lectureId = ''}) => _bucket(kind, lectureId, now()).count++;

  _Bucket _bucket(String kind, String lectureId, DateTime t) {
    final day = '${t.year}-${t.month}-${t.day}';
    return (_pending[(kind, lectureId, day)] ??= _Bucket(t))..at = t;
  }

  void _check() {
    final t = now();
    for (final c in _clocks) {
      c._credit(t);
    }
    if (_lastFlush == null || t.difference(_lastFlush!) >= flushEvery) unawaited(flush());
  }

  /// Runs one tick now.
  @visibleForTesting
  void tickNow() => _check();

  /// Unsent seconds per "kind/lecture".
  @visibleForTesting
  Map<String, double> get pendingSeconds => {
        for (final MapEntry(:key, :value) in _pending.entries)
          if (value.seconds > 0) '${key.$1}/${key.$2}': value.seconds,
      };

  void _add(ActivityClock c, DateTime t, double seconds) {
    if (seconds > 0) _bucket(c.kind, c.lectureId, t).seconds += seconds;
  }

  /// Sends accumulated time and counts. Failed reports stay queued for a day,
  /// the window lookd accepts back-dated reports in. A report keeps its id
  /// until lookd confirms it, so a retry after a lost response counts once.
  Future<void> flush() async {
    if (_flushing || (!app.connected && !_testing)) return;
    _flushing = true;
    final t = _lastFlush = now();
    try {
      for (final MapEntry(:key, value: b) in _pending.entries.toList()) {
        if (t.difference(b.at) > const Duration(hours: 23)) {
          _pending.remove(key);
          continue;
        }
        final at = b.at.millisecondsSinceEpoch ~/ 1000;
        final lecture = {if (key.$2.isNotEmpty) 'lecture_id': key.$2};
        while (true) {
          var r = b.unsent;
          if (r == null) {
            if (b.seconds >= 1) {
              r = {'kind': key.$1, 'seconds': math.min(b.seconds.floor(), 300), 'at': at, ...lecture};
            } else if (b.count > 0) {
              r = {'kind': key.$1, 'count': math.min(b.count, 50), 'at': at, ...lecture};
            } else {
              break;
            }
            b.unsent = r = {...r, 'id': _reportId()};
          }
          await _post(r);
          b.unsent = null;
          b.seconds -= (r['seconds'] as int?) ?? 0;
          b.count -= (r['count'] as int?) ?? 0;
        }
        // Keep the sub-second remainder only while its clock may add to it.
        if (b.seconds < 1 && b.count == 0 && !_clocks.any((c) => c.kind == key.$1 && c.lectureId == key.$2)) _pending.remove(key);
      }
    } catch (e) {
      debugPrint('activity flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final t = now();
    for (final c in _clocks) {
      c._credit(t); // close the interval under the old state
    }
    _life = state;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  void dispose() {
    _ticker.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

class _Bucket {
  _Bucket(this.at);
  DateTime at;
  double seconds = 0;
  int count = 0;

  /// The report being sent, already counted in [seconds] or [count].
  Map<String, Object>? unsent;
}

final _rand = math.Random.secure();
String _reportId() => [for (var i = 0; i < 12; i++) _rand.nextInt(256).toRadixString(16).padLeft(2, '0')].join();

/// Time on one surface (the player, a reader, a quiz).
class ActivityClock {
  ActivityClock._(this._t, this.kind, this.lectureId, this.interactive);
  final ActivityTracker _t;
  final String kind;
  final String lectureId;
  final bool interactive;
  DateTime? _since;

  /// Last interaction; an interactive clock credits nothing before the first.
  DateTime? _touched;

  bool get running => _since != null;

  void start() {
    if (running) return;
    _since = _t.now();
    _touched = interactive ? null : _since;
    _t._clocks.add(this);
  }

  void stop() {
    if (!running) return;
    _credit(_t.now());
    _since = null;
    _t._clocks.remove(this);
  }

  /// Marks user interaction (scroll, click, key, answer). The first one
  /// starts an interactive clock's time.
  void touch() {
    final t = _t.now();
    if (interactive && _touched == null && running) _since = t;
    _touched = t;
  }

  void _credit(DateTime t) {
    final since = _since;
    if (since == null) return;
    _since = t;
    var end = t;
    if (interactive) {
      final touched = _touched;
      if (!_t._focused || touched == null) return;
      final idle = touched.add(ActivityTracker.idleAfter);
      if (idle.isBefore(end)) end = idle;
    } else if (!_t._visible) {
      return;
    }
    // A suspended timer must not credit hours at once.
    final s = end.difference(since).inMilliseconds / 1000;
    _t._add(this, end, math.min(s, 2 * ActivityTracker.tick.inSeconds.toDouble()));
  }
}

/// Counts reading or practice time while this subtree is shown and the user
/// interacts with it.
class ActivityRegion extends StatefulWidget {
  const ActivityRegion({super.key, required this.kind, this.lectureId = '', required this.child});
  final String kind;
  final String lectureId;
  final Widget child;

  @override
  State<ActivityRegion> createState() => _ActivityRegionState();
}

class _ActivityRegionState extends State<ActivityRegion> {
  ActivityClock? _clock;

  @override
  void initState() {
    super.initState();
    _clock = ActivityTracker.instance?.clock(widget.kind, lectureId: widget.lectureId, interactive: true)?..start();
  }

  @override
  void didUpdateWidget(ActivityRegion old) {
    super.didUpdateWidget(old);
    if (old.kind == widget.kind && old.lectureId == widget.lectureId) return;
    _clock?.stop();
    _clock = ActivityTracker.instance?.clock(widget.kind, lectureId: widget.lectureId, interactive: true)?..start();
  }

  @override
  void dispose() {
    _clock?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _clock?.touch(),
        onPointerSignal: (_) => _clock?.touch(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _clock?.touch();
            return false;
          },
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, _) {
              _clock?.touch();
              return KeyEventResult.ignored;
            },
            child: widget.child,
          ),
        ),
      );
}
