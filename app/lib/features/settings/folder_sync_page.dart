import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import 'settings_common.dart';

/// Course-scoped portable library, carried by the NAS's WebDAV server.
/// Contract: docs/specs/0023-course-folder-sync.md.
class FolderSyncPage extends StatefulWidget {
  const FolderSyncPage({super.key, this.api});
  final ApiCall? api;
  @override
  State<FolderSyncPage> createState() => _FolderSyncPageState();
}

class _FolderSyncPageState extends State<FolderSyncPage>
    with WidgetsBindingObserver {
  Map<String, dynamic> _status = {}, _courses = {};
  final Set<String> _selected = {};
  final _url = TextEditingController(),
      _user = TextEditingController(),
      _pass = TextEditingController(),
      _folder = TextEditingController();
  bool _busy = false, _media = true, _auto = true, _obscure = true;
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
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _folder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_run());
  }

  Map<String, dynamic> _settings() => {
    'kind': 'folder',
    'url': _url.text.trim(),
    'user': _user.text.trim(),
    if (_pass.text.isNotEmpty) 'password': _pass.text,
    'folder': _folder.text.trim(),
    'course_ids': _selected.toList()..sort(),
    'media': _media,
    'auto': _auto,
  };

  Future<void> _load() async {
    try {
      final s = Map<String, dynamic>.from(
        await _call('GET', '/api/sync') as Map,
      );
      if (!mounted) return;
      // The page polls while it is open; rebuild only when the daemon actually
      // reported something new so idle polling does not repaint the form.
      if (_status.isNotEmpty && jsonEncode(s) == jsonEncode(_status)) return;
      setState(() {
        _status = s;
        if (_url.text.isEmpty && '${s['url'] ?? ''}'.isNotEmpty) {
          _url.text = '${s['url']}';
          _user.text = '${s['user'] ?? ''}';
          _folder.text = '${s['folder'] ?? ''}';
          _media = s['media'] == true;
          _auto = s['auto'] == true;
          if (s['kind'] == 'folder') {
            _selected.addAll((s['course_ids'] as List? ?? []).cast<String>());
          }
        }
      });
      if (_courses.isEmpty && _selected.isNotEmpty) await _preview();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<Map<String, dynamic>> _preview() async {
    final p = Map<String, dynamic>.from(
      await _call('POST', '/api/sync/folder/preview', _settings()) as Map,
    );
    if (mounted) {
      setState(() {
        _courses = Map<String, dynamic>.from(p['courses'] as Map? ?? {});
      });
    }
    return p;
  }

  Future<void> _refreshCourses() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _preview();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A stored password is reused when the field is left empty, so only a first
  /// connection has to type it.
  bool get _ready =>
      _url.text.trim().length > 8 &&
      _user.text.trim().isNotEmpty &&
      (_pass.text.isNotEmpty ||
          (_status['has_password'] == true && _status['kind'] == 'folder')) &&
      _selected.isNotEmpty;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await _preview();
      if (!mounted) return;
      final mb = ((preview['bytes'] as num? ?? 0) / 1000000).toStringAsFixed(1);
      final remoteMb = ((preview['incoming_bytes'] as num? ?? 0) / 1000000)
          .toStringAsFixed(1);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l10n.folderSyncConfirmTitle),
          content: Text(
            '${l10n.folderSyncSelected(_selected.length)}\n\n'
            '${l10n.folderSyncPreview(preview['files'] ?? 0, mb, preview['incoming_files'] ?? 0, remoteMb)}\n\n'
            '${l10n.folderSyncPrivacy(_media)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.folderSyncConfirm),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await _call('PUT', '/api/sync', _settings());
      _pass.clear();
      await _run();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    try {
      if (_status['kind'] == 'folder') await _call('POST', '/api/sync/run');
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
          title: Text(l10n.folderSyncConflicts),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rows.isEmpty) Text(l10n.folderSyncNoConflicts),
                  for (final row in rows)
                    ListTile(
                      title: Text('${row['path']}'),
                      subtitle: Text('${row['bytes']} B'),
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
              child: Text(l10n.commonClose),
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
          title: Text(l10n.folderSyncOtherCopy),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: SelectableText(
                '${detail['body'] ?? l10n.folderSyncBinaryCopy}',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(l10n.folderSyncLater),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'keep'),
              child: Text(l10n.folderSyncKeepCurrent),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'restore'),
              child: Text(l10n.folderSyncUseThis),
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final last = Map<String, dynamic>.from(_status['last'] as Map? ?? {});
    final running = _status['running'] == true;
    final on = _status['configured'] == true && _status['kind'] == 'folder';
    final host = Uri.tryParse(_url.text.trim())?.host ?? '';
    return SettingsSubpage(
      title: l10n.folderSyncTitle,
      children: [
        IntegrationHeader(
          mark: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(Corners.lg),
            ),
            child: Icon(
              Icons.folder_copy_outlined,
              size: 30,
              color: cs.onPrimaryContainer,
            ),
          ),
          title: l10n.folderSyncTitle,
          on: on,
          status: on && host.isNotEmpty
              ? l10n.webdavConnectedTo(host)
              : l10n.commonNotSet,
          body: l10n.folderSyncBody,
        ),
        SettingsGroup(
          title: l10n.folderSyncAccount,
          icon: Icons.dns_outlined,
          children: [
            const SizedBox(height: Space.xs),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: l10n.webdavServer,
                helperText: l10n.folderSyncAccountHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _user,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.webdavAccount,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.webdavAppPassword,
                helperText: on && _status['has_password'] == true
                    ? l10n.webdavKeepPassword
                    : l10n.webdavPasswordSealed,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? l10n.commonShow : l10n.commonHide,
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _folder,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.webdavFolder,
                helperText: l10n.webdavFolderHelper,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.folderSyncCourses,
          icon: Icons.menu_book_outlined,
          children: [
            if (_courses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Text(
                  l10n.folderSyncNoCourses,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            for (final entry in _courses.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
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
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy || _url.text.trim().isEmpty
                    ? null
                    : _refreshCourses,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.folderSyncRefresh),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.folderSyncOptions,
          icon: Icons.tune_rounded,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.webdavMedia),
              subtitle: Text(l10n.webdavMediaHint),
              value: _media,
              onChanged: _busy ? null : (v) => setState(() => _media = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.commonAutoSync),
              subtitle: Text(l10n.folderSyncAutoHint),
              value: _auto,
              onChanged: _busy ? null : (v) => setState(() => _auto = v),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Text(
              _error!,
              style: tt.bodyMedium?.copyWith(color: cs.error),
            ),
          ),
        if (last['error'] != null && '${last['error']}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Text(
              '${last['error']}',
              style: tt.bodyMedium?.copyWith(color: cs.error),
            ),
          ),
        if (running)
          const Padding(
            padding: EdgeInsets.only(top: Space.md),
            child: LinearProgressIndicator(),
          )
        else if (last['at'] != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Text(
              l10n.folderSyncLastRun(
                last['uploaded'] ?? 0,
                last['downloaded'] ?? 0,
                last['conflicts'] ?? 0,
              ),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: Space.lg),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            FilledButton.icon(
              onPressed: _busy || !_ready ? null : _connect,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.cloud_done_outlined),
              label: Text(l10n.folderSyncConnect),
            ),
            OutlinedButton.icon(
              onPressed: _busy || running || !on ? null : _run,
              icon: const Icon(Icons.sync_rounded),
              label: Text(l10n.folderSyncCheck),
            ),
            TextButton.icon(
              onPressed: _conflicts,
              icon: const Icon(Icons.call_split_rounded),
              label: Text(l10n.folderSyncConflicts),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, 0),
          child: Text(
            l10n.webdavPrivacy,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
