import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/look_markdown.dart' show openPlainLink;
import '../../widgets/states.dart';
import 'canvas_course.dart';
import 'school_emblem.dart';
import '../../l10n/l10n.dart';

/// Connects the school's Canvas: school, sign-in method, status and which
/// Look course each Canvas course belongs to.
/// Contract: docs/specs/0011-canvas-and-schools.md
class CanvasPage extends StatefulWidget {
  const CanvasPage({super.key, this.api, this.events, this.lookCourses, this.lookSignedIn});

  /// For tests; default to the app's daemon connection and state.
  final ApiCall? api;
  final Stream<Map<String, dynamic>>? events;
  final List<({String id, String title})>? lookCourses;
  final bool? lookSignedIn;

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => jsonList(v).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

final _other = {'id': 'other', 'name': l10n.schoolOther, 'canvas': '', 'sso': '', 'look': false};

class _CanvasPageState extends State<CanvasPage> {
  Map<String, dynamic>? _r;
  Object? _error;
  StreamSubscription? _sub;
  bool _editing = false;
  bool _busy = false;
  String _school = 'tongji';
  String _mode = 'sso';
  bool _create = true;
  final _base = TextEditingController();
  final _token = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  ApiCall get _call => widget.api ?? context.read<AppState>().api.call;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = (widget.events ?? context.read<AppState>().events).listen((e) {
      if (e['type'] == 'canvas_changed') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final c in [_base, _token, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = _map(await _call('GET', '/api/canvas'));
      if (!mounted) return;
      final st = _map(r['status']);
      setState(() {
        if (_r == null && st['connected'] == true) {
          _school = '${st['school']}';
          _mode = '${st['mode']}';
          _user.text = '${st['username'] ?? ''}';
          if (_school == 'other') _base.text = '${st['base']}';
        }
        _r = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<Map<String, dynamic>> get _schools => [..._maps(_r?['schools']), _other];
  Map<String, dynamic> get _sc => _schools.firstWhere((s) => s['id'] == _school, orElse: () => _other);
  bool get _hasSso => '${_sc['sso']}'.isNotEmpty;
  bool get _needsUis => _sc['sso'] == 'uis' && (_mode == 'sso' || _create);
  bool get _lookSignedIn => widget.lookSignedIn ?? context.read<AppState?>()?.auth.signedIn ?? false;

  String get _baseUrl => _school == 'other' ? _base.text.trim() : '${_sc['canvas']}';

  bool get _ready {
    if (_school == 'other' && !_baseUrl.startsWith('https://')) return false;
    if (_mode == 'token' && !(_hasSso && _create) && _token.text.trim().isEmpty) return false;
    if (_needsUis && (_user.text.trim().isEmpty || (_pass.text.isEmpty && _user.text.trim() != '${_map(_r?['status'])['username'] ?? ''}'))) return false;
    if (_sc['sso'] == 'look' && (_mode == 'sso' || _create) && !_lookSignedIn) return false;
    return true;
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await _call('POST', '/api/canvas/connect', {
        'school': _school,
        'base': _baseUrl,
        'mode': _mode,
        if (_mode == 'token' && !(_hasSso && _create)) 'token': _token.text.trim(),
        if (_mode == 'token' && _hasSso && _create) 'create': true,
        if (_needsUis) 'username': _user.text.trim(),
        if (_needsUis && _pass.text.isNotEmpty) 'password': _pass.text,
      });
      _token.clear();
      _pass.clear();
      if (mounted) setState(() => _editing = false);
      await _load();
      if (mounted) showSnack(context, l10n.canvasConnected);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    try {
      final st = await _call('POST', '/api/canvas/sync');
      if (mounted) setState(() => _r = {...?_r, 'status': st});
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _disconnect(Map<String, dynamic> st) async {
    final auto = st['token_auto'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.link_off_rounded),
        title: Text(l10n.canvasDisconnectTitle),
        content: Text(l10n.canvasDisconnectBody(auto ? l10n.canvasRevokesToken : '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.commonDisconnect)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _call('POST', '/api/canvas/disconnect');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _link(String canvasId, {String course = '', bool auto = false}) async {
    try {
      final st = await _call('PUT', '/api/canvas/links/$canvasId', {'course': course, 'auto': auto});
      if (mounted) setState(() => _r = {...?_r, 'status': st});
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSchoolCanvas)),
      body: r == null
          ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const CenteredLoader())
          : ListView(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.huge),
              children: [
                ContentWidth(
                  max: 840,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _map(r['status'])['connected'] == true && !_editing ? _connected(context, _map(r['status'])) : _form(context, _map(r['status'])),
                  ),
                ),
              ],
            ),
    );
  }

  // ---- connect form ----

  List<Widget> _form(BuildContext context, Map<String, dynamic> st) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sc = _sc;
    final note = '${sc['note'] ?? ''}';
    return [
      Text(l10n.canvasConnectTitle, style: tt.headlineSmall),
      const SizedBox(height: Space.xs),
      Text(l10n.canvasConnectBody, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Space.xl),
      Text(l10n.commonSchool, style: tt.titleSmall),
      const SizedBox(height: Space.sm),
      Wrap(spacing: Space.md, runSpacing: Space.md, children: [
        for (final s in _schools)
          _SchoolCard(
            school: s,
            selected: s['id'] == _school,
            onTap: () => setState(() {
              _school = '${s['id']}';
              if ('${s['sso']}'.isEmpty) _mode = 'token';
            }),
          ),
      ]),
      if (note.isNotEmpty) ...[
        const SizedBox(height: Space.md),
        _Banner(icon: Icons.info_outline_rounded, text: note),
      ],
      if (_school == 'other') ...[
        const SizedBox(height: Space.lg),
        TextField(
          controller: _base,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: l10n.canvasUrl, hintText: 'https://canvas.example.edu.cn', border: OutlineInputBorder()),
        ),
      ],
      const SizedBox(height: Space.xl),
      Text(l10n.canvasSignInMethod, style: tt.titleSmall),
      const SizedBox(height: Space.sm),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'sso', enabled: _hasSso, icon: const Icon(Icons.verified_user_outlined), label: Text(l10n.authTongji)),
          ButtonSegment(value: 'token', icon: Icon(Icons.key_outlined), label: Text(l10n.canvasAccessToken)),
        ],
        selected: {_hasSso ? _mode : 'token'},
        onSelectionChanged: (v) => setState(() => _mode = v.first),
      ),
      const SizedBox(height: Space.lg),
      ..._method(context),
      const SizedBox(height: Space.xl),
      Row(children: [
        FilledButton.icon(
          onPressed: _busy || !_ready ? null : _connect,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.link_rounded),
          label: Text(_busy ? l10n.commonConnecting : l10n.commonConnect),
        ),
        if (st['connected'] == true) ...[
          const SizedBox(width: Space.sm),
          TextButton(onPressed: _busy ? null : () => setState(() => _editing = false), child: Text(l10n.commonCancel)),
        ],
      ]),
    ];
  }

  List<Widget> _method(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sso = '${_sc['sso']}';
    final mode = _hasSso ? _mode : 'token';
    final uisFields = [
      TextField(
        controller: _user,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: l10n.canvasFudanId, border: OutlineInputBorder()),
      ),
      const SizedBox(height: Space.md),
      TextField(
        controller: _pass,
        obscureText: true,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: l10n.canvasFudanPassword, border: OutlineInputBorder(), helperText: l10n.canvasFudanPasswordHelper),
      ),
    ];
    final lookWarning = sso == 'look' && !_lookSignedIn ? [_Banner(icon: Icons.login_rounded, text: l10n.canvasNeedsTongji, error: true), const SizedBox(height: Space.md)] : <Widget>[];
    if (mode == 'sso') {
      return [
        ...lookWarning,
        _Explain(
          icon: Icons.autorenew_rounded,
          title: sso == 'look' ? l10n.canvasTongjiTitle : l10n.canvasFudanTitle,
          body: sso == 'look'
              ? l10n.canvasTongjiBody
              : l10n.canvasFudanBody,
        ),
        if (sso == 'uis') ...[const SizedBox(height: Space.lg), ...uisFields],
      ];
    }
    final base = _baseUrl;
    return [
      if (_hasSso) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.canvasAutoTokenTitle),
          subtitle: Text(l10n.canvasAutoTokenBody),
          value: _create,
          onChanged: (v) => setState(() => _create = v),
        ),
        const SizedBox(height: Space.sm),
      ],
      if (_hasSso && _create) ...[
        ...lookWarning,
        if (sso == 'uis') ...uisFields,
      ] else ...[
        Text(l10n.canvasManualToken, style: tt.titleSmall),
        const SizedBox(height: Space.sm),
        for (final (i, s) in [
          l10n.canvasTokenStep1,
          l10n.canvasTokenStep2,
          l10n.canvasTokenStep3,
        ].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 11, backgroundColor: cs.secondaryContainer, child: Text('${i + 1}', style: tt.labelSmall?.copyWith(color: cs.onSecondaryContainer))),
              const SizedBox(width: Space.md),
              Expanded(child: Text(s, style: tt.bodyMedium)),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: base.startsWith('https://') ? () => openPlainLink(context, '$base/profile/settings') : null,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(l10n.canvasOpenSettings),
          ),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _token,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.canvasAccessToken,
            border: OutlineInputBorder(),
            helperText: l10n.canvasTokenHelper,
            helperMaxLines: 2,
          ),
        ),
      ],
    ];
  }

  // ---- connected ----

  List<Widget> _connected(BuildContext context, Map<String, dynamic> st) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sc = _schools.firstWhere((s) => s['id'] == st['school'], orElse: () => _other);
    final syncing = st['syncing'] == true;
    final synced = (st['synced_at'] as num?)?.toInt() ?? 0;
    final err = '${st['error'] ?? ''}';
    final exp = DateTime.tryParse('${st['expires_at'] ?? ''}')?.toLocal();
    final auth = st['mode'] == 'sso'
        ? l10n.canvasSessionAuth
        : [
            l10n.canvasTokenTail(st['token_last4'] ?? ''),
            if (st['token_auto'] == true) l10n.canvasAutoRenew,
            if (exp != null) l10n.canvasTokenExpires(st['token_auto'] == true ? l10n.canvasCurrentToken : '', fmtIsoDay(exp)),
          ].join(' · ');
    final courses = _maps(st['courses']);
    final open = courses.fold<int>(0, (n, c) => n + ((c['open'] as num?)?.toInt() ?? 0));
    return [
      Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SchoolEmblem(id: '${sc['id']}', name: '${sc['name']}', url: '${sc['emblem_url'] ?? ''}', size: 56),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${sc['id'] == 'other' ? Uri.tryParse('${st['base']}')?.host ?? 'Canvas' : sc['name']} · Canvas', style: tt.titleLarge),
                  const SizedBox(height: Space.xxs),
                  Text('${st['user'] ?? ''}'.isEmpty ? l10n.commonConnected : l10n.canvasConnectedAs(st['user']), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
            const SizedBox(height: Space.lg),
            _Line(icon: st['mode'] == 'sso' ? Icons.verified_user_outlined : Icons.key_outlined, text: auth),
            _Line(
              icon: Icons.schedule_rounded,
              text: syncing
                  ? l10n.commonSyncing
                  : [synced > 0 ? l10n.commonLastSynced(fmtRelative(DateTime.fromMillisecondsSinceEpoch(synced))) : l10n.canvasNotSynced, l10n.canvasSyncInterval].join(' · '),
            ),
            _Line(icon: Icons.assignment_outlined, text: l10n.canvasSummary(courses.length, open)),
            AnimatedSize(
              duration: Motion.medium2,
              curve: Motion.emphasized,
              child: syncing ? const Padding(padding: EdgeInsets.only(top: Space.sm), child: LinearProgressIndicator()) : const SizedBox(width: double.infinity),
            ),
            if (err.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              _Banner(icon: Icons.error_outline_rounded, text: err, error: true),
            ],
            const SizedBox(height: Space.lg),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              FilledButton.tonalIcon(onPressed: syncing ? null : _sync, icon: const Icon(Icons.sync_rounded), label: Text(l10n.commonSyncNow)),
              OutlinedButton.icon(onPressed: () => setState(() => _editing = true), icon: const Icon(Icons.manage_accounts_outlined), label: Text(l10n.canvasChangeMethod)),
              TextButton.icon(onPressed: () => _disconnect(st), icon: const Icon(Icons.link_off_rounded), label: Text(l10n.commonDisconnect)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: Space.xl),
      Text(l10n.canvasCourseLinks, style: tt.titleMedium),
      const SizedBox(height: Space.xs),
      Text(l10n.canvasCourseLinksBody, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Space.md),
      if (courses.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xl),
          child: Text(syncing ? l10n.canvasLoadingCourses : l10n.canvasNoCourses, textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        )
      else
        Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Corners.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, c) in courses.indexed) ...[
              if (i > 0) Divider(height: 1, indent: 72, color: cs.outlineVariant.withValues(alpha: 0.5)),
              _CourseRow(course: c, looks: _looks(), onLink: _link),
            ],
          ]),
        ),
    ];
  }

  List<({String id, String title})> _looks() =>
      widget.lookCourses ?? [for (final c in context.read<AppState?>()?.courses ?? const []) (id: c.id, title: c.title)];
}

