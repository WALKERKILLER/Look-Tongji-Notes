import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/look_markdown.dart' show openPlainLink;
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import 'asr_bench.dart';

typedef _J = Map<String, dynamic>;

_J _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<_J> _maps(Object? v) => jsonList(v).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

/// Minutes to transcribe a 90-minute lecture at the measured speed.
double lectureMinutes(Map<String, dynamic> model) => ((_map(model['measured'])['rtf'] as num?) ?? 0).toDouble() * 90;

String _gb(num mb) => mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '${mb.round()} MB';

const _tagLabels = {'recommended': '推荐', 'fast': '最快', 'accurate': '最准'};

/// The benchmark metrics shown on the board, in board order.
List<BenchMetric> benchMetrics(Map<String, dynamic> reference) => [
  BenchMetric(
    label: '错字率',
    hint: '越短越准',
    format: (v) => '${v.toStringAsFixed(1)}%',
    source: 'WenetSpeech 会议测试集（最接近课堂录音）的字错误率，取自各模型的论文；来源不同，相差 1% 以内可视为持平',
  ),
  BenchMetric(
    label: '转写用时',
    hint: '一节 90 分钟的课',
    format: (v) => '${v < 10 ? v.toStringAsFixed(1) : v.round()} 分钟',
    source: '在 ${reference['machine'] ?? '参考机器'} 上实测（${reference['clip'] ?? ''}，含加载模型），你的电脑会有不同',
  ),
  BenchMetric(label: '内存', hint: '识别时的峰值', format: (v) => '${v.toStringAsFixed(1)} GB', source: '同一次实测的进程峰值内存'),
];

List<BenchRow> benchRows(List<Map<String, dynamic>> models) => [
  for (final m in models)
    BenchRow(
      id: '${m['id']}',
      name: '${m['name']}',
      tag: jsonList(m['tags']).contains('recommended') ? '推荐' : null,
      values: [
        (_map(m['bench'])['cer'] as num?)?.toDouble(),
        lectureMinutes(m) > 0 ? lectureMinutes(m) : null,
        ((_map(m['measured'])['peak_mb'] as num?) ?? 0) > 0 ? (_map(m['measured'])['peak_mb'] as num) / 1024 : null,
      ],
    ),
];

/// On-device recognition: pick a model with the benchmark board, download
/// it from a chosen source and make it the "local" transcription channel.
class LocalAsrPage extends StatefulWidget {
  const LocalAsrPage({super.key, this.api, this.events});

  /// For tests; defaults to the app's daemon connection.
  final ApiCall? api;
  final Stream<Map<String, dynamic>>? events;

  @override
  State<LocalAsrPage> createState() => _LocalAsrPageState();
}

class _LocalAsrPageState extends State<LocalAsrPage> {
  _J? _st;
  Object? _error;
  String? _focus;
  StreamSubscription? _sub;
  final _custom = TextEditingController();
  final _proxy = TextEditingController();
  final _keys = <String, GlobalKey>{};

