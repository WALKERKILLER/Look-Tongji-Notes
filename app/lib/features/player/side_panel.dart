import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../theme/prefs.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../courses/download_sheet.dart';
import '../library/note_editor.dart';
import '../courseware/courseware.dart';
import '../schedule/schedule_store.dart';
import '../schedule/schedule_widgets.dart';
import 'lecture_player.dart';
import 'outline_tab.dart';
import 'player_page.dart';
import '../library/note_reader.dart';
import '../practice/quiz.dart';
import '../../widgets/look_markdown.dart';

/// Outline / transcript / materials / notes (and the assistant) beside or
/// below the video.
class PlayerSidePanel extends StatefulWidget {
  const PlayerSidePanel({super.key, required this.ctl, this.onAsk, this.assistant});
  final LecturePlayer ctl;

  /// Embedded assistant shown as the last tab.
  final Widget? assistant;

  /// Hands a prompt to the assistant.
  final ValueChanged<String>? onAsk;

  @override
  State<PlayerSidePanel> createState() => _PlayerSidePanelState();
}

class _PlayerSidePanelState extends State<PlayerSidePanel> with SingleTickerProviderStateMixin {
  static const _names = ['outline', 'transcript', 'materials', 'notes', 'assistant'];
  late final _tabs = TabController(length: widget.assistant == null ? 4 : 5, vsync: this);

  @override
  void initState() {
    super.initState();
    widget.ctl.panelTab.addListener(_onRequest);
  }

  void _onRequest() {
    final i = _names.indexOf(widget.ctl.panelTab.value ?? '');
    if (i >= 0 && i < _tabs.length) _tabs.animateTo(i);
    widget.ctl.panelTab.value = null;
  }

  void _ask(String text) {
    if (widget.assistant != null) _tabs.animateTo(4);
    widget.onAsk?.call(text);
  }

