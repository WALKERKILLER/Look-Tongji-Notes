part of 'study_canvas.dart';

// The lecture's material, out of the player's tabs: subtitles, files,
// practice, notes and conversations sit on a shelf beside the canvas and
// drag onto it as ordinary cards. Files fan out like a small stack of paper.
// Contract: docs/study-canvas.md (课次素材).

/// Something on the shelf that becomes a card where it is dropped.
class StudyAsset {
  const StudyAsset(
    this.kind,
    this.title, {
    this.data,
    this.size = const Size(420, 320),
  });

  /// segments, file, quiz, note, thread or new-thread.
  final String kind;
  final String title;
  final Object? data;

  /// The card's world size, for the drop outline.
  final Size size;
}

enum _ShelfTab { transcript, files, practice, notes, threads }

extension _StudyShelf on StudyCanvasState {
  /// The shelf sits beside the canvas on wide windows and above the bottom
  /// edge on phones, where dragging needs a long press.
  bool get _shelfSide => _viewport.width >= 720;

  void _toggleShelf([_ShelfTab? tab]) => _update(() {
    _shelfTab = _shelfTab == null || (tab != null && tab != _shelfTab)
        ? (tab ?? _shelfShown ?? _ShelfTab.transcript)
        : null;
    _shelfShown = _shelfTab ?? _shelfShown;
  });

  Widget _shelf() {
    final tab = _shelfTab;
    // Built once first opened, so it can slide away with its content.
    final shown = tab ?? _shelfShown;
    if (shown == null) return const SizedBox.shrink();
    final side = _shelfSide;
    final top = math.max(
      Space.xxxl + Space.xl + studyDockMargin,
      _topBarsBottom + 8,
    );
    return AnimatedPositioned(
      duration: Motion.medium2,
      curve: Motion.emphasized,
      left: side ? (tab == null ? -360 : Space.md) : Space.sm,
      right: side ? null : Space.sm,
      top: side ? top : null,
      bottom: side
          ? Space.xxxl + Space.lg
          : (tab == null ? -_viewport.height : Space.sm),
      height: side ? null : math.min(480, _viewport.height * .62),
      width: side ? 340 : null,
      child: IgnorePointer(
        ignoring: tab == null,
        child: _Shelf(key: _shelfKey, owner: this, tab: shown),
      ),
    );
  }

  /// Takes shelf items anywhere on the canvas and outlines where they land.
  Widget _assetDropTarget() => Positioned.fill(
    child: DragTarget<StudyAsset>(
      onMove: (e) {
        final box =
            _inputSurface.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final p = box.globalToLocal(e.offset);
        final s = e.data.size * document!.zoom;
        _dropHint.value = Rect.fromCenter(
          center: p,
          width: s.width,
          height: s.height,
        );
      },
      onLeave: (_) => _dropHint.value = null,
      onAcceptWithDetails: (e) {
        _dropHint.value = null;
        final box =
            _inputSurface.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        unawaited(_placeAsset(e.data, _world(box.globalToLocal(e.offset))));
      },
      builder: (context, _, _) => const SizedBox.expand(),
    ),
  );

  Widget _dropOutline() => Positioned.fill(
    child: IgnorePointer(
      child: ValueListenableBuilder<Rect?>(
        valueListenable: _dropHint,
        builder: (context, rect, _) => CustomPaint(
          painter: _DropOutline(rect, Theme.of(context).colorScheme.primary),
        ),
      ),
    ),
  );

  /// Places [a] centred on [at] (world coordinates), or in view when null.
  Future<void> _placeAsset(StudyAsset a, [Offset? at]) async {
    final d = document;
    if (d == null) return;
    if (!d.editable(d.activeLayer)) {
      _toast(l10n.studyPickLayer);
      return;
    }
    at ??= _world(_viewport.center(Offset.zero));
    switch (a.kind) {
      case 'file':
        await _import(courseware: a.data as String, wholeCourse: true, at: at);
        return;
      case 'new-thread':
        await _startConversation(bind: false, at: at);
        return;
      case 'thread':
        final card = d.cards.where((c) => c.id == a.data).firstOrNull;
        if (card == null) return;
        d.checkpoint();
        card.rect = Rect.fromCenter(
          center: at,
          width: card.rect.width,
          height: card.rect.height,
        );
        d.changed();
        _activateThread(card.id);
        return;
    }
    StudyCard? card;
    try {
      card = switch (a.kind) {
        'segments' => _transcriptCard(a.data as List<Segment>, at),
        'quiz' => await _practiceCard(a.data as String, at),
        'note' => await _noteCard(a.data as String, at),
        _ => null,
      };
    } catch (e) {
      _toast(l10n.studyShelfLoadFailed('$e'));
      return;
    }
    if (card == null || !mounted) return;
    if (d.cards.length >= 2000) {
      _toast(l10n.studyCardLimit);
      return;
    }
    d.checkpoint();
    d.cards.add(card);
    d.changed();
    _update(
      () => _selection
        ..clear()
        ..add(card!.id),
    );
  }

