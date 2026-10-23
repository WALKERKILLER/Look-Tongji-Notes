import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'workspace.dart';
import '../l10n/l10n.dart';

/// [setup]: on Android, the Linux workspace lookd runs in is not installed.
enum DaemonState { setup, starting, ready, failed }

/// Starts and supervises the Go daemon (lookd): next to the app on desktop,
/// in the Linux workspace on Android. The daemon in turn supervises the
/// Node.js Pi agent host.
class LookdService extends ChangeNotifier {
  LookdService({Workspace? workspace}) : workspace = workspace ?? (Platform.isAndroid ? Workspace() : null);

  /// The Android Linux workspace; null on desktop.
  final Workspace? workspace;

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
    final win = Platform.isWindows;
    final home = Platform.environment[win ? 'USERPROFILE' : 'HOME'] ?? '';
    final candidates = <String>[];
    for (final dir in (Platform.environment['PATH'] ?? '').split(win ? ';' : ':')) {
      if (dir.isNotEmpty) candidates.add(p.join(dir, win ? 'node.exe' : 'node'));
    }
    final mise = Directory(p.join(home, '.local/share/mise/installs/node'));
    if (mise.existsSync()) {
      final versions = mise.listSync().whereType<Directory>().map((d) => d.path).toList()..sort();
      for (final v in versions.reversed) {
        candidates.add(win ? p.join(v, 'node.exe') : p.join(v, 'bin', 'node'));
      }
    }
    // Apps started from Finder or the Start menu get a minimal PATH.
    candidates.addAll(win
        ? [p.join(Platform.environment['ProgramFiles'] ?? r'C:\Program Files', 'nodejs', 'node.exe')]
        : ['/usr/bin/node', '/usr/local/bin/node', '/opt/homebrew/bin/node']);
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<void> start() async {
    token = _token();
    await _spawn();
  }

  /// Starts lookd once the workspace has been installed.
  Future<void> afterSetup() async {
    _ready = Completer();
    await _spawn();
  }

  Future<void> _spawn() async {
    final ws = workspace;
    if (ws != null) return _spawnInWorkspace(ws);
    final exe = Platform.isWindows ? 'lookd.exe' : 'lookd';
    final bin = _find('LOOKD_BIN', [exe, 'lib/$exe'], ['look-studio/lookd/bin/$exe', 'lookd/bin/$exe']);
    if (bin == null) {
      _fail(l10n.daemonNotFound);
      return;
    }
    // A macOS app keeps the agent in Contents/Resources, beside Contents/MacOS.
    final agent = _find('LOOK_AGENT', ['agent/src/host.mjs', '../Resources/agent/src/host.mjs'], ['look-studio/agent/src/host.mjs', 'agent/src/host.mjs']);
    final node = _findNode();
    // Without Node.js lookd still gets the agent, so the in-app runtime
    // install (docs/specs/0008-assistant-runtime-setup.md) can set it up.
    final args = ['-exit-on-stdin-eof'];
    if (agent != null) args.addAll(['-agent', agent]);
    if (node != null) args.addAll(['-node', node]);
    await _launch(bin, args, {'LOOKD_TOKEN': token});
  }

  Future<void> _spawnInWorkspace(Workspace ws) async {
    try {
      await ws.load();
    } catch (e) {
      _fail(l10n.daemonCannotReadAppDir(e));
      return;
    }
    if (!ws.installed) {
      state = DaemonState.setup;
      notifyListeners();
      return;
    }
    state = DaemonState.starting;
    notifyListeners();
    try {
      await ws.ensureAgent();
    } catch (e) {
      _log('agent sources: $e');
    }
    final (exe, args, env) = ws.guest([
      '${Workspace.guestNative}/liblookd.so',
      '-exit-on-stdin-eof',
      '-data', ws.dataDir,
      '-library', ws.library,
      '-agent', '${ws.agentDir}/src/host.mjs',
    ], env: {'LOOKD_TOKEN': token, if (ws.device.isNotEmpty) 'LOOK_DEVICE': ws.device});
    await _launch(exe, args, env);
  }

  Future<void> _launch(String exe, List<String> args, Map<String, String> env) async {
    state = DaemonState.starting;
    notifyListeners();
    try {
      _proc = await Process.start(exe, args, environment: env);
    } catch (e) {
      _fail(l10n.daemonCannotStart(e));
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
        _fail(l10n.daemonKeepsExiting(code));
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
    if (!_ready.isCompleted) {
      _ready.future.ignore(); // the failed state already reports it
      _ready.completeError(msg);
    }
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
