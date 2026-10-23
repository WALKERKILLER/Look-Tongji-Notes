import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'android_bridge.dart';
import '../l10n/l10n.dart';

// The Android app's Linux workspace: an Ubuntu base system run with proot,
// where lookd, Node.js and the assistant run as on desktop Linux.
// Contract: docs/specs/draft-android-app.md

class WorkspaceMirror {
  const WorkspaceMirror(this.id, this.name, this.images, this.ports, this.archive);
  final String id, name;

  /// Ubuntu base images, and the package archives for arm64 and x86_64.
  final String images, ports, archive;
}

final workspaceMirrors = [
  WorkspaceMirror('tuna', l10n.mirrorTuna, 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/',
      'http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/', 'http://mirrors.tuna.tsinghua.edu.cn/ubuntu/'),
  WorkspaceMirror('ustc', l10n.mirrorUstc, 'https://mirrors.ustc.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/',
      'http://mirrors.ustc.edu.cn/ubuntu-ports/', 'http://mirrors.ustc.edu.cn/ubuntu/'),
  WorkspaceMirror('official', l10n.mirrorUbuntu, 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/',
      'http://ports.ubuntu.com/ubuntu-ports/', 'http://archive.ubuntu.com/ubuntu/'),
];

const _release = '24.04.5';

/// SHA-256 of `ubuntu-base-<release>-base-<arch>.tar.gz` (SHA256SUMS).
const _sums = {
  'arm64': 'a91d5a93010193712d346d761372b7c9db6dfcf093893161c64ca107f05914f2',
  'amd64': 'e77b6f10c2590cef872b33ee9f635a0e3fd1f57fb074c0e52b5c7f56147a0c86',
};

/// What an install step reports.
class WorkspaceProgress {
  const WorkspaceProgress(this.step, {this.done = 0, this.total = 0});
  final String step;
  final int done, total;
  double? get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : null;
}

class Workspace extends ChangeNotifier {
  Workspace({Future<Map<String, dynamic>> Function()? info}) : _infoOf = info ?? AndroidBridge.info;
  final Future<Map<String, dynamic>> Function() _infoOf;

  late String nativeDir, filesDir, cacheDir;

  /// Where the native library folder appears in the guest. Its real path
  /// (`/data/app/~~…==/…`) contains `=`, which `env` would read as a
  /// variable assignment instead of the command.
  static const guestNative = '/opt/look';

  /// The phone's maker and model, which names this device in sync and backups.
  String device = '';

  /// The phone's IANA time zone; the guest has no /etc/localtime.
  String timeZone = '';
  String _arch = 'arm64';
  bool _loaded = false;

  WorkspaceProgress? progress;
  String? error;
  bool busy = false;
  final List<String> log = [];

  String get rootfs => '$filesDir/ubuntu';
  String get dataDir => '$filesDir/look-data';
  String get library => '$filesDir/LookStudio';
  String get agentDir => '$filesDir/agent';
  String get _marker => '$rootfs/.look-workspace';

  bool get installed => File(_marker).existsSync();
  bool get hasFFmpeg => File('$rootfs/usr/bin/ffmpeg').existsSync();

  Future<void> load() async {
    if (_loaded) return;
    final i = await _infoOf();
    nativeDir = '${i['nativeLibraryDir']}';
    filesDir = '${i['filesDir']}';
    cacheDir = '${i['cacheDir']}';
    _arch = '${i['abi']}'.startsWith('x86_64') ? 'amd64' : 'arm64';
    device = '${i['device'] ?? ''}'.trim();
    timeZone = '${i['timezone'] ?? ''}'.trim();
    _loaded = true;
  }

  Map<String, String> get _mirror {
    try {
      final m = jsonDecode(File(_marker).readAsStringSync()) as Map;
      return m.cast<String, String>();
    } catch (_) {
      return const {};
    }
  }

  void _report(WorkspaceProgress p) {
    progress = p;
    notifyListeners();
  }

  void _log(String line) {
    log.add(line);
    if (log.length > 300) log.removeRange(0, log.length - 300);
  }

