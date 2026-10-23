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
import '../../l10n/l10n.dart';

typedef _J = Map<String, dynamic>;

_J _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<_J> _maps(Object? v) => jsonList(v).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

/// Minutes to transcribe a 90-minute lecture at the measured speed.
double lectureMinutes(Map<String, dynamic> model) => ((_map(model['measured'])['rtf'] as num?) ?? 0).toDouble() * 90;

String _gb(num mb) => mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '${mb.round()} MB';

final _tagLabels = {'recommended': l10n.asrModelRecommended, 'fast': l10n.asrModelFastest, 'accurate': l10n.asrModelAccurate};

/// The benchmark metrics shown on the board, in board order.
List<BenchMetric> benchMetrics(Map<String, dynamic> reference) => [
  BenchMetric(
    label: l10n.benchCer,
    hint: l10n.benchLowerIsBetter,
    format: (v) => '${v.toStringAsFixed(1)}%',
    source: l10n.benchCerSource,
  ),
  BenchMetric(
    label: l10n.benchTime,
    hint: l10n.benchTimeHint,
    format: (v) => l10n.benchMinutes(v < 10 ? v.toStringAsFixed(1) : v.round()),
    source: l10n.benchTimeSource(reference['machine'] ?? l10n.benchReferenceMachine, reference['clip'] ?? ''),
  ),
  BenchMetric(label: l10n.benchMemory, hint: l10n.benchMemoryHint, format: (v) => '${v.toStringAsFixed(1)} GB', source: l10n.benchMemorySource),
];

