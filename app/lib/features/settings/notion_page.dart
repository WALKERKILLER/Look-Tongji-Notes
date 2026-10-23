import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/look_markdown.dart';
import '../../widgets/states.dart';
import 'settings_common.dart';
import '../../l10n/l10n.dart';

// Notion sync of the library: connect an internal integration, pick the
// page it lives under, sync. Contract: docs/specs/0013-notion-sync.md

const notionLogo = 'assets/brands/notion.svg';
const _integrationsUrl = 'https://www.notion.so/profile/integrations';

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

/// One line for the Notion status, also used by the settings tile.
String notionSummary(Map<String, dynamic> st) {
  if (st['connected'] != true) return l10n.notionSubtitle;
  if (st['running'] == true) return l10n.commonSyncing;
  final parent = _map(st['parent']);
  if (parent.isEmpty) return l10n.notionNoParent;
  final err = '${_map(st['last'])['error'] ?? ''}';
  if (err.isNotEmpty) return err;
  return l10n.notionStatus(parent['title'], st['pages'] ?? 0, st['auto'] == true ? l10n.commonAutoSuffix : '');
}

class NotionPage extends StatefulWidget {
  const NotionPage({super.key, this.api, this.events});

  /// For tests; default to the app's daemon connection.
  final ApiCall? api;
  final Stream<Map<String, dynamic>>? events;

  @override
  State<NotionPage> createState() => _NotionPageState();
}

class _NotionPageState extends State<NotionPage> {
  Map<String, dynamic>? _st;
  Object? _error;
  String? _connectError;
  bool _busy = false, _obscure = true;
  final _token = TextEditingController();
  StreamSubscription? _sub;

  ApiCall get _call => widget.api ?? context.read<AppState>().api.call;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = (widget.events ?? context.read<AppState>().events).listen((e) {
      if (!mounted) return;
      switch (e['type']) {
        case 'notion_progress':
          setState(() => _st = {...?_st, 'running': true, 'progress': e['data']});
        case 'notion_synced' || 'notion_changed':
          _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = _map(await _call('GET', '/api/notion'));
      if (mounted) {
        setState(() {
          _st = st;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Runs a request that answers with the status; reports failures.
  Future<bool> _do(String method, String path, [Object? body]) async {
    setState(() => _busy = true);
    try {
      final st = _map(await _call(method, path, body));
      if (mounted) setState(() => _st = st);
      return true;
    } catch (e) {
      if (mounted) showSnack(context, '$e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _connectError = null;
    });
    try {
      final st = _map(await _call('POST', '/api/notion/connect', {'token': _token.text.trim()}));
      _token.clear();
      if (mounted) setState(() => _st = st);
    } catch (e) {
      if (mounted) setState(() => _connectError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.notionDisconnectTitle),
        content: Text(l10n.notionDisconnectBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.commonDisconnect)),
        ],
      ),
    );
    if (ok == true) await _do('POST', '/api/notion/disconnect');
  }

  Future<void> _pickParent() async {
    final st = _st ?? {};
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PagePicker(call: _call),
    );
    if (picked == null || !mounted) return;
    if ((st['pages'] as num? ?? 0) > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l10n.notionChangeParentTitle),
          content: Text(l10n.notionChangeParentBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.commonChange)),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _do('PUT', '/api/notion', {'parent': picked});
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    if (st == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notion')),
        body: _error != null ? ErrorState(error: _error!, onRetry: _load) : const CenteredLoader(),
      );
    }
    final connected = st['connected'] == true;
    final bot = _map(st['bot']);
    return SettingsSubpage(title: 'Notion', children: [
      IntegrationHeader(
        mark: const BrandMark(notionLogo, size: 56, mono: true),
        title: 'Notion',
        on: connected,
        status: connected ? l10n.notionConnectedTo('${bot['workspace'] ?? ''}'.isEmpty ? l10n.notionWorkspace : bot['workspace']) : l10n.commonNotConnected,
        body: l10n.notionBody,
      ),
      if (connected) ..._connected(context, st) else ..._connectForm(context),
    ]);
  }

  // ---- not connected ----

