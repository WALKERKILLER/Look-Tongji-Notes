import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../theme/tokens.dart';

/// What the assistant needs to run (GET /api/agent/runtime), see
/// docs/specs/0008-assistant-runtime-setup.md.
class RuntimeStatus {
  RuntimeStatus(this.j);
  final Map<String, dynamic> j;
  Map get _node => (j['node'] as Map?) ?? const {};
  Map get _deps => (j['deps'] as Map?) ?? const {};
  Map get _install => (j['install'] as Map?) ?? const {};
  bool get nodeOk => _node['ok'] == true;
  String get nodeVersion => '${_node['version'] ?? ''}';
  String get nodeSource => '${_node['source'] ?? 'none'}';
  bool get depsOk => _deps['ok'] == true;
  String get state => '${_install['state'] ?? 'idle'}';
  String get step => '${_install['step'] ?? ''}';
  double get progress => ((_install['progress'] as num?) ?? 0).toDouble().clamp(0, 1);
  String get error => '${_install['error'] ?? ''}';
  List<String> get log => ((_install['log'] as List?) ?? const []).map((e) => '$e').toList();
  bool get ready => nodeOk && depsOk;
  bool get running => state == 'running';

  RuntimeStatus withInstall(Map<String, dynamic> install) => RuntimeStatus({...j, 'install': install});
}

/// Offers the one-click install of Node.js and the agent's dependencies and
/// follows its progress through `runtime` events.
class RuntimeSetupCard extends StatefulWidget {
  const RuntimeSetupCard({super.key, this.api, this.events});

  /// Defaults to the app's lookd client and event stream.
  final ApiCall? api;
  final Stream<Map<String, dynamic>>? events;

  @override
  State<RuntimeSetupCard> createState() => _RuntimeSetupCardState();
}

class _RuntimeSetupCardState extends State<RuntimeSetupCard> {
  RuntimeStatus? _st;
  Object? _error;
  String _mirror = 'npmmirror';
  StreamSubscription? _sub;
  late final ApiCall _api = widget.api ?? context.read<AppState>().api.call;

  @override
  void initState() {
    super.initState();
    _sub = (widget.events ?? context.read<AppState>().events).listen((e) {
      if (!mounted) return;
      if (e['type'] == 'runtime' && e['data'] is Map && _st != null) {
        final install = (e['data'] as Map).cast<String, dynamic>();
        setState(() => _st = _st!.withInstall(install));
        if (install['state'] == 'done' || install['state'] == 'failed') _load();
      } else if (e['type'] == 'agent') {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = (await _api('GET', '/api/agent/runtime') as Map).cast<String, dynamic>();
      if (mounted) {
        setState(() {
          _st = RuntimeStatus(r);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _install() async {
    try {
      final r = (await _api('POST', '/api/agent/runtime/install', {'mirror': _mirror}) as Map).cast<String, dynamic>();
      if (mounted) setState(() => _st = RuntimeStatus(r));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final st = _st;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Card.filled(
        color: cs.surfaceContainerHigh,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(Corners.lg)),
                child: Icon(Icons.download_for_offline_outlined, color: cs.onTertiaryContainer),
              ),
              const SizedBox(width: Space.lg),
              Expanded(child: Text(st?.ready == true ? '运行环境已就绪' : '安装助手运行环境', style: tt.titleLarge)),
            ]),
            const SizedBox(height: Space.md),
            Text(
              '助手运行在 Node.js 上，并使用 Pi SDK。缺少的部分会安装到 Look Studio 的数据目录，不改动系统；安装包会按官方发布的 SHA-256 校验。',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: Space.lg),
            if (st == null && _error == null)
              const LinearProgressIndicator()
            else if (st == null)
              Text('无法读取运行环境：$_error', style: tt.bodyMedium?.copyWith(color: cs.error))
            else ...[
              _StepRow(
                label: 'Node.js',
                detail: st.nodeOk ? '${st.nodeVersion} · ${st.nodeSource == 'managed' ? '应用内安装' : '系统'}' : '未找到可用的 Node.js 22+',
                state: st.nodeOk ? _Step.done : (st.running && st.step.contains('Node') ? _Step.active : _Step.todo),
              ),
              _StepRow(
                label: '助手依赖（Pi SDK）',
                detail: st.depsOk ? '已安装' : '未安装',
                state: st.depsOk ? _Step.done : (st.running && st.step == '安装依赖' ? _Step.active : _Step.todo),
              ),
              _StepRow(
                label: '启动助手',
                detail: st.state == 'done' ? '正在启动…' : '安装完成后自动启动',
                state: st.state == 'done' ? _Step.done : _Step.todo,
              ),
              const SizedBox(height: Space.md),
              AnimatedSize(
                duration: Motion.medium2,
                curve: Motion.emphasized,
                child: st.running
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(st.step, style: tt.labelLarge),
                        const SizedBox(height: Space.sm),
                        LinearProgressIndicator(value: st.progress > 0 && st.progress < 1 ? st.progress : null, borderRadius: BorderRadius.circular(Corners.xs)),
                      ])
                    : st.state == 'failed'
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(Space.md),
                            decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(Corners.md)),
                            child: Text(st.error, style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer)),
                          )
                        : const SizedBox(width: double.infinity),
              ),
              if (!st.running && !st.ready) ...[
                const SizedBox(height: Space.lg),
                Text('下载源', style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: Space.sm),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'npmmirror', label: Text('国内镜像'), icon: Icon(Icons.bolt_rounded)),
                    ButtonSegment(value: 'official', label: Text('官方源'), icon: Icon(Icons.public_rounded)),
                  ],
                  selected: {_mirror},
                  onSelectionChanged: (v) => setState(() => _mirror = v.first),
                ),
              ],
              if (st.log.isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('安装日志', style: tt.labelLarge),
                    children: [
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 200),
                        padding: const EdgeInsets.all(Space.md),
                        decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(Corners.sm)),
                        child: SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(st.log.join('\n'), style: tt.bodySmall?.copyWith(fontFamily: 'monospace')),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Space.lg),
              Align(
                alignment: Alignment.centerRight,
                child: st.ready
                    ? OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('重新检查'))
                    : FilledButton.icon(
                        onPressed: st.running ? null : _install,
                        icon: Icon(st.state == 'failed' ? Icons.refresh_rounded : Icons.download_rounded),
                        label: Text(st.running ? '正在安装' : st.state == 'failed' ? '重试' : '开始安装'),
                      ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

enum _Step { todo, active, done }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.detail, required this.state});
  final String label, detail;
  final _Step state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(children: [
        SizedBox(
          width: 24,
          height: 24,
          child: switch (state) {
            _Step.done => Icon(Icons.check_circle_rounded, color: cs.primary),
            _Step.active => const Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2.5)),
            _Step.todo => Icon(Icons.radio_button_unchecked_rounded, color: cs.outline),
          },
        ),
        const SizedBox(width: Space.md),
        Expanded(child: Text(label, style: tt.bodyLarge)),
        Flexible(child: Text(detail, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

/// Opens the setup card in a dialog (设置 → 助手 → 运行环境).
Future<void> showRuntimeSetup(BuildContext context) => showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Stack(children: [
          const RuntimeSetupCard(),
          Positioned(top: Space.sm, right: Space.sm, child: IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))),
        ]),
      ),
    );
