import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import 'settings_common.dart';

// Sync between devices through a WebDAV folder.
// Contract: docs/specs/0014-data-sync-and-backup.md

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

class _Preset {
  const _Preset(this.name, this.url, this.hint, {this.userLabel = '账号', this.passLabel = '应用密码'});
  final String name, url, hint, userLabel, passLabel;
}

const _presets = [
  _Preset('坚果云', 'https://dav.jianguoyun.com/dav/', '账号是坚果云登录邮箱；在网页版「账户信息 → 安全选项 → 第三方应用管理」添加应用，得到应用密码',
      userLabel: '坚果云账号（邮箱）'),
  _Preset('Nextcloud', 'https://', '地址形如 https://域名/remote.php/dav/files/用户名/；在「个人设置 → 安全」创建应用密码'),
  _Preset('AList', 'http://', '地址形如 http://主机:5244/dav/，账号和密码用 AList 的用户', passLabel: '密码'),
  _Preset('其他', 'https://', '填写服务商提供的 WebDAV 地址、账号和密码', passLabel: '密码'),
];

/// One line for the sync status, also used by the settings tile.
String webdavSummary(Map<String, dynamic> st) {
  if (st['configured'] != true) return '用坚果云、Nextcloud 等网盘在设备间同步';
  if (st['running'] == true) return '正在同步…';
  final last = _map(st['last']);
  final err = '${last['error'] ?? ''}';
  if (err.isNotEmpty) return err;
  final host = Uri.tryParse('${st['url'] ?? ''}')?.host ?? '';
  final at = (last['at'] as num?)?.toInt() ?? 0;
  final when = at == 0 ? '还没同步过' : '${fmtRelative(DateTime.fromMillisecondsSinceEpoch(at))}同步';
  return '$host · $when${st['auto'] == true ? ' · 自动' : ''}';
}

class WebDavPage extends StatefulWidget {
  const WebDavPage({super.key, this.api, this.events});

  /// For tests; default to the app's daemon connection.
  final ApiCall? api;
  final Stream<Map<String, dynamic>>? events;

  @override
  State<WebDavPage> createState() => _WebDavPageState();
}

class _WebDavPageState extends State<WebDavPage> {
  Map<String, dynamic>? _st;
  Object? _error;
  String? _formError;
  bool _busy = false, _obscure = true, _editing = false, _auto = true, _media = false;
  int _preset = 0;
  final _url = TextEditingController(text: _presets.first.url);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _folder = TextEditingController(text: 'LookStudio');
  StreamSubscription? _sub;

  ApiCall get _call => widget.api ?? context.read<AppState>().api.call;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = (widget.events ?? context.read<AppState>().events).listen((e) {
      if (!mounted) return;
      switch (e['type']) {
        case 'sync_progress':
          setState(() => _st = {...?_st, 'running': true, 'progress': e['data']});
        case 'sync_done' || 'sync_changed':
          _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final c in [_url, _user, _pass, _folder]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = _map(await _call('GET', '/api/sync'));
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

  void _edit() {
    final st = _st ?? {};
    final url = '${st['url'] ?? ''}';
    setState(() {
      _editing = true;
      _formError = null;
      _url.text = url;
      _user.text = '${st['user'] ?? ''}';
      _pass.clear();
      _folder.text = '${st['folder'] ?? 'LookStudio'}';
      _auto = st['auto'] == true;
      _media = st['media'] == true;
      final i = _presets.indexWhere((p) => p.url.length > 8 && url.startsWith(p.url));
      _preset = i < 0 ? _presets.length - 1 : i;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _formError = null;
    });
    final keepPass = _st?['configured'] == true && _st?['has_password'] == true && _pass.text.isEmpty;
    try {
      final st = _map(await _call('PUT', '/api/sync', {
        'url': _url.text.trim(),
        'user': _user.text.trim(),
        if (!keepPass) 'password': _pass.text,
        'folder': _folder.text.trim(),
        'auto': _auto,
        'media': _media,
      }));
      _pass.clear();
      if (!mounted) return;
      final first = _st?['configured'] != true;
      setState(() {
        _st = st;
        _editing = false;
      });
      if (first) unawaited(_do('POST', '/api/sync/run'));
    } catch (e) {
      if (mounted) setState(() => _formError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('停止同步？'),
        content: const Text('会删除本机保存的 WebDAV 账号和同步记录。网盘和本机上的文件都会保留；之后重新设置时会按文件内容重新比对。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('停止同步')),
        ],
      ),
    );
    if (ok == true) await _do('DELETE', '/api/sync');
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    if (st == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('WebDAV 同步')),
        body: _error != null ? ErrorState(error: _error!, onRetry: _load) : const CenteredLoader(),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final on = st['configured'] == true;
    final host = Uri.tryParse('${st['url'] ?? ''}')?.host ?? '';
    return SettingsSubpage(title: 'WebDAV 同步', children: [
      IntegrationHeader(
        mark: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(Corners.lg)),
          child: Icon(Icons.cloud_sync_rounded, size: 30, color: cs.onPrimaryContainer),
        ),
        title: 'WebDAV 同步',
        on: on,
        status: on ? '已连接 $host' : '未设置',
        body: '在电脑、手机之间同步课程库和助手对话：笔记、转写稿、PPT 截图、题目与学习记录、播放进度和书签。每台设备只上传改动过的文件；两边都改过的文件保留较新的一份，另一份放进冲突文件夹。',
      ),
      if (!on || _editing) _form(context, on) else ..._connected(context, st),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.lg, Space.xs, 0),
        child: Text('登录状态、模型密钥和本机设置不会上传，每台设备分别登录。同步目录里的文件按原样保存，不做加密，请使用可信的网盘。',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ),
    ]);
  }

