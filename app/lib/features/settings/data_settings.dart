import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/android_bridge.dart';
import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import 'settings_common.dart';
import 'webdav_page.dart';
import '../../l10n/l10n.dart';

// The 数据与同步 pane: sync between devices, backups, and what takes space.
// Contract: docs/specs/0014-data-sync-and-backup.md

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

final _backupType = XTypeGroup(label: l10n.backupTypeLabel, extensions: ['zip'], mimeTypes: ['application/zip'], uniformTypeIdentifiers: ['public.zip-archive']);

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
    final name = l10n.backupFileName(now.year, '${now.month}'.padLeft(2, '0'), '${now.day}'.padLeft(2, '0'));
    // Android saves through the system's document screen after the export.
    final android = Platform.isAndroid;
    final path = android
        ? '${(await AndroidBridge.info())['cacheDir']}/$name'
        : await pickSavePath(context, suggestedName: name, type: _backupType, confirm: l10n.commonExport);
    if (path == null || !mounted) return;
    final e = _estimate ?? {};
    setState(() {
      _task = l10n.commonExporting;
      _done = 0;
      _total = ((e['bytes'] as num? ?? 0) + (_media ? e['media_bytes'] as num? ?? 0 : 0)).toInt();
    });
    try {
      await context.read<AppState>().api.download('/api/data/export', {if (_media) 'media': '1'}, File(path),
          onProgress: (n) => mounted ? setState(() => _done = n) : null);
      if (!mounted) return;
      if (android) {
        final saved = await AndroidBridge.saveAs(path, name: name, mime: 'application/zip');
        await File(path).delete().catchError((_) => File(path));
        if (mounted) showSnack(context, saved ? l10n.backupSaved(fmtBytes(_done)) : l10n.backupNotSaved);
        return;
      }
      showSnack(context, l10n.backupSaved(fmtBytes(_done)), action: l10n.commonShowInFolder, onAction: () => revealPath(path));
    } catch (err) {
      if (mounted) showSnack(context, l10n.backupExportFailed(err));
    } finally {
      if (mounted) setState(() => _task = null);
    }
  }

  Future<void> _restore() async {
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [_backupType]);
    } on PlatformException catch (e) {
      if (mounted) showSnack(context, l10n.commonFilePickerFailed(e.message ?? e.code));
      return;
    }
    if (file == null || !mounted) return;
    final api = context.read<AppState>().api;
    final length = await file.length();
    setState(() {
      _task = l10n.backupReading;
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
      _task = l10n.backupRestoring;
      _done = _total = 0;
    });
    try {
      final r = _map(await api.post('/api/data/import/$id/apply', {'mode': mode}, const Duration(minutes: 30)));
      if (!mounted) return;
      final conflict = '${r['conflict'] ?? ''}';
      showSnack(
        context,
        r['written'] == 0 ? l10n.backupNothingToRestore : l10n.backupRestored(r['written'], fmtBytes(r['bytes'] as num? ?? 0)),
        action: conflict.isEmpty || !canOpenFolders ? null : l10n.backupViewReplaced,
        onAction: conflict.isEmpty || !canOpenFolders ? null : () => revealPath(conflict),
      );
      unawaited(_load());
    } catch (e) {
      if (mounted) showSnack(context, l10n.backupRestoreFailed(e));
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
          title: Text(l10n.storageCleanSyncTitle),
          content: Text(l10n.storageCleanSyncBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.commonEmpty)),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _task = done);
    try {
      final r = _map(await _call('POST', '/api/storage/clean', {what: true}));
      if (mounted) showSnack(context, l10n.storageFreed(fmtBytes(r['freed'] as num? ?? 0)));
    } catch (e) {
      if (mounted) showSnack(context, l10n.storageCleanFailed(e));
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
      SettingsGroup(title: l10n.dataSyncTitle, icon: Icons.devices_rounded, padding: const EdgeInsets.symmetric(vertical: Space.sm), children: [
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
          title: Text(l10n.webdavTitle),
          subtitle: Text(webdavSummary(_sync), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: syncOn && syncErr.isNotEmpty ? TextStyle(color: cs.error) : null),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _openSync,
        ),
      ]),
      SettingsGroup(title: l10n.backupTitle, icon: Icons.inventory_2_outlined, children: [
        Text(l10n.backupIntro, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: Space.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.backupIncludeMedia),
          subtitle: Text(e == null ? '…' : (e['media_files'] == 0 ? l10n.backupNoMedia : l10n.backupMediaSize(e['media_files'], fmtBytes(e['media_bytes'] as num? ?? 0)))),
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
            label: Text(e == null ? l10n.backupExport : l10n.backupExportSize(fmtBytes((e['bytes'] as num? ?? 0) + (_media ? e['media_bytes'] as num? ?? 0 : 0)))),
          ),
          OutlinedButton.icon(onPressed: busy ? null : _restore, icon: const Icon(Icons.unarchive_outlined), label: Text(l10n.backupRestoreFrom)),
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
      title: Text(l10n.backupRestore),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              l10n.backupPreviewMeta(fmtLectureDate(created), created.hour.toString().padLeft(2, '0'), created.minute.toString().padLeft(2, '0'), device.isEmpty ? '' : l10n.backupFromDevice(device), n('files'), fmtBytes(n('bytes'))),
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: Space.md),
            row(Icons.add_circle_outline_rounded, l10n.restoreNew, n('new'), color: cs.primary),
            row(Icons.update_rounded, l10n.restoreNewer, n('newer')),
            row(Icons.history_rounded, l10n.restoreOlder, n('older'), color: n('older') > 0 ? cs.tertiary : null),
            row(Icons.check_rounded, l10n.restoreSame, n('same')),
            if (n('skipped') > 0) row(Icons.block_rounded, l10n.restoreSkipped, n('skipped')),
            const SizedBox(height: Space.lg),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'merge', label: Text(l10n.restoreMerge), icon: Icon(Icons.merge_rounded)),
                ButtonSegment(value: 'overwrite', label: Text(l10n.restoreOverwrite), icon: Icon(Icons.restore_rounded)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: Space.sm),
            Text(
              _mode == 'merge'
                  ? l10n.restoreMergeHint
                  : l10n.restoreOverwriteHint,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
        FilledButton(onPressed: n('files') == 0 ? null : () => Navigator.pop(context, _mode), child: Text(l10n.commonRestore)),
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
      return SettingsGroup(title: l10n.storageTitle, icon: Icons.pie_chart_outline_rounded, children: [
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
    return SettingsGroup(title: l10n.storageTitle, icon: Icons.pie_chart_outline_rounded, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(fmtBytes(total), style: tt.headlineSmall),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(l10n.commonLibrary, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ),
        if (root.isNotEmpty && canOpenFolders) IconButton(tooltip: l10n.commonOpenInFileManager, onPressed: () => openPath(root), icon: const Icon(Icons.folder_open_rounded)),
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
        title: l10n.storageCache,
        subtitle: bytes(clean['cache']) > 0 ? l10n.storageCacheCleanable(fmtBytes(bytes(clean['cache']))) : l10n.storageCacheEmpty,
        action: l10n.commonClean,
        onPressed: busy || bytes(clean['cache']) == 0 ? null : () => onClean('cache', l10n.storageCleaningCache),
      ),
      _CleanTile(
        icon: Icons.restore_from_trash_outlined,
        title: l10n.storageSync,
        subtitle: bytes(clean['sync']) > 0 ? l10n.storageSyncSize(fmtBytes(bytes(clean['sync']))) : l10n.storageNoFiles,
        action: l10n.commonEmpty,
        onPressed: busy || bytes(clean['sync']) == 0 ? null : () => onClean('sync', l10n.storageEmptying),
      ),
      _CleanTile(
        icon: Icons.compress_rounded,
        title: l10n.storageCompact,
        subtitle: l10n.storageCompactHint,
        action: l10n.storageCompactAction,
        onPressed: busy ? null : () => onClean('compact', l10n.storageCompacting),
      ),
      const Divider(),
      for (final (label, key, icon) in [
        (l10n.storageModels, 'models', Icons.graphic_eq_rounded),
        (l10n.storageAssistant, 'assistant', Icons.forum_outlined),
        (l10n.storageRuntime, 'runtime', Icons.terminal_rounded),
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