  /// Downloads, checks and unpacks Ubuntu base, then configures it.
  Future<void> install(WorkspaceMirror mirror) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    final name = 'ubuntu-base-$_release-base-$_arch.tar.gz';
    final archive = File('$cacheDir/$name');
    final staging = Directory('$rootfs.part');
    try {
      await _download(Uri.parse(mirror.images + name), archive);
      _report(WorkspaceProgress(l10n.workspaceStepUnpack));
      if (staging.existsSync()) await staging.delete(recursive: true);
      final total = await archive.length();
      await _unpack(archive.path, staging.path, _sums[_arch]!, (n) => _report(WorkspaceProgress(l10n.workspaceStepUnpack, done: n, total: total)));
      _report(WorkspaceProgress(l10n.workspaceStepConfigure));
      final old = Directory(rootfs);
      if (old.existsSync()) await old.delete(recursive: true);
      await staging.rename(rootfs);
      await _configure(mirror);
      await archive.delete();
      progress = null;
    } catch (e) {
      error = '$e';
      _log('install: $e');
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _download(Uri url, File dest) async {
    _report(WorkspaceProgress(l10n.workspaceStepDownload));
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', url)).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw l10n.workspaceDownloadHttpError(res.statusCode);
      final total = res.contentLength ?? 0;
      final sink = dest.openWrite();
      var n = 0;
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          n += chunk.length;
          _report(WorkspaceProgress(l10n.workspaceStepDownload, done: n, total: total));
        }
      } finally {
        await sink.close();
      }
    } on TimeoutException {
      throw l10n.workspaceDownloadTimeout;
    } on SocketException catch (e) {
      throw l10n.workspaceMirrorUnreachable(e.message);
    } finally {
      client.close();
    }
  }

  /// lookd unpacks: it runs straight from the native library folder and
  /// keeps file modes, which Dart cannot set.
  Future<void> _unpack(String archive, String dir, String sha, void Function(int) onBytes) async {
    final p = await Process.start('$nativeDir/liblookd.so', ['unpack', archive, dir, sha]);
    final err = StringBuffer();
    p.stderr.transform(utf8.decoder).listen(err.write);
    await p.stdout.transform(utf8.decoder).transform(const LineSplitter()).forEach((l) {
      if (l.startsWith('PROGRESS ')) onBytes(int.tryParse(l.substring(9)) ?? 0);
    });
    if (await p.exitCode != 0) {
      final msg = err.toString().trim();
      throw msg.contains('checksum') ? l10n.workspaceChecksumFailed : l10n.workspaceUnpackFailed(msg);
    }
  }

  Future<void> _configure(WorkspaceMirror mirror) async {
    Future<void> write(String rel, String body) async {
      final f = File('$rootfs/$rel');
      await f.parent.create(recursive: true);
      if (await FileSystemEntity.type(f.path, followLinks: false) == FileSystemEntityType.link) await Link(f.path).delete();
      await f.writeAsString(body);
    }

    await write('etc/resolv.conf', 'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 8.8.8.8\n');
    await write('etc/hosts', '127.0.0.1 localhost\n::1 localhost ip6-localhost\n');
    final archive = _arch == 'arm64' ? mirror.ports : mirror.archive;
    await write('etc/apt/sources.list.d/ubuntu.sources',
        'Types: deb\nURIs: $archive\nSuites: noble noble-updates noble-security\nComponents: main universe\n'
        'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n');
    // apt drops to the _apt user, which proot's fake root cannot do.
    await write('etc/apt/apt.conf.d/01-look', 'APT::Sandbox::User "root";\nAcquire::Retries "3";\n');
    for (final d in ['root', 'tmp']) {
      await Directory('$rootfs/$d').create(recursive: true);
    }
    await write('.look-workspace', jsonEncode({'release': _release, 'arch': _arch, 'mirror': mirror.id}));
  }

  /// Unpacks the assistant's sources the APK carries when they changed.
  Future<void> ensureAgent() async {
    final sum = File('$cacheDir/agent.sha256');
    await AndroidBridge.extractAsset('look/agent.sha256', sum.path);
    final want = (await sum.readAsString()).trim();
    final have = File('$agentDir/.sha256');
    if (have.existsSync() && have.readAsStringSync().trim() == want) return;
    final tar = '$cacheDir/agent.tgz';
    await AndroidBridge.extractAsset('look/agent.tgz', tar);
    await _unpack(tar, agentDir, '', (_) {});
    await have.writeAsString(want);
    await File(tar).delete();
  }

  /// proot's command line for running [command] in the guest. The app's
  /// files folder appears at the same path inside, so paths lookd reports
  /// work in the app too; native libraries appear at [guestNative].
  (String, List<String>, Map<String, String>) guest(List<String> command, {Map<String, String> env = const {}, String cwd = '/root'}) {
    final tmp = Directory('$cacheDir/proot')..createSync(recursive: true);
    final binds = ['/dev', '/proc', '/sys', '/system', if (Directory('/apex').existsSync()) '/apex', filesDir, '$nativeDir:$guestNative'];
    final certs = [
      if (Directory('/apex/com.android.conscrypt/cacerts').existsSync()) '/apex/com.android.conscrypt/cacerts',
      '/system/etc/security/cacerts',
    ].join(':');
    return (
      '$nativeDir/libproot.so',
      [
        '--kill-on-exit',
        '--link2symlink',
        '-0',
        '-r', rootfs,
        for (final b in binds) ...['-b', b],
        '-w', cwd,
        '/usr/bin/env', '-i',
        'HOME=/root',
        'LANG=C.UTF-8',
        if (timeZone.isNotEmpty) 'TZ=$timeZone',
        'TERM=xterm-256color',
        'TMPDIR=/tmp',
        'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        // Go reads Android's certificate store; Node and npm carry their own.
        'SSL_CERT_DIR=$certs',
        for (final e in env.entries) '${e.key}=${e.value}',
        ...command,
      ],
      {'PROOT_LOADER': '$nativeDir/libproot_loader.so', 'PROOT_TMP_DIR': tmp.path, 'LD_LIBRARY_PATH': nativeDir},
    );
  }

  /// Runs a shell command in the guest, streaming its output to [onLine].
  Future<int> run(String script, {void Function(String line)? onLine}) async {
    final (exe, args, env) = guest(['/bin/sh', '-c', script]);
    final p = await Process.start(exe, args, environment: env);
    void each(String l) {
      _log(l);
      onLine?.call(l);
    }

    final out = p.stdout.transform(utf8.decoder).transform(const LineSplitter()).forEach(each);
    final err = p.stderr.transform(utf8.decoder).transform(const LineSplitter()).forEach(each);
    await Future.wait([out, err]);
    return p.exitCode;
  }

  /// Installs ffmpeg, which transcription needs, from the chosen mirror.
  Future<void> installFFmpeg({void Function(String line)? onLine}) async {
    if (busy) return;
    busy = true;
    error = null;
    _report(WorkspaceProgress(l10n.workspaceInstallFfmpeg));
    try {
      final code = await run(
        'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates',
        onLine: onLine,
      );
      if (code != 0) throw l10n.workspaceAptExit(code);
    } catch (e) {
      error = l10n.workspaceFfmpegFailed(e);
      rethrow;
    } finally {
      busy = false;
      progress = null;
      notifyListeners();
    }
  }

  String get mirrorId => _mirror['mirror'] ?? workspaceMirrors.first.id;
}