  Widget _form(BuildContext context, bool on) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final preset = _presets[_preset];
    final hasPass = _st?['has_password'] == true;
    final ready = _url.text.trim().length > 8 && _user.text.trim().isNotEmpty && (_pass.text.isNotEmpty || (on && hasPass));
    return SettingsGroup(title: on ? '修改账号' : '连接网盘', children: [
      const SizedBox(height: Space.xs),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        for (final (i, p) in _presets.indexed)
          ChoiceChip(
            label: Text(p.name),
            selected: _preset == i,
            onSelected: _busy
                ? null
                : (_) => setState(() {
                      _preset = i;
                      _url.text = p.url;
                      _formError = null;
                    }),
          ),
      ]),
      const SizedBox(height: Space.md),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: Space.sm),
        Expanded(child: Text(preset.hint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
      ]),
      const SizedBox(height: Space.lg),
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        autocorrect: false,
        onChanged: (_) => setState(() => _formError = null),
        decoration: const InputDecoration(labelText: '服务器地址', border: OutlineInputBorder()),
      ),
      const SizedBox(height: Space.md),
      TextField(
        controller: _user,
        autocorrect: false,
        onChanged: (_) => setState(() => _formError = null),
        decoration: InputDecoration(labelText: preset.userLabel, border: const OutlineInputBorder()),
      ),
      const SizedBox(height: Space.md),
      TextField(
        controller: _pass,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() => _formError = null),
        decoration: InputDecoration(
          labelText: preset.passLabel,
          border: const OutlineInputBorder(),
          helperText: on && hasPass ? '留空则沿用已保存的密码' : '用本机密钥加密保存',
          suffixIcon: IconButton(
            tooltip: _obscure ? '显示' : '隐藏',
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          ),
        ),
      ),
      const SizedBox(height: Space.md),
      TextField(
        controller: _folder,
        autocorrect: false,
        decoration: const InputDecoration(labelText: '同步目录', helperText: '在网盘里新建，所有设备填同一个', border: OutlineInputBorder()),
      ),
      const SizedBox(height: Space.sm),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('自动同步'),
        subtitle: const Text('打开应用时、每 30 分钟，以及笔记改动约 2 分钟后'),
        value: _auto,
        onChanged: _busy ? null : (v) => setState(() => _auto = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('同步视频与录音'),
        subtitle: const Text('文件很大，会占用较多网盘空间和流量；不同步时可以在其他设备上重新下载'),
        value: _media,
        onChanged: _busy ? null : (v) => setState(() => _media = v),
      ),
      if (_formError != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Text(_formError!, style: tt.bodyMedium?.copyWith(color: cs.error)),
        ),
      const SizedBox(height: Space.lg),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        FilledButton.icon(
          onPressed: _busy || !ready ? null : _save,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.cloud_done_outlined),
          label: Text(_busy ? '正在连接' : (on ? '保存' : '连接并同步')),
        ),
        if (on) TextButton(onPressed: _busy ? null : () => setState(() => _editing = false), child: const Text('取消')),
      ]),
    ]);
  }

  List<Widget> _connected(BuildContext context, Map<String, dynamic> st) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final running = st['running'] == true;
    final prog = _map(st['progress']);
    final done = (prog['done'] as num?)?.toInt() ?? 0, total = (prog['total'] as num?)?.toInt() ?? 0;
    final last = _map(st['last']);
    final errors = jsonList(last['errors']).map((e) => '$e').toList();
    final at = (last['at'] as num?)?.toInt() ?? 0;
    final conflictDir = '${last['conflict_dir'] ?? ''}';
    return [
      SettingsGroup(title: '同步', children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('自动同步'),
          subtitle: const Text('打开应用时、每 30 分钟，以及笔记改动约 2 分钟后'),
          value: st['auto'] == true,
          onChanged: _busy ? null : (v) => _do('POST', '/api/sync/auto', {'auto': v}),
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
                    Text(
                      [
                        '${prog['step'] ?? '正在同步'}',
                        if (total > 0) '$done / $total',
                        if ((prog['bytes'] as num? ?? 0) > 0) fmtBytes(prog['bytes'] as num),
                      ].join(' · '),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ]),
                )
              : at == 0
                  ? const SizedBox(width: double.infinity)
                  : Padding(padding: const EdgeInsets.only(bottom: Space.lg), child: _LastSync(last: last)),
        ),
        if (!running && conflictDir.isNotEmpty && (last['conflicts'] as num? ?? 0) > 0)
          _Notice(
            icon: Icons.difference_outlined,
            text: '${last['conflicts']} 个文件在两台设备上都改过，保留了较新的版本，另一份在冲突文件夹里',
            action: '查看',
            onAction: () => revealPath(conflictDir),
          ),
        if (!running && errors.isNotEmpty) _Notice(icon: Icons.error_outline_rounded, text: '${errors.length} 个文件没有同步成功：${errors.first}', error: true),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          FilledButton.icon(
            onPressed: running || _busy ? null : () => _do('POST', '/api/sync/run'),
            icon: const Icon(Icons.sync_rounded),
            label: Text(at == 0 ? '开始同步' : '立即同步'),
          ),
        ]),
      ]),
      SettingsGroup(title: '账号', children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: Text('${st['user'] ?? ''}'),
          subtitle: Text('${st['url'] ?? ''}${st['folder'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.movie_outlined),
          title: const Text('视频与录音'),
          subtitle: Text(st['media'] == true ? '一起同步' : '不同步，在其他设备上重新下载'),
        ),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          OutlinedButton(onPressed: _busy || running ? null : _edit, child: const Text('修改')),
          TextButton(
            onPressed: _busy || running ? null : _disconnect,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('停止同步'),
          ),
        ]),
      ]),
    ];
  }
}

