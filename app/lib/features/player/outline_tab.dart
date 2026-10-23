import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import 'lecture_player.dart';
import '../../l10n/l10n.dart';

/// The skill's timeline format: minutes may exceed 59.
String skillClock(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// AI chapter outline of the lecture: a rail of topics that follows playback.
class OutlineTab extends StatefulWidget {
  const OutlineTab({super.key, required this.ctl});
  final LecturePlayer ctl;
  @override
  State<OutlineTab> createState() => _OutlineTabState();
}

class _OutlineTabState extends State<OutlineTab> with AutomaticKeepAliveClientMixin {
  final _keys = <int, GlobalKey>{};
  int _current = -1;
  DateTime _userScrolled = DateTime(0);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.ctl.position.addListener(_onPos);
    _current = widget.ctl.chapterAt(widget.ctl.positionMs);
  }

  @override
  void dispose() {
    widget.ctl.position.removeListener(_onPos);
    super.dispose();
  }

  void _onPos() {
    final i = widget.ctl.chapterAt(widget.ctl.positionMs);
    if (i == _current) return;
    setState(() => _current = i);
    if (DateTime.now().difference(_userScrolled) < const Duration(seconds: 5)) return;
    final c = _keys[i]?.currentContext;
    if (c != null) Scrollable.ensureVisible(c, alignment: 0.3, duration: Motion.long2, curve: Motion.emphasized);
  }

  Future<void> _generate() async {
    await widget.ctl.generateOutline();
    if (!mounted) return;
    final e = widget.ctl.outlineError;
    if (e != null) showSnack(context, l10n.outlineFailed(e));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ctl = widget.ctl;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (ctl.chapters.isEmpty) {
      if (ctl.outlineBusy) return const _Drafting();
      if (ctl.segments.isEmpty) {
        return EmptyState(
          icon: Icons.view_timeline_outlined,
          title: l10n.outlineNeedsTranscript,
          body: l10n.outlineNeedsTranscriptBody,
          action: FilledButton.tonalIcon(
            onPressed: () async {
              await context.read<AppState>().enqueue([ctl.lectureId], ['transcript']);
              if (context.mounted) showSnack(context, l10n.asrQueued);
            },
            icon: const Icon(Icons.subject_rounded),
            label: Text(l10n.asrStart),
          ),
        );
      }
      return EmptyState(
        icon: Icons.view_timeline_outlined,
        title: l10n.outlineTitle,
        body: ctl.outlineError == null ? l10n.outlineBody : l10n.outlineLastError(ctl.outlineError!),
        action: FilledButton.icon(onPressed: _generate, icon: const Icon(Icons.auto_awesome_rounded), label: Text(ctl.outlineError == null ? l10n.outlineGenerate : l10n.commonRetry)),
      );
    }

    final total = ctl.chapters.last.endMs;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.xs, 0),
        child: Row(children: [
          Expanded(
            child: Text(ctl.outlineBusy ? l10n.outlineRegenerating : l10n.outlineSummary(ctl.chapters.length, fmtClock(total)), style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
          ),
          MenuAnchor(
            menuChildren: [
              MenuItemButton(leadingIcon: const Icon(Icons.refresh_rounded), onPressed: ctl.outlineBusy ? null : _generate, child: Text(l10n.commonRegenerate)),
              MenuItemButton(
                leadingIcon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: ctl.chapters.map((c) => l10n.outlineChapterLine(skillClock(c.startMs), skillClock(c.endMs), c.title)).join('\n')));
                  showSnack(context, l10n.outlineCopied);
                },
                child: Text(l10n.commonCopy),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.delete_outline_rounded),
                onPressed: ctl.outlineBusy
                    ? null
                    : () async {
                        final old = ctl.chapters;
                        await ctl.deleteOutline();
                        if (!context.mounted) return;
                        showSnack(context, l10n.outlineDeleted, action: l10n.commonUndo, onAction: () async {
                          await ctl.api.put('/api/lectures/${ctl.lectureId}/timeline', {
                            'chapters': [for (final c in old) c.j],
                          });
                          ctl.reloadTimeline();
                        });
                      },
                child: Text(l10n.commonDelete),
              ),
            ],
            builder: (context, m, _) => IconButton(tooltip: l10n.outlineOptions, onPressed: () => m.isOpen ? m.close() : m.open(), icon: const Icon(Icons.more_vert_rounded)),
          ),
        ]),
      ),
      AnimatedSwitcher(
        duration: Motion.medium2,
        child: ctl.outlineBusy ? const LinearProgressIndicator(minHeight: 2) : const SizedBox(height: 2),
      ),
      Expanded(
        child: NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            _userScrolled = DateTime.now();
            return false;
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, Space.xxl),
            itemCount: ctl.chapters.length,
            itemBuilder: (context, i) => KeyedSubtree(
              key: _keys.putIfAbsent(i, GlobalKey.new),
              child: _ChapterRow(
                ctl: ctl,
                chapter: ctl.chapters[i],
                number: i + 1,
                state: i < _current ? _Pass.past : i == _current ? _Pass.now : _Pass.ahead,
                first: i == 0,
                last: i == ctl.chapters.length - 1,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

enum _Pass { past, now, ahead }

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.ctl, required this.chapter, required this.number, required this.state, required this.first, required this.last});
  final LecturePlayer ctl;
  final Chapter chapter;
  final int number;
  final _Pass state;
  final bool first, last;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = state == _Pass.now;
    final rail = state == _Pass.ahead ? cs.outlineVariant : cs.primary;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The rail: a line through every chapter, a node per chapter.
        SizedBox(
          width: 36,
          child: Column(children: [
            Container(width: 2, height: 14, color: first ? Colors.transparent : (state == _Pass.ahead ? cs.outlineVariant : cs.primary)),
            AnimatedContainer(
              duration: Motion.medium2,
              curve: Motion.emphasized,
              width: now ? 24 : 20,
              height: now ? 24 : 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: now ? cs.primary : state == _Pass.past ? cs.primaryContainer : cs.surface,
                border: state == _Pass.ahead ? Border.all(color: cs.outlineVariant, width: 1.5) : null,
              ),
              child: Text('$number',
                  style: tt.labelSmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: now ? cs.onPrimary : state == _Pass.past ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  )),
            ),
            Expanded(child: Container(width: 2, color: last ? Colors.transparent : rail == cs.primary && now ? cs.outlineVariant : rail)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: AnimatedContainer(
              duration: Motion.medium2,
              curve: Motion.emphasized,
              decoration: BoxDecoration(color: now ? cs.secondaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(Corners.lg)),
              child: InkWell(
                borderRadius: BorderRadius.circular(Corners.lg),
                onTap: () => ctl.seekTo(chapter.startMs),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.md, 10, Space.md, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(chapter.title,
                        style: (now ? tt.titleSmall : tt.bodyLarge)?.copyWith(
                          color: now ? cs.onSecondaryContainer : state == _Pass.past ? cs.onSurfaceVariant : cs.onSurface,
                          height: 1.35,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      '${fmtClock(chapter.startMs)} – ${fmtClock(chapter.endMs)} · ${_mins(chapter.endMs - chapter.startMs)}',
                      style: tt.labelSmall?.copyWith(color: now ? cs.onSecondaryContainer : cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    if (now)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: ValueListenableBuilder(
                          valueListenable: ctl.position,
                          builder: (_, p, _) {
                            final span = (chapter.endMs - chapter.startMs).clamp(1, 1 << 40);
                            return LinearProgressIndicator(
                              value: ((p.inMilliseconds - chapter.startMs) / span).clamp(0.0, 1.0),
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                              backgroundColor: cs.onSecondaryContainer.withValues(alpha: 0.12),
                            );
                          },
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  static String _mins(int ms) {
    final m = (ms / 60000).round();
    return m < 1 ? l10n.durationUnderMinute : l10n.durationMinutes(m);
  }
}

/// Placeholder while the model writes the outline.
class _Drafting extends StatefulWidget {
  const _Drafting();
  @override
  State<_Drafting> createState() => _DraftingState();
}

class _DraftingState extends State<_Drafting> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const widths = [0.72, 0.55, 0.8, 0.62, 0.7, 0.5];
    return ListView(padding: const EdgeInsets.all(Space.lg), children: [
      Text(l10n.outlineWorking, style: tt.titleSmall),
      const SizedBox(height: 2),
      Text(l10n.outlineWorkingHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Space.xl),
      FadeTransition(
        opacity: Tween(begin: 0.35, end: 0.9).animate(CurvedAnimation(parent: _pulse, curve: Motion.standard)),
        child: Column(children: [
          for (final w in widths)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.lg),
              child: Row(children: [
                Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surfaceContainerHighest)),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: w,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(height: 14, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(7))),
                      const SizedBox(height: 6),
                      Container(height: 10, width: 72, decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(5))),
                    ]),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}
