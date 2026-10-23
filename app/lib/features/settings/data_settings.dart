import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import 'settings_common.dart';
import 'webdav_page.dart';

// The 数据与同步 pane: sync between devices, backups, and what takes space.
// Contract: docs/specs/0014-data-sync-and-backup.md

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

const _backupType = XTypeGroup(label: 'Look Studio 备份', extensions: ['zip'], mimeTypes: ['application/zip'], uniformTypeIdentifiers: ['public.zip-archive']);

class DataSettings extends StatefulWidget {
  const DataSettings({super.key, this.api, this.events});

  /// For tests; default to the app's daemon connection.
  final ApiCall? api;
  final Stream<Map<String, dynamic>>? events;

  @override
  State<DataSettings> createState() => _DataSettingsState();
}

class _DataSettingsState extends State<DataSettings> {
  Map<String, dynamic> _sync = const {};
  Map<String, dynamic>? _estimate, _storage;
  bool _media = false;

  /// Export or restore in progress: what, bytes so far, and of how many.
  String? _task;
  int _done = 0, _total = 0;
  StreamSubscription? _sub;

  ApiCall get _call => widget.api ?? context.read<AppState>().api.call;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = (widget.events ?? context.read<AppState>().events).listen((e) {
      final t = '${e['type']}';
      if (t == 'sync_done' || t == 'sync_changed') _load();
      if (t == 'sync_progress' && mounted && _sync['running'] != true) setState(() => _sync = {..._sync, 'running': true});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([
      _call('GET', '/api/sync').then((r) => _sync = _map(r)),
      _call('GET', '/api/data/estimate').then((r) => _estimate = _map(r)),
      _call('GET', '/api/storage').then((r) => _storage = _map(r)),
    ].map((f) => f.catchError((_) => const <String, dynamic>{})));
    if (mounted) setState(() {});
  }

  // ---- backup ----

  Future<void> _export() async {
    final now = DateTime.now();
    final name = 'LookStudio-备份-${now.year}${'${now.month}'.padLeft(2, '0')}${'${now.day}'.padLeft(2, '0')}.zip';
    final path = await pickSavePath(context, suggestedName: name, type: _backupType, confirm: '导出');
    if (path == null || !mounted) return;
    final e = _estimate ?? {};
    setState(() {
      _task = '正在导出';
      _done = 0;
      _total = ((e['bytes'] as num? ?? 0) + (_media ? e['media_bytes'] as num? ?? 0 : 0)).toInt();
    });
    try {
      await context.read<AppState>().api.download('/api/data/export', {if (_media) 'media': '1'}, File(path),
          onProgress: (n) => mounted ? setState(() => _done = n) : null);
      if (!mounted) return;
      showSnack(context, '备份已保存（${fmtBytes(_done)}）', action: '在文件夹中显示', onAction: () => revealPath(path));
    } catch (err) {
      if (mounted) showSnack(context, '导出失败：$err');
    } finally {
      if (mounted) setState(() => _task = null);
    }
  }

  Future<void> _restore() async {
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [_backupType]);
    } on PlatformException catch (e) {
      if (mounted) showSnack(context, '无法打开文件选择器：${e.message}');
      return;
    }
    if (file == null || !mounted) return;
    final api = context.read<AppState>().api;
    final length = await file.length();
    setState(() {
      _task = '正在读取备份';
      _done = 0;
      _total = length;
    });
    Map<String, dynamic> preview;
    try {
      var sent = 0;
      final data = file.openRead().map((c) {
        sent += c.length;
        if (mounted) setState(() => _done = sent);
        return c;
      });
      preview = _map(await api.upload('/api/data/import', const {}, data, length));
    } catch (e) {
      if (mounted) {
        setState(() => _task = null);
        showSnack(context, '$e');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _task = null);
    final mode = await showDialog<String>(context: context, builder: (_) => _RestoreDialog(preview: preview));
    final id = '${preview['id']}';
    if (mode == null) {
      unawaited(api.delete('/api/data/import/$id').catchError((_) => null));
      return;
    }
    if (!mounted) return;
    setState(() {
      _task = '正在恢复';
      _done = _total = 0;
    });
    try {
      final r = _map(await api.post('/api/data/import/$id/apply', {'mode': mode}, const Duration(minutes: 30)));
      if (!mounted) return;
      final conflict = '${r['conflict'] ?? ''}';
      showSnack(
        context,
        r['written'] == 0 ? '没有需要恢复的文件，本机已是最新' : '已恢复 ${r['written']} 个文件（${fmtBytes(r['bytes'] as num? ?? 0)}）',
        action: conflict.isEmpty ? null : '查看被替换的文件',
        onAction: conflict.isEmpty ? null : () => revealPath(conflict),
      );
      unawaited(_load());
    } catch (e) {
      if (mounted) showSnack(context, '恢复失败：$e');
    } finally {
      if (mounted) setState(() => _task = null);
    }
  }

  // ---- storage ----