List<BenchRow> benchRows(List<Map<String, dynamic>> models) => [
  for (final m in models)
    BenchRow(
      id: '${m['id']}',
      name: '${m['name']}',
      tag: jsonList(m['tags']).contains('recommended') ? l10n.asrModelRecommended : null,
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
      if (mounted) showSnack(context, l10n.commonSaveFailed(e));
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
        title: Text(l10n.asrModelDeleteTitle(m['name'])),
        content: Text(l10n.asrModelDeleteBody(fmtBytes(m['size'] as num))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.commonDelete)),
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
    dir ??= await pickDirectory(context, initial: current, title: l10n.asrModelLocation);
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
      if (!move && mounted) showSnack(context, l10n.asrModelLocationChanged);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.asrLocalTitle)),
      body: st == null ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const CenteredLoader()) : _body(context, st),
    );
  }

  Widget _body(BuildContext context, _J st) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final status = _map(st['status']);
    if (status['supported'] != true) {
      return EmptyState(icon: Icons.memory_rounded, title: l10n.asrUnsupportedTitle, body: l10n.asrUnsupportedBody(status['platform']));
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
              Text(l10n.asrHowToChoose, style: tt.titleMedium),
              const SizedBox(height: Space.xs),
              Text(l10n.asrHowToChooseBody, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
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
              Text(l10n.commonModel, style: tt.titleMedium),
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
              Text(l10n.asrStorage, style: tt.titleMedium),
              const SizedBox(height: Space.sm),
              _Storage(
                loc: _map(status['location']),
                install: install,
                onChange: () => _relocate(_map(status['location'])),
                onReset: () => _relocate(_map(status['location']), dir: '${_map(status['location'])['default']}'),
              ),
              const SizedBox(height: Space.xl),
              Text(l10n.asrSource, style: tt.titleMedium),
              const SizedBox(height: Space.xs),
              Text(
                l10n.asrSourceVerify,
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
                Text(custom ? l10n.asrCustomLocation : l10n.asrDefaultLocation, style: tt.labelLarge?.copyWith(color: cs.primary)),
                const SizedBox(height: Space.xxs),
                Tooltip(
                  message: dir,
                  waitDuration: const Duration(milliseconds: 600),
                  child: Text(dir, style: tt.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  [
                    l10n.asrUsedSpace(fmtBytes(used)),
                    if (free >= 0) l10n.asrFreeSpace(fmtBytes(free)),
                  ].join(' · '),
                  style: tt.bodySmall?.copyWith(color: low ? cs.error : cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ]),
            ),
          ]),
          if (low && !moving) ...[
            const SizedBox(height: Space.md),
            Text(l10n.asrLowSpace, style: tt.bodySmall?.copyWith(color: cs.error)),
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
                label: Text(l10n.asrChangeLocation),
              ),
              TextButton.icon(
                onPressed: dir.isEmpty ? null : () => openPath(dir),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l10n.commonOpenInFileManager),
              ),
            ],
            if (custom) TextButton(onPressed: running ? null : onReset, child: Text(l10n.asrResetLocation)),
          ]),
          if (running && !moving) ...[
            const SizedBox(height: Space.xs),
            Text(l10n.asrLocationAfterDownload, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
      title: Text(l10n.asrMoveTitle),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: Corners.all(Corners.md)),
            child: Text(to, style: tt.bodyMedium),
          ),
          const SizedBox(height: Space.lg),
          Text(l10n.asrMoveBody(fmtBytes(used)),
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: Space.sm),
          Text(l10n.asrChangeOnlyBody,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.asrChangeOnly)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.asrMove)),
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
        ? (Icons.drive_file_move_outline, l10n.asrMoving, l10n.asrMovingBody)
        : active != null
        ? (Icons.offline_bolt_rounded, l10n.asrUsingModel(active!['name']), l10n.asrUsingModelBody)
        : running
        ? (Icons.downloading_rounded, l10n.asrDownloadingModel(name?['name'] ?? l10n.commonModel), l10n.asrDownloadingModelBody)
        : (Icons.computer_rounded, l10n.asrLocalHeroTitle, l10n.asrLocalHeroBody);
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
      l10n.commonDownloadSize(fmtBytes(size)),
      if ((measured['peak_mb'] as num? ?? 0) > 0) l10n.asrModelMemory(_gb(measured['peak_mb'] as num)),
      if (mins > 0) l10n.asrModelSpeed(mins < 10 ? mins.toStringAsFixed(1) : mins.round()),
      l10n.asrModelCer(bench['cer']),
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
                    if (active) _Tag(l10n.commonInUse, strong: true) else if (installed) _Tag(l10n.commonDownloaded),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${m['org']} · ${m['langs']} · ${m['punct'] == true ? l10n.asrModelPunctuated : l10n.asrModelAutoPunctuation}',
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
                                    label: Text(l10n.asrModelCerSource(bench['source'])),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => openPlainLink(context, '${m['license_url']}'),
                                    icon: const Icon(Icons.gavel_rounded, size: 18),
                                    label: Text(l10n.commonLicense(m['license'])),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => openPlainLink(context, '${m['upstream']}'),
                                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                    label: Text(l10n.asrModelOriginal),
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
                  Text(l10n.asrModelDownloadFailed(install!['error']), style: tt.bodySmall?.copyWith(color: cs.error)),
                ],
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    const Spacer(),
                    if (running)
                      OutlinedButton(onPressed: onCancel, child: Text(l10n.commonPause))
                    else if (!installed)
                      FilledButton.icon(
                        onPressed: busy ? null : onInstall,
                        icon: const Icon(Icons.download_rounded),
                        label: Text(
                          failed || install?['state'] == 'canceled' ? l10n.asrModelResume : l10n.asrModelDownload(fmtBytes(size + extra), extra > 0 ? l10n.asrModelIncludesEngine : ''),
                        ),
                      )
                    else ...[
                      TextButton(onPressed: onRemove, child: Text(l10n.commonDelete)),
                      const SizedBox(width: Space.sm),
                      if (active)
                        OutlinedButton(onPressed: onStop, child: Text(l10n.commonDisable))
                      else
                        FilledButton.tonal(onPressed: onUse, child: Text(l10n.asrModelUse)),
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
            if (left != null) l10n.commonTimeLeft(fmtDuration(left)),
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

  static final _guides = {
    'hf-mirror': l10n.asrSourceHfMirror,
    'modelscope': l10n.asrSourceModelscope,
    'huggingface': l10n.asrSourceHuggingface,
    'custom': l10n.asrSourceCustom,
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
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: l10n.asrSourceTemplate,
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
                  Text(l10n.asrEngineSource, style: tt.titleSmall),
                  const SizedBox(height: Space.xs),
                  Text(
                    l10n.asrEngineSourceBody,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: Space.sm),
                  TextField(
                    controller: proxy,
                    decoration: InputDecoration(border: OutlineInputBorder(), labelText: l10n.asrEngineProxy, hintText: 'https://…/'),
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
            Expanded(child: Text(l10n.asrThreads, style: tt.titleMedium)),
            Text(l10n.asrThreadCount(value), style: tt.labelLarge?.copyWith(color: cs.primary)),
          ],
        ),
        Text(l10n.asrThreadsHint(cpus), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
