import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/prefs.dart';

/// One video source: a remote stream or the downloaded file.
class Source {
  Source({required this.label, required this.uri, this.local = false, this.headers = const {}});
  final String label;
  final String uri;
  final bool local;
  final Map<String, String> headers;
}

/// Owns the media_kit players and everything the player UI shows.
class LecturePlayer extends ChangeNotifier implements PlayerHandle {
  LecturePlayer({required this.api, required this.lectureId, required this.prefs}) {
    _subs.addAll([
      player.stream.position.listen((p) {
        position.value = p;
        _syncPip(p);
      }),
      player.stream.duration.listen((d) {
        if (d > Duration.zero) duration = d;
        notifyListeners();
      }),
      player.stream.buffer.listen((b) => buffer.value = b),
      player.stream.playing.listen((v) {
        playing = v;
        v ? pip?.play() : pip?.pause();
        notifyListeners();
      }),
      player.stream.buffering.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      player.stream.rate.listen((v) {
        if (!boosting) rate = v;
        pip?.setRate(v);
        notifyListeners();
      }),
      player.stream.volume.listen((v) {
        volume = v;
        notifyListeners();
      }),
      player.stream.error.listen((e) {
        error = e;
        notifyListeners();
      }),
      player.stream.completed.listen((done) {
        if (done) save();
      }),
    ]);
    _saver = Timer.periodic(const Duration(seconds: 10), (_) => save());
  }

  final Api api;
  @override
  final String lectureId;
  final UiPrefs prefs;

  final player = Player(configuration: const PlayerConfiguration(title: 'Look Studio', bufferSize: 64 * 1024 * 1024));
  late final video = VideoController(player);
  Player? pip;
  VideoController? pipVideo;

  final position = ValueNotifier(Duration.zero);
  final buffer = ValueNotifier(Duration.zero);

  /// Asks the side panel to show a tab ('outline', 'transcript', …).
  final panelTab = ValueNotifier<String?>(null);
  Duration duration = Duration.zero;
  bool playing = false, buffering = true, boosting = false;
  double rate = 1, volume = 100;
  String? error;

  Lecture? lecture;
  Course? course;
  LectureMedia? media;
  List<Source> sources = [];
  int sourceIdx = 0;
  int? pipIdx;
  List<Slide> slides = [];
  List<Segment> segments = [];
  List<Bookmark> bookmarks = [];
  List<Note> notes = [];
  List<Chapter> chapters = [];
  List<CoursewareFile> courseware = [];
  bool outlineBusy = false;
  String? outlineError;
  bool loading = true;
  Object? loadError;
  int resumedFrom = 0;

  final _subs = <StreamSubscription>[];
  Timer? _saver;
  int _lastSaved = -1;
  bool _disposed = false;

  Source? get source => sources.isEmpty ? null : sources[sourceIdx];
  @override
  int get positionMs => position.value.inMilliseconds;

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final d = (await api.get('/api/lectures/$lectureId') as Map).cast<String, dynamic>();
      lecture = Lecture((d['lecture'] as Map).cast<String, dynamic>());
      if (d['course'] is Map) course = Course((d['course'] as Map).cast<String, dynamic>());
      bookmarks = jsonList(d['bookmarks']).map((e) => Bookmark((e as Map).cast<String, dynamic>())).toList();
      notes = jsonList(d['notes']).map((e) => Note((e as Map).cast<String, dynamic>())).toList();
      chapters = jsonList(d['timeline']).map((e) => Chapter((e as Map).cast<String, dynamic>())).toList();
      var localLabel = '';
      for (final a in jsonList(d['assets'])) {
        if (a is Map && a['kind'] == 'video') {
          final meta = a['meta'];
          localLabel = (meta is Map ? meta['stream'] : meta is String ? (jsonDecode(meta) as Map)['stream'] : null)?.toString() ?? '';
        }
      }
      final pb = d['playback'];
      final resumeMs = pb is Map ? (pb['position_ms'] as num? ?? 0).toInt() : 0;

      media = LectureMedia((await api.get('/api/lectures/$lectureId/media') as Map).cast<String, dynamic>());
      sources = [
        for (final s in media!.streams) Source(label: s.label, uri: s.url, headers: media!.headers),
      ];
      if (media!.localPath.isNotEmpty) {
        sources.insert(0, Source(label: localLabel.isEmpty ? '本地' : localLabel, uri: Uri.file(media!.localPath).toString(), local: true));
      }
      if (sources.isEmpty) throw StateError('这节课没有可播放的视频');
      sourceIdx = 0;
      if (media!.duration > 0) duration = Duration(seconds: media!.duration);
      loading = false;
      notifyListeners();