  List<Widget> _connectForm(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return [
      SettingsGroup(title: l10n.notionCreateIntegration, children: [
        const SizedBox(height: Space.xs),
        SettingsSteps([
          l10n.notionStep1,
          l10n.notionStep2,
          l10n.notionStep3,
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openPlainLink(context, _integrationsUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(l10n.notionOpenIntegrations),
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: _token,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() => _connectError = null),
          onSubmitted: (_) => _token.text.trim().isEmpty || _busy ? null : _connect(),
          decoration: InputDecoration(
            labelText: l10n.notionSecret,
            hintText: 'ntn_…',
            border: const OutlineInputBorder(),
            errorText: _connectError,
            helperText: l10n.notionSecretHelper,
            suffixIcon: IconButton(
              tooltip: _obscure ? l10n.commonShow : l10n.commonHide,
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        Row(children: [
          FilledButton.icon(
            onPressed: _busy || _token.text.trim().isEmpty ? null : _connect,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.link_rounded),
            label: Text(_busy ? l10n.commonConnecting : l10n.commonConnect),
          ),
        ]),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, 0),
        child: Text(l10n.notionShareHint,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ),
    ];
  }

  // ---- connected ----

  List<Widget> _connected(BuildContext context, Map<String, dynamic> st) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final parent = _map(st['parent']);
    final bot = _map(st['bot']);
    final root = '${st['root_url'] ?? ''}';
    return [
      SettingsGroup(title: l10n.notionParent, children: [
        if (parent.isEmpty) ...[
          const SizedBox(height: Space.xs),
          SettingsSteps([
            l10n.notionParentStep1,
            l10n.notionParentStep2,
            l10n.notionParentStep3,
          ]),
          const SizedBox(height: Space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(onPressed: _busy ? null : _pickParent, icon: const Icon(Icons.add_link_rounded), label: Text(l10n.notionChoosePage)),
          ),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _PageIcon(icon: '${parent['icon'] ?? ''}'),
            title: Text('${parent['title']}'),
            subtitle: Text(l10n.notionParentHint),
            trailing: TextButton(onPressed: _busy || st['running'] == true ? null : _pickParent, child: Text(l10n.commonChange)),
          ),
          if (root.startsWith('https://'))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openPlainLink(context, root),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l10n.notionOpenInNotion),
              ),
            ),
        ],
      ]),
      if (parent.isNotEmpty) _syncGroup(context, st),
      SettingsGroup(title: l10n.commonConnect, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.key_outlined),
          title: Text('${bot['name'] ?? l10n.notionIntegration}'.isEmpty ? l10n.notionIntegration : '${bot['name']}'),
          subtitle: Text(l10n.notionSecretTail(st['token_last4'] ?? '')),
          trailing: TextButton(
            onPressed: _busy ? null : _disconnect,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: Text(l10n.commonDisconnect),
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, 0),
        child: Text(l10n.notionLimits,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ),
    ];
  }

  Widget _syncGroup(BuildContext context, Map<String, dynamic> st) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final running = st['running'] == true;
    final prog = _map(st['progress']);
    final done = (prog['done'] as num?)?.toInt() ?? 0, total = (prog['total'] as num?)?.toInt() ?? 0;
    final last = _map(st['last']);
    final conflicts = jsonList(last['conflicts']).map((e) => '$e').toList();
    final errors = jsonList(last['errors']).map((e) => '$e').toList();
    final err = '${last['error'] ?? ''}';
    final at = (last['at'] as num?)?.toInt() ?? 0;
    return SettingsGroup(title: l10n.commonSync, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.notionAutoSync),
        subtitle: Text(l10n.notionAutoSyncHint),
        value: st['auto'] == true,
        onChanged: _busy ? null : (v) => _do('PUT', '/api/notion', {'auto': v}),
      ),
      const SizedBox(height: Space.sm),
      AnimatedSize(
        duration: Motion.medium2,
        curve: Motion.emphasized,
        alignment: Alignment.topCenter,
        child: running
            ? Padding(
                padding: const EdgeInsets.only(bottom: Space.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  LinearProgressIndicator(value: total > 0 ? done / total : null, borderRadius: BorderRadius.circular(Corners.full)),
                  const SizedBox(height: Space.sm),
                  Text(total > 0 ? l10n.commonSyncProgress(done, total) : l10n.commonChecking, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              )
            : at == 0
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: Space.lg),
                    child: _LastSync(at: at, last: last, error: err),
                  ),
      ),
      if (!running && conflicts.isNotEmpty)
        _Issues(
          icon: Icons.edit_note_rounded,
          title: l10n.notionConflicts(conflicts.length),
          items: conflicts,
        ),
      if (!running && errors.isNotEmpty) _Issues(icon: Icons.error_outline_rounded, title: l10n.notionErrors(errors.length), items: errors, error: true),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        FilledButton.icon(
          onPressed: running || _busy ? null : () => _do('POST', '/api/notion/sync', {'full': false}),
          icon: const Icon(Icons.sync_rounded),
          label: Text(at == 0 ? l10n.commonStartSync : l10n.commonSyncNow),
        ),
        Tooltip(
          message: l10n.notionFullCheckHint,
          child: OutlinedButton(
            onPressed: running || _busy || at == 0 ? null : () => _do('POST', '/api/notion/sync', {'full': true}),
            child: Text(l10n.notionFullCheck),
          ),
        ),
      ]),
    ]);
  }
}