class _LastSync extends StatelessWidget {
  const _LastSync({required this.last});
  final Map<String, dynamic> last;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    int n(String k) => (last[k] as num?)?.toInt() ?? 0;
    final error = '${last['error'] ?? ''}';
    final at = DateTime.fromMillisecondsSinceEpoch(n('at'));
    final counts = [
      if (n('uploaded') > 0) '上传 ${n('uploaded')}',
      if (n('downloaded') > 0) '下载 ${n('downloaded')}',
      if (n('deleted') > 0) '删除 ${n('deleted')}',
      if (n('bytes') > 0) fmtBytes(n('bytes')),
    ];
    final partial = last['partial'] == true;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(error.isEmpty ? Icons.check_circle_outline_rounded : (partial ? Icons.pause_circle_outline_rounded : Icons.error_outline_rounded),
          size: 20, color: error.isEmpty ? cs.primary : (partial ? cs.tertiary : cs.error)),
      const SizedBox(width: Space.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('上次同步 ${fmtRelative(at)}', style: tt.bodyMedium),
          Text(
            error.isNotEmpty ? error : (counts.isEmpty ? '两边已经一致' : counts.join(' · ')),
            style: tt.bodySmall?.copyWith(color: error.isEmpty ? cs.onSurfaceVariant : (partial ? cs.tertiary : cs.error)),
          ),
        ]),
      ),
    ]);
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action, this.onAction, this.error = false});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Corners.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
          child: Row(children: [
            Icon(icon, size: 20, color: error ? cs.error : cs.tertiary),
            const SizedBox(width: Space.md),
            Expanded(child: Text(text, style: tt.bodyMedium)),
            if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
          ]),
        ),
      ),
    );
  }
}
