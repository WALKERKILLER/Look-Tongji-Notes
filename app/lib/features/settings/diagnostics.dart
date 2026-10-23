import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/lookd_service.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../assistant/runtime_setup.dart';
import '../setup/workspace_setup_page.dart';
import '../../l10n/l10n.dart';

/// 设置 → 诊断: whether the background service, transcription and the
/// assistant work, where things are, the logs, and a restart.
class Diagnostics extends StatefulWidget {
  const Diagnostics({super.key});
  @override
  State<Diagnostics> createState() => _DiagnosticsState();
}

enum _Health { ok, attention, pending }

class _Check {
  const _Check(this.icon, this.title, this.detail, this.health, {this.action});
  final IconData icon;
  final String title, detail;
  final _Health health;
  final Widget? action;
}

class _DiagnosticsState extends State<Diagnostics> {
  Map<String, dynamic>? _runtime;
  List<String> _agentLog = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.connected) return;
    try {
      final rt = (await app.api.get('/api/agent/runtime') as Map).cast<String, dynamic>();
      final st = await app.api.get('/api/agent/status') as Map;
      if (!mounted) return;
      setState(() {
        _runtime = rt;
        _agentLog = [for (final l in (st['logs'] as List?) ?? const []) '$l'];
      });
    } catch (_) {
      // The checks below already show what is not reachable.
    }
  }

  static String get _platform => switch (Platform.operatingSystem) {
        'linux' => 'Linux',
        'windows' => 'Windows',
        'macos' => 'macOS',
        'android' => 'Android',
        final os => os,
      };

  List<_Check> _checks(AppState app, LookdService daemon) {
    final h = app.health;
    final agent = app.agent;
    final node = (_runtime?['node'] as Map?)?.cast<String, dynamic>();
    final ready = daemon.state == DaemonState.ready;
    final agentState = '${agent['state']}';
    final agentError = '${agent['error'] ?? ''}'.trim();
    return [
      _Check(
        Icons.dns_outlined,
        l10n.diagDaemon,
        switch (daemon.state) {
          DaemonState.ready => l10n.diagDaemonDetail(h['version'] ?? '—', daemon.port),
          DaemonState.failed => daemon.error ?? l10n.diagNotStarted,
          _ => l10n.commonStarting,
        },
        ready ? _Health.ok : (daemon.state == DaemonState.failed ? _Health.attention : _Health.pending),
      ),
      if (daemon.workspace != null) _Check(Icons.terminal_rounded, l10n.diagWorkspace, 'Ubuntu 24.04 · proot', _Health.ok),
      _Check(
        Icons.graphic_eq_rounded,
        'ffmpeg',
        h['ffmpeg'] == true ? l10n.diagFfmpegOk : (daemon.workspace != null ? l10n.diagFfmpegMissingWorkspace : l10n.diagFfmpegMissing),
        !ready ? _Health.pending : (h['ffmpeg'] == true ? _Health.ok : _Health.attention),
        action: daemon.workspace != null && ready && h['ffmpeg'] != true ? WorkspaceFFmpegButton(workspace: daemon.workspace!, onDone: app.refreshHealth) : null,
      ),
      _Check(
        Icons.smart_toy_outlined,
        l10n.commonAssistant,
        switch (agentState) {
          'ready' => node?['version'] != null ? l10n.diagAgentRunningNode(node!['version']) : l10n.commonRunning,
          'starting' => l10n.commonStarting,
          _ => agentError.isNotEmpty ? agentError : l10n.diagAgentNotRunning,
        },
        !ready || agentState == 'starting' ? _Health.pending : (agentState == 'ready' ? _Health.ok : _Health.attention),
        action: ready && agentState != 'ready' && agentState != 'starting'
            ? FilledButton.tonal(onPressed: () => showRuntimeSetup(context), child: Text(l10n.diagSetupRuntime))
            : null,
      ),
    ];
  }

  String _report(AppState app, LookdService daemon, List<_Check> checks) => [
        'Look Studio ${app.health['version'] ?? ''} · $_platform',
        for (final c in checks) l10n.diagReportLine(c.title, c.detail),
        if ('${app.health['library'] ?? ''}'.isNotEmpty) l10n.diagReportLibrary(app.health['library']),
      ].join('\n');

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final daemon = context.watch<LookdService>();
    final checks = _checks(app, daemon);
    final library = '${app.health['library'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: Space.xl),
      _Summary(
        checks: checks,
        subtitle: 'Look Studio ${app.health['version'] ?? ''} · $_platform${daemon.workspace != null ? l10n.diagWorkspaceSuffix : ''}',
        onCopy: () {
          Clipboard.setData(ClipboardData(text: _report(app, daemon, checks)));
          showSnack(context, l10n.diagCopied);
        },
      ),
      _Heading(l10n.diagStatus),
      _Segmented(children: [for (final c in checks) _CheckTile(c)]),
      if (library.isNotEmpty) ...[
        _Heading(l10n.commonLocation),
        _Segmented(children: [_PathTile(label: l10n.commonLibrary, path: library)]),
      ],
      _Heading(l10n.diagLogs),
      _Segmented(children: [
        _LogTile(icon: Icons.receipt_long_outlined, title: l10n.diagDaemonLog, lines: daemon.log),
        _LogTile(icon: Icons.smart_toy_outlined, title: l10n.diagAgentLog, lines: _agentLog, onOpen: _load),
      ]),
      _Heading(l10n.diagMaintenance),
      _Segmented(children: [
        _Tile(
          leading: Icons.restart_alt_rounded,
          title: l10n.diagRestart,
          subtitle: l10n.diagRestartHint,
          trailing: OutlinedButton(onPressed: daemon.restart, child: Text(l10n.diagRestartAction)),
        ),
      ]),
    ]);
  }
}