      final durMs = duration.inMilliseconds;
      final start = prefs.autoResume && resumeMs > 10000 && (durMs == 0 || resumeMs < durMs - 30000) ? resumeMs : 0;
      resumedFrom = start;
      await _open(source!, Duration(milliseconds: start));
      await player.setRate(prefs.defaultSpeed);
      unawaited(_loadSide());
    } catch (e) {
      loading = false;
      loadError = e;
      notifyListeners();
    }
  }

  Future<void> _loadSide() async {
    try {
      final sl = jsonList(await api.get('/api/lectures/$lectureId/slides'));
      slides = sl.map((e) => Slide((e as Map).cast<String, dynamic>())).toList()..sort((a, b) => a.tSec - b.tSec);
      notifyListeners();
    } catch (_) {}
    await reloadTranscript();
    await reloadCourseware();
  }

  Future<void> reloadTimeline() async {
    try {
      final r = jsonList(await api.get('/api/lectures/$lectureId/timeline'));
      chapters = r.map((e) => Chapter((e as Map).cast<String, dynamic>())).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> reloadCourseware() async {
    try {
      final r = jsonList(await api.get('/api/lectures/$lectureId/courseware'));
      courseware = r.map((e) => CoursewareFile((e as Map).cast<String, dynamic>())).toList();
      notifyListeners();
    } catch (_) {}
  }

  /// Asks the assistant host to write the outline (one model call over the
  /// whole transcript). Errors land in [outlineError].
  Future<void> generateOutline() async {
    if (outlineBusy) return;
    outlineBusy = true;
    outlineError = null;
    notifyListeners();
    try {
      final r = (await api.post('/agent/timeline', {'lecture_id': lectureId}, const Duration(minutes: 4)) as Map).cast<String, dynamic>();
      chapters = jsonList(r['chapters']).map((e) => Chapter((e as Map).cast<String, dynamic>())).toList();
    } catch (e) {
      outlineError = '$e';
    } finally {
      outlineBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> deleteOutline() async {
    chapters = [];
    notifyListeners();
    await api.delete('/api/lectures/$lectureId/timeline');
  }

  int chapterAt(int ms) {
    for (var i = chapters.length - 1; i >= 0; i--) {
      if (chapters[i].startMs <= ms) return i;
    }
    return chapters.isEmpty ? -1 : 0;
  }

  Future<void> reloadTranscript() async {
    try {
      final sg = jsonList(await api.get('/api/lectures/$lectureId/transcript'));
      segments = sg.map((e) => Segment((e as Map).cast<String, dynamic>())).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> reloadNotes() async {
    try {
      final ns = jsonList(await api.get('/api/notes', {'lecture_id': lectureId}));
      notes = ns.map((e) => Note((e as Map).cast<String, dynamic>())).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _open(Source s, Duration start) async {
    error = null;
    await player.open(Media(s.uri, httpHeaders: s.headers, start: start > Duration.zero ? start : null));
  }

  Future<void> switchSource(int i) async {
    if (i == sourceIdx || i >= sources.length) return;
    final at = position.value;
    final wasPlaying = playing;
    final r = rate;
    sourceIdx = i;
    if (pipIdx == i) await setPip(null);
    notifyListeners();
    await _open(sources[i], at);
    await player.setRate(r);
    if (!wasPlaying) await player.pause();
  }

  /// Shows a second camera in a floating window, kept in sync with the main one.
  Future<void> setPip(int? i) async {
    if (i == pipIdx) return;
    await pip?.dispose();
    pip = null;
    pipVideo = null;
    pipIdx = i;
    if (i != null) {
      final p = Player(configuration: const PlayerConfiguration(title: 'Look Studio PiP', muted: true));
      pip = p;
      pipVideo = VideoController(p);
      final s = sources[i];
      await p.setVolume(0);
      await p.open(Media(s.uri, httpHeaders: s.headers, start: position.value), play: playing);
      await p.setRate(rate);
    }
    notifyListeners();
  }

  DateTime _lastPipSync = DateTime(0);
  void _syncPip(Duration main) {
    final p = pip;
    if (p == null) return;
    final now = DateTime.now();
    if (now.difference(_lastPipSync) < const Duration(seconds: 2)) return;
    _lastPipSync = now;
    final drift = (p.state.position - main).inMilliseconds.abs();
    if (drift > 1200) p.seek(main);
  }

  @override
  void seekTo(int ms) {
    final d = Duration(milliseconds: ms.clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : ms));
    position.value = d;
    player.seek(d);
    pip?.seek(d);
  }

  void seekBy(int seconds) => seekTo(positionMs + seconds * 1000);

  Future<void> setRate(double r) async {
    rate = r;
    await player.setRate(r);
  }

  void startBoost() {
    if (boosting || !playing) return;
    boosting = true;
    player.setRate(prefs.boostSpeed);
    notifyListeners();
  }

  void endBoost() {
    if (!boosting) return;
    boosting = false;
    player.setRate(rate);
    notifyListeners();
  }

  void setVolume(double v) => player.setVolume(v.clamp(0, 100));

  // ---- derived lookups ----

  int slideAt(int ms) {
    if (slides.isEmpty) return -1;
    final s = ms ~/ 1000;
    var lo = 0, hi = slides.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (slides[mid].tSec <= s) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  int segmentAt(int ms) {
    if (segments.isEmpty) return -1;
    var lo = 0, hi = segments.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (segments[mid].startMs <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  String slideUrl(Slide s) => s.path.isNotEmpty ? api.fileUrl(s.path) : s.remoteUrl;

  // ---- persistence ----

  Future<void> save() async {
    final ms = positionMs;
    if (ms <= 0 || (ms - _lastSaved).abs() < 2000) return;
    _lastSaved = ms;
    try {
      await api.put('/api/lectures/$lectureId/playback', {
        'position_ms': ms,
        'duration_ms': duration.inMilliseconds,
        'speed': rate,
      });
    } catch (_) {}
  }

  Future<Bookmark?> addBookmark([String label = '']) async {
    try {
      final r = await api.post('/api/lectures/$lectureId/bookmarks', {'t_ms': positionMs, 'label': label});
      final b = Bookmark((r as Map).cast<String, dynamic>());
      bookmarks = [...bookmarks, b]..sort((a, b) => a.tMs - b.tMs);
      notifyListeners();
      return b;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteBookmark(Bookmark b) async {
    bookmarks = bookmarks.where((x) => x.id != b.id).toList();
    notifyListeners();
    try {
      await api.delete('/api/bookmarks/${b.id}');
    } catch (_) {}
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> close() async {
    await save();
    _disposed = true;
    _saver?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    await pip?.dispose();
    await player.dispose();
    position.dispose();
    buffer.dispose();
    panelTab.dispose();
  }
}