class _SchoolCard extends StatelessWidget {
  const _SchoolCard({required this.school, required this.selected, required this.onTap});
  final Map<String, dynamic> school;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final chips = [if (school['look'] == true) l10n.canvasLookReplay, 'Canvas'];
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: Motion.medium2,
        curve: Motion.emphasized,
        width: 196,
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(selected ? Corners.xl : Corners.lg),
          border: Border.all(color: selected ? Colors.transparent : cs.outlineVariant),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(selected ? Corners.xl : Corners.lg),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SchoolEmblem(id: '${school['id']}', name: '${school['name']}', url: '${school['emblem_url'] ?? ''}', size: 48),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: Motion.short4,
                    opacity: selected ? 1 : 0,
                    child: Icon(Icons.check_circle_rounded, color: cs.onSecondaryContainer),
                  ),
                ]),
                const SizedBox(height: Space.md),
                Text('${school['name']}', style: tt.titleMedium?.copyWith(color: selected ? cs.onSecondaryContainer : null)),
                const SizedBox(height: Space.xs),
                Text(
                  school['id'] == 'other' ? l10n.canvasAnySite : chips.join(' · '),
                  style: tt.bodySmall?.copyWith(color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course, required this.looks, required this.onLink});
  final Map<String, dynamic> course;
  final List<({String id, String title})> looks;
  final Future<void> Function(String canvasId, {String course, bool auto}) onLink;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final id = '${course['id']}';
    final look = '${course['look_course'] ?? ''}';
    final manual = course['manual'] == true;
    final title = looks.where((l) => l.id == look).map((l) => l.title).firstOrNull ?? '';
    final label = look.isEmpty ? (manual ? l10n.canvasNoLink : l10n.canvasAutoNoMatch) : (manual ? title : l10n.canvasAutoMatch(title));
    final open = (course['open'] as num?)?.toInt() ?? 0;
    final term = '${_map(course['term'])['name'] ?? ''}';
    final meta = Text([if (term.isNotEmpty) term, open > 0 ? l10n.canvasOpenAssignments(open) : l10n.canvasNoOpenAssignments].join(' · '),
        maxLines: 1, overflow: TextOverflow.ellipsis);
    // On a phone the link sits under the name, which keeps the row's width.
    final compact = context.isCompact;
    final link = MenuAnchor(
      builder: (context, ctl, _) => ActionChip(
        avatar: Icon(look.isEmpty ? Icons.link_off_rounded : Icons.link_rounded, size: 18),
        label: ConstrainedBox(constraints: BoxConstraints(maxWidth: compact ? 220 : 180), child: Text(label, overflow: TextOverflow.ellipsis)),
        tooltip: l10n.canvasLinkCourse,
        onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
      ),
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Icons.auto_awesome_outlined), onPressed: () => onLink(id, auto: true), child: Text(l10n.canvasAutoLink)),
        MenuItemButton(leadingIcon: const Icon(Icons.link_off_rounded), onPressed: () => onLink(id), child: Text(l10n.canvasNoLink)),
        if (looks.isNotEmpty) const Divider(),
        for (final l in looks)
          MenuItemButton(
            leadingIcon: Icon(l.id == look && manual ? Icons.check_rounded : Icons.class_outlined),
            onPressed: () => onLink(id, course: l.id),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: Text(l.title, overflow: TextOverflow.ellipsis)),
          ),
      ],
    );
    return ListTile(
      contentPadding: EdgeInsets.fromLTRB(Space.lg, Space.xs, compact ? Space.lg : Space.sm, Space.xs),
      leading: CircleAvatar(
        backgroundColor: cs.tertiaryContainer,
        child: Text('${course['name']}'.characters.firstOrNull ?? '?', style: TextStyle(color: cs.onTertiaryContainer)),
      ),
      title: Text('${course['name']}', maxLines: compact ? 2 : 1, overflow: TextOverflow.ellipsis),
      subtitle: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [meta, const SizedBox(height: Space.xs), link])
          : meta,
      onTap: () => showCanvasCourseSheet(context, id, '${course['name']}'),
      trailing: compact ? null : link,
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: Space.md),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}