/// The overall verdict, in words rather than a dashboard.
class _Summary extends StatelessWidget {
  const _Summary({required this.checks, required this.subtitle, required this.onCopy});
  final List<_Check> checks;
  final String subtitle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final issues = checks.where((c) => c.health == _Health.attention).length;
    final pending = checks.any((c) => c.health == _Health.pending);
    final (title, icon, bg, fg) = issues > 0
        ? (l10n.diagIssues(issues), Icons.priority_high_rounded, cs.errorContainer, cs.onErrorContainer)
        : pending
            ? (l10n.commonChecking, Icons.more_horiz_rounded, cs.surfaceContainerHighest, cs.onSurfaceVariant)
            : (l10n.diagAllGood, Icons.check_rounded, cs.primaryContainer, cs.onPrimaryContainer);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      child: Row(children: [
        AnimatedContainer(
          duration: Motion.medium2,
          curve: Motion.emphasized,
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Corners.lgIncreased)),
          child: Icon(icon, color: fg, size: 28),
        ),
        const SizedBox(width: Space.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: tt.headlineSmall),
            const SizedBox(height: Space.xxs),
            Text(subtitle, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: Space.sm),
        IconButton.filledTonal(tooltip: l10n.diagCopy, onPressed: onCopy, icon: const Icon(Icons.content_copy_rounded, size: 20)),
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.sm),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
    );
  }
}