  ApiCall get _call => widget.api ?? context.read<AppState>().api.call;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = (widget.events ?? context.read<AppState>().events).listen((e) {
      if (e['type'] == 'asr_local') {
        final p = _map(e['data']);
        setState(() => _map(_st?['status'])['install'] = p);
        if (p['state'] != 'running') _load();
      } else if (e['type'] == 'settings_changed') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _custom.dispose();
    _proxy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = _map(await _call('GET', '/api/asr/local'));
      if (!mounted) return;
      setState(() {
        _st = r;
        _error = null;
        _focus ??= '${r['active'] ?? ''}'.isNotEmpty ? '${r['active']}' : _recommended(r);
      });
      if (_custom.text.isEmpty) _custom.text = '${r['custom_url'] ?? ''}';
      if (_proxy.text.isEmpty) _proxy.text = '${r['github_proxy'] ?? ''}';
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String? _recommended(_J r) {
    for (final m in _maps(_map(r['status'])['models'])) {
      if (jsonList(m['tags']).contains('recommended')) return '${m['id']}';
    }
    return null;
  }

  Future<void> _set(String key, Object? value) async {
    try {
      await _call('PUT', '/api/settings', {key: value});
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '保存失败：$e');
    }
  }

  Future<void> _install(String id) async {
    try {
      await _call('POST', '/api/asr/local/install', {'model': id});
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _remove(_J m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text('删除 ${m['name']}？'),
        content: Text('会释放 ${fmtBytes(m['size'] as num)} 空间。已经转写好的文字稿不受影响，之后可以重新下载。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _call('DELETE', '/api/asr/local/models/${m['id']}');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  void _select(String id) {
    setState(() => _focus = id);
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: Motion.medium2, curve: Motion.emphasized, alignment: 0.3);
  }

  /// Picks a new folder for the engine and models; asks whether the
  /// downloaded ones should move along. [dir] skips the picker (恢复默认).
  Future<void> _relocate(_J loc, {String? dir}) async {
    final current = '${loc['dir'] ?? ''}';
    dir ??= await pickDirectory(context, initial: current, title: '模型存储位置');
    if (dir == null || dir == current || !mounted) return;
    var move = false;
    final used = (loc['used'] as num?) ?? 0;
    if (used > 0) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (c) => _MoveDialog(to: dir!, used: used),
      );
      if (choice == null) return;
      move = choice;
    }
    try {
      final st = _map(await _call('PUT', '/api/asr/local/location', {'dir': dir, 'move': move}));
      if (mounted) setState(() => _st = {...?_st, 'status': st});
      if (!move && mounted) showSnack(context, '之后下载的模型会保存到新位置');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return Scaffold(
      appBar: AppBar(title: const Text('本地识别模型')),
      body: st == null ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const CenteredLoader()) : _body(context, st),
    );
  }

  Widget _body(BuildContext context, _J st) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final status = _map(st['status']);
    if (status['supported'] != true) {
      return EmptyState(icon: Icons.memory_rounded, title: '这台电脑暂不支持', body: '本地识别引擎没有提供 ${status['platform']} 的预编译版本，转写会继续使用免费云端渠道。');
    }
    final models = _maps(status['models']);
    final install = _map(status['install']);
    final active = '${st['active'] ?? ''}';
    final reference = _map(status['reference']).map((k, v) => MapEntry(k, '$v'));
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.huge),
      children: [
        ContentWidth(
          max: 960,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Hero(active: models.where((m) => m['id'] == active).firstOrNull, install: install, models: models),
              const SizedBox(height: Space.xl),
              Text('怎么选', style: tt.titleMedium),
              const SizedBox(height: Space.xs),
              Text('三项都是越短越好。点一行可以在下面看到详情。没有特别需求就选带 ★ 的推荐模型。', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: Space.md),
              Card.outlined(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: AsrBenchBoard(
                    metrics: benchMetrics(reference),
                    rows: benchRows(models),
                    selected: _focus,
                    onSelect: _select,
                    animate: !MediaQuery.of(context).disableAnimations,
                  ),
                ),
              ),
              const SizedBox(height: Space.xl),
              Text('模型', style: tt.titleMedium),
              const SizedBox(height: Space.sm),
              for (final m in models)
                Padding(
                  key: _keys.putIfAbsent('${m['id']}', GlobalKey.new),
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _ModelCard(
                    m: m,
                    focused: _focus == m['id'],
                    active: active == m['id'],
                    install: install['model'] == m['id'] ? install : null,
                    busy: install['state'] == 'running',
                    onFocus: () => setState(() => _focus = '${m['id']}'),
                    onInstall: () => _install('${m['id']}'),
                    onCancel: () => _call('POST', '/api/asr/local/cancel'),
                    onUse: () => _set('asr.local.model', m['id']),
                    onStop: () => _set('asr.local.model', ''),
                    onRemove: () => _remove(m),
                  ),
                ),
              const SizedBox(height: Space.xl),
              Text('存储位置', style: tt.titleMedium),
              const SizedBox(height: Space.sm),
              _Storage(
                loc: _map(status['location']),
                install: install,
                onChange: () => _relocate(_map(status['location'])),
                onReset: () => _relocate(_map(status['location']), dir: '${_map(status['location'])['default']}'),
              ),
              const SizedBox(height: Space.xl),
              Text('下载来源', style: tt.titleMedium),
              const SizedBox(height: Space.xs),
              Text(
                '所有文件都会按目录里记录的 SHA-256 校验，来源被篡改或版本不一致时会直接报错，不会装上。中断后再次下载会从断点继续。',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Space.sm),
              _Sources(
                sources: _maps(status['sources']),
                source: '${st['source'] ?? 'hf-mirror'}',
                custom: _custom,
                proxy: _proxy,
                onSource: (v) => _set('asr.local.source', v),
                onCustom: (v) => _set('asr.local.custom_url', v.trim()),
                onProxy: (v) => _set('asr.local.github_proxy', v.trim()),
              ),
              const SizedBox(height: Space.xl),
              _Threads(
                value: (st['threads'] as num?)?.toInt() ?? 4,
                cpus: (status['cpus'] as num?)?.toInt() ?? 4,
                onChanged: (v) => _set('asr.local.threads', v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where the engine and models are kept, with the space they use and what
/// is left on that disk.
class _Storage extends StatelessWidget {
  const _Storage({required this.loc, required this.install, required this.onChange, required this.onReset});
  final _J loc, install;
  final VoidCallback onChange, onReset;

  /// Below this, a model download may not fit.
  static const _low = 2 << 30;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dir = '${loc['dir'] ?? ''}';
    final custom = loc['custom'] == true;
    final used = (loc['used'] as num?) ?? 0;
    final free = (loc['free'] as num?) ?? -1;
    final running = install['state'] == 'running';
    final moving = running && '${install['model'] ?? ''}'.isEmpty;
    final moveFailed = install['state'] == 'failed' && '${install['model'] ?? ''}'.isEmpty;
    final low = free >= 0 && free < _low;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: Corners.all(Corners.lg)),
              child: Icon(custom ? Icons.folder_special_outlined : Icons.folder_outlined, color: cs.onSecondaryContainer),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(custom ? '自定义位置' : '默认位置', style: tt.labelLarge?.copyWith(color: cs.primary)),
                const SizedBox(height: Space.xxs),
                Tooltip(
                  message: dir,
                  waitDuration: const Duration(milliseconds: 600),
                  child: Text(dir, style: tt.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  [
                    '已用 ${fmtBytes(used)}',
                    if (free >= 0) '磁盘剩余 ${fmtBytes(free)}',
                  ].join(' · '),
                  style: tt.bodySmall?.copyWith(color: low ? cs.error : cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ]),
            ),
          ]),
          if (low && !moving) ...[
            const SizedBox(height: Space.md),
            Text('这块磁盘剩余空间不多，模型可能下载不完。可以换到空间更大的磁盘。', style: tt.bodySmall?.copyWith(color: cs.error)),
          ],
          if (moving) ...[
            const SizedBox(height: Space.lg),
            _Progress(p: install),
          ],
          if (moveFailed) ...[
            const SizedBox(height: Space.md),
            Text('${install['error']}', style: tt.bodySmall?.copyWith(color: cs.error)),
          ],
          const SizedBox(height: Space.lg),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            // Android keeps models inside the app, where no other folder is
            // reachable.
            if (canOpenFolders) ...[
              FilledButton.tonalIcon(
                onPressed: running ? null : onChange,
                icon: const Icon(Icons.drive_file_move_outline, size: 18),
                label: const Text('更改位置'),
              ),
              TextButton.icon(
                onPressed: dir.isEmpty ? null : () => openPath(dir),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('在文件管理器中打开'),
              ),
            ],
            if (custom) TextButton(onPressed: running ? null : onReset, child: const Text('恢复默认')),
          ]),
          if (running && !moving) ...[
            const SizedBox(height: Space.xs),
            Text('下载完成后才能更改位置', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ]),
      ),
    );
  }
}

