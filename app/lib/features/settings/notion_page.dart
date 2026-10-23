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

// Notion sync of the library: connect an internal integration, pick the
// page it lives under, sync. Contract: docs/specs/0013-notion-sync.md

const notionLogo = 'assets/brands/notion.svg';
const _integrationsUrl = 'https://www.notion.so/profile/integrations';

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

/// One line for the Notion status, also used by the settings tile.
String notionSummary(Map<String, dynamic> st) {
  if (st['connected'] != true) return '同步到你的 Notion 工作区';
  if (st['running'] == true) return '正在同步…';
  final parent = _map(st['parent']);
  if (parent.isEmpty) return '已连接 · 还没选同步位置';
  final err = '${_map(st['last'])['error'] ?? ''}';
  if (err.isNotEmpty) return err;
  return '${parent['title']} · ${st['pages'] ?? 0} 个页面${st['auto'] == true ? ' · 自动' : ''}';
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
        title: const Text('断开 Notion？'),
        content: const Text('会删除本机保存的令牌和同步记录。已经同步到 Notion 的页面会留在那里；之后重新连接时会新建一份。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('断开')),
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
          title: const Text('换一个同步位置？'),
          content: const Text('之后会在新页面下重新创建课程库。原来同步过去的页面留在原处，不再更新。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('更换')),
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
        status: connected ? '已连接到 ${'${bot['workspace'] ?? ''}'.isEmpty ? '工作区' : bot['workspace']}' : '未连接',
        body: '把课程库同步到 Notion 的一个页面下：每门课、每节课一个页面，下面是笔记和转写稿。只写入 Look Studio 创建的页面；在 Notion 里改过的页面不会被覆盖。',
      ),
      if (connected) ..._connected(context, st) else ..._connectForm(context),
    ]);
  }

  // ---- not connected ----

  List<Widget> _connectForm(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return [
      SettingsGroup(title: '创建集成', children: [
        const SizedBox(height: Space.xs),
        const SettingsSteps([
          '在 Notion 的「集成」页新建一个 Internal 集成，名称填 Look Studio，选择要同步到的工作区',
          '在「功能」里保留读取、更新和插入内容，其余可以关闭',
          '复制「Internal Integration Secret」，粘贴到下面',
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openPlainLink(context, _integrationsUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('打开 Notion 集成页'),
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
            labelText: '集成密钥',
            hintText: 'ntn_…',
            border: const OutlineInputBorder(),
            errorText: _connectError,
            helperText: '用本机密钥加密保存，只用来访问你授权给集成的页面',
            suffixIcon: IconButton(
              tooltip: _obscure ? '显示' : '隐藏',
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
            label: Text(_busy ? '正在连接' : '连接'),
          ),
        ]),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, 0),
        child: Text('连接后，还要在 Notion 里把一个页面分享给这个集成，课程库会建在那个页面下面。',
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
      SettingsGroup(title: '同步位置', children: [
        if (parent.isEmpty) ...[
          const SizedBox(height: Space.xs),
          const SettingsSteps([
            '在 Notion 打开想放课程库的页面',
            '点右上角「···」→「连接」，选择你的集成',
            '回到这里选择这个页面',
          ]),
          const SizedBox(height: Space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(onPressed: _busy ? null : _pickParent, icon: const Icon(Icons.add_link_rounded), label: const Text('选择页面')),
          ),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _PageIcon(icon: '${parent['icon'] ?? ''}'),
            title: Text('${parent['title']}'),
            subtitle: const Text('课程库在这个页面下的「Look Studio 课程库」里'),
            trailing: TextButton(onPressed: _busy || st['running'] == true ? null : _pickParent, child: const Text('更换')),
          ),
          if (root.startsWith('https://'))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openPlainLink(context, root),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('在 Notion 中打开'),
              ),
            ),
        ],
      ]),
      if (parent.isNotEmpty) _syncGroup(context, st),
      SettingsGroup(title: '连接', children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.key_outlined),
          title: Text('${bot['name'] ?? '集成'}'.isEmpty ? '集成' : '${bot['name']}'),
          subtitle: Text('集成密钥 ••••${st['token_last4'] ?? ''}'),
          trailing: TextButton(
            onPressed: _busy ? null : _disconnect,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('断开'),
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, 0),
        child: Text('Notion 里的时间戳显示为文字，图片和课件不上传；需要跳回课堂时刻可以用 Obsidian 导出。',
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
    return SettingsGroup(title: '同步', children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('笔记变化后自动同步'),
        subtitle: const Text('保存或删除笔记约 1 分钟后，只同步改动的页面'),
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
                  Text(total > 0 ? '正在同步 $done / $total' : '正在检查', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
          title: '${conflicts.length} 个页面在 Notion 里改过，保留了你的版本',
          items: conflicts,
        ),
      if (!running && errors.isNotEmpty) _Issues(icon: Icons.error_outline_rounded, title: '${errors.length} 个页面没有同步成功', items: errors, error: true),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        FilledButton.icon(
          onPressed: running || _busy ? null : () => _do('POST', '/api/notion/sync', {'full': false}),
          icon: const Icon(Icons.sync_rounded),
          label: Text(at == 0 ? '开始同步' : '立即同步'),
        ),
        Tooltip(
          message: '逐页确认还在，补建在 Notion 里删掉的页面；页面多时较慢',
          child: OutlinedButton(
            onPressed: running || _busy || at == 0 ? null : () => _do('POST', '/api/notion/sync', {'full': true}),
            child: const Text('完整检查'),
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
      if (n('created') > 0) '新建 ${n('created')}',
      if (n('updated') > 0) '更新 ${n('updated')}',
      if (n('trashed') > 0) '移到废纸篓 ${n('trashed')}',
      '未变 ${n('unchanged')}',
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(error.isEmpty ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 20, color: error.isEmpty ? cs.primary : cs.error),
      const SizedBox(width: Space.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('上次同步 ${fmtRelative(DateTime.fromMillisecondsSinceEpoch(at))}', style: tt.bodyMedium),
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
            if (items.length > 50) Text('还有 ${items.length - 50} 项', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
          child: Text('选择同步位置', style: tt.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
          child: Text('这里只列出分享给集成的页面。也可以粘贴页面链接。', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: SearchBar(
            controller: _q,
            hintText: '搜索页面或粘贴链接',
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
                          title: const Text('使用这个链接'),
                          subtitle: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(context, q),
                        ),
                      for (final p in pages)
                        ListTile(
                          shape: const StadiumBorder(),
                          leading: _PageIcon(icon: '${p['icon'] ?? ''}'),
                          title: Text('${p['title']}'.isEmpty ? '无标题' : '${p['title']}'),
                          onTap: () => Navigator.pop(context, '${p['id']}'),
                        ),
                      if (pages.isEmpty && !_link.hasMatch(q))
                        Padding(
                          padding: const EdgeInsets.all(Space.xl),
                          child: Column(children: [
                            Text(q.isEmpty ? '集成还没有可用的页面' : '没有找到「$q」', style: tt.titleSmall),
                            const SizedBox(height: Space.sm),
                            Text('在 Notion 打开目标页面，点右上角「···」→「连接」，选择你的集成，然后刷新。',
                                textAlign: TextAlign.center, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                            const SizedBox(height: Space.md),
                            TextButton.icon(onPressed: _search, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('刷新')),
                          ]),
                        ),
                    ]),
        ),
      ]),
    );
  }
}