  @override
  void dispose() {
    widget.ctl.panelTab.removeListener(_onRequest);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = widget.ctl;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    String count(String label, int n) => n == 0 ? label : '$label $n';
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, Space.xs, Space.sm, Space.xs),
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(Corners.full)),
            indicatorPadding: const EdgeInsets.symmetric(vertical: 6),
            labelColor: cs.onSecondaryContainer,
            unselectedLabelColor: cs.onSurfaceVariant,
            labelStyle: tt.labelLarge,
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            splashBorderRadius: BorderRadius.circular(Corners.full),
            overlayColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? cs.onSurface.withValues(alpha: 0.06) : null),
            tabs: [
              Tab(text: count('大纲', ctl.chapters.length), height: 44),
              const Tab(text: '文字稿', height: 44),
              Tab(text: count('资料', ctl.slides.length + ctl.courseware.length), height: 44),
              Tab(text: count('笔记', ctl.notes.length + ctl.bookmarks.length), height: 44),
              if (widget.assistant != null) const Tab(text: '助手', height: 44),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            OutlineTab(ctl: ctl),
            _TranscriptTab(ctl: ctl, onAsk: widget.onAsk == null ? null : _ask),
            _MaterialsTab(ctl: ctl),
            _NotesTab(ctl: ctl, onAsk: widget.onAsk == null ? null : _ask),
            ?widget.assistant,
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- materials

/// Platform slides and user-uploaded courseware under one tab.
class _MaterialsTab extends StatefulWidget {
  const _MaterialsTab({required this.ctl});
  final LecturePlayer ctl;
  @override
  State<_MaterialsTab> createState() => _MaterialsTabState();
}

class _MaterialsTabState extends State<_MaterialsTab> with AutomaticKeepAliveClientMixin {
  bool? _slides;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ctl = widget.ctl;
    final slides = _slides ?? (ctl.slides.isNotEmpty || ctl.courseware.isEmpty);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, 0),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity(vertical: -2)),
            segments: [
              ButtonSegment(value: true, icon: const Icon(Icons.slideshow_outlined, size: 18), label: Text(ctl.slides.isEmpty ? 'PPT 截图' : 'PPT 截图 ${ctl.slides.length}')),
              ButtonSegment(value: false, icon: const Icon(Icons.description_outlined, size: 18), label: Text(ctl.courseware.isEmpty ? '课件' : '课件 ${ctl.courseware.length}')),
            ],
            selected: {slides},
            onSelectionChanged: (v) => setState(() => _slides = v.first),
          ),
        ),
      ),
      Expanded(
        child: AnimatedSwitcher(
          duration: Motion.medium2,
          switchInCurve: Motion.emphasizedDecelerate,
          child: slides
              ? _SlidesTab(key: const ValueKey('ppt'), ctl: ctl)
              : CoursewareList(key: const ValueKey('cw'), lectureId: ctl.lectureId, files: ctl.courseware, onChanged: ctl.reloadCourseware),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- slides

class _SlidesTab extends StatefulWidget {
  const _SlidesTab({super.key, required this.ctl});
  final LecturePlayer ctl;
  @override
  State<_SlidesTab> createState() => _SlidesTabState();
}

class _SlidesTabState extends State<_SlidesTab> with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  bool _keyOnly = true;
  int _current = -1;
  double _extent = 200;
  DateTime _userScrolled = DateTime(0);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.ctl.position.addListener(_onPos);
  }

  @override
  void dispose() {
    widget.ctl.position.removeListener(_onPos);
    _scroll.dispose();
    super.dispose();
  }

  List<Slide> get _list => _keyOnly && widget.ctl.slides.any((s) => s.isKey) ? widget.ctl.slides.where((s) => s.isKey).toList() : widget.ctl.slides;

  int _indexAt(int ms) {
    final l = _list;
    var ans = -1;
    for (var i = 0; i < l.length; i++) {
      if (l[i].tSec * 1000 <= ms) {
        ans = i;
      } else {
        break;
      }
    }
    return ans;
  }

  void _onPos() {
    final i = _indexAt(widget.ctl.positionMs);
    if (i == _current) return;
    setState(() => _current = i);
    final follow = context.read<UiPrefs>().slideFollow;
    if (follow && i >= 0 && _scroll.hasClients && DateTime.now().difference(_userScrolled) > const Duration(seconds: 4)) {
      final target = (i * _extent - _scroll.position.viewportDimension * 0.3).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(target, duration: Motion.long2, curve: Motion.emphasized);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ctl = widget.ctl;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final prefs = context.watch<UiPrefs>();
    final list = _list;
    if (ctl.slides.isEmpty) {
      return EmptyState(
        icon: Icons.slideshow_outlined,
        title: '这节课没有 PPT 截图',
        body: '平台只在老师投屏时生成截图',
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
        child: Row(children: [
          FilterChip(label: const Text('仅换页'), selected: _keyOnly, onSelected: (v) => setState(() => _keyOnly = v)),
          const SizedBox(width: Space.sm),
          FilterChip(
            label: const Text('跟随播放'),
            selected: prefs.slideFollow,
            onSelected: (v) => prefs.update((p) => p.slideFollow = v),
          ),
          const Spacer(),
          if (!ctl.slides.any((s) => s.path.isNotEmpty))
            IconButton(
              tooltip: '下载 PPT',
              onPressed: () => showDownloadSheet(context, [ctl.lectureId], title: ctl.lecture?.shortTitle),
              icon: const Icon(Icons.download_outlined),
            ),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth - Space.md * 2;
          _extent = w * 9 / 16 + 34 + Space.md;
          return NotificationListener<UserScrollNotification>(
            onNotification: (_) {
              _userScrolled = DateTime.now();
              return false;
            },
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(Space.md),
              itemExtent: _extent,
              itemCount: list.length,
              itemBuilder: (context, i) {
                final s = list[i];
                final on = i == _current;
                return Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Corners.lg),
                    onTap: () => ctl.seekTo(s.tSec * 1000),
                    onDoubleTap: () => _openViewer(context, list, i),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AnimatedContainer(
                        duration: Motion.medium2,
                        curve: Motion.emphasized,
                        padding: EdgeInsets.all(on ? 3 : 0),
                        decoration: BoxDecoration(
                          color: on ? cs.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(Corners.lg),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(on ? Corners.md : Corners.lg),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              ctl.slideUrl(s),
                              headers: ctl.media?.headers,
                              fit: BoxFit.cover,
                              cacheWidth: (w * MediaQuery.devicePixelRatioOf(context)).round(),
                              frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
                                opacity: frame == null && !sync ? 0 : 1,
                                duration: Motion.medium1,
                                child: child,
                              ),
                              errorBuilder: (_, _, _) => ColoredBox(color: cs.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text('第 ${s.idx} 张', style: tt.labelMedium?.copyWith(color: on ? cs.primary : cs.onSurfaceVariant)),
                        const Spacer(),
                        Text(fmtClock(s.tSec * 1000), style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          );
        }),
      ),
    ]);
  }

  void _openViewer(BuildContext context, List<Slide> list, int start) {
    final ctl = widget.ctl;
    final page = PageController(initialPage: start);
    var cur = start;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.black87,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => page.nextPage(duration: Motion.medium2, curve: Motion.emphasized),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => page.previousPage(duration: Motion.medium2, curve: Motion.emphasized),
          },
          child: Focus(
            autofocus: true,
            child: Dialog.fullscreen(
              backgroundColor: Colors.transparent,
              child: Stack(children: [
                PageView.builder(
                  controller: page,
                  itemCount: list.length,
                  onPageChanged: (i) => set(() => cur = i),
                  itemBuilder: (_, i) => InteractiveViewer(
                    maxScale: 5,
                    child: Center(child: Image.network(ctl.slideUrl(list[i]), headers: ctl.media?.headers, fit: BoxFit.contain)),
                  ),
                ),
                Positioned(
                  top: Space.lg,
                  right: Space.lg,
                  child: IconButton.filledTonal(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ),
                Positioned(
                  bottom: Space.xl,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton.filledTonal(onPressed: () => page.previousPage(duration: Motion.medium2, curve: Motion.emphasized), icon: const Icon(Icons.chevron_left_rounded)),
                      const SizedBox(width: Space.md),
                      FilledButton.icon(
                        onPressed: () {
                          ctl.seekTo(list[cur].tSec * 1000);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text('${cur + 1} / ${list.length} · 从 ${fmtClock(list[cur].tSec * 1000)} 播放'),
                      ),
                      const SizedBox(width: Space.md),
                      IconButton.filledTonal(onPressed: () => page.nextPage(duration: Motion.medium2, curve: Motion.emphasized), icon: const Icon(Icons.chevron_right_rounded)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- transcript

class _TranscriptTab extends StatefulWidget {
  const _TranscriptTab({required this.ctl, this.onAsk});
  final LecturePlayer ctl;
  final ValueChanged<String>? onAsk;
  @override
  State<_TranscriptTab> createState() => _TranscriptTabState();
}

class _TranscriptTabState extends State<_TranscriptTab> with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final _q = TextEditingController();
  final _keys = <int, GlobalKey>{};
  int _current = -1;
  bool _follow = true;
  DateTime _userScrolled = DateTime(0);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.ctl.position.addListener(_onPos);
  }

  @override
  void dispose() {
    widget.ctl.position.removeListener(_onPos);
    _scroll.dispose();
    _q.dispose();
    super.dispose();
  }

  void _onPos() {
    final i = widget.ctl.segmentAt(widget.ctl.positionMs);
    if (i == _current) return;
    setState(() => _current = i);
    if (!_follow || i < 0 || _q.text.isNotEmpty || DateTime.now().difference(_userScrolled) < const Duration(seconds: 5)) return;
    _reveal(i);
  }

  void _reveal(int i) {
    final ctx = _keys[i]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.3, duration: Motion.long2, curve: Motion.emphasized);
      return;
    }
    if (!_scroll.hasClients) return;
    // Not built yet: jump near it by estimate, then align precisely.
    final est = (i * 52.0).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(est);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys[i]?.currentContext;
      if (c != null) Scrollable.ensureVisible(c, alignment: 0.3);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ctl = widget.ctl;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (ctl.segments.isEmpty) {
      return EmptyState(
        icon: Icons.subject_rounded,
        title: '还没有文字稿',
        body: '转写会提取音频并生成带时间戳的文字，之后可以搜索、做字幕，也能让助手整理笔记。',
        action: FilledButton.tonalIcon(
          onPressed: () async {
            await context.read<AppState>().enqueue([ctl.lectureId], ['transcript']);
            if (context.mounted) showSnack(context, '已加入转写队列，完成后自动显示');
          },
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('开始转写'),
        ),
      );
    }
    final q = _q.text.trim();
    final marks = <int, List<ScheduleItem>>{};
    for (final it in context.watch<ScheduleStore>().forLecture(ctl.lectureId)) {
      if (it.tMs < 0) continue;
      final i = ctl.segmentAt(it.tMs);
      if (i >= 0) (marks[i] ??= []).add(it);
    }
    // Index of the segment that opens each chapter.
    final heads = <int, Chapter>{};
    if (q.isEmpty) {
      var seg = 0;
      for (final c in ctl.chapters) {
        while (seg < ctl.segments.length && ctl.segments[seg].endMs <= c.startMs) {
          seg++;
        }
        if (seg < ctl.segments.length) heads.putIfAbsent(seg, () => c);
      }
    }
    final idx = <int>[
      for (var i = 0; i < ctl.segments.length; i++)
        if (q.isEmpty || ctl.segments[i].text.contains(q)) i,
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, 0),
        child: Row(children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '在文字稿中查找',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.full), borderSide: BorderSide.none),
                  suffixText: q.isEmpty ? null : '${idx.length} 处',
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _follow ? '跟随播放：开' : '跟随播放：关',
            isSelected: _follow,
            onPressed: () {
              setState(() => _follow = !_follow);
              if (_follow && _current >= 0) _reveal(_current);
            },
            icon: const Icon(Icons.my_location_outlined),
            selectedIcon: const Icon(Icons.my_location_rounded),
          ),
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: ctl.segments.map((s) => '[${fmtClock(s.startMs)}] ${s.text}').join('\n')));
                  showSnack(context, '已复制全文');
                },
                child: const Text('复制全文'),
              ),
              if (widget.onAsk != null) ...[
                MenuItemButton(
                  leadingIcon: const Icon(Icons.auto_awesome_outlined),
                  onPressed: () => widget.onAsk!('请为这节课整理一份完整的学习笔记并保存：以字幕为主，找出重点和不确定的地方，对照当时的 PPT 和已上传的课件核实，公式用 LaTeX，要点附时间戳。'),
                  child: const Text('让助手整理笔记'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.quiz_outlined),
                  onPressed: () => showQuizSheet(context, lectureId: ctl.lectureId, onAsk: widget.onAsk!),
                  child: const Text('出题练习…'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.summarize_outlined),
                  onPressed: () => widget.onAsk!('用几句话概括我刚才看的这一段（当前播放位置前 5 分钟）讲了什么。'),
                  child: const Text('概括刚才这段'),
                ),
              ],
            ],
            builder: (context, m, _) => IconButton(onPressed: () => m.isOpen ? m.close() : m.open(), icon: const Icon(Icons.more_vert_rounded)),
          ),
        ]),
      ),
      Expanded(
        child: NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            _userScrolled = DateTime.now();
            return false;
          },
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, Space.xxl),
              itemCount: idx.length,
              itemBuilder: (context, k) {
                final i = idx[k];
                final s = ctl.segments[i];
                final on = i == _current;
                final head = heads[i];
                final row = KeyedSubtree(
                  key: _keys.putIfAbsent(i, GlobalKey.new),
                  child: AnimatedContainer(
                    duration: Motion.medium1,
                    curve: Motion.emphasized,
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: on ? cs.secondaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(Corners.md),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Corners.md),
                      onTap: () => ctl.seekTo(s.startMs),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 52,
                            child: Text(fmtClock(s.startMs),
                                style: tt.labelSmall?.copyWith(color: on ? cs.onSecondaryContainer : cs.primary, fontFeatures: const [FontFeature.tabularFigures()], height: 1.9)),
                          ),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _Highlighted(text: s.text, q: q, style: tt.bodyMedium!.copyWith(height: 1.55, color: on ? cs.onSecondaryContainer : cs.onSurface)),
                              for (final it in marks[i] ?? const <ScheduleItem>[]) _MarkChip(item: it),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                );
                if (head == null) return row;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _ChapterHeader(chapter: head, first: i == 0, onTap: () => ctl.panelTab.value = 'outline'),
                  row,
                ]);
              },
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Chapter title woven into the transcript.
class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({required this.chapter, required this.first, required this.onTap});
  final Chapter chapter;
  final bool first;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.sm, first ? Space.xs : Space.lg, Space.sm, Space.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(Corners.sm),
        onTap: onTap,
        child: Row(children: [
          Text('${chapter.idx + 1}'.padLeft(2, '0'), style: tt.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleSmall?.copyWith(color: cs.primary))),
        ]),
      ),
    );
  }
}

