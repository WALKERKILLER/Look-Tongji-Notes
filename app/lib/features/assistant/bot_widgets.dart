import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

// Chat pieces of the bot operating the app: a chip for an operation done at
// once, and a card for a change that waits for the user
// (docs/specs/0007-resident-bot-and-course-agents.md).

const _kindIcons = <String, IconData>{
  'settings': Icons.tune_rounded,
  'download': Icons.download_rounded,
  'delete_files': Icons.delete_sweep_outlined,
  'downloads': Icons.downloading_rounded,
  'course': Icons.school_outlined,
  'task': Icons.schedule_rounded,
  'plugin': Icons.extension_outlined,
};

/// An operation the bot already did, with 返回 (navigation) or 撤销.
class AppOpChip extends StatefulWidget {
  const AppOpChip({super.key, required this.label, required this.icon, this.actionLabel, this.doneLabel = '已撤销', this.onAction, this.done = false});
  final String label;
  final IconData icon;
  final String? actionLabel;
  final String doneLabel;

  /// Runs once: after it succeeds the chip shows [doneLabel].
  final Future<void> Function()? onAction;

  /// The action already ran: the chip says so and offers nothing.
  final bool done;

  @override
  State<AppOpChip> createState() => _AppOpChipState();
}

class _AppOpChipState extends State<AppOpChip> {
  bool _busy = false, _ran = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final done = widget.done || _ran;
    final fg = done ? cs.onSurfaceVariant : cs.onTertiaryContainer;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.only(left: Space.md, right: Space.xs),
      decoration: BoxDecoration(
        color: done ? cs.surfaceContainerHigh : cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(Corners.full),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(done ? Icons.undo_rounded : widget.icon, size: 16, color: fg),
        const SizedBox(width: Space.sm),
        Flexible(
          child: Text(done ? '${widget.doneLabel} · ${widget.label}' : widget.label,
              style: tt.labelLarge?.copyWith(color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (widget.onAction != null && !done) ...[
          const SizedBox(width: Space.xs),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: cs.onTertiaryContainer, visualDensity: VisualDensity.compact),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.onAction!();
                      _ran = true;
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: Text(widget.actionLabel ?? '撤销'),
          ),
        ] else
          const SizedBox(width: Space.sm),
      ]),
    );
  }
}

/// A change the bot proposed: its lines and 应用 / 忽略, then the outcome.
class ProposalCard extends StatefulWidget {
  const ProposalCard({super.key, required this.proposal, required this.onApply, required this.onDismiss, required this.onUndo});
  final Map<String, dynamic> proposal;
  final Future<void> Function() onApply, onDismiss, onUndo;

  @override
  State<ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends State<ProposalCard> {
  String? _busy;
  String? _error;

  Future<void> _run(String which, Future<void> Function() f) async {
    setState(() {
      _busy = which;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst(RegExp(r'^ApiError\(\d+\): '), ''));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final p = widget.proposal;
    final state = '${p['state'] ?? 'pending'}';
    final pending = state == 'pending';
    final lines = [for (final l in (p['lines'] as List?) ?? const []) '$l'].where((l) => l.isNotEmpty).toList();
    final (outcome, outcomeIcon) = switch (state) {
      'applied' => ('已应用', Icons.check_circle_rounded),
      'dismissed' => ('已忽略', Icons.do_not_disturb_on_outlined),
      'undone' => ('已撤销', Icons.undo_rounded),
      'expired' => ('已过期，请让助手重新生成', Icons.schedule_rounded),
      'failed' => ('执行失败', Icons.error_outline_rounded),
      _ => ('等你确认', Icons.pending_outlined),
    };
    return AnimatedContainer(
      duration: Motion.medium2,
      curve: Motion.emphasized,
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: pending ? cs.secondaryContainer : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Corners.lg),
      ),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_kindIcons[p['kind']] ?? Icons.touch_app_outlined, size: 20, color: pending ? cs.onSecondaryContainer : cs.onSurfaceVariant),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text('${p['title'] ?? ''}',
                style: tt.titleSmall?.copyWith(color: pending ? cs.onSecondaryContainer : cs.onSurface)),
          ),
        ]),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          for (final l in lines.take(14))
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 2, right: Space.sm),
              child: Text(l, style: tt.bodySmall?.copyWith(color: pending ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
            ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: Space.xs, right: Space.sm),
            child: Text(_error!, style: tt.bodySmall?.copyWith(color: cs.error)),
          ),
        const SizedBox(height: Space.xs),
        Row(children: [
          const SizedBox(width: 28),
          if (!pending) ...[
            Icon(outcomeIcon, size: 16, color: state == 'failed' ? cs.error : cs.onSurfaceVariant),
            const SizedBox(width: Space.xs),
            Expanded(child: Text(outcome, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
            if (state == 'applied' && p['undoable'] == true)
              TextButton(onPressed: _busy != null ? null : () => _run('undo', widget.onUndo), child: const Text('撤销')),
          ] else ...[
            const Spacer(),
            TextButton(
              onPressed: _busy != null ? null : () => _run('dismiss', widget.onDismiss),
              child: const Text('忽略'),
            ),
            const SizedBox(width: Space.xs),
            FilledButton(
              onPressed: _busy != null ? null : () => _run('apply', widget.onApply),
              child: _busy == 'apply'
                  ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : const Text('应用'),
            ),
          ],
        ]),
      ]),
    );
  }
}
