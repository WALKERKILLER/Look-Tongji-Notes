import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/organic_shapes.dart';
import 'local_asr_page.dart';
import '../../l10n/l10n.dart';

/// Free cloud transcription channels: enable/disable, strategy, concurrency
/// and live status from lookd's ASR pool.
class AsrSettings extends StatefulWidget {
  const AsrSettings({super.key, required this.server, required this.put});
  final Map<String, dynamic> server;
  final Future<void> Function(String key, Object? value) put;
  @override
  State<AsrSettings> createState() => _AsrSettingsState();
}

class _AsrSettingsState extends State<AsrSettings> {
  List<Map<String, dynamic>> _chans = [];
  List<Map<String, dynamic>> _events = [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AppState>().api.get('/api/asr') as Map;
      if (!mounted) return;
      setState(() {
        _chans = jsonList(r['channels']).map((e) => (e as Map).cast<String, dynamic>()).toList();
        _events = jsonList(r['events']).map((e) => (e as Map).cast<String, dynamic>()).toList();
      });
    } catch (_) {}
  }

  List<String> get _disabled => [for (final d in (widget.server['asr.disabled'] as List?) ?? const []) '$d'];

  Future<void> _toggle(String id, bool on) async {
    final d = _disabled..remove(id);
    if (!on) d.add(id);
    await widget.put('asr.disabled', d);
    _load();
  }

  String _slotsHint() {
    final parts = [for (final c in _chans) l10n.asrChannelSlots(c['name'], c['slots'] ?? 1)];
    return parts.isEmpty ? l10n.asrPerChannelLimits : l10n.asrChannelLimits(parts.join(l10n.listSeparator));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final strategy = '${widget.server['asr.strategy'] ?? 'balance'}';
    final conc = ((widget.server['asr.concurrency'] as num?) ?? 2).toDouble();
    final local = _chans.where((c) => c['local'] == true).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Text(l10n.asrIntro,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.6)),
      ),
      Card.filled(
        margin: const EdgeInsets.only(top: Space.sm),
        color: local != null ? cs.secondaryContainer : cs.primaryContainer,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
          shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.lg)),
          leading: Icon(local != null ? Icons.offline_bolt_rounded : Icons.computer_rounded,
              color: local != null ? cs.onSecondaryContainer : cs.onPrimaryContainer),
          title: Text(local != null ? l10n.asrLocalEnabled : l10n.asrTryLocal,
              style: TextStyle(color: local != null ? cs.onSecondaryContainer : cs.onPrimaryContainer)),
          subtitle: Text(local != null ? l10n.asrLocalUnlimited(local['name']) : l10n.asrLocalHint,
              style: TextStyle(color: local != null ? cs.onSecondaryContainer : cs.onPrimaryContainer)),
          trailing: Icon(Icons.chevron_right_rounded, color: local != null ? cs.onSecondaryContainer : cs.onPrimaryContainer),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LocalAsrPage()));
            _load();
          },
        ),
      ),
      for (final c in _chans)
        Padding(padding: const EdgeInsets.only(top: Space.sm), child: _ChannelCard(c: c, onToggle: (v) => _toggle('${c['id']}', v))),
      const SizedBox(height: Space.lg),
      Text(l10n.asrDistribution, style: tt.titleSmall),
      const SizedBox(height: Space.sm),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 'balance', icon: Icon(Icons.balance_rounded), label: Text(l10n.asrBalanced)),
          for (final c in _chans) ButtonSegment(value: '${c['id']}', label: Text(l10n.asrPrefer(c['name']))),
        ],
        selected: {strategy},
        onSelectionChanged: (s) => widget.put('asr.strategy', s.first),
      ),
      const SizedBox(height: Space.lg),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.asrConcurrency, style: tt.titleSmall),
            Text(_slotsHint(), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        Text(l10n.asrSegments(conc.round()), style: tt.labelLarge?.copyWith(color: cs.primary)),
      ]),
      Slider(
        value: conc.clamp(1, 4),
        min: 1,
        max: 4,
        divisions: 3,
        label: '${conc.round()}',
        onChanged: (v) => setState(() => widget.server['asr.concurrency'] = v.round()),
        onChangeEnd: (v) => widget.put('asr.concurrency', v.round()),
      ),
      if (_events.isNotEmpty) _EventLog(events: _events),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.auto_delete_outlined),
        title: Text(l10n.asrDeleteVideo),
        subtitle: Text(l10n.asrDeleteVideoHint),
        value: widget.server['transcript.delete_video'] == true,
        onChanged: (v) => widget.put('transcript.delete_video', v),
      ),
    ]);
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.c, required this.onToggle});
  final Map<String, dynamic> c;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = '${c['state']}';
    final enabled = c['enabled'] == true;
    final used = (c['used_secs'] as num?)?.toDouble() ?? 0;
    final quota = (c['quota_secs'] as num?)?.toDouble() ?? 1;
    final coolUntil = (c['cool_until'] as num?)?.toInt() ?? 0;
    final (label, color) = switch (state) {
      'ready' => (l10n.asrReady, cs.primary),
      'busy' => (l10n.asrBusy(c['busy']), cs.tertiary),
      'cooling' => (l10n.asrCooling(_hm(coolUntil)), cs.error),
      'quota' => (l10n.asrQuotaFull, cs.error),
      _ => (l10n.commonDisabled, cs.outline),
    };
    final lastErr = '${c['last_error'] ?? ''}';
    final local = c['local'] == true;
    return AnimatedOpacity(
      duration: Motion.medium1,
      opacity: enabled ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Corners.lg)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _Mark(text: '${c['name']}'.characters.first, busy: state == 'busy'),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${c['name']}', style: tt.titleSmall),
                  const SizedBox(width: Space.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Corners.full)),
                    child: Text(label, style: tt.labelSmall?.copyWith(color: color)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text('${c['note']}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Switch(value: enabled, onChanged: onToggle),
          ]),
          const SizedBox(height: Space.md),
          if (!local)
            Padding(
              padding: const EdgeInsets.only(right: Space.md),
              child: Row(children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: (used / quota).clamp(0.0, 1.0),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                    color: used >= quota ? cs.error : cs.primary,
                  ),
                ),
                const SizedBox(width: Space.md),
                Text(l10n.asrQuotaUsage(_dur(used), _dur(quota)), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          const SizedBox(height: Space.xs),
          Text(
            [l10n.asrOkSegments(c['ok'] ?? 0), l10n.asrFailedSegments(c['fail'] ?? 0), if ((c['last_used'] ?? 0) != 0) l10n.commonLastUsed(fmtRelative(DateTime.fromMillisecondsSinceEpoch((c['last_used'] as num).toInt() * 1000)))]
                .join(' · '),
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (lastErr.isNotEmpty && state == 'cooling')
            Padding(
              padding: const EdgeInsets.only(top: 2, right: Space.md),
              child: Text(lastErr, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.labelSmall?.copyWith(color: cs.error)),
            ),
        ]),
      ),
    );
  }

  static String _hm(int unix) {
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _dur(double s) {
    final m = (s / 60).round();
    return m >= 60 ? l10n.durationHoursOnly((m / 60).toStringAsFixed(m % 60 == 0 ? 0 : 1)) : l10n.durationMinutes(m);
  }
}