  Future<void> _clean(String what, String done) async {
    if (what == 'sync') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('清空同步冲突与回收站？'),
          content: const Text('其中是同步时被替换或在其他设备上删除的文件副本，清空后无法找回。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清空')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _task = done);
    try {
      final r = _map(await _call('POST', '/api/storage/clean', {what: true}));
      if (mounted) showSnack(context, '已释放 ${fmtBytes(r['freed'] as num? ?? 0)}');
    } catch (e) {
      if (mounted) showSnack(context, '清理失败：$e');
    } finally {
      if (mounted) setState(() => _task = null);
      unawaited(_load());
    }
  }

  void _openSync() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WebDavPage())).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final syncOn = _sync['configured'] == true;
    final syncErr = '${_map(_sync['last'])['error'] ?? ''}';
    final e = _estimate;
    final busy = _task != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsGroup(title: '多端同步', icon: Icons.devices_rounded, padding: const EdgeInsets.symmetric(vertical: Space.sm), children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.xs),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: _sync['running'] == true
                ? Padding(padding: const EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimaryContainer))
                : Icon(Icons.cloud_sync_rounded, color: cs.onPrimaryContainer),
          ),
          title: const Text('WebDAV 同步'),
          subtitle: Text(webdavSummary(_sync), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: syncOn && syncErr.isNotEmpty ? TextStyle(color: cs.error) : null),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _openSync,
        ),
      ]),
      SettingsGroup(title: '备份与恢复', icon: Icons.inventory_2_outlined, children: [
        Text('把课程库和助手对话打包成一个 zip，换电脑或重装时恢复。登录状态和密钥不在备份里。', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: Space.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('包含视频与录音'),
          subtitle: Text(e == null ? '…' : (e['media_files'] == 0 ? '课程库里还没有视频' : '${e['media_files']} 个文件，另需 ${fmtBytes(e['media_bytes'] as num? ?? 0)}')),
          value: _media,
          onChanged: busy || e?['media_files'] == 0 ? null : (v) => setState(() => _media = v),
        ),
        AnimatedSize(
          duration: Motion.medium2,
          curve: Motion.emphasized,
          alignment: Alignment.topCenter,
          child: !busy
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    LinearProgressIndicator(value: _total > 0 ? (_done / _total).clamp(0.0, 1.0) : null, borderRadius: BorderRadius.circular(Corners.full)),
                    const SizedBox(height: Space.sm),
                    Text(_done > 0 ? '$_task · ${fmtBytes(_done)}' : _task!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
        ),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.tonalIcon(
            onPressed: busy ? null : _export,
            icon: const Icon(Icons.archive_outlined),
            label: Text(e == null ? '导出备份' : '导出备份 · 约 ${fmtBytes((e['bytes'] as num? ?? 0) + (_media ? e['media_bytes'] as num? ?? 0 : 0))}'),
          ),
          OutlinedButton.icon(onPressed: busy ? null : _restore, icon: const Icon(Icons.unarchive_outlined), label: const Text('从备份恢复')),
        ]),
      ]),
      _StorageGroup(report: _storage, busy: busy, onClean: _clean),
    ]);
  }
}

/// Asks how to restore a backup; pops 'merge', 'overwrite' or null.
class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.preview});
  final Map<String, dynamic> preview;
  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  String _mode = 'merge';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final p = widget.preview;
    int n(String k) => (p[k] as num?)?.toInt() ?? 0;
    final created = DateTime.fromMillisecondsSinceEpoch(n('created'));
    final device = '${p['device'] ?? ''}';
    Widget row(IconData icon, String label, int count, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(children: [
            Icon(icon, size: 18, color: color ?? cs.onSurfaceVariant),
            const SizedBox(width: Space.md),
            Expanded(child: Text(label, style: tt.bodyMedium)),
            Text('$count', style: tt.titleSmall),
          ]),
        );
    return AlertDialog(
      icon: const Icon(Icons.unarchive_outlined),
      title: const Text('恢复备份'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              '${fmtLectureDate(created)} ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')} 导出'
              '${device.isEmpty ? '' : '自 $device'} · ${n('files')} 个文件 · ${fmtBytes(n('bytes'))}',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: Space.md),
            row(Icons.add_circle_outline_rounded, '本机没有', n('new'), color: cs.primary),
            row(Icons.update_rounded, '备份里的较新', n('newer')),
            row(Icons.history_rounded, '本机的较新', n('older'), color: n('older') > 0 ? cs.tertiary : null),
            row(Icons.check_rounded, '相同', n('same')),
            if (n('skipped') > 0) row(Icons.block_rounded, '不会恢复（密钥或无效路径）', n('skipped')),
            const SizedBox(height: Space.lg),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'merge', label: Text('合并'), icon: Icon(Icons.merge_rounded)),
                ButtonSegment(value: 'overwrite', label: Text('以备份为准'), icon: Icon(Icons.restore_rounded)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: Space.sm),
            Text(
              _mode == 'merge'
                  ? '补上本机没有的文件，更新较旧的文件；本机较新的文件保持不变。'
                  : '所有文件换成备份里的版本；被替换的较新文件会移到课程库的 .sync-conflicts 文件夹。',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: n('files') == 0 ? null : () => Navigator.pop(context, _mode), child: const Text('恢复')),
      ],
    );
  }
}

