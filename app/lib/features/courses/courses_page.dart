import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/prefs.dart';
import '../../theme/tokens.dart';
import '../../widgets/horizontal_scroller.dart';
import '../../widgets/states.dart';
import 'course_card.dart';
import 'course_page.dart';
import '../../l10n/l10n.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  final _q = TextEditingController();
  String? _term; // null = latest term, '' = all
  bool _showHidden = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final compact = context.isCompact;
    final pad = compact ? Space.lg : Space.xl;

    final terms = app.courses.map((c) => c.term).toSet().toList()..sort((a, b) => b.compareTo(a));
    final term = _term ?? (terms.isEmpty ? '' : terms.first);
    final q = _q.text.trim().toLowerCase();
    final list = app.courses.where((c) {
      if (term.isNotEmpty && c.term != term) return false;
      if (c.hidden && !_showHidden) return false;
      if (q.isEmpty) return true;
      return c.title.toLowerCase().contains(q) || c.rawTitle.toLowerCase().contains(q) || c.teacher.contains(q) || c.teachers.any((t) => t.contains(q));
    }).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.lastLearnAt.compareTo(a.lastLearnAt);
      });
    final hiddenCount = app.courses.where((c) => c.hidden && (term.isEmpty || c.term == term)).length;

    return RefreshIndicator(
      onRefresh: () => app.loadCourses(sync: true),
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: ContentWidth(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, compact ? Space.xl : Space.xxl, pad, Space.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(l10n.commonCourses, style: compact ? tt.headlineMedium : tt.displaySmall)),
                  IconButton(
                    tooltip: l10n.coursesSync,
                    onPressed: app.coursesLoading ? null : () => app.loadCourses(sync: true),
                    icon: app.coursesLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Icon(Icons.sync_rounded),
                  ),
                ]),
                const SizedBox(height: Space.lg),
                SearchBar(
                  controller: _q,
                  hintText: l10n.coursesSearchHint,
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    if (_q.text.isNotEmpty)
                      IconButton(onPressed: () => setState(_q.clear), icon: const Icon(Icons.close_rounded)),
                  ],
                  onChanged: (_) => setState(() {}),
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
                ),
                const SizedBox(height: Space.md),
                HorizontalScroller(fade: true, builder: (c) => SingleChildScrollView(
                  controller: c,
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final t in terms) ...[
                      ChoiceChip(
                        label: Text(Course({'term': t}).termLabel),
                        selected: term == t,
                        onSelected: (_) => setState(() => _term = t),
                      ),
                      const SizedBox(width: Space.sm),
                    ],
                    ChoiceChip(label: Text(l10n.coursesAllTerms), selected: term.isEmpty, onSelected: (_) => setState(() => _term = '')),
                    if (hiddenCount > 0) ...[
                      const SizedBox(width: Space.sm),
                      FilterChip(
                        label: Text(l10n.coursesHiddenCount(hiddenCount)),
                        selected: _showHidden,
                        onSelected: (v) => setState(() => _showHidden = v),
                      ),
                    ],
                  ]),
                )),
              ]),
            ),
          ),
        ),
        if (app.coursesLoading && app.courses.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: CenteredLoader(label: l10n.coursesSyncing))
        else if (app.coursesError != null && app.courses.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: ErrorState(error: app.coursesError!, onRetry: () => app.loadCourses(sync: true)))
        else if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(icon: Icons.search_off_rounded, title: q.isEmpty ? l10n.coursesEmptyTerm : l10n.coursesNoMatch(_q.text)),
          )
        else
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, Space.sm, pad, Space.huge),
                child: LayoutBuilder(builder: (context, c) {
                  final cols = (c.maxWidth / 280).floor().clamp(1, 4);
                  final w = (c.maxWidth - Space.md * (cols - 1)) / cols;
                  return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
                    for (final course in list)
                      SizedBox(
                        key: ValueKey(course.id),
                        width: w,
                        child: AnimatedOpacity(
                          opacity: course.hidden ? 0.55 : 1,
                          duration: Motion.medium1,
                          child: CourseCard(
                            course: course,
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoursePage(courseId: course.id))),
                            onMenu: (pos) => showCourseMenu(context, course, pos),
                          ),
                        ),
                      ),
                  ]);
                }),
              ),
            ),
          ),
      ]),
    );
  }
}

Future<void> showCourseMenu(BuildContext context, Course c, Offset pos) async {
  final app = context.read<AppState>();
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(pos & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      PopupMenuItem(value: 'pin', child: ListTile(leading: Icon(c.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded), title: Text(c.pinned ? l10n.coursesUnpin : l10n.coursesPin))),
      PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text(l10n.commonRename))),
      PopupMenuItem(value: 'color', child: ListTile(leading: Icon(Icons.palette_outlined), title: Text(l10n.coursesColor))),
      PopupMenuItem(value: 'hide', child: ListTile(leading: Icon(c.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined), title: Text(c.hidden ? l10n.coursesUnhide : l10n.commonHide))),
    ],
  );
  if (!context.mounted || v == null) return;
  switch (v) {
    case 'pin':
      await app.patchCourse(c.id, {'pinned': !c.pinned});
    case 'hide':
      await app.patchCourse(c.id, {'hidden': !c.hidden});
    case 'rename':
      final name = await _renameDialog(context, c);
      if (name != null) await app.patchCourse(c.id, {'alias': name});
    case 'color':
      final color = await _colorDialog(context, c);
      if (color != null) await app.patchCourse(c.id, {'color': color});
  }
}

Future<String?> _renameDialog(BuildContext context, Course c) {
  final ctl = TextEditingController(text: c.alias);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.edit_outlined),
      title: Text(l10n.coursesRenameTitle),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.coursesOriginalName(c.rawTitle), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Space.md),
        TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.coursesDisplayName, helperText: l10n.coursesDisplayNameHelper),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
        FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: Text(l10n.commonSave)),
      ],
    ),
  );
}

Future<String?> _colorDialog(BuildContext context, Course c) {
  String hex(Color col) => '#${(col.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.coursesColor),
      content: Wrap(spacing: Space.md, runSpacing: Space.md, children: [
        _Swatch(color: null, selected: c.color.isEmpty, onTap: () => Navigator.pop(context, '')),
        for (final (_, col) in kSeedPalette)
          _Swatch(color: col, selected: c.color.toUpperCase() == hex(col), onTap: () => Navigator.pop(context, hex(col))),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel))],
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: Motion.short4,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color ?? cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(selected ? Corners.md : 22),
          border: Border.all(color: selected ? cs.onSurface : Colors.transparent, width: 2),
        ),
        child: color == null ? Icon(Icons.auto_awesome_outlined, size: 18, color: cs.onSurfaceVariant) : (selected ? const Icon(Icons.check_rounded, color: Colors.white) : null),
      ),
    );
  }
}
