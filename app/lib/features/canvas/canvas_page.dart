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

const _other = {'id': 'other', 'name': '其他学校', 'canvas': '', 'sso': '', 'look': false};

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
      if (mounted) showSnack(context, '已连接 Canvas，正在同步课程和作业');
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
        title: const Text('断开 Canvas？'),
        content: Text('日程里的 Canvas 作业和课程关联会一起移除，已下载的课件保留。${auto ? 'Look Studio 创建的访问令牌也会被撤销。' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('断开')),
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
      appBar: AppBar(title: const Text('学校与 Canvas')),
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
      Text('连接你学校的 Canvas', style: tt.headlineSmall),
      const SizedBox(height: Space.xs),
      Text('作业会进入日程，截止前一天提醒你；课件可以直接下载到对应课程的文件夹。Look Studio 只读取，不会提交或修改任何内容。', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Space.xl),
      Text('学校', style: tt.titleSmall),
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
          decoration: const InputDecoration(labelText: 'Canvas 地址', hintText: 'https://canvas.example.edu.cn', border: OutlineInputBorder()),
        ),
      ],
      const SizedBox(height: Space.xl),
      Text('登录方式', style: tt.titleSmall),
      const SizedBox(height: Space.sm),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'sso', enabled: _hasSso, icon: const Icon(Icons.verified_user_outlined), label: const Text('统一身份认证')),
          const ButtonSegment(value: 'token', icon: Icon(Icons.key_outlined), label: Text('访问令牌')),
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
          label: Text(_busy ? '正在连接' : '连接'),
        ),
        if (st['connected'] == true) ...[
          const SizedBox(width: Space.sm),
          TextButton(onPressed: _busy ? null : () => setState(() => _editing = false), child: const Text('取消')),
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
        decoration: const InputDecoration(labelText: '复旦 UIS 学号', border: OutlineInputBorder()),
      ),
      const SizedBox(height: Space.md),
      TextField(
        controller: _pass,
        obscureText: true,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'UIS 密码', border: OutlineInputBorder(), helperText: '用本机密钥加密保存，只用来登录复旦 UIS'),
      ),
    ];
    final lookWarning = sso == 'look' && !_lookSignedIn ? [const _Banner(icon: Icons.login_rounded, text: '需要先在 Look Studio 登录同济统一身份认证。', error: true), const SizedBox(height: Space.md)] : <Widget>[];
    if (mode == 'sso') {
      return [
        ...lookWarning,
        _Explain(
          icon: Icons.autorenew_rounded,
          title: sso == 'look' ? '沿用 Look Studio 的同济登录' : '用复旦 UIS 登录 Canvas',
          body: sso == 'look'
              ? '不在 Canvas 账户里创建任何东西。Canvas 的登录过期时，会用和 Look 相同的方式自动续上：先静默单点登录，必要时用你记住的密码。'
              : '不在 Canvas 账户里创建任何东西。Canvas 的登录过期时，会用保存的 UIS 账号自动重新登录。',
        ),
        if (sso == 'uis') ...[const SizedBox(height: Space.lg), ...uisFields],
      ];
    }
    final base = _baseUrl;
    return [
      if (_hasSso) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('由 Look Studio 创建并自动续期'),
          subtitle: const Text('通过统一身份认证在你的 Canvas 账户里新建一个 90 天的访问令牌，到期前 14 天自动换新，断开时撤销'),
          value: _create,
          onChanged: (v) => setState(() => _create = v),
        ),
        const SizedBox(height: Space.sm),
      ],
      if (_hasSso && _create) ...[
        ...lookWarning,
        if (sso == 'uis') ...uisFields,
      ] else ...[
        Text('手动获取令牌', style: tt.titleSmall),
        const SizedBox(height: Space.sm),
        for (final (i, s) in [
          '打开 Canvas，进入「账户 → 设置」',
          '在「已批准的集成」下点「新建访问许可证」，用途填 Look Studio；过期日期可以留空',
          '复制生成的令牌（只显示一次），粘贴到下面',
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
            label: const Text('打开 Canvas 设置页'),
          ),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _token,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: '访问令牌',
            border: OutlineInputBorder(),
            helperText: '加密保存在本机，界面上只显示末 4 位。令牌到期或被撤销时会提醒你重新粘贴',
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
        ? '统一身份认证会话 · 过期自动续上'
        : [
            '访问令牌 ····${st['token_last4'] ?? ''}',
            if (st['token_auto'] == true) '自动续期',
            if (exp != null) '${st['token_auto'] == true ? '当前令牌' : ''}到期 ${fmtIsoDay(exp)}',
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
                  Text('${st['user'] ?? ''}'.isEmpty ? '已连接' : '已连接为 ${st['user']}', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
            const SizedBox(height: Space.lg),
            _Line(icon: st['mode'] == 'sso' ? Icons.verified_user_outlined : Icons.key_outlined, text: auth),
            _Line(
              icon: Icons.schedule_rounded,
              text: syncing
                  ? '正在同步…'
                  : [synced > 0 ? '上次同步 ${fmtRelative(DateTime.fromMillisecondsSinceEpoch(synced))}' : '还没有同步', '每 15 分钟自动同步'].join(' · '),
            ),
            _Line(icon: Icons.assignment_outlined, text: '${courses.length} 门课程 · $open 项作业待交'),
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
              FilledButton.tonalIcon(onPressed: syncing ? null : _sync, icon: const Icon(Icons.sync_rounded), label: const Text('立即同步')),
              OutlinedButton.icon(onPressed: () => setState(() => _editing = true), icon: const Icon(Icons.manage_accounts_outlined), label: const Text('更改登录方式')),
              TextButton.icon(onPressed: () => _disconnect(st), icon: const Icon(Icons.link_off_rounded), label: const Text('断开')),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: Space.xl),
      Text('课程关联', style: tt.titleMedium),
      const SizedBox(height: Space.xs),
      Text('作业按关联的 Look 课程归类，课件会下载到那门课的文件夹。同名课程会自动关联。', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Space.md),
      if (courses.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xl),
          child: Text(syncing ? '正在读取课程…' : '这个学期在 Canvas 上没有课程', textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
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
    final chips = [if (school['look'] == true) 'Look 录播', 'Canvas'];
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
                  school['id'] == 'other' ? '任意 Canvas 站点，用访问令牌' : chips.join(' · '),
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
    final label = look.isEmpty ? (manual ? '不关联' : '自动：未找到同名课程') : (manual ? title : '自动：$title');
    final open = (course['open'] as num?)?.toInt() ?? 0;
    final term = '${_map(course['term'])['name'] ?? ''}';
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.sm, Space.xs),
      leading: CircleAvatar(
        backgroundColor: cs.tertiaryContainer,
        child: Text('${course['name']}'.characters.firstOrNull ?? '?', style: TextStyle(color: cs.onTertiaryContainer)),
      ),
      title: Text('${course['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([if (term.isNotEmpty) term, open > 0 ? '$open 项作业待交' : '没有待交作业'].join(' · ')),
      onTap: () => showCanvasCourseSheet(context, id, '${course['name']}'),
      trailing: MenuAnchor(
        builder: (context, ctl, _) => ActionChip(
          avatar: Icon(look.isEmpty ? Icons.link_off_rounded : Icons.link_rounded, size: 18),
          label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(label, overflow: TextOverflow.ellipsis)),
          tooltip: '关联到 Look 课程',
          onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
        ),
        menuChildren: [
          MenuItemButton(leadingIcon: const Icon(Icons.auto_awesome_outlined), onPressed: () => onLink(id, auto: true), child: const Text('自动匹配同名课程')),
          MenuItemButton(leadingIcon: const Icon(Icons.link_off_rounded), onPressed: () => onLink(id), child: const Text('不关联')),
          if (looks.isNotEmpty) const Divider(),
          for (final l in looks)
            MenuItemButton(
              leadingIcon: Icon(l.id == look && manual ? Icons.check_rounded : Icons.class_outlined),
              onPressed: () => onLink(id, course: l.id),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: Text(l.title, overflow: TextOverflow.ellipsis)),
            ),
        ],
      ),
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
      title: Text(connected ? '${sc['id'] == 'other' ? '' : sc['name']} Canvas 已连接' : '连接 Canvas'),
      subtitle: Text(
        !connected
            ? '同济、复旦或其他学校的 Canvas：作业进日程，课件下载到课程文件夹'
            : err.isNotEmpty
                ? err
                : '${_maps(st['courses']).length} 门课程 · $open 项作业待交',
        style: err.isNotEmpty ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CanvasPage())).then((_) => _load()),
    );
  }
}