  StudyCard _transcriptCard(List<Segment> all, Offset at) {
    // Eight lines a paragraph, within the 32 blocks a card holds.
    final segments = all.take(256).toList();
    final blocks = <StudyBlock>[
      for (var i = 0; i < segments.length; i += 8)
        StudyBlock(
          type: 'paragraph',
          text: [
            for (final s in segments.skip(i).take(8))
              '${fmtClock(s.startMs)}  ${s.text}',
          ].join('\n'),
        ),
    ];
    if (all.length > segments.length) {
      blocks.add(
        StudyBlock(
          type: 'paragraph',
          text: l10n.studyTranscriptExcerpt(segments.length),
        ),
      );
    }
    final first = segments.first, last = segments.last;
    final quote = first.text;
    return StudyCard(
      id: studyId(),
      type: 'note',
      layer: document!.activeLayer,
      rect: Rect.fromCenter(center: at, width: 420, height: 320),
      title: l10n.studyTranscriptTitle(
        '${fmtClock(first.startMs)}–${fmtClock(last.endMs)}',
      ),
      blocks: blocks,
      sources: [
        StudyAnchor(
          id: studyId(),
          objectId: 'lecture',
          kind: 'video',
          workspaceId: widget.ctl.lectureId,
          timeStartMs: first.startMs,
          timeEndMs: math.max(first.startMs, last.endMs),
          quote: quote.substring(0, math.min(200, quote.length)),
        ),
      ],
    );
  }

  Future<StudyCard?> _practiceCard(String id, Offset at) async {
    final quiz = Quiz(
      ((await widget.api.get('/api/quizzes/${Uri.encodeComponent(id)}')) as Map)
          .cast<String, dynamic>(),
    );
    if (!mounted || quiz.questions.isEmpty) return null;
    const letters = 'ABCDEFGH';
    return StudyCard(
      id: studyId(),
      type: 'practice',
      layer: document!.activeLayer,
      rect: Rect.fromCenter(center: at, width: 520, height: 560),
      title: quiz.title,
      blocks: [
        for (final (i, q) in quiz.questions.take(32).indexed)
          StudyBlock(
            type: 'exercise',
            text: [
              '${i + 1}. ${q.stem}',
              for (final (j, o) in q.options.take(8).indexed)
                '${letters[j]}. ${o.text}',
            ].join('\n'),
            hint: q.hint,
            answer: q.answer >= 0 && q.answer < q.options.length
                ? [
                    l10n.studyAnswerLabel(letters[q.answer]),
                    q.options[q.answer].rationale,
                  ].where((s) => s.isNotEmpty).join('\n')
                : '',
          ),
      ],
    );
  }

  Future<StudyCard?> _noteCard(String id, Offset at) async {
    final note = Note(
      ((await widget.api.get('/api/notes/${Uri.encodeComponent(id)}')) as Map)
          .cast<String, dynamic>(),
    );
    if (!mounted) return null;
    final blocks = studyBlocksFromMarkdown(note.body);
    return StudyCard(
      id: studyId(),
      type: 'note',
      layer: document!.activeLayer,
      rect: Rect.fromCenter(center: at, width: 480, height: 420),
      title: note.title.isEmpty ? l10n.studyShelfNotes : note.title,
      blocks: blocks.isEmpty ? [StudyBlock(type: 'paragraph')] : blocks,
    );
  }
}

