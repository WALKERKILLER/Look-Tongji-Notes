import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';

/// Background refresh of Look (and Canvas) with in-app notifications.
/// Contract: docs/specs/0010-live-refresh.md
class WatchSettings extends StatefulWidget {
  const WatchSettings({super.key, required this.server, required this.put});
  final Map<String, dynamic> server;
  final Future<void> Function(String key, Object? value) put;
  @override
  State<WatchSettings> createState() => _WatchSettingsState();
}

class _WatchSettingsState extends State<WatchSettings> {
  Map<String, dynamic>? _st;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AppState>().api.get('/api/watch') as Map;
      if (mounted) setState(() => _st = r.cast<String, dynamic>());
    } catch (_) {}
  }

  Future<void> _runNow() async {
    setState(() => _running = true);
    try {
      await context.read<AppState>().api.post('/api/watch/run');
      if (mounted) showSnack(context, '已开始检查，有变化会马上通知你');
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      await _load();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final on = widget.server['watch.enabled'] != false;
    final courses = jsonList(_st?['courses']).whereType<Map>().toList();
    final awaiting = courses.fold<int>(0, (n, c) => n + ((c['awaiting'] as num?)?.toInt() ?? 0));
    final next = courses
        .map((c) => (c['next_at'] as num?)?.toInt() ?? 0)
        .where((t) => t > 0)
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    final last = (_st?['last_run'] as num?)?.toInt() ?? 0;
    final err = '${_st?['last_error'] ?? ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.sync_rounded),
          title: const Text('后台自动检查新回放和新课次'),
          subtitle: const Text('刚下课的课每 10 分钟查一次回放，之后逐渐放缓；其他课程每 6 小时同步一次；已连接的 Canvas 每 15 分钟同步作业和公告。有变化时立即提醒，课程页也会自动刷新'),
          value: on,
          onChanged: (v) => widget.put('watch.enabled', v),
        ),
        if (on && _st != null)
          Padding(
            padding: const EdgeInsets.only(left: 56, bottom: Space.sm),
            child: Text(
              [
                awaiting > 0 ? '正在等待 $awaiting 节课的回放' : '没有等待中的回放',
                if (next != null) '下次检查 ${fmtUntil(DateTime.fromMillisecondsSinceEpoch(next * 1000))}',
                if (last > 0) '上次 ${fmtRelative(DateTime.fromMillisecondsSinceEpoch(last * 1000))}',
              ].join(' · '),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        if (err.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 56, bottom: Space.sm),
            child: Text(
              '最近一次检查失败：$err',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 48),
            child: TextButton.icon(
              onPressed: !on || _running ? null : _runNow,
              icon: _running
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
              label: const Text('立即检查'),
            ),
          ),
        ),
      ],
    );
  }
}