/// M3 Expressive segmented list: one tile per item, 2dp apart, with the
/// group's large corners only at its ends.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const outer = Radius.circular(Corners.lgIncreased), inner = Radius.circular(Corners.xs);
    return Column(children: [
      for (final (i, c) in children.indexed) ...[
        if (i > 0) const SizedBox(height: Space.xxs),
        Material(
          color: cs.surfaceContainer,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: i == 0 ? outer : inner, bottom: i == children.length - 1 ? outer : inner),
          ),
          child: c,
        ),
      ],
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.leading, required this.title, this.subtitle, this.trailing, this.below, this.onTap, this.leadingColor});
  final IconData leading;
  final String title;
  final String? subtitle;
  final Widget? trailing, below;
  final VoidCallback? onTap;
  final Color? leadingColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(Corners.md)),
              child: Icon(leading, size: 20, color: leadingColor ?? cs.onSurfaceVariant),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tt.titleSmall),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: Space.xxs),
                  Text(subtitle!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: Space.md), trailing!],
          ]),
          if (below != null) Padding(padding: const EdgeInsets.only(left: 40 + Space.lg, top: Space.sm), child: below!),
        ]),
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile(this.c);
  final _Check c;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Tile(
      leading: c.icon,
      leadingColor: c.health == _Health.attention ? cs.error : null,
      title: c.title,
      subtitle: c.detail,
      trailing: _StatusPill(c.health),
      below: c.action == null ? null : Align(alignment: AlignmentDirectional.centerStart, child: c.action!),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.health);
  final _Health health;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, dot) = switch (health) {
      _Health.ok => (l10n.diagOk, cs.primary),
      _Health.attention => (l10n.commonNeedsAttention, cs.error),
      _Health.pending => (l10n.diagChecking, cs.outline),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      const SizedBox(width: Space.sm),
      Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: health == _Health.attention ? cs.error : cs.onSurfaceVariant)),
    ]);
  }
}

class _PathTile extends StatelessWidget {
  const _PathTile({required this.label, required this.path});
  final String label, path;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      leading: Icons.folder_outlined,
      title: label,
      subtitle: path,
      onTap: canOpenFolders ? () => openPath(path) : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: l10n.commonCopyPath,
          icon: const Icon(Icons.content_copy_outlined, size: 20),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: path));
            showSnack(context, l10n.commonPathCopied);
          },
        ),
        if (canOpenFolders) IconButton(tooltip: l10n.commonOpenFolder, icon: const Icon(Icons.open_in_new_rounded, size: 20), onPressed: () => openPath(path)),
      ]),
    );
  }
}

/// A log's last lines as a preview; opens the whole log.
class _LogTile extends StatelessWidget {
  const _LogTile({required this.icon, required this.title, required this.lines, this.onOpen});
  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tail = lines.length > 3 ? lines.sublist(lines.length - 3) : lines;
    return _Tile(
      leading: icon,
      title: title,
      subtitle: lines.isEmpty ? l10n.diagLogEmpty : l10n.diagLogLines(lines.length),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      onTap: () {
        onOpen?.call();
        showLogViewer(context, title, lines);
      },
      below: tail.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
              decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(Corners.sm)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final l in tail) Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: _mono(context, l)),
              ]),
            ),
    );
  }
}

bool _isError(String l) => RegExp(r'\b(error|failed|panic|fatal)\b|错误|失败', caseSensitive: false).hasMatch(l);

TextStyle _mono(BuildContext context, String line) {
  final cs = Theme.of(context).colorScheme;
  return TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5, color: _isError(line) ? cs.error : cs.onSurfaceVariant);
}

/// The whole log, newest at the bottom: full screen on phones, a large
/// dialog elsewhere.
Future<void> showLogViewer(BuildContext context, String title, List<String> lines) {
  Widget body(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.sm, Space.sm),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: tt.titleLarge),
              Text(lines.isEmpty ? l10n.diagLogEmpty : l10n.diagLogRecent(lines.length), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          IconButton(
            tooltip: l10n.commonCopyAll,
            icon: const Icon(Icons.content_copy_rounded),
            onPressed: lines.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: lines.join('\n')));
                    showSnack(context, l10n.diagLogCopied);
                  },
          ),
          IconButton(tooltip: l10n.commonClose, icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
          decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(Corners.lg)),
          clipBehavior: Clip.antiAlias,
          child: lines.isEmpty
              ? Center(child: Text(l10n.diagLogNothing, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
              : SelectionArea(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(Space.lg),
                    itemCount: lines.length,
                    itemBuilder: (context, i) {
                      final l = lines[lines.length - 1 - i];
                      return Text(l, style: _mono(context, l));
                    },
                  ),
                ),
        ),
      ),
    ]);
  }

  if (context.isCompact) {
    return showDialog(context: context, builder: (context) => Dialog.fullscreen(child: SafeArea(child: body(context))));
  }
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.xl)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760, maxHeight: 600), child: body(context)),
    ),
  );
}