/// Headings, lists, steps, code and paragraphs from a note's Markdown, within
/// the 32 blocks a card holds; anything past that joins the last paragraph.
List<StudyBlock> studyBlocksFromMarkdown(String text) {
  final out = <StudyBlock>[];
  final para = <String>[];
  List<String>? items;
  String? kind;
  void flush() {
    if (para.isNotEmpty) {
      out.add(StudyBlock(type: 'paragraph', text: para.join('\n')));
      para.clear();
    }
    if (items != null && items!.isNotEmpty) {
      out.add(StudyBlock(type: kind!, items: items!.take(30).toList()));
    }
    items = null;
  }

  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trimRight();
    if (line.trimLeft().startsWith('```')) {
      flush();
      final language = line.trimLeft().substring(3).trim();
      final code = <String>[];
      while (++i < lines.length && !lines[i].trimLeft().startsWith('```')) {
        code.add(lines[i]);
      }
      out.add(
        StudyBlock(type: 'code', text: code.join('\n'), language: language),
      );
      continue;
    }
    final heading = RegExp(r'^#{1,6}\s+(.*)').firstMatch(line);
    final bullet = RegExp(r'^\s*[-*+]\s+(.*)').firstMatch(line);
    final step = RegExp(r'^\s*\d+[.)]\s+(.*)').firstMatch(line);
    if (heading != null) {
      flush();
      out.add(StudyBlock(type: 'heading', text: heading.group(1)!));
    } else if (bullet != null || step != null) {
      final k = bullet != null ? 'list' : 'steps';
      if (para.isNotEmpty || kind != k) flush();
      kind = k;
      (items ??= []).add((bullet ?? step)!.group(1)!);
    } else if (line.trim().isEmpty) {
      flush();
    } else {
      if (items != null) flush();
      para.add(line);
    }
  }
  flush();
  if (out.length > 32) {
    final rest = out.sublist(31).map((b) => b.plainText).join('\n\n');
    out
      ..removeRange(31, out.length)
      ..add(StudyBlock(type: 'paragraph', text: rest));
  }
  return out;
}

class _DropOutline extends CustomPainter {
  _DropOutline(this.rect, this.color);
  final Rect? rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect;
    if (r == null) return;
    final shape = RRect.fromRectAndRadius(r, const Radius.circular(Corners.lg));
    canvas.drawRRect(shape, Paint()..color = color.withValues(alpha: .07));
    final path = Path()..addRRect(shape);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: .7);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, math.min(m.length, d + 7)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DropOutline o) => o.rect != rect || o.color != color;
}

