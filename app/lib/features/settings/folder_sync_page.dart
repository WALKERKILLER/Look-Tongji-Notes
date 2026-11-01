import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/android_bridge.dart';

/// Course-scoped portable library; transport delivery is owned by Syncthing.
class FolderSyncPage extends StatefulWidget {
  const FolderSyncPage({super.key, this.api, this.chooseFolder});
  final ApiCall? api;
  final Future<Map<String, dynamic>?> Function()? chooseFolder;
  @override
  State<FolderSyncPage> createState() => _FolderSyncPageState();
}

class _FolderSyncPageState extends State<FolderSyncPage>
    with WidgetsBindingObserver {
  Map<String, dynamic> _status = {},
      _location = {},
      _courses = {},
      _preview = {};
  final Set<String> _selected = {};
  bool _busy = false, _media = true, _auto = true;
  String? _error;
  Timer? _poll;
  ApiCall get _call => widget.api ?? context.read<AppState>().api.call;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_run());
  }

  Future<void> _load() async {
    try {
      final s = Map<String, dynamic>.from(
        await _call('GET', '/api/sync') as Map,
      );
      if (!mounted) return;
      setState(() {
        _status = s;
        if (_location.isEmpty &&
            s['kind'] == 'folder' &&
            s['configured'] == true) {
          _location = {'local_folder': s['local_folder']};
          _selected.addAll((s['course_ids'] as List? ?? []).cast<String>());
          _media = s['media'] == true;
          _auto = s['auto'] == true;
        }
      });
      if (_courses.isEmpty) {
        final p = Map<String, dynamic>.from(
          await _call('POST', '/api/sync/folder/preview', {
            'course_ids': _selected.toList(),
            'media': _media,
          }) as Map,
        );
        if (mounted)
          setState(
            () => _courses = Map<String, dynamic>.from(
              p['courses'] as Map? ?? {},
            ),
          );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Map<String, dynamic> _settings() => {
    'kind': 'folder',
    ..._location,
    'course_ids': _selected.toList()..sort(),
    'media': _media,
    'auto': _auto,
  };
  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? location;
      if (widget.chooseFolder != null) {
        location = await widget.chooseFolder!();
      } else if (!kIsWeb && Platform.isAndroid) {
        location = await AndroidBridge.pickSyncFolder();
      } else if (!kIsWeb) {
        final p = await getDirectoryPath(
          confirmButtonText: '选择 LookStudioSync 文件夹',
        );
        if (p != null) location = {'local_folder': p};
      } else {
        throw StateError('请在桌面或安卓应用中选择同步目录');
      }
      if (location == null) return;
      final p = Map<String, dynamic>.from(
        await _call('POST', '/api/sync/folder/preview', {
          'kind': 'folder',
          ...location,
          'course_ids': _selected.toList(),
          'media': _media,
        }) as Map,
      );
      if (mounted)
        setState(() {
          _location = location!;
          _preview = p;
          _courses = Map<String, dynamic>.from(p['courses'] as Map? ?? {});
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!kIsWeb &&
          Platform.isAndroid &&
          !_location.containsKey('bridge_token')) {
        final b = await AndroidBridge.syncFolderBridge();
        if (b != null) _location = b;
      }
      final preview = Map<String, dynamic>.from(
        await _call('POST', '/api/sync/folder/preview', _settings()) as Map,
      );
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('接入同步资料库'),
          content: Text(
            '所选 ${_selected.length} 门课程；本机待扫描 ${preview['files']} 个文件，约 ${((preview['bytes'] as num? ?? 0) / 1000000).toStringAsFixed(1)} MB。\n\n远端已发布 ${preview['incoming_files'] ?? 0} 个文件，约 ${((preview['incoming_bytes'] as num? ?? 0) / 1000000).toStringAsFixed(1)} MB；传输完成后接收。\n\n合并已有内容，保留冲突副本。视频音频${_media ? '包含' : '不包含'}。学校登录和密钥留在本机。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('接入并同步'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await _call('PUT', '/api/sync', _settings());
      await _run();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    try {
      if (_status['kind'] == 'folder' || _location.isNotEmpty) {
        await _call('POST', '/api/sync/run');
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _conflicts() async {
    try {
      final rows = await _call('GET', '/api/sync/folder/conflicts') as List;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('同步冲突副本'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rows.isEmpty) const Text('没有待处理的冲突'),
                  for (final row in rows)
                    ListTile(
                      title: Text('${row['path']}'),
                      subtitle: Text('${row['bytes']} 字节'),
                      onTap: () => _inspectConflict(
                        Map<String, dynamic>.from(row as Map),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _inspectConflict(Map<String, dynamic> row) async {
    try {
      final detail =
          await _call('GET', '/api/sync/folder/conflicts/${row['id']}') as Map;
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('保留的另一版本'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: SelectableText('${detail['body'] ?? '二进制文件，副本已完整保留。'}'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('稍后处理'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'keep'),
              child: const Text('保留当前版'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'restore'),
              child: const Text('使用此副本'),
            ),
          ],
        ),
      );
      if (action != null) {
        await _call('POST', '/api/sync/folder/conflicts/${row['id']}/resolve', {
          'action': action,
          'expected_hash': detail['current_hash'],
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = Map<String, dynamic>.from(_status['last'] as Map? ?? {});
    final running = _status['running'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('同步文件夹')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '连接 Syncthing / NAS 已同步到本机的 LookStudioSync 文件夹。每端保留本地工作库，保存后自动发布；设备之间的传输由同步工具完成。',
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.folder_shared_outlined),
            title: Text('${_location['local_folder'] ?? '尚未选择同步文件夹'}'),
            trailing: OutlinedButton(
              onPressed: _busy ? null : _pick,
              child: const Text('选择文件夹'),
            ),
          ),
          const Text('选择课程'),
          for (final entry in _courses.entries)
            CheckboxListTile(
              title: Text('${entry.value}'),
              value: _selected.contains(entry.key),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        _selected.add(entry.key);
                      } else {
                        _selected.remove(entry.key);
                      }
                    }),
            ),
          if (_courses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择已有同步文件夹后，将列出其中的课程。'),
            ),
          SwitchListTile(
            title: const Text('包含视频和音频'),
            subtitle: const Text('操作系统期末速成整课约433MB，保持原始画质'),
            value: _media,
            onChanged: _busy ? null : (v) => setState(() => _media = v),
          ),
          SwitchListTile(
            title: const Text('自动检查与发布'),
            subtitle: const Text('保存后自动发布；接收到文件后自动刷新'),
            value: _auto,
            onChanged: _busy ? null : (v) => setState(() => _auto = v),
          ),
          if (_preview.isNotEmpty) Text('已识别 ${_courses.length} 门可接入课程'),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (last['error'] != null && '${last['error']}'.isNotEmpty)
            Text(
              '${last['error']}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (running)
            const LinearProgressIndicator()
          else if (last['at'] != null)
            Text(
              '已写入同步文件夹：${last['uploaded'] ?? 0} 项；已接收：${last['downloaded'] ?? 0} 项。其他设备接收状态请查看 Syncthing。',
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: _busy || _location.isEmpty || _selected.isEmpty
                    ? null
                    : _connect,
                child: const Text('预览并接入'),
              ),
              OutlinedButton(
                onPressed: _busy || running || _status['kind'] != 'folder'
                    ? null
                    : _run,
                child: const Text('立即检查'),
              ),
              TextButton(onPressed: _conflicts, child: const Text('查看冲突')),
            ],
          ),
        ],
      ),
    );
  }
}