/// Recent chunk attempts, newest first, to see why transcription failed.
class _EventLog extends StatelessWidget {
  const _EventLog({required this.events});
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fails = events.where((e) => e['ok'] != true).length;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.history_rounded),
        title: Text(l10n.asrRecent),
        subtitle: Text(l10n.asrRecentSummary(events.length, fails), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        children: [
          for (final e in events.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(e['ok'] == true ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                    size: 18, color: e['ok'] == true ? cs.primary : cs.error),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      l10n.asrEventLine(_ChannelCard._hm((e['at'] as num).toInt()), e['channel'], e['chunk'], _ChannelCard._dur((e['secs'] as num).toDouble()), (e['took'] as num).round()),
                      style: tt.labelMedium,
                    ),
                    if ('${e['error'] ?? ''}'.isNotEmpty)
                      Text('${e['error']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.labelSmall?.copyWith(color: cs.error)),
                  ]),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Channel badge: a soft cookie shape that turns while the channel works.
class _Mark extends StatelessWidget {
  const _Mark({required this.text, required this.busy});
  final String text;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: busy ? 1 : 0),
      duration: Motion.long2,
      curve: Motion.emphasized,
      builder: (_, t, child) => CustomPaint(
        painter: _MarkPainter(t, cs.secondaryContainer),
        child: child,
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Center(child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onSecondaryContainer))),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.t, this.color);
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawPath(shapePath(morphRadii(OrganicShape.cookie9, OrganicShape.softBurst, t), Offset.zero & size, rotation: t * 0.6), Paint()..color = color);
  @override
  bool shouldRepaint(_MarkPainter o) => o.t != t || o.color != color;
}
