import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum DaemonState { starting, ready, failed }

/// Starts and supervises the Go daemon (lookd) on desktop. The daemon in turn
/// supervises the Node.js Pi agent host.
class LookdService extends ChangeNotifier {
  DaemonState state = DaemonState.starting;
  String? error;
  late String token;
  int port = 0;
  String libraryRoot = '';
  final List<String> log = [];

  Process? _proc;
  int _restarts = 0;
  bool _disposed = false;
  Completer<void> _ready = Completer();

  String get baseUrl => 'http://127.0.0.1:$port';
  Future<void> get ready => _ready.future;

  static String _token() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String get _exeDir => p.dirname(Platform.resolvedExecutable);

  /// Search order: env override, bundled next to the executable, then the
  /// development tree (look-studio/lookd/bin/lookd).
  String? _find(String envKey, List<String> bundled, List<String> devRel) {
    final env = Platform.environment[envKey];
    if (env != null && File(env).existsSync()) return env;
    for (final b in bundled) {
      final f = p.join(_exeDir, b);
      if (File(f).existsSync()) return f;
    }
    var dir = Directory(_exeDir);
    for (var i = 0; i < 10; i++) {
      for (final rel in devRel) {
        final f = p.join(dir.path, rel);
        if (File(f).existsSync()) return f;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  String? _findNode() {
    final env = Platform.environment['LOOK_NODE'];
    if (env != null && File(env).existsSync()) return env;
    final home = Platform.environment['HOME'] ?? '';
    final candidates = <String>[];
    for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
      candidates.add(p.join(dir, 'node'));
    }
    final mise = Directory(p.join(home, '.local/share/mise/installs/node'));
    if (mise.existsSync()) {
      final versions = mise.listSync().whereType<Directory>().map((d) => d.path).toList()..sort();
      for (final v in versions.reversed) {
        candidates.add(p.join(v, 'bin', 'node'));
      }
    }
    candidates.addAll(['/usr/bin/node', '/usr/local/bin/node']);
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<void> start() async {
    token = _token();
    await _spawn();
  }

  Future<void> _spawn() async {
    final bin = _find('LOOKD_BIN', ['lookd', 'lib/lookd'], ['look-studio/lookd/bin/lookd', 'lookd/bin/lookd']);
    if (bin == null) {
      _fail('找不到 lookd 守护进程。请先构建 look-studio/lookd（go build -o bin/lookd ./cmd/lookd）。');
      return;
    }
    final agent = _find('LOOK_AGENT', ['agent/src/host.mjs'], ['look-studio/agent/src/host.mjs', 'agent/src/host.mjs']);
    final node = _findNode();
    final args = ['-exit-on-stdin-eof'];
    if (agent != null && node != null) args.addAll(['-node', node, '-agent', agent]);
    state = DaemonState.starting;
    notifyListeners();
    try {
      _proc = await Process.start(bin, args, environment: {'LOOKD_TOKEN': token});
    } catch (e) {
      _fail('无法启动 lookd：$e');
      return;
    }
    final proc = _proc!;
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_log);
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (line.startsWith('LOOKD_READY ')) {
        final info = jsonDecode(line.substring(12)) as Map<String, dynamic>;
        port = info['port'] as int;
        libraryRoot = info['library'] as String? ?? '';
        state = DaemonState.ready;
        error = null;
        _restarts = 0;
        if (!_ready.isCompleted) _ready.complete();
        notifyListeners();
      } else {
        _log(line);
      }
    });
    unawaited(proc.exitCode.then((code) async {
      if (_disposed) return;
      _log('lookd exited with code $code');
      state = DaemonState.starting;
      notifyListeners();
      _restarts++;
      if (_restarts > 5) {
        _fail('lookd 反复退出（代码 $code），请查看诊断日志。');
        return;
      }
      await Future.delayed(Duration(milliseconds: 400 * _restarts * _restarts));
      if (!_disposed) {
        _ready = Completer();
        await _spawn();
      }
    }));
  }

  void _log(String line) {
    log.add(line);
    if (log.length > 400) log.removeRange(0, log.length - 400);
    if (kDebugMode) debugPrint('[lookd] $line');
  }

  void _fail(String msg) {
    state = DaemonState.failed;
    error = msg;
    if (!_ready.isCompleted) _ready.completeError(msg);
    notifyListeners();
  }

  Future<void> restart() async {
    _restarts = 0;
    _ready = Completer();
    final old = _proc;
    _proc = null;
    if (old != null) {
      old.kill(ProcessSignal.sigterm);
      return; // exit handler respawns
    }
    await _spawn();
  }

  @override
  void dispose() {
    _disposed = true;
    _proc?.stdin.close(); // lookd exits on stdin EOF
    _proc?.kill(ProcessSignal.sigterm);
    super.dispose();
  }
}