class _Explain extends StatelessWidget {
  const _Explain({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(Corners.lg)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: cs.primary),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: tt.titleSmall),
            const SizedBox(height: Space.xs),
            Text(body, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.error = false});
  final IconData icon;
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = error ? cs.onErrorContainer : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      decoration: BoxDecoration(color: error ? cs.errorContainer : cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Corners.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: fg),
        const SizedBox(width: Space.md),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg))),
      ]),
    );
  }
}

/// The settings row for Canvas: connection at a glance, opens [CanvasPage].
class CanvasSettingsEntry extends StatefulWidget {
  const CanvasSettingsEntry({super.key});
  @override
  State<CanvasSettingsEntry> createState() => _CanvasSettingsEntryState();
}

class _CanvasSettingsEntryState extends State<CanvasSettingsEntry> {
  Map<String, dynamic>? _r;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<AppState>().events.listen((e) {
      if (e['type'] == 'canvas_changed' && _map(e['data'])['what'] != 'syncing') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = _map(await context.read<AppState>().api.get('/api/canvas'));
      if (mounted) setState(() => _r = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final st = _map(_r?['status']);
    final connected = st['connected'] == true;
    final sc = [..._maps(_r?['schools']), _other].firstWhere((s) => s['id'] == (connected ? st['school'] : 'tongji'), orElse: () => _other);
    final err = '${st['error'] ?? ''}';
    final open = _maps(st['courses']).fold<int>(0, (n, c) => n + ((c['open'] as num?)?.toInt() ?? 0));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SchoolEmblem(id: '${sc['id']}', name: '${sc['name']}', url: '${sc['emblem_url'] ?? ''}'),
      title: Text(connected ? l10n.canvasSchoolConnected(sc['id'] == 'other' ? '' : sc['name']) : l10n.canvasConnect),
      subtitle: Text(
        !connected
            ? l10n.canvasEntryHint
            : err.isNotEmpty
                ? err
                : l10n.canvasSummary(_maps(st['courses']).length, open),
        style: err.isNotEmpty ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CanvasPage())).then((_) => _load()),
    );
  }
}