/// What a dragged shelf item looks like under the pointer.
class _AssetChip extends StatelessWidget {
  const _AssetChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: FractionalTranslation(
        translation: const Offset(-.5, -.5),
        child: GlassSurface(
          depth: GlassDepth.float,
          radius: Corners.full,
          padding: const EdgeInsets.fromLTRB(
            Space.md,
            Space.sm,
            Space.lg,
            Space.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: Space.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shelf extends StatefulWidget {
  const _Shelf({super.key, required this.owner, required this.tab});
  final StudyCanvasState owner;
  final _ShelfTab tab;

  @override
  State<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<_Shelf> {
  StudyCanvasState get owner => widget.owner;
  LecturePlayer get ctl => owner.widget.ctl;
  List<Map>? _files;
  List<Quiz>? _quizzes;
  Object? _filesError, _quizError;
  String? _openGroup;
  final _transcript = ScrollController();
  final _nowKey = GlobalKey();

  @override
  void didUpdateWidget(_Shelf old) {
    super.didUpdateWidget(old);
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transcript.dispose();
    super.dispose();
  }

  /// Reads files and practice the first time their tab shows.
  void _load() {
    if (widget.tab == _ShelfTab.files &&
        _files == null &&
        _filesError == null) {
      final course = ctl.lecture?.courseId;
      if (course == null) return;
      owner.widget.api
          .libraryCatalog(courseId: course)
          .then((v) {
            if (mounted) setState(() => _files = (v as List).cast<Map>());
          })
          .catchError((Object e) {
            if (mounted) setState(() => _filesError = e);
          });
    }
    if (widget.tab == _ShelfTab.practice &&
        _quizzes == null &&
        _quizError == null) {
      owner.widget.api
          .get('/api/quizzes', {'lecture_id': ctl.lectureId})
          .then((v) {
            if (!mounted) return;
            setState(
              () => _quizzes = [
                for (final q in jsonList(v))
                  Quiz((q as Map).cast<String, dynamic>()),
              ],
            );
          })
          .catchError((Object e) {
            if (mounted) setState(() => _quizError = e);
          });
    }
  }

  /// Wide windows drag sideways out of the list (vertical moves scroll);
  /// phones lift an item with a long press.
  Widget _drag(StudyAsset asset, IconData icon, Widget child) {
    final feedback = _AssetChip(icon: icon, label: asset.title);
    final placeholder = Opacity(opacity: .35, child: child);
    return owner._shelfSide
        ? Draggable<StudyAsset>(
            data: asset,
            affinity: Axis.horizontal,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: child,
          )
        : LongPressDraggable<StudyAsset>(
            data: asset,
            delay: const Duration(milliseconds: 280),
            hapticFeedbackOnStart: true,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: child,
          );
  }

  Widget _place(StudyAsset asset) => IconButton(
    tooltip: l10n.studyShelfPlace,
    visualDensity: VisualDensity.compact,
    onPressed: () => owner._placeAsset(asset),
    icon: const Icon(Icons.add_rounded, size: 20),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final labels = {
      _ShelfTab.transcript: (
        l10n.studyShelfTranscript,
        Icons.subtitles_outlined,
      ),
      _ShelfTab.files: (l10n.studyShelfFiles, Icons.folder_copy_outlined),
      _ShelfTab.practice: (l10n.studyShelfPractice, Icons.quiz_outlined),
      _ShelfTab.notes: (l10n.studyShelfNotes, Icons.sticky_note_2_outlined),
      _ShelfTab.threads: (l10n.studyShelfThreads, Icons.forum_outlined),
    };
    return GlassSurface(
      depth: GlassDepth.panel,
      radius: Corners.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.xs, 0),
            child: Row(
              children: [
                Expanded(child: Text(l10n.studyShelf, style: tt.titleMedium)),
                IconButton(
                  tooltip: l10n.studyShelfPanel,
                  onPressed: owner._openPlayerPanel,
                  icon: const Icon(Icons.view_sidebar_outlined, size: 20),
                ),
                IconButton(
                  tooltip: l10n.commonClose,
                  onPressed: () => owner._update(() => owner._shelfTab = null),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              owner._shelfSide ? l10n.studyShelfHint : l10n.studyShelfHintTouch,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.md,
              Space.md,
              Space.sm,
            ),
            // Five sections side by side, styled like the navigation dock.
            child: Row(
              children: [
                for (final MapEntry(key: tab, value: (label, icon))
                    in labels.entries)
                  Expanded(
                    child: Semantics(
                      selected: widget.tab == tab,
                      button: true,
                      child: InkResponse(
                        key: ValueKey('study-shelf-${tab.name}'),
                        radius: 28,
                        onTap: () => owner._update(
                          () => owner._shelfTab = owner._shelfShown = tab,
                        ),
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: Motion.short4,
                              curve: Motion.emphasized,
                              width: 48,
                              height: 30,
                              decoration: ShapeDecoration(
                                color: widget.tab == tab
                                    ? cs.secondaryContainer
                                    : Colors.transparent,
                                shape: const StadiumBorder(),
                              ),
                              child: Icon(
                                icon,
                                size: 20,
                                color: widget.tab == tab
                                    ? cs.onSecondaryContainer
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: Space.xxs),
                            Text(
                              label,
                              style: tt.labelSmall?.copyWith(
                                color: widget.tab == tab
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                                fontWeight: widget.tab == tab
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.short4,
              child: KeyedSubtree(
                key: ValueKey(widget.tab),
                child: switch (widget.tab) {
                  _ShelfTab.transcript => _transcriptList(context),
                  _ShelfTab.files => _fileStacks(context),
                  _ShelfTab.practice => _practiceList(context),
                  _ShelfTab.notes => _noteList(context),
                  _ShelfTab.threads => _threadList(context),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String text, {VoidCallback? retry}) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (retry != null)
              TextButton(onPressed: retry, child: Text(l10n.commonRetry)),
          ],
        ),
      ),
    );
  }

  Widget _transcriptList(BuildContext context) {
    final segments = ctl.segments;
    if (segments.isEmpty) return _empty(l10n.studyShelfNoTranscript);
    final chapters = ctl.chapters;
    // Chapter headers interleave with their lines.
    final rows = <Object>[];
    var c = 0;
    for (final s in segments) {
      while (c < chapters.length && chapters[c].startMs <= s.startMs) {
        rows.add(chapters[c++]);
      }
      rows.add(s);
    }
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Stack(
      children: [
        ValueListenableBuilder<Duration>(
          valueListenable: ctl.position,
          builder: (context, position, _) {
            final now = ctl.segmentAt(position.inMilliseconds);
            return ListView.builder(
              controller: _transcript,
              padding: const EdgeInsets.fromLTRB(
                Space.sm,
                0,
                Space.sm,
                Space.huge,
              ),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                if (row is Chapter) {
                  final inside = [
                    for (final s in segments)
                      if (s.startMs >= row.startMs &&
                          (row.endMs <= 0 || s.startMs < row.endMs))
                        s,
                  ];
                  final asset = StudyAsset('segments', row.title, data: inside);
                  return _drag(
                    asset,
                    Icons.segment_rounded,
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(
                        left: Space.sm,
                        right: Space.xxs,
                      ),
                      title: Text(
                        row.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall,
                      ),
                      subtitle: Text(
                        l10n.studyShelfChapterLines(inside.length),
                        style: tt.labelSmall,
                      ),
                      trailing: inside.isEmpty ? null : _place(asset),
                    ),
                  );
                }
                final s = row as Segment;
                final playing = segments.indexOf(s) == now;
                final asset = StudyAsset(
                  'segments',
                  s.text,
                  data: [s],
                  size: const Size(420, 220),
                );
                return _drag(
                  asset,
                  Icons.subtitles_outlined,
                  Material(
                    key: playing ? _nowKey : null,
                    color: playing ? cs.secondaryContainer : Colors.transparent,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(Corners.md),
                    ),
                    child: InkWell(
                      customBorder: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(Corners.md),
                      ),
                      onTap: () => ctl.seekTo(s.startMs),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.sm,
                          Space.sm,
                          Space.xxs,
                          Space.sm,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 48,
                              child: Text(
                                fmtClock(s.startMs),
                                style: tt.labelMedium?.copyWith(
                                  color: cs.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                s.text,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodyMedium?.copyWith(
                                  color: playing
                                      ? cs.onSecondaryContainer
                                      : cs.onSurface,
                                  height: 1.45,
                                ),
                              ),
                            ),
                            _place(asset),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          right: Space.md,
          bottom: Space.md,
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: l10n.studyShelfNow,
            onPressed: () {
              final row = _nowKey.currentContext;
              if (row != null) {
                Scrollable.ensureVisible(
                  row,
                  alignment: .3,
                  duration: Motion.medium2,
                  curve: Motion.emphasized,
                );
                return;
              }
              final i = rows.indexOf(
                segments[math.max(
                  0,
                  ctl.segmentAt(ctl.position.value.inMilliseconds),
                )],
              );
              _transcript.jumpTo(
                (i * 64.0).clamp(0, _transcript.position.maxScrollExtent),
              );
            },
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
      ],
    );
  }

  Widget _fileStacks(BuildContext context) {
    if (ctl.lecture?.courseId == null) return _empty(l10n.studyShelfNoCourse);
    if (_filesError != null) {
      return _empty(
        l10n.studyShelfLoadFailed('$_filesError'),
        retry: () => setState(() {
          _filesError = null;
          _load();
        }),
      );
    }
    final files = _files;
    if (files == null) return const Center(child: CircularProgressIndicator());
    if (files.isEmpty) return _empty(l10n.studyShelfNoFiles);
    // This lecture's files first, then one stack per kind of material.
    final groups = <String, List<Map>>{};
    for (final f in files) {
      final key = f['lecture_id'] == ctl.lectureId
          ? l10n.studyShelfThisLecture
          : '${f['category'] ?? ''}'.isEmpty
          ? l10n.studyShelfFiles
          : '${f['category']}';
      (groups[key] ??= []).add(f);
    }
    final open = _openGroup;
    if (open != null && groups[open] != null) {
      return _openStack(context, open, groups[open]!);
    }
    return GridView.extent(
      maxCrossAxisExtent: 160,
      childAspectRatio: .86,
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
      mainAxisSpacing: Space.md,
      crossAxisSpacing: Space.md,
      children: [
        for (final MapEntry(:key, :value) in groups.entries)
          _FileFan(
            key: ValueKey('study-fan-$key'),
            label: key,
            files: value,
            onOpen: () => setState(() => _openGroup = key),
            drag: (f, child) => _fileDrag(f, child),
          ),
      ],
    );
  }

  Widget _fileDrag(Map f, Widget child) {
    final supported = _studyImportable.contains('${f['file_type']}');
    if (!supported) {
      return Tooltip(
        message: l10n.studyShelfUnsupported,
        child: Opacity(opacity: .45, child: child),
      );
    }
    return _drag(
      StudyAsset(
        'file',
        '${f['name']}',
        data: '${f['path']}',
        size: const Size(320, 420),
      ),
      Icons.description_outlined,
      child,
    );
  }

  Widget _openStack(BuildContext context, String label, List<Map> files) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.studyShelfBack,
                onPressed: () => setState(() => _openGroup = null),
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
              ),
              Expanded(
                child: Text(
                  label,
                  style: tt.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                l10n.studyShelfFilesCount(files.length),
                style: tt.labelSmall,
              ),
              const SizedBox(width: Space.md),
            ],
          ),
        ),
        Expanded(
          child: GridView.extent(
            maxCrossAxisExtent: 100,
            childAspectRatio: .62,
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.sm,
              Space.md,
              Space.lg,
            ),
            mainAxisSpacing: Space.md,
            crossAxisSpacing: Space.sm,
            children: [
              for (final f in files)
                _fileDrag(
                  f,
                  InkWell(
                    borderRadius: BorderRadius.circular(Corners.md),
                    onTap: _studyImportable.contains('${f['file_type']}')
                        ? () => owner._placeAsset(
                            StudyAsset(
                              'file',
                              '${f['name']}',
                              data: '${f['path']}',
                            ),
                          )
                        : null,
                    child: Column(
                      children: [
                        _FileTile(file: f),
                        const SizedBox(height: Space.xs),
                        Text(
                          '${f['name']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: tt.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _practiceList(BuildContext context) {
    if (_quizError != null) {
      return _empty(
        l10n.studyShelfLoadFailed('$_quizError'),
        retry: () => setState(() {
          _quizError = null;
          _load();
        }),
      );
    }
    final quizzes = _quizzes;
    if (quizzes == null)
      return const Center(child: CircularProgressIndicator());
    if (quizzes.isEmpty) return _empty(l10n.studyShelfNoPractice);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.lg),
      children: [
        for (final q in quizzes)
          _drag(
            StudyAsset('quiz', q.title, data: q.id, size: const Size(520, 560)),
            Icons.quiz_outlined,
            ListTile(
              leading: const Icon(Icons.quiz_outlined),
              title: Text(
                q.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                q.meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _place(StudyAsset('quiz', q.title, data: q.id)),
            ),
          ),
      ],
    );
  }

  Widget _noteList(BuildContext context) {
    final notes = ctl.notes;
    if (notes.isEmpty) return _empty(l10n.studyShelfNoNotes);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.lg),
      children: [
        for (final n in notes)
          _drag(
            StudyAsset(
              'note',
              n.title.isEmpty ? l10n.studyShelfNotes : n.title,
              data: n.id,
              size: const Size(480, 420),
            ),
            Icons.sticky_note_2_outlined,
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(
                n.title.isEmpty ? l10n.studyShelfNotes : n.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                n.body.replaceAll(RegExp(r'\s+'), ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _place(StudyAsset('note', n.title, data: n.id)),
            ),
          ),
      ],
    );
  }

  Widget _threadList(BuildContext context) {
    const fresh = StudyAsset('new-thread', '', size: Size(300, 200));
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.lg),
      children: [
        _drag(
          StudyAsset('new-thread', l10n.studyThreadNew, size: fresh.size),
          Icons.add_comment_outlined,
          ListTile(
            leading: const Icon(Icons.add_comment_outlined),
            title: Text(l10n.studyThreadNew),
            subtitle: Text(l10n.studyShelfThreadHint),
            trailing: _place(fresh),
          ),
        ),
        for (final t in owner._threads)
          _drag(
            StudyAsset('thread', t.title, data: t.id, size: t.rect.size),
            Icons.forum_outlined,
            ListTile(
              leading: Icon(
                Icons.forum_outlined,
                color: t.id == owner._activeConversation
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(t.title),
              subtitle: Text(
                l10n.studyThreadTurns(
                  owner._threadSummary[t.id]?['turns'] as int? ?? 0,
                ),
              ),
              onTap: () => owner._activateThread(t.id),
            ),
          ),
      ],
    );
  }
}

/// File types the canvas can import (mirrors the importer's accepted types).
const _studyImportable = {
  'pdf',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'txt',
  'md',
  'markdown',
  'mp4',
  'mov',
  'm4v',
  'webm',
  'mkv',
};

/// A stack of up to five files fanned like paper in a hand. Hovering opens
/// the fan and lifts the file under the pointer; that file drags straight
/// onto the canvas. Tapping the stack lays all its files out.
class _FileFan extends StatefulWidget {
  const _FileFan({
    super.key,
    required this.label,
    required this.files,
    required this.onOpen,
    required this.drag,
  });
  final String label;
  final List<Map> files;
  final VoidCallback onOpen;
  final Widget Function(Map file, Widget child) drag;

  @override
  State<_FileFan> createState() => _FileFanState();
}

class _FileFanState extends State<_FileFan> {
  bool _open = false;
  int? _lift;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final shown = widget.files.take(5).toList();
    final mid = (shown.length - 1) / 2;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label:
          '${widget.label} ${l10n.studyShelfFilesCount(widget.files.length)}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _open = true),
        onExit: (_) => setState(() {
          _open = false;
          _lift = null;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      for (final (i, f) in shown.indexed)
                        AnimatedContainer(
                          duration: reduce ? Duration.zero : Motion.medium1,
                          curve: Motion.emphasized,
                          transformAlignment: Alignment.bottomCenter,
                          transform: Matrix4.identity()
                            ..translateByDouble(
                              (i - mid) * (_open ? box.maxWidth / 7 : 3),
                              _lift == i ? -16 : (_open ? -4 : -i * 1.5),
                              0,
                              1,
                            )
                            ..rotateZ((i - mid) * (_open ? .2 : .06)),
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _lift = i),
                            child: widget.drag(f, _FileTile(file: f)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelLarge,
              ),
              Text(
                l10n.studyShelfFilesCount(widget.files.length),
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One file as a small sheet of paper with a folded corner and its type.
class _FileTile extends StatelessWidget {
  const _FileTile({required this.file});
  final Map file;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final type = '${file['file_type']}'.toLowerCase();
    final (fill, ink) = switch (type) {
      'pdf' => (cs.tertiaryContainer, cs.onTertiaryContainer),
      'png' ||
      'jpg' ||
      'jpeg' ||
      'gif' ||
      'webp' => (cs.secondaryContainer, cs.onSecondaryContainer),
      'mp4' ||
      'mov' ||
      'm4v' ||
      'webm' ||
      'mkv' => (cs.primaryContainer, cs.onPrimaryContainer),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    final dark = cs.brightness == Brightness.dark;
    return SizedBox(
      width: 64,
      height: 84,
      child: CustomPaint(
        painter: _Sheet(
          paper: dark ? cs.surfaceContainerHighest : cs.surfaceContainerLowest,
          edge: cs.onSurface.withValues(alpha: dark ? .16 : .1),
          fold: fill,
          dark: dark,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 22, 7, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${file['name']}',
                  maxLines: 3,
                  overflow: TextOverflow.fade,
                  style: tt.labelSmall?.copyWith(
                    fontSize: 9,
                    height: 1.25,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: fill,
                  shape: const StadiumBorder(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  child: Text(
                    type.isEmpty ? '?' : type.toUpperCase(),
                    style: tt.labelSmall?.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: ink,
                      letterSpacing: .4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sheet extends CustomPainter {
  _Sheet({
    required this.paper,
    required this.edge,
    required this.fold,
    required this.dark,
  });
  final Color paper, edge, fold;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const corner = 14.0, r = 6.0;
    final w = size.width, h = size.height;
    final body = Path()
      ..moveTo(r, 0)
      ..lineTo(w - corner, 0)
      ..lineTo(w, corner)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
    if (!dark) {
      canvas.drawShadow(body, Colors.black, 2, false);
    }
    canvas.drawPath(body, Paint()..color = paper);
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = edge,
    );
    final flap = Path()
      ..moveTo(w - corner, 0)
      ..lineTo(w - corner, corner - 3)
      ..quadraticBezierTo(w - corner, corner, w - corner + 3, corner)
      ..lineTo(w, corner)
      ..close();
    canvas.drawPath(flap, Paint()..color = fold);
  }

  @override
  bool shouldRepaint(_Sheet o) =>
      o.paper != paper || o.edge != edge || o.fold != fold || o.dark != dark;
}
