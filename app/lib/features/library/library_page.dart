import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/format.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/look_markdown.dart';
import '../../widgets/report_screen.dart';
import '../../widgets/states.dart';
import '../../l10n/l10n.dart';
import '../player/player_page.dart';
import '../practice/quiz.dart';
import 'note_reader.dart';
import '../../shell.dart';
import 'catalog_browser.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _q = TextEditingController();
  Timer? _debounce;
  StreamSubscription? _sub;
  List<Map<String, dynamic>>? _items;
  List<Hit>? _hits;
  Map<String, dynamic>? _library;
  String _courseId = '';
  String? _error;
  bool _searching = false;
  int _searchVersion = 0;
  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<AppState>().events.listen((e) {
      if (['notes_changed', 'lecture_changed'].contains(e['type'])) _load();
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
    try {
      final api = context.read<AppState>().api;
      final results = await Future.wait([
        api.libraryCatalog(),
        api.get('/api/library'),
      ]);
      final data = jsonList(results[0]);
      if (!mounted) return;
      setState(() {
        _items = data.map((i) => (i as Map).cast<String, dynamic>()).toList();
        _library = (results[1] as Map).cast<String, dynamic>();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _search() async {
    final version = ++_searchVersion;
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() {
        _hits = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final data = jsonList(
        await context.read<AppState>().api.get('/api/search', {
          'q': q,
          'limit': '120',
          if (_courseId.isNotEmpty) 'course_id': _courseId,
        }),
      );
      if (!mounted || version != _searchVersion) return;
      setState(
        () => _hits = data
            .map((e) => Hit((e as Map).cast<String, dynamic>()))
            .toList(),
      );
    } catch (e) {
      if (mounted && version == _searchVersion)
        showSnack(context, l10n.searchFailed(e));
    } finally {
      if (mounted && version == _searchVersion)
        setState(() => _searching = false);
    }
  }

  void _query(String _) {
    _searchVersion++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _search);
    setState(() {});
  }

  void _open(Map<String, dynamic> item) {
    if ('${item['note_id'] ?? ''}'.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NotePage(noteId: '${item['note_id']}'),
        ),
      );
    } else {
      openLibraryFile(context, '${item['path']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pad = context.isCompact ? Space.lg : Space.xl;
    Widget padded(Widget w) => ContentWidth(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: Space.md),
        child: w,
      ),
    );
    return ReportScreen(
      value: {'screen': l10n.screenLibrary},
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: PageFab(
          child: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const NotePage())),
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(l10n.libraryWriteNote),
          ),
        ),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: padded(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Space.lg),
                    Text(l10n.screenLibrary, style: tt.headlineLarge),
                    const SizedBox(height: Space.lg),
                    SearchBar(
                      controller: _q,
                      hintText: l10n.catalogSearchHint,
                      leading: _searching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.manage_search_rounded),
                      onChanged: _query,
                      onSubmitted: (_) => _search(),
                      trailing: [
                        if (_q.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _q.clear();
                              _query('');
                              _search();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: padded(
                  Column(
                    children: [
                      Text(l10n.catalogLoadFailed(_error!)),
                      TextButton(
                        onPressed: _load,
                        child: Text(l10n.commonRetry),
                      ),
                    ],
                  ),
                ),
              ),
            if (_items == null && _error == null)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            if (_items != null)
              SliverToBoxAdapter(
                child: padded(
                  CatalogBrowser(
                    items: _items!,
                    query: _q.text,
                    courseId: _courseId,
                    onCourse: (id) {
                      setState(() => _courseId = id);
                      _search();
                    },
                    onOpen: _open,
                  ),
                ),
              ),
            if (_q.text.trim().isNotEmpty && _hits != null) ...[
              SliverToBoxAdapter(
                child: padded(
                  Text(
                    l10n.catalogFulltextTitle(_hits!.length),
                    style: tt.titleLarge,
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: _hits!.length,
                itemBuilder: (context, i) => padded(
                  _HitTile(
                    hit: _hits![i],
                    onTap: () {
                      final h = _hits![i];
                      Navigator.of(
                        context,
                        rootNavigator: h.kind != 'note',
                      ).push(
                        MaterialPageRoute(
                          builder: (_) => h.kind == 'note'
                              ? NotePage(noteId: h.noteId)
                              : PlayerPage(
                                  lectureId: h.lectureId,
                                  startMs: h.startMs,
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (_q.text.trim().isEmpty)
              SliverToBoxAdapter(
                child: padded(
                  QuizList(
                    columns: context.isCompact ? 1 : 3,
                    header: Text(l10n.commonPractice, style: tt.titleLarge),
                  ),
                ),
              ),
            if (_library != null)
              SliverToBoxAdapter(
                child: padded(
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.libraryStatLocal, style: tt.titleSmall),
                          Text(
                            '${_library!['stats']?['local_lectures'] ?? 0} · ${fmtBytes((_library!['stats']?['bytes'] as num?) ?? 0)}',
                          ),
                          Wrap(
                            spacing: Space.sm,
                            children: [
                              if (canOpenFolders)
                                TextButton.icon(
                                  onPressed: () =>
                                      openPath('${_library!['root']}'),
                                  icon: const Icon(Icons.folder_open_outlined),
                                  label: Text(l10n.commonOpenFolder),
                                ),
                              TextButton.icon(
                                onPressed: () async {
                                  try {
                                    final r = await context
                                        .read<AppState>()
                                        .api
                                        .post('/api/library/reindex');
                                    if (context.mounted)
                                      showSnack(
                                        context,
                                        l10n.libraryReindexed(r['indexed']),
                                      );
                                    if (mounted) await _load();
                                  } catch (e) {
                                    if (context.mounted)
                                      showSnack(
                                        context,
                                        l10n.libraryReindexFailed(e),
                                      );
                                  }
                                },
                                icon: const Icon(Icons.manage_history_rounded),
                                label: Text(l10n.libraryReindex),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
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
      if (m.start > at)
        spans.add(TextSpan(text: hit.snippet.substring(at, m.start)));
      spans.add(
        TextSpan(
          text: m[1],
          style: TextStyle(
            backgroundColor: cs.tertiaryContainer,
            color: cs.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                note ? Icons.description_outlined : Icons.subject_rounded,
                color: cs.primary,
                size: 20,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: spans),
                      style: tt.bodyMedium?.copyWith(height: 1.55),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      [
                        hit.courseTitle,
                        hit.lecture,
                        if (!note) fmtClock(hit.startMs),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!note)
                Icon(
                  Icons.play_circle_outline_rounded,
                  color: cs.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
