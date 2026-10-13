import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/course_visuals.dart';
import '../../widgets/report_screen.dart';
import '../../widgets/states.dart';
import '../player/player_page.dart';
import 'note_reader.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Hit>? _hits;
  bool _searching = false;
  String _kind = '';
  String _courseId = '';
  List<Note> _notes = [];
  Map<String, dynamic>? _lib;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<AppState>().events.listen((e) {
      if (e['type'] == 'notes_changed' || e['type'] == 'lecture_changed') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    try {
      final ns = jsonList(await api.get('/api/notes'));
      final lib = await api.get('/api/library') as Map;
      if (!mounted) return;
      setState(() {
        _notes = ns.map((e) => Note((e as Map).cast<String, dynamic>())).toList();
        _lib = lib.cast<String, dynamic>();
      });
    } catch (_) {}
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _search);
    setState(() {});
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() => _hits = null);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = jsonList(await context.read<AppState>().api.get('/api/search', {'q': q, 'limit': '120', if (_courseId.isNotEmpty) 'course_id': _courseId}));
      if (!mounted || _q.text.trim() != q) return;
      setState(() => _hits = r.map((e) => Hit((e as Map).cast<String, dynamic>())).toList());
    } catch (e) {
      if (mounted) showSnack(context, '搜索失败：$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openNote(Note? n) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotePage(noteId: n?.id)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final compact = context.isCompact;
    final pad = compact ? Space.lg : Space.xl;
    final hits = _hits?.where((h) => _kind.isEmpty || h.kind == _kind).toList();
    final courses = app.courses.where((c) => c.localLectures > 0 || _notes.any((n) => n.courseId == c.id)).toList();

    return ReportScreen(
      value: const {'screen': '资料库'},
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () => _openNote(null),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('写笔记'),
        ),
        body: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, compact ? Space.xl : Space.xxl, pad, Space.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('资料库', style: compact ? tt.headlineMedium : tt.displaySmall),
                  const SizedBox(height: Space.xs),
                  Text('全文搜索所有文字稿与笔记', style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: Space.lg),
                  SearchBar(
                    controller: _q,
                    hintText: '例如：傅里叶变换、期中、作业',
                    leading: _searching
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Icon(Icons.manage_search_rounded),
                    trailing: [
                      if (_q.text.isNotEmpty)
                        IconButton(
                          onPressed: () {
                            _q.clear();
                            setState(() => _hits = null);
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                    onChanged: _onQuery,
                    onSubmitted: (_) => _search(),
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
                  ),
                  const SizedBox(height: Space.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final (k, l) in const [('', '全部'), ('segment', '文字稿'), ('note', '笔记')]) ...[
                        ChoiceChip(label: Text(l), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
                        const SizedBox(width: Space.sm),
                      ],
                      if (courses.isNotEmpty)
                        MenuAnchor(
                          menuChildren: [
                            MenuItemButton(
                              onPressed: () {
                                setState(() => _courseId = '');
                                _search();
                              },
                              child: const Text('所有课程'),
                            ),
                            for (final c in courses)
                              MenuItemButton(
                                onPressed: () {
                                  setState(() => _courseId = c.id);
                                  _search();
                                },
                                child: Text(c.title),
                              ),
                          ],
                          builder: (context, m, _) => FilterChip(
                            avatar: const Icon(Icons.school_outlined, size: 18),
                            label: Text(_courseId.isEmpty ? '所有课程' : app.course(_courseId)?.title ?? '课程'),
                            selected: _courseId.isNotEmpty,
                            onSelected: (_) => m.isOpen ? m.close() : m.open(),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          if (hits != null) ..._results(context, hits, pad) else ..._overview(context, pad),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ]),
      ),
    );
  }

  List<Widget> _results(BuildContext context, List<Hit> hits, double pad) {
    if (hits.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(icon: Icons.search_off_rounded, title: '没有找到“${_q.text.trim()}”', body: '只有转写过的课和笔记可以被搜索。'),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: ContentWidth(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, Space.sm, pad, Space.sm),
            child: Text('${hits.length} 条结果', style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
      ),
      SliverList.builder(
        itemCount: hits.length,
        itemBuilder: (context, i) => ContentWidth(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 2),
            child: _HitTile(
              hit: hits[i],
              onTap: () {
                final h = hits[i];
                if (h.kind == 'note') {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotePage(noteId: h.noteId)));
                } else {
                  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: h.lectureId, startMs: h.startMs)));
                }
              },
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _overview(BuildContext context, double pad) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final app = context.read<AppState>();
    final st = (_lib?['stats'] as Map?) ?? {};
    return [
      SliverToBoxAdapter(
        child: ContentWidth(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, Space.lg, pad, Space.sm),
            child: Text('笔记 · ${_notes.length}', style: tt.titleLarge),
          ),
        ),
      ),
      if (_notes.isEmpty)
        SliverToBoxAdapter(
          child: ContentWidth(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Text('在播放器里边看边记，或让助手根据文字稿整理笔记。', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ),
        )
      else
        SliverToBoxAdapter(
          child: ContentWidth(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: LayoutBuilder(builder: (context, c) {
                final cols = (c.maxWidth / 300).floor().clamp(1, 3);
                final w = (c.maxWidth - Space.md * (cols - 1)) / cols;
                return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
                  for (final n in _notes)
                    SizedBox(
                      width: w,
                      child: Card(
                        margin: EdgeInsets.zero,
                        color: cs.surfaceContainer,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(Corners.md),
                          onTap: () => _openNote(n),
                          child: Padding(
                            padding: const EdgeInsets.all(Space.lg),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                _NoteMark(note: n, course: app.course(n.courseId)),
                                const SizedBox(width: Space.md),
                                Expanded(child: Text(n.title, style: tt.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                              ]),
                              const SizedBox(height: Space.sm),
                              Text(
                                [app.course(n.courseId)?.title ?? '未归类', fmtRelative(DateTime.fromMillisecondsSinceEpoch(n.updatedAt * 1000))].join(' · '),
                                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]);
              }),
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: ContentWidth(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, Space.xxl, pad, Space.sm),
            child: Text('课程库', style: tt.titleLarge),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: ContentWidth(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Card(
              margin: EdgeInsets.zero,
              color: cs.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: Space.xxl, runSpacing: Space.md, children: [
                    _Stat(value: '${st['local_lectures'] ?? 0}', label: '节课在本地'),
                    _Stat(value: fmtBytes((st['bytes'] ?? 0) as num), label: '占用空间'),
                    _Stat(value: '${st['segments'] ?? 0}', label: '句文字稿'),
                    _Stat(value: '${st['notes'] ?? 0}', label: '篇笔记'),
                  ]),
                  const SizedBox(height: Space.lg),
                  Text('每节课一个文件夹：video.mp4、slides/、courseware/、transcript.md/.srt、lecture.json。'
                      '根目录的 README.md 说明了结构，方便 AI 工具直接阅读；library.db 是可重建的索引。',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.6)),
                  const SizedBox(height: Space.lg),
                  Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                    FilledButton.tonalIcon(
                      onPressed: _lib == null ? null : () => openPath('${_lib!['root']}'),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('打开文件夹'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final r = await app.api.post('/api/library/reindex') as Map;
                          if (context.mounted) showSnack(context, '已重建索引，${r['indexed']} 节课');
                          _load();
                        } catch (e) {
                          if (context.mounted) showSnack(context, '重建失败：$e');
                        }
                      },
                      icon: const Icon(Icons.manage_history_rounded),
                      label: const Text('从文件重建索引'),
                    ),
                  ]),
                  const SizedBox(height: Space.sm),
                  Text('${_lib?['root'] ?? ''}', style: tt.labelSmall?.copyWith(color: cs.outline)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

/// Course organic badge with a small source marker (agent sparkle / own note).
class _NoteMark extends StatelessWidget {
  const _NoteMark({required this.note, required this.course});
  final Note note;
  final Course? course;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final agent = note.source == 'agent';
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(clipBehavior: Clip.none, children: [
        if (course != null)
          CourseGlyph(course: course!, size: 40)
        else
          Container(decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(Corners.md))),
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: cs.surfaceContainer, shape: BoxShape.circle),
            child: Icon(agent ? Icons.auto_awesome_rounded : Icons.edit_rounded, size: 12, color: agent ? cs.tertiary : cs.primary),
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: tt.headlineSmall?.copyWith(color: cs.primary)),
      Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.onTap});
  final Hit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final spans = <TextSpan>[];
    final re = RegExp('«(.*?)»');
    var at = 0;
    for (final m in re.allMatches(hit.snippet)) {
      if (m.start > at) spans.add(TextSpan(text: hit.snippet.substring(at, m.start)));
      spans.add(TextSpan(text: m[1], style: TextStyle(backgroundColor: cs.tertiaryContainer, color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)));
      at = m.end;
    }
    spans.add(TextSpan(text: hit.snippet.substring(at)));
    final note = hit.kind == 'note';
    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(Corners.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(note ? Icons.description_outlined : Icons.subject_rounded, color: cs.primary, size: 20),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: spans), style: tt.bodyMedium?.copyWith(height: 1.55)),
                const SizedBox(height: Space.xs),
                Text(
                  [hit.courseTitle, hit.lecture, if (!note) fmtClock(hit.startMs)].where((s) => s.isNotEmpty).join(' · '),
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ]),
            ),
            if (!note) Icon(Icons.play_circle_outline_rounded, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
