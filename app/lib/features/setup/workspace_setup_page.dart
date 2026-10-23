import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/lookd_service.dart';
import '../../core/workspace.dart';
import '../../theme/tokens.dart';
import '../../l10n/l10n.dart';

// First run on Android: install the Linux workspace lookd and the
// assistant run in. Contract: docs/specs/draft-android-app.md

class WorkspaceSetupPage extends StatefulWidget {
  const WorkspaceSetupPage({super.key});
  @override
  State<WorkspaceSetupPage> createState() => _WorkspaceSetupPageState();
}

class _WorkspaceSetupPageState extends State<WorkspaceSetupPage> {
  String _mirror = workspaceMirrors.first.id;

  static final _steps = [l10n.workspaceStepDownload, l10n.workspaceStepUnpack, l10n.workspaceStepConfigure];

  Future<void> _start(LookdService daemon, Workspace ws) async {
    try {
      await ws.install(workspaceMirrors.firstWhere((m) => m.id == _mirror));
    } catch (_) {
      return; // shown from ws.error
    }
    await daemon.afterSetup();
  }

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<LookdService>();
    final ws = daemon.workspace!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: ws,
      builder: (context, _) {
        final p = ws.progress;
        final current = p == null ? -1 : _steps.indexOf(p.step);
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(Corners.lgIncreased)),
                        child: Icon(Icons.terminal_rounded, size: 32, color: cs.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    Text(l10n.workspaceTitle, style: tt.headlineMedium),
                    const SizedBox(height: Space.md),
                    Text(
                      l10n.workspaceBody,
                      style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: Space.xl),
                    Text(l10n.commonMirror, style: tt.titleSmall),
                    const SizedBox(height: Space.sm),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [for (final m in workspaceMirrors) ButtonSegment(value: m.id, label: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis))],
                      selected: {_mirror},
                      onSelectionChanged: ws.busy ? null : (s) => setState(() => _mirror = s.first),
                    ),
                    const SizedBox(height: Space.xl),
                    Material(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(Corners.xl),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                        child: Column(children: [
                          for (final (i, s) in _steps.indexed) _Step(label: s, index: i, current: current, busy: ws.busy, progress: i == current ? p : null),
                        ]),
                      ),
                    ),
                    AnimatedSize(
                      duration: Motion.medium2,
                      curve: Motion.emphasized,
                      child: ws.error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: Space.lg),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
                                const SizedBox(width: Space.sm),
                                Expanded(child: Text(ws.error!, style: tt.bodyMedium?.copyWith(color: cs.error))),
                              ]),
                            ),
                    ),
                    const SizedBox(height: Space.xl),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: ws.busy ? null : () => _start(daemon, ws),
                      icon: ws.busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : Icon(ws.error == null ? Icons.download_rounded : Icons.refresh_rounded),
                      label: Text(ws.busy ? l10n.workspacePreparing : (ws.error == null ? l10n.workspaceStart : l10n.commonRetry)),
                    ),
                    const SizedBox(height: Space.md),
                    Text(l10n.workspaceUninstallNote,
                        textAlign: TextAlign.center, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.index, required this.current, required this.busy, this.progress});
  final String label;
  final int index, current;
  final bool busy;
  final WorkspaceProgress? progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final done = busy && current > index;
    final active = busy && current == index;
    final p = progress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 24,
            height: 24,
            child: done
                ? Icon(Icons.check_circle_rounded, color: cs.primary)
                : active
                    ? Padding(padding: const EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2.5, value: p?.fraction))
                    : Icon(Icons.radio_button_unchecked_rounded, color: cs.outline),
          ),
          const SizedBox(width: Space.md),
          Expanded(child: Text(label, style: tt.bodyLarge?.copyWith(color: active || done ? cs.onSurface : cs.onSurfaceVariant))),
          if (active && p != null && p.total > 0)
            Text('${fmtBytes(p.done)} / ${fmtBytes(p.total)}', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        ]),
        if (active && p?.fraction != null)
          Padding(
            padding: const EdgeInsets.only(left: 36, top: Space.sm),
            child: LinearProgressIndicator(value: p!.fraction, borderRadius: BorderRadius.circular(Corners.full)),
          ),
      ]),
    );
  }
}

/// Installs ffmpeg in the workspace from settings, showing apt's output.
class WorkspaceFFmpegButton extends StatelessWidget {
  const WorkspaceFFmpegButton({super.key, required this.workspace, required this.onDone});
  final Workspace workspace;
  final VoidCallback onDone;

  Future<void> _install(BuildContext context) async {
    final lines = ValueNotifier<List<String>>(const []);
    final done = ValueNotifier<String?>(null);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(l10n.workspaceInstallFfmpeg),
        content: SizedBox(
          width: 560,
          height: 320,
          child: ValueListenableBuilder(
            valueListenable: lines,
            builder: (_, ls, _) => SingleChildScrollView(
              reverse: true,
              child: SelectableText(ls.isEmpty ? l10n.workspaceConnecting : ls.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
          ),
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: done,
            builder: (_, d, _) => d == null
                ? const Padding(padding: EdgeInsets.all(Space.sm), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)))
                : FilledButton(onPressed: () => Navigator.pop(c), child: Text(l10n.commonClose)),
          ),
        ],
      ),
    );
    try {
      await workspace.installFFmpeg(onLine: (l) => lines.value = [...lines.value.length > 400 ? lines.value.sublist(200) : lines.value, l]);
      done.value = 'ok';
      lines.value = [...lines.value, '', l10n.workspaceFfmpegInstalled];
      onDone();
    } catch (e) {
      done.value = 'error';
      lines.value = [...lines.value, '', '$e'];
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: workspace,
        builder: (context, _) => FilledButton.tonalIcon(
          onPressed: workspace.busy ? null : () => _install(context),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(l10n.workspaceInstallFfmpeg),
        ),
      );
}