/// A schedule item the teacher mentioned at this line.
class _MarkChip extends StatelessWidget {
  const _MarkChip({required this.item});
  final ScheduleItem item;
  @override
  Widget build(BuildContext context) {
    final st = KindStyle.of(context, item.kind);
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs, bottom: 2),
      child: Material(
        color: st.container,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showScheduleEditor(context, item: item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(item.done ? Icons.check_rounded : st.icon, size: 14, color: st.onContainer),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${st.label} · ${item.title} · ${fmtDue(item)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.labelSmall?.copyWith(color: st.onContainer)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.q, required this.style});
  final String text, q;
  final TextStyle style;
  @override
  Widget build(BuildContext context) {
    if (q.isEmpty) return Text(text, style: style);
    final cs = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    var at = 0;
    while (true) {
      final i = text.indexOf(q, at);
      if (i < 0) break;
      if (i > at) spans.add(TextSpan(text: text.substring(at, i)));
      spans.add(TextSpan(text: q, style: TextStyle(backgroundColor: cs.tertiaryContainer, color: cs.onTertiaryContainer)));
      at = i + q.length;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}

// ---------------------------------------------------------------- notes

class _NotesTab extends StatefulWidget {
  const _NotesTab({required this.ctl, this.onAsk});
  final LecturePlayer ctl;
  final ValueChanged<String>? onAsk;
  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab> with AutomaticKeepAliveClientMixin {
  Note? _editing;
  bool _new = false;
  bool _write = false;
  StreamSubscription? _sub;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ctl = widget.ctl;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    void seek(TimeRef t) {
      if (t.lectureId.isEmpty || t.lectureId == ctl.lectureId) {
        ctl.seekTo(t.seconds * 1000);
      } else {
        seekOrOpen(context, t.lectureId, t.seconds);
      }
    }

    if (_editing != null && !_write) {
      return NoteInlineReader(
        key: ValueKey(_editing!.id),
        note: _editing!,
        onSeek: seek,
        onBack: () => setState(() => _editing = null),
        onEdit: () => setState(() => _write = true),
      );
    }
    if (_editing != null || _new) {
      return Padding(
        padding: const EdgeInsets.all(Space.md),
        child: NoteEditor(
          key: ValueKey(_editing?.id ?? 'new'),
          note: _editing,
          courseId: ctl.lecture?.courseId ?? '',
          lectureId: ctl.lectureId,
          timestamp: () => ctl.positionMs,
          onSeek: seek,
          edit: true,
          onSaved: (n) {
            ctl.reloadNotes();
            if (_editing != null) _editing = n;
          },
          onClose: () => setState(() {
            if (_editing == null) _new = false;
            _write = false;
          }),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.all(Space.md), children: [
      Row(children: [
        Text('书签', style: tt.titleSmall),
        const Spacer(),
        TextButton.icon(onPressed: () => ctl.addBookmark(), icon: const Icon(Icons.bookmark_add_outlined, size: 18), label: const Text('当前位置')),
      ]),
      if (ctl.bookmarks.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Text('按 B 键或点播放器上的书签按钮标记重点', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
      for (final b in ctl.bookmarks)
        ListTile(
          contentPadding: const EdgeInsets.only(left: Space.sm),
          leading: ActionChip(label: Text(fmtClock(b.tMs)), onPressed: () => ctl.seekTo(b.tMs)),
          title: Text(b.label.isEmpty ? _snippetAt(ctl, b.tMs) : b.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodyMedium),
          trailing: IconButton(onPressed: () => ctl.deleteBookmark(b), icon: const Icon(Icons.close_rounded, size: 18)),
          onTap: () => ctl.seekTo(b.tMs),
        ),
      const SizedBox(height: Space.lg),
      Row(children: [
        Text('笔记', style: tt.titleSmall),
        const Spacer(),
        FilledButton.tonalIcon(onPressed: () => setState(() => _new = true), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('新建')),
      ]),
      const SizedBox(height: Space.sm),
      if (ctl.notes.isEmpty) Text('笔记以 Markdown 文件保存在课程库中，助手也能读取', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      for (final n in ctl.notes)
        Card(
          color: cs.surfaceContainerHigh,
          child: ListTile(
            leading: Icon(n.source == 'agent' ? Icons.auto_awesome_outlined : Icons.description_outlined),
            title: Text(n.title),
            subtitle: Text(fmtRelative(DateTime.fromMillisecondsSinceEpoch(n.updatedAt * 1000))),
            onTap: () async {
              final full = await ctl.api.get('/api/notes/${n.id}');
              if (mounted) {
                setState(() {
                  _editing = Note((full as Map).cast<String, dynamic>());
                  _write = false;
                });
              }
            },
          ),
        ),
      const SizedBox(height: Space.lg),
      Row(children: [
        Text('练习', style: tt.titleSmall),
        const Spacer(),
        if (widget.onAsk != null)
          FilledButton.tonalIcon(
            onPressed: () => showQuizSheet(context, lectureId: ctl.lectureId, onAsk: widget.onAsk!),
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('出题'),
          ),
      ]),
      const SizedBox(height: Space.sm),
      QuizList(
        lectureId: ctl.lectureId,
        empty: Text('让助手根据这节课出一组选择题，每题附解析和出处', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ),
    ]);
  }

  String _snippetAt(LecturePlayer ctl, int ms) {
    final i = ctl.segmentAt(ms);
    return i >= 0 ? ctl.segments[i].text : '书签';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