class _StorageGroup extends StatelessWidget {
  const _StorageGroup({required this.report, required this.busy, required this.onClean});
  final Map<String, dynamic>? report;
  final bool busy;
  final Future<void> Function(String what, String doing) onClean;

  Color _color(ColorScheme cs, String key) => switch (key) {
        'video' => cs.primary,
        'slides' => cs.tertiary,
        'courseware' => cs.secondary,
        'text' => cs.primaryFixedDim,
        'index' => cs.outline,
        'cache' => cs.error,
        'sync' => cs.tertiaryFixedDim,
        _ => cs.outlineVariant,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final r = report;
    if (r == null || r.isEmpty) {
      return const SettingsGroup(title: '存储空间', icon: Icons.pie_chart_outline_rounded, children: [
        Padding(padding: EdgeInsets.all(Space.lg), child: Center(child: CircularProgressIndicator())),
      ]);
    }
    final total = (r['total'] as num? ?? 0).toInt();
    final cats = [
      for (final c in r['categories'] as List? ?? const [])
        if (((c as Map)['bytes'] as num? ?? 0) > 0) c.cast<String, dynamic>(),
    ];
    final clean = _map(r['cleanable']);
    int bytes(Object? v) => (v as num? ?? 0).toInt();
    final root = '${r['library'] ?? ''}';
    return SettingsGroup(title: '存储空间', icon: Icons.pie_chart_outline_rounded, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(fmtBytes(total), style: tt.headlineSmall),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('课程库', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ),
        if (root.isNotEmpty) IconButton(tooltip: '在文件管理器中打开', onPressed: () => openPath(root), icon: const Icon(Icons.folder_open_rounded)),
      ]),
      const SizedBox(height: Space.md),
      if (total > 0) _Bar(parts: [for (final c in cats) (bytes(c['bytes']) / total, _color(cs, '${c['key']}'))]),
      const SizedBox(height: Space.md),
      Wrap(spacing: Space.lg, runSpacing: Space.sm, children: [
        for (final c in cats)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _color(cs, '${c['key']}'), shape: BoxShape.circle)),
            const SizedBox(width: Space.sm),
            Text('${c['label']}', style: tt.bodySmall),
            const SizedBox(width: Space.xs),
            Text(fmtBytes(bytes(c['bytes'])), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
      ]),
      const SizedBox(height: Space.md),
      const Divider(),
      _CleanTile(
        icon: Icons.cleaning_services_outlined,
        title: '转写缓存与未完成下载',
        subtitle: bytes(clean['cache']) > 0 ? '可释放 ${fmtBytes(bytes(clean['cache']))} · 进行中和暂停的任务会保留' : '没有可清理的缓存',
        action: '清理',
        onPressed: busy || bytes(clean['cache']) == 0 ? null : () => onClean('cache', '正在清理缓存'),
      ),
      _CleanTile(
        icon: Icons.restore_from_trash_outlined,
        title: '同步冲突与回收站',
        subtitle: bytes(clean['sync']) > 0 ? '${fmtBytes(bytes(clean['sync']))} · 同步时替换或删除的文件副本' : '没有文件',
        action: '清空',
        onPressed: busy || bytes(clean['sync']) == 0 ? null : () => onClean('sync', '正在清空'),
      ),
      _CleanTile(
        icon: Icons.compress_rounded,
        title: '整理索引',
        subtitle: '合并写入日志、回收空闲空间，让搜索和列表更快',
        action: '整理',
        onPressed: busy ? null : () => onClean('compact', '正在整理索引'),
      ),
      const Divider(),
      for (final (label, key, icon) in [
        ('本地语音模型', 'models', Icons.graphic_eq_rounded),
        ('助手对话、记忆与插件', 'assistant', Icons.forum_outlined),
        ('助手运行环境（Node.js 与依赖）', 'runtime', Icons.terminal_rounded),
      ])
        if (bytes(r[key]) > 0)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, size: 20),
            title: Text(label),
            trailing: Text(fmtBytes(bytes(r[key])), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
    ]);
  }
}

class _CleanTile extends StatelessWidget {
  const _CleanTile({required this.icon, required this.title, required this.subtitle, required this.action, required this.onPressed});
  final IconData icon;
  final String title, subtitle, action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: TextButton(onPressed: onPressed, child: Text(action)),
      );
}

/// A rounded bar split into proportional parts with small gaps.
class _Bar extends StatelessWidget {
  const _Bar({required this.parts});
  final List<(double, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final shown = parts.where((p) => p.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(Corners.full),
      child: SizedBox(
        height: 12,
        child: Row(children: [
          for (final (i, (share, color)) in shown.indexed) ...[
            if (i > 0) const SizedBox(width: 3),
            // Tiny parts stay visible.
            Expanded(flex: (share * 1000).round().clamp(8, 1000), child: ColoredBox(color: color)),
          ],
        ]),
      ),
    );
  }
}