class _LastSync extends StatelessWidget {
  const _LastSync({required this.at, required this.last, required this.error});
  final int at;
  final Map<String, dynamic> last;
  final String error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    int n(String k) => (last[k] as num?)?.toInt() ?? 0;
    final counts = [
      if (n('created') > 0) l10n.syncCreated(n('created')),
      if (n('updated') > 0) l10n.syncUpdated(n('updated')),
      if (n('trashed') > 0) l10n.syncTrashed(n('trashed')),
      l10n.syncUnchanged(n('unchanged')),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(error.isEmpty ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 20, color: error.isEmpty ? cs.primary : cs.error),
      const SizedBox(width: Space.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.commonLastSynced(fmtRelative(DateTime.fromMillisecondsSinceEpoch(at))), style: tt.bodyMedium),
          Text(error.isEmpty ? counts.join(' · ') : error, style: tt.bodySmall?.copyWith(color: error.isEmpty ? cs.onSurfaceVariant : cs.error)),
        ]),
      ),
    ]);
  }
}

/// Pages kept or failed in the last sync, folded.
class _Issues extends StatelessWidget {
  const _Issues({required this.icon, required this.title, required this.items, this.error = false});
  final IconData icon;
  final String title;
  final List<String> items;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = error ? cs.error : cs.tertiary;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Material(
        color: cs.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(Corners.lg),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(icon, color: color),
          title: Text(title, style: tt.bodyMedium),
          childrenPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in items.take(50))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                child: Text(s, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            if (items.length > 50) Text(l10n.notionMoreItems(items.length - 50), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _PageIcon extends StatelessWidget {
  const _PageIcon({required this.icon});
  final String icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(Corners.md)),
      child: icon.isEmpty ? Icon(Icons.description_outlined, size: 20, color: cs.onSurfaceVariant) : Text(icon, style: const TextStyle(fontSize: 20)),
    );
  }
}

/// Lists the pages shared with the integration; a pasted link works too.
class _PagePicker extends StatefulWidget {
  const _PagePicker({required this.call});
  final ApiCall call;

  @override
  State<_PagePicker> createState() => _PagePickerState();
}

class _PagePickerState extends State<_PagePicker> {
  final _q = TextEditingController();
  List<Map<String, dynamic>>? _pages;
  Object? _error;
  Timer? _debounce;
  int _seq = 0;

  static final _link = RegExp(r'(notion\.(so|site)/|^[0-9a-f]{32}$|^[0-9a-f-]{36}$)', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final seq = ++_seq;
    final q = _q.text.trim();
    setState(() => _error = null);
    try {
      final r = await widget.call('GET', '/api/notion/pages${q.isEmpty || _link.hasMatch(q) ? '' : '?q=${Uri.encodeQueryComponent(q)}'}');
      if (mounted && seq == _seq) setState(() => _pages = jsonList(r).map(_map).toList());
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = _q.text.trim();
    final pages = _pages;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xs),
          child: Text(l10n.notionChooseParent, style: tt.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
          child: Text(l10n.notionChooseParentHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: SearchBar(
            controller: _q,
            hintText: l10n.notionSearchHint,
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
            leading: const Icon(Icons.search_rounded),
            onChanged: (_) {
              setState(() {});
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _search);
            },
          ),
        ),
        const SizedBox(height: Space.sm),
        Expanded(
          child: _error != null
              ? ErrorState(error: _error!, onRetry: _search)
              : pages == null
                  ? const CenteredLoader()
                  : ListView(padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm), children: [
                      if (_link.hasMatch(q))
                        ListTile(
                          shape: const StadiumBorder(),
                          leading: const Icon(Icons.link_rounded),
                          title: Text(l10n.notionUseLink),
                          subtitle: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(context, q),
                        ),
                      for (final p in pages)
                        ListTile(
                          shape: const StadiumBorder(),
                          leading: _PageIcon(icon: '${p['icon'] ?? ''}'),
                          title: Text('${p['title']}'.isEmpty ? l10n.commonUntitled : '${p['title']}'),
                          onTap: () => Navigator.pop(context, '${p['id']}'),
                        ),
                      if (pages.isEmpty && !_link.hasMatch(q))
                        Padding(
                          padding: const EdgeInsets.all(Space.xl),
                          child: Column(children: [
                            Text(q.isEmpty ? l10n.notionNoPages : l10n.notionNoMatch(q), style: tt.titleSmall),
                            const SizedBox(height: Space.sm),
                            Text(l10n.notionShareSteps,
                                textAlign: TextAlign.center, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                            const SizedBox(height: Space.md),
                            TextButton.icon(onPressed: _search, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(l10n.commonRefresh)),
                          ]),
                        ),
                    ]),
        ),
      ]),
    );
  }
}
