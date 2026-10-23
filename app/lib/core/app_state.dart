import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'lookd_service.dart';
import 'models.dart';

/// Global app state fed by lookd's SSE event stream.
class AppState extends ChangeNotifier {
  AppState(this.daemon);
  final LookdService daemon;

  Api? _api;
  Api get api => _api!;
  bool get connected => _api != null;

  AuthState auth = AuthState.empty;
  bool authKnown = false;
  Map<String, dynamic> agent = const {'state': 'starting'};
  Map<String, dynamic> health = const {};

  List<Course> courses = [];
  bool coursesLoading = false;
  Object? coursesError;

  final Map<String, Job> jobs = {};

  /// Unread items in lookd's notification feed (new replays, assignments …).
  int unreadNotifications = 0;
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// Raw daemon events (lecture_changed, notes_changed, ...).
  Stream<Map<String, dynamic>> get events => _events.stream;

  StreamSubscription? _sse;
  bool _disposed = false;

  Future<void> init() async {
    daemon.addListener(_onDaemon);
    await _onDaemon();
  }

  Future<void> _onDaemon() async {
    if (daemon.state != DaemonState.ready) {
      notifyListeners();
      return;
    }
    final base = daemon.baseUrl;
    if (_api?.baseUrl == base) return;
    _api = Api(base, daemon.token);
    try {
      health = (await api.get('/api/health') as Map).cast<String, dynamic>();
      auth = AuthState((await api.get('/api/auth') as Map).cast<String, dynamic>());
      authKnown = true;
      final js = jsonList(await api.get('/api/jobs'));
      jobs
        ..clear()
        ..addEntries(js.map((e) => Job((e as Map).cast<String, dynamic>())).map((j) => MapEntry(j.id, j)));
      unreadNotifications = ((await api.get('/api/notifications') as Map)['unread'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('init failed: $e');
    }
    _connectEvents();
    notifyListeners();
    if (auth.signedIn) unawaited(loadCourses());
  }

  void _connectEvents() {
    _sse?.cancel();
    _sse = api.sse('/api/events').listen(_onEvent, onError: (_) => _reconnect(), onDone: _reconnect);
  }

  void _reconnect() {
    if (_disposed || _api == null) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!_disposed && daemon.state == DaemonState.ready) _connectEvents();
    });
  }

  void _onEvent(Map<String, dynamic> e) {
    final data = e['data'];
    switch (e['type']) {
      case 'hello':
        final m = (data as Map).cast<String, dynamic>();
        auth = AuthState((m['auth'] as Map).cast<String, dynamic>());
        agent = (m['agent'] as Map).cast<String, dynamic>();
        authKnown = true;
        notifyListeners();
      case 'auth':
        final was = auth.signedIn;
        auth = AuthState((data as Map).cast<String, dynamic>());
        notifyListeners();
        if (!was && auth.signedIn) unawaited(loadCourses());
      case 'agent':
        agent = (data as Map).cast<String, dynamic>();
        notifyListeners();
      case 'job':
        final j = Job((data as Map).cast<String, dynamic>());
        jobs[j.id] = j;
        notifyListeners();
      case 'job_removed':
        jobs.remove((data as Map)['id']);
        notifyListeners();
      case 'courses_changed':
        unawaited(loadCourses(quiet: true));
      case 'notification':
        unreadNotifications++;
        notifyListeners();
      case 'notifications_read':
        unreadNotifications = ((data as Map)['unread'] as num?)?.toInt() ?? 0;
        notifyListeners();
    }
    _events.add(e);
  }

  /// Reads lookd's health again, e.g. after installing ffmpeg.
  Future<void> refreshHealth() async {
    if (!connected) return;
    try {
      health = (await api.get('/api/health') as Map).cast<String, dynamic>();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadCourses({bool sync = false, bool quiet = false}) async {
    if (!connected) return;
    if (!quiet) {
      coursesLoading = true;
      coursesError = null;
      notifyListeners();
    }
    try {
      final list = jsonList(await api.get('/api/courses', sync ? {'sync': '1'} : null));
      courses = list.map((e) => Course((e as Map).cast<String, dynamic>())).toList();
      coursesError = null;
    } catch (e) {
      coursesError = e;
    } finally {
      coursesLoading = false;
      notifyListeners();
    }
  }

  Course? course(String id) {
    for (final c in courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> login(String user, String pass, {String captcha = '', bool remember = true}) async {
    final r = await api.post('/api/auth/login', {'username': user, 'password': pass, 'captcha': captcha, 'remember': remember});
    auth = AuthState((r as Map).cast<String, dynamic>());
    notifyListeners();
  }

  Future<void> logout() async {
    final r = await api.post('/api/auth/logout');
    auth = AuthState((r as Map).cast<String, dynamic>());
    courses = [];
    notifyListeners();
  }

  Future<void> patchCourse(String id, Map<String, dynamic> patch) async {
    await api.patch('/api/courses/$id', patch);
    await loadCourses(quiet: true);
  }

  Future<List<Job>> enqueue(List<String> lectureIds, List<String> kinds) async {
    final r = jsonList(await api.post('/api/jobs', {'lecture_ids': lectureIds, 'kinds': kinds}));
    final js = r.map((e) => Job((e as Map).cast<String, dynamic>())).toList();
    for (final j in js) {
      jobs[j.id] = j;
    }
    notifyListeners();
    return js;
  }

  Future<void> jobAction(String id, String action) async {
    if (action == 'remove') {
      await api.delete('/api/jobs/$id');
      jobs.remove(id);
      notifyListeners();
    } else {
      await api.post('/api/jobs/$id/$action');
    }
  }

  /// Pauses every queued or running job, resumes every paused one, or retries
  /// every failed one ([ids] limits it); returns how many changed.
  Future<int> bulkJobs(String action, {List<String>? ids}) async {
    final r = await api.post('/api/jobs/bulk', {'action': action, 'ids': ?ids});
    return r is Map ? (r['changed'] as num?)?.toInt() ?? 0 : 0;
  }

  /// Clears finished records; with [files] the downloaded files go too.
  /// Returns the number of bytes freed.
  Future<int> clearFinished({bool files = false}) async {
    final r = await api.post('/api/jobs/clear${files ? '?files=1' : ''}');
    jobs.removeWhere((_, j) => j.state == 'done' || j.state == 'canceled');
    notifyListeners();
    return r is Map ? (r['freed'] as num?)?.toInt() ?? 0 : 0;
  }

  /// Removes a job together with the files it produced.
  Future<int> removeJobFiles(String id) async {
    final r = await api.delete('/api/jobs/$id?files=1');
    jobs.remove(id);
    notifyListeners();
    return r is Map ? (r['freed'] as num?)?.toInt() ?? 0 : 0;
  }

  /// Deletes one kind of local asset (video/slides/courseware/transcript) for a lecture.
  Future<int> removeAsset(String lectureId, String kind) async {
    final r = await api.delete('/api/lectures/$lectureId/assets/$kind');
    jobs.remove('$lectureId-$kind');
    notifyListeners();
    return r is Map ? (r['freed'] as num?)?.toInt() ?? 0 : 0;
  }

  List<Job> get sortedJobs {
    final l = jobs.values.toList();
    int rank(Job j) => switch (j.state) { 'running' => 0, 'queued' => 1, 'paused' => 2, 'failed' => 3, _ => 4 };
    l.sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : b.updatedAt - a.updatedAt);
    return l;
  }

  int get activeJobCount => jobs.values.where((j) => j.active).length;

  Job? jobFor(String lectureId, String kind) => jobs['$lectureId-$kind'];

  bool get agentReady => agent['state'] == 'ready';

  @override
  void dispose() {
    _disposed = true;
    _sse?.cancel();
    daemon.removeListener(_onDaemon);
    _events.close();
    super.dispose();
  }
}

/// What the user is looking at, shared with the assistant.
class ScreenContext extends ChangeNotifier {
  Map<String, String> value = const {'screen': '首页'};
  void set(Map<String, String> v) {
    if (mapEquals(v, value)) return;
    value = v;
    notifyListeners();
  }
}

/// The active player registers here so the assistant can seek it.
abstract class PlayerHandle {
  String get lectureId;
  int get positionMs;
  void seekTo(int ms);
}

class PlayerHub extends ValueNotifier<PlayerHandle?> {
  PlayerHub() : super(null);
}