/// Asks whether downloaded models move to the new folder; pops true to
/// move, false to only switch, null to cancel.
class _MoveDialog extends StatelessWidget {
  const _MoveDialog({required this.to, required this.used});
  final String to;
  final num used;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      icon: const Icon(Icons.drive_file_move_outline),
      title: const Text('把已下载的模型一起移过去？'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: Corners.all(Corners.md)),
            child: Text(to, style: tt.bodyMedium),
          ),
          const SizedBox(height: Space.lg),
          Text('移动：${fmtBytes(used)} 的引擎和模型会搬到新位置，旧位置随后清空。跨磁盘时需要复制一会儿，期间不能转写。',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: Space.sm),
          Text('只更改位置：旧文件留在原处，之后下载到新位置；新位置里已有的模型会直接可用。',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('只更改位置')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('移动')),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.active, required this.install, required this.models});
  final _J? active;
  final _J install;
  final List<_J> models;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final running = install['state'] == 'running';
    final name = running ? models.where((m) => m['id'] == install['model']).firstOrNull : null;
    final moving = running && '${install['model'] ?? ''}'.isEmpty;
    final (icon, title, body) = moving
        ? (Icons.drive_file_move_outline, '正在移动模型', '移动完成前本地识别暂停，云端渠道照常转写。可以离开这个页面。')
        : active != null
        ? (Icons.offline_bolt_rounded, '正在使用 ${active!['name']}', '转写会交给本机模型，不受限流和额度影响；开着的云端渠道也会并行分担一部分。想让音频完全不离开电脑，在“设置 → 转写”里关掉云端渠道。')
        : running
        ? (Icons.downloading_rounded, '正在下载 ${name?['name'] ?? '模型'}', '下载完成后会自动启用。可以离开这个页面，进度会在后台继续。')
        : (Icons.computer_rounded, '在本机识别', '下载一个语音识别模型到这台电脑，转写不再受免费云端渠道的限流和额度影响，音频也不会离开电脑。');
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: active != null ? cs.primaryContainer : cs.surfaceContainerHigh,
        borderRadius: Corners.all(Corners.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: active != null ? cs.onPrimaryContainer : cs.primary),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.titleLarge?.copyWith(color: active != null ? cs.onPrimaryContainer : cs.onSurface)),
                const SizedBox(height: Space.xs),
                Text(
                  body,
                  style: tt.bodyMedium?.copyWith(color: active != null ? cs.onPrimaryContainer : cs.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});
  final String text;
  final bool strong;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(color: strong ? cs.primaryContainer : cs.secondaryContainer, borderRadius: Corners.all(Corners.full)),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: strong ? cs.onPrimaryContainer : cs.onSecondaryContainer),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.m,
    required this.focused,
    required this.active,
    required this.install,
    required this.busy,
    required this.onFocus,
    required this.onInstall,
    required this.onCancel,
    required this.onUse,
    required this.onStop,
    required this.onRemove,
  });
  final _J m;
  final bool focused, active, busy;
  final _J? install;
  final VoidCallback onFocus, onInstall, onCancel, onUse, onStop, onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final installed = m['installed'] == true;
    final bench = _map(m['bench']);
    final measured = _map(m['measured']);
    final size = (m['size'] as num?) ?? 0;
    final extra = (m['extra'] as num?) ?? 0;
    final mins = lectureMinutes(m);
    final running = install?['state'] == 'running';
    final failed = install?['state'] == 'failed';
    final facts = [
      '下载 ${fmtBytes(size)}',
      if ((measured['peak_mb'] as num? ?? 0) > 0) '内存约 ${_gb(measured['peak_mb'] as num)}',
      if (mins > 0) '90 分钟课约 ${mins < 10 ? mins.toStringAsFixed(1) : mins.round()} 分钟',
      '错字率 ${bench['cer']}%',
    ];
    return AnimatedContainer(
      duration: Motion.medium1,
      curve: Motion.standard,
      decoration: BoxDecoration(
        color: active ? cs.secondaryContainer : cs.surfaceContainerLow,
        borderRadius: Corners.all(Corners.lg),
        border: Border.all(color: focused ? cs.primary : Colors.transparent, width: 2),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: Corners.all(Corners.lg),
          onTap: onFocus,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${m['name']}', style: tt.titleMedium),
                    for (final t in jsonList(m['tags']))
                      if (_tagLabels[t] != null) _Tag(_tagLabels[t]!, strong: t == 'recommended'),
                    if (active) const _Tag('使用中', strong: true) else if (installed) const _Tag('已下载'),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${m['org']} · ${m['langs']} · ${m['punct'] == true ? '自带标点' : '自动补标点'}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: Space.sm),
                Text('${m['summary']}', style: tt.bodyMedium),
                const SizedBox(height: Space.xs),
                Text(facts.join(' · '), style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                AnimatedSize(
                  duration: Motion.medium2,
                  curve: Motion.emphasized,
                  alignment: Alignment.topCenter,
                  child: focused || running || failed
                      ? Padding(
                          padding: const EdgeInsets.only(top: Space.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if ('${bench['note'] ?? ''}'.isNotEmpty)
                                Text('${bench['note']}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                              Wrap(
                                spacing: Space.xs,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => openPlainLink(context, '${bench['source_url']}'),
                                    icon: const Icon(Icons.article_outlined, size: 18),
                                    label: Text('错字率来源：${bench['source']}'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => openPlainLink(context, '${m['license_url']}'),
                                    icon: const Icon(Icons.gavel_rounded, size: 18),
                                    label: Text('许可：${m['license']}'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => openPlainLink(context, '${m['upstream']}'),
                                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                    label: const Text('原始模型'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                if (running) ...[const SizedBox(height: Space.sm), _Progress(p: install!)],
                if (failed) ...[
                  const SizedBox(height: Space.sm),
                  Text('下载失败：${install!['error']}', style: tt.bodySmall?.copyWith(color: cs.error)),
                ],
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    const Spacer(),
                    if (running)
                      OutlinedButton(onPressed: onCancel, child: const Text('暂停'))
                    else if (!installed)
                      FilledButton.icon(
                        onPressed: busy ? null : onInstall,
                        icon: const Icon(Icons.download_rounded),
                        label: Text(
                          failed || install?['state'] == 'canceled' ? '继续下载' : '下载 ${fmtBytes(size + extra)}${extra > 0 ? '（含引擎等）' : ''}',
                        ),
                      )
                    else ...[
                      TextButton(onPressed: onRemove, child: const Text('删除')),
                      const SizedBox(width: Space.sm),
                      if (active)
                        OutlinedButton(onPressed: onStop, child: const Text('停用'))
                      else
                        FilledButton.tonal(onPressed: onUse, child: const Text('使用这个模型')),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.p});
  final _J p;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final done = (p['done'] as num?) ?? 0;
    final total = (p['total'] as num?) ?? 0;
    final speed = (p['speed'] as num?) ?? 0;
    final frac = total > 0 ? (done / total).clamp(0.0, 1.0) : null;
    final left = speed > 0 && total > done ? ((total - done) / speed).round() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: frac?.toDouble(), minHeight: 6, borderRadius: Corners.all(3)),
        const SizedBox(height: Space.xs),
        Text(
          [
            '${p['step'] ?? ''}',
            if (total > 0) '${fmtBytes(done)} / ${fmtBytes(total)}',
            if (speed > 0) fmtSpeed(speed),
            if (left != null) '还需 ${fmtDuration(left)}',
          ].where((s) => s.isNotEmpty).join(' · '),
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        if ('${p['note'] ?? ''}'.isNotEmpty) Text('${p['note']}', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

/// Download source choice, with a short guide per source.
class _Sources extends StatelessWidget {
  const _Sources({
    required this.sources,
    required this.source,
    required this.custom,
    required this.proxy,
    required this.onSource,
    required this.onCustom,
    required this.onProxy,
  });
  final List<_J> sources;
  final String source;
  final TextEditingController custom, proxy;
  final ValueChanged<String> onSource, onCustom, onProxy;

  static const _guides = {
    'hf-mirror': '无需任何配置。hf-mirror.com 是社区维护的 Hugging Face 镜像，国内大多数网络可以直连，目录里的全部模型都能从这里下载。',
    'modelscope': '无需账号或 Token，公开模型直接下载。魔搭上目前只有 Qwen3-ASR 0.6B 和语音检测模型有与原版逐字节相同的副本（社区用户上传），选它们时走魔搭；其余文件自动改用 HF-Mirror，下载时会提示。',
    'huggingface': '官方源，文件最全，但国内通常需要代理。Look Studio 的后台服务会使用系统的 HTTPS_PROXY 环境变量。',
    'custom': '适合学校、实验室或自建的 Hugging Face 兼容镜像。填写地址模板，{repo} 会换成模型仓库名，{file} 换成文件路径，例如 https://hf-mirror.com/{repo}/resolve/main/{file}。',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: Corners.all(Corners.lg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, Space.sm, Space.lg, Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<String>(
              groupValue: source,
              onChanged: (v) => v == null ? null : onSource(v),
              child: Column(
                children: [
                  for (final s in sources)
                    RadioListTile<String>(
                      value: '${s['id']}',
                      title: Text('${s['name']}'),
                      subtitle: Text(source == s['id'] ? (_guides[s['id']] ?? '${s['note']}') : '${s['note']}'),
                    ),
                ],
              ),
            ),
            if (source == 'custom')
              Padding(
                padding: const EdgeInsets.only(left: Space.lg, top: Space.sm),
                child: TextField(
                  controller: custom,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '地址模板',
                    hintText: 'https://example.org/{repo}/resolve/main/{file}',
                  ),
                  onSubmitted: onCustom,
                  onTapOutside: (_) => onCustom(custom.text),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: Space.lg, top: Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('识别引擎（GitHub）', style: tt.titleSmall),
                  const SizedBox(height: Space.xs),
                  Text(
                    '第一次下载时会从 GitHub Releases 取 sherpa-onnx 识别引擎（约 25 MB）。GitHub 很慢时，可以填一个 GitHub 下载加速服务的前缀，实际地址为“前缀 + 原始地址”，同样会校验 SHA-256。',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: Space.sm),
                  TextField(
                    controller: proxy,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '加速前缀（可选）', hintText: 'https://…/'),
                    onSubmitted: onProxy,
                    onTapOutside: (_) => onProxy(proxy.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Threads extends StatefulWidget {
  const _Threads({required this.value, required this.cpus, required this.onChanged});
  final int value, cpus;
  final ValueChanged<int> onChanged;
  @override
  State<_Threads> createState() => _ThreadsState();
}

class _ThreadsState extends State<_Threads> {
  int? _drag;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cpus = widget.cpus;
    final max = cpus.clamp(2, 8);
    final value = _drag ?? widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('识别线程', style: tt.titleMedium)),
            Text('$value 线程', style: tt.labelLarge?.copyWith(color: cs.primary)),
          ],
        ),
        Text('线程越多越快，但转写时电脑会更忙、更费电。这台电脑有 $cpus 个逻辑核心，默认用一半（最多 4 个）。', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        Slider(
          value: value.clamp(1, max).toDouble(),
          min: 1,
          max: max.toDouble(),
          divisions: max - 1,
          label: '$value',
          onChanged: (v) => setState(() => _drag = v.round()),
          onChangeEnd: (v) {
            widget.onChanged(v.round());
            setState(() => _drag = null);
          },
        ),
      ],
    );
  }
}
