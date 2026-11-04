part of 'study_canvas.dart';

// Conversations use a collapsible sidebar; only explicitly pinned answers
// become canvas cards. Source bindings and sidecar histories remain independent.
// Contract: docs/multimodal-canvas.md, spec 0021.

/// The zoom capsule's offset from the corner and its approximate width.
const studyZoomInset = Space.md;
const studyZoomWidth = 172.0;

extension _StudyStage on StudyCanvasState {
  StudyEdgeDock _aiDock() => StudyEdgeDock(
    key: const ValueKey('dock-ai'),
    id: 'ai',
    label: 'AI 入口',
    showHandle: false,
    dragIcon: Icons.auto_awesome_outlined,
    surfaceKey: _aiDockKey,
    placement: _aiPlacement,
    onChanged: (p) => _moveDock('ai', p),
    children: (_) => [
      IconButton(
        key: const ValueKey('study-ai-tab'),
        tooltip: '打开 AI 对话',
        onPressed: _ask,
        icon: const Icon(Icons.auto_awesome_outlined),
      ),
    ],
  );

  List<StudyCard> get _threads =>
      document?.cards.where((c) => c.type == 'conversation').toList() ?? [];

  Widget _agentStage() {
    final threads = {for (final c in _threads) c.id: c};
    _liveThreads.removeWhere((id) => !threads.containsKey(id));
    if (!threads.containsKey(_activeConversation)) _activeConversation = null;
    if (_activeConversation != null) _liveThreads.add(_activeConversation!);
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final id in _liveThreads)
            Offstage(
              offstage: id != _activeConversation,
              child: TickerMode(
                enabled: id == _activeConversation,
                child: _ConversationBody(
                  key: _conversationKeys.putIfAbsent(
                    id,
                    () => GlobalKey<_ConversationBodyState>(),
                  ),
                  owner: this,
                  card: threads[id]!,
                  initial: _initialConversations[id],
                  active: id == _activeConversation,
                ),
              ),
            ),
          if (_activeConversation == null)
            _StageView(
              key: const ValueKey('study-stage-idle'),
              owner: this,
              active: true,
              input: _idleInput,
              onSend: (text) => _startConversation(send: text),
              onPickSources: () => _startConversation(pick: true),
              onDrop: (id) {
                _selection
                  ..clear()
                  ..add(id);
                _detail.clear();
                _startConversation();
              },
            ),
        ],
      ),
    );
  }

  /// Retain conversation identities and histories without moving saved objects.
  void _adoptThreads(StudyDocument d) {
    if (!d.cards.any((c) => c.id == _activeConversation)) {
      _activeConversation = d.cards
          .where((c) => c.type == 'conversation')
          .lastOrNull
          ?.id;
    }
  }

  /// Starts a conversation node bound to the current selection; [send]
  /// asks its first question once the node has loaded.
  Future<void> _startConversation({
    String? send,
    bool bind = true,
    bool pick = false,
    bool allowImages = false,
    Offset? at,
  }) async {
    final d = document;
    if (d == null || !d.editable(d.activeLayer)) return;
    final query = bind
        ? _selectedQuery()
        : <String, dynamic>{
            'objects': <String>[],
            'selection': <String, dynamic>{},
            'include_video': false,
          };
    final visual = bind && _regionSelection != null
        ? await _captureSelection()
        : <Map<String, dynamic>>[];
    if (!mounted) return;
    final card = StudyCard(
      id: studyId(),
      type: 'conversation',
      layer: d.activeLayer,
      rect: at == null
          ? _freeSpot(const Size(300, 200))
          : Rect.fromCenter(center: at, width: 300, height: 200),
      title: l10n.studyThreadTitle(_threads.length + 1),
      conversationId: studyId(),
    );
    d.checkpoint();
    d.cards.add(card);
    d.changed();
    _initialConversations[card.id] = {
      'query': query,
      'visuals': visual,
      'allow_images': allowImages,
      if (send != null && send.trim().isNotEmpty) 'send': send.trim(),
      if (pick) 'pick': true,
    };
    _idleInput.clear();
    _update(() {
      _activeConversation = card.id;
      _stageOpen = true;
    });
  }

  /// A place for a new node at the right of what is in view, clear of cards.
  Rect _freeSpot(Size size) {
    final view = _visibleWorld;
    var rect = Rect.fromLTWH(
      view.right - size.width - 48 / document!.zoom,
      view.top + 96 / document!.zoom,
      size.width,
      size.height,
    );
    for (
      var i = 0;
      i < 60 &&
          document!.cards.any(
            (c) =>
                c.type != 'conversation' && c.rect.inflate(16).overlaps(rect),
          );
      i++
    ) {
      rect = rect.shift(Offset(0, size.height + 24));
    }
    return rect;
  }

  void _pinAnswer(Map turn) {
    final d = document;
    final answer = '${turn['answer'] ?? ''}'.trim();
    if (d == null || answer.isEmpty || !d.editable(d.activeLayer)) return;
    if (d.cards.length >= 2000) {
      _toast('画布卡片已达上限');
      return;
    }
    final anchors = [
      for (final source in (turn['result'] as Map?)?['sources'] as List? ?? [])
        StudyAnchor.fromJson(source as Map),
    ];
    final source = d.cards
        .where((c) => anchors.any((a) => a.objectId == c.id))
        .firstOrNull;
    final rect = source == null
        ? _freeSpot(const Size(400, 300))
        : Rect.fromLTWH(source.rect.right + 24, source.rect.top, 400, 300);
    d.checkpoint();
    d.cards.add(
      StudyCard(
        id: studyId(),
        type: 'text',
        layer: d.activeLayer,
        rect: rect,
        title: '${turn['question'] ?? 'AI 解答'}'.characters.take(60).toString(),
        text: answer,
        sources: anchors,
      ),
    );
    // Pinning is an explicit placement action; reveal the resulting card.
    final view = _visibleWorld.deflate(64 / d.zoom);
    if (!view.contains(rect.topLeft) || !view.contains(rect.bottomRight)) {
      d.camera = _viewport.center(Offset.zero) - rect.center * d.zoom;
      _cameraChanged();
    }
    d.changed();
    _update(() => _stageOpen = false);
    _composerFocus.unfocus();
    _toast('已留在画布，可移动、编辑或撤销');
  }

  void _activateThread(String? id) {
    _update(() {
      _activeConversation = id;
      _stageOpen = true;
    });
    if (id == null) _composerFocus.requestFocus();
  }
}

/// A conversation on the canvas: its name, how far it went, and the last
/// question. Opening it brings the conversation to the stage.
class _ThreadNode extends StatefulWidget {
  const _ThreadNode({required this.owner, required this.card});
  final StudyCanvasState owner;
  final StudyCard card;

  @override
  State<_ThreadNode> createState() => _ThreadNodeState();
}

class _ThreadNodeState extends State<_ThreadNode> {
  StudyCanvasState get owner => widget.owner;

  @override
  void initState() {
    super.initState();
    // A mounted conversation reports its own summary; others are read once.
    if (!owner._threadSummary.containsKey(widget.card.id)) unawaited(_read());
  }

  Future<void> _read() async {
    try {
      final value = await owner.widget.api.studyConversation(
        owner.widget.ctl.lectureId,
        widget.card.conversationId,
      );
      final turns = (value as Map)['turns'] as List? ?? const [];
      if (!mounted || owner._threadSummary.containsKey(widget.card.id)) return;
      owner._threadSummary[widget.card.id] = {
        'turns': turns.length,
        'last': turns.isEmpty ? '' : '${(turns.last as Map)['question'] ?? ''}',
      };
      owner._threadTick.value++;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ValueListenableBuilder<int>(
      valueListenable: owner._threadTick,
      builder: (context, _, _) {
        final active = owner._activeConversation == widget.card.id;
        final summary = owner._threadSummary[widget.card.id];
        final count = summary?['turns'] as int? ?? 0;
        final last = '${summary?['last'] ?? ''}';
        return InkWell(
          onTap: () => owner._activateThread(widget.card.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (active) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 8),
                      ),
                      const SizedBox(width: Space.sm),
                    ],
                    Expanded(
                      child: Text(
                        active
                            ? l10n.studyThreadActive
                            : l10n.studyThreadTurns(count),
                        style: tt.labelMedium?.copyWith(
                          color: active ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Expanded(
                  child: Text(
                    active
                        ? l10n.studyThreadActiveHint
                        : last.isEmpty
                        ? l10n.studyThreadEmpty
                        : last,
                    style: tt.bodyMedium?.copyWith(
                      color: active ? cs.onSurfaceVariant : cs.onSurface,
                      height: 1.45,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!active)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => owner._activateThread(widget.card.id),
                      icon: const Icon(Icons.south_rounded, size: 16),
                      label: Text(l10n.studyThreadOpen),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Icons for the kinds of material a conversation can read.
IconData _sourceIcon(Map source) => switch ('${source['kind']}') {
  'video' => Icons.smart_display_outlined,
  'ink' => Icons.gesture_rounded,
  'image' || 'region' || 'visual' => Icons.crop_rounded,
  'text' || 'note' => Icons.notes_rounded,
  _ => Icons.description_outlined,
};

/// What the agent is doing now, from the last step of its trace.
String _stepLabel(Map? live, List sources) {
  final trace = live?['trace'] as List? ?? const [];
  if (trace.isEmpty) return l10n.studyAgentPreparing;
  final step = trace.last as Map;
  final id = '${step['source_id'] ?? ''}';
  final source = sources
      .cast<Map>()
      .where((s) => '${s['id']}' == id)
      .firstOrNull;
  final label = '${source?['label'] ?? ''}';
  if (label.isEmpty) {
    return step['tool'] == 'get_canvas_context'
        ? l10n.studyAgentLookingAround
        : l10n.studyAgentThinking;
  }
  return switch ('${step['tool']}') {
    'get_video_context' => l10n.studyAgentListening(label),
    'prepare_video_clip' => l10n.studyAgentTranscribing(label),
    'inspect_canvas_region' => l10n.studyAgentLooking(label),
    _ => l10n.studyAgentReading(label),
  };
}

/// The card ids the agent is reading right now.
Set<String> _readingNow(Map? live, List sources) {
  final trace = live?['trace'] as List? ?? const [];
  if (trace.isEmpty || '${(trace.last as Map)['status']}' != 'running') {
    return const {};
  }
  final id = '${(trace.last as Map)['source_id'] ?? ''}';
  return {
    for (final s in sources.cast<Map>())
      if ('${s['id']}' == id && (s['anchor'] as Map?)?['object_id'] != null)
        '${(s['anchor'] as Map)['object_id']}',
  };
}

/// The stage: header, conversation and composer at the bottom centre, with
/// the threads to bound cards painted behind them.
class _StageView extends StatefulWidget {
  const _StageView({
    super.key,
    required this.owner,
    required this.active,
    required this.input,
    required this.onSend,
    required this.onDrop,
    this.thread,
    this.turns = const [],
    this.sources = const [],
    this.busy = false,
    this.loading = false,
    this.live,
    this.error,
    this.onStop,
    this.onRetry,
    this.onRemoveSource,
    this.onPickSources,
    this.onInspectSources,
    this.onEditVideo,
    this.allowImages,
    this.onAllowImages,
    this.onDraft,
  });

  final StudyCanvasState owner;

  /// Only the conversation on stage keeps the canvas from drawing under it.
  final bool active;
  final TextEditingController input;
  final ValueChanged<String> onSend;
  final ValueChanged<String> onDrop;
  final StudyCard? thread;
  final List turns, sources;
  final bool busy, loading;
  final Map? live;
  final String? error;
  final VoidCallback? onStop, onPickSources, onInspectSources;
  final ValueChanged<String>? onRetry;
  final ValueChanged<Map>? onRemoveSource, onEditVideo;

  /// Null hides the vision switch (no visual selection is bound).
  final bool? allowImages;
  final ValueChanged<bool>? onAllowImages;
  final VoidCallback? onDraft;

  @override
  State<_StageView> createState() => _StageViewState();
}

class _StageViewState extends State<_StageView>
    with SingleTickerProviderStateMixin {
  late final _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  final _composer = GlobalKey(), _panel = GlobalKey(), _stage = GlobalKey();
  bool _hover = false;
  String? _focusSource;
  bool _looping = false;

  /// One focus node belongs to the composer on stage; a hidden
  /// conversation's field keeps its own.
  final _localFocus = FocusNode();
  FocusNode get _focus => widget.active ? owner._composerFocus : _localFocus;

  StudyCanvasState get owner => widget.owner;

  @override
  void initState() {
    super.initState();
    _claim();
    owner._composerFocus.addListener(_focusChanged);
  }

  void _focusChanged() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  List<GlobalKey> get _keys => [_composer, _panel];

  void _claim() {
    owner._stageKeys.removeAll(_keys);
    // Offstage retains drafts and layout, but must not reserve canvas input.
    if (widget.active && owner._stageOpen) {
      owner._stageKeys.add(_panel);
    }
  }

  @override
  void didUpdateWidget(_StageView old) {
    super.didUpdateWidget(old);
    final answered =
        old.busy &&
        !widget.busy &&
        widget.turns.isNotEmpty &&
        (widget.turns.last as Map)['state'] == 'done';
    _claim();
    _sync(pulse: answered);
  }

  /// Loops the flow while the agent works; after an answer, one pass
  /// carries a light along the cited threads.
  void _sync({bool pulse = false}) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _looping = false;
      _flow.value = 0;
      return;
    }
    if (widget.busy) {
      if (!_looping) _flow.repeat();
      _looping = true;
    } else if (pulse) {
      _looping = false;
      _flow.forward(from: 0);
    } else if (_looping) {
      _looping = false;
      _flow.value = 0;
    }
  }

  @override
  void dispose() {
    owner._stageKeys.removeAll(_keys);
    owner._composerFocus.removeListener(_focusChanged);
    _localFocus.dispose();
    _flow.dispose();
    super.dispose();
  }

  void _send() {
    final text = widget.input.text.trim();
    if (text.isEmpty || widget.busy || widget.loading) return;
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    _claim();
    final viewport = owner._viewport;
    final width = math.min(420.0, math.max(240.0, viewport.width - 16));
    final open = owner._stageOpen;
    final cited = <String>{
      for (final s
          in ((widget.turns.lastOrNull as Map?)?['result'] as Map?)?['sources']
                  as List? ??
              [])
        if ((s as Map)['object_id'] != null) '${s['object_id']}',
    };
    final bound = <String>{
      for (final s in widget.sources.cast<Map>())
        if ((s['anchor'] as Map?)?['object_id'] != null)
          '${(s['anchor'] as Map)['object_id']}',
    };
    return Stack(
      key: _stage,
      children: [
        if (open)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FlowPainter(
                  owner: owner,
                  stage: _stage,
                  composer: _composer,
                  bound: bound,
                  reading: _readingNow(widget.live, widget.sources),
                  cited: cited,
                  focus: _focusSource,
                  busy: widget.busy,
                  flow: _flow,
                  scheme: cs,
                  repaint: Listenable.merge([
                    owner._camera,
                    owner._scene,
                    _flow,
                  ]),
                ),
              ),
            ),
          ),
        Positioned(
          left: owner._aiPlacement.edge == StudyDockEdge.left ? 8 : null,
          right: owner._aiPlacement.edge == StudyDockEdge.left ? null : 8,
          top: math.max(76, owner._topBarsBottom + 8),
          bottom: 80,
          width: width,
          child: Offstage(
            offstage: !open,
            child: GlassSurface(
              key: _panel,
              radius: Corners.lg,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _headerRow(context, open),
                  Expanded(
                    child: widget.turns.isEmpty
                        ? SingleChildScrollView(child: _welcome(context))
                        : _conversation(context),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(100, viewport.height * .4),
                    ),
                    child: SingleChildScrollView(child: _composerPane(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerRow(BuildContext context, bool open) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final threads = owner._threads;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          MenuAnchor(
            menuChildren: [
              for (final t in threads)
                MenuItemButton(
                  leadingIcon: Icon(
                    t.id == widget.thread?.id
                        ? Icons.check_rounded
                        : Icons.forum_outlined,
                    size: 18,
                  ),
                  onPressed: () => owner._activateThread(t.id),
                  child: Text(t.title),
                ),
              if (threads.isNotEmpty) const Divider(height: Space.sm),
              MenuItemButton(
                leadingIcon: const Icon(Icons.add_comment_outlined, size: 18),
                onPressed: () => owner._activateThread(null),
                child: Text(l10n.studyThreadNew),
              ),
            ],
            builder: (context, menu, _) => GlassSurface(
              radius: Corners.full,
              shadow: false,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => menu.isOpen ? menu.close() : menu.open(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.md,
                    Space.xs + 2,
                    Space.sm,
                    Space.xs + 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          widget.thread?.title ?? l10n.studyThreadNew,
                          style: tt.labelLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: Space.xxs),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            key: const ValueKey('study-ai-close'),
            tooltip: '收起 AI 对话',
            onPressed: () {
              owner._composerFocus.unfocus();
              owner._update(() => owner._stageOpen = false);
            },
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final ideas = [
      l10n.studyIdeaSummary,
      l10n.studyIdeaExplain,
      l10n.studyIdeaQuiz,
    ];
    return GlassSurface(
      depth: GlassDepth.panel,
      radius: Corners.xl,
      padding: const EdgeInsets.fromLTRB(
        Space.xl,
        Space.lg,
        Space.xl,
        Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.studyStageTitle, style: tt.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            l10n.studyStageBody,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final idea in ideas)
                ActionChip(
                  label: Text(idea),
                  onPressed: () {
                    widget.input.text = idea;
                    widget.input.selection = TextSelection.collapsed(
                      offset: idea.length,
                    );
                    owner._composerFocus.requestFocus();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _conversation(BuildContext context) {
    final turns = widget.turns.reversed.toList();
    return ShaderMask(
      // The oldest messages fade into the canvas instead of being cut off.
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black],
        stops: [0, .08],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        reverse: true,
        shrinkWrap: true,
        padding: const EdgeInsets.only(top: Space.xl),
        itemCount: turns.length,
        itemBuilder: (context, i) =>
            _turn(context, turns[i] as Map, newest: i == 0),
      ),
    );
  }

  Widget _turn(BuildContext context, Map raw, {required bool newest}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final answer = '${raw['answer'] ?? ''}';
    final failed =
        raw['error'] != null ||
        raw['state'] == 'interrupted' ||
        raw['state'] == 'error' ||
        raw['state'] == 'cancelled';
    final working = newest && widget.busy && answer.isEmpty && !failed;
    final sources = ((raw['result'] as Map?)?['sources'] as List?) ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: owner._viewport.width < 600 ? 280 : 460,
              ),
              child: GlassSurface(
                depth: GlassDepth.panel,
                radius: Corners.lg,
                shadow: false,
                tint: cs.primaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm + 2,
                ),
                child: SelectableText(
                  '${raw['question']}',
                  style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          if (working)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GlassSurface(
                depth: GlassDepth.panel,
                radius: Corners.full,
                shadow: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Pulse(color: cs.primary),
                    const SizedBox(width: Space.sm),
                    Flexible(
                      child: Text(
                        _stepLabel(widget.live, widget.sources),
                        style: tt.labelLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (answer.isNotEmpty)
            GlassSurface(
              depth: GlassDepth.panel,
              radius: Corners.xl,
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                Space.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectionArea(child: LookMarkdown(answer)),
                  if (raw['state'] == 'done')
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: ValueKey('study-pin-answer-${raw['id']}'),
                        onPressed: () => owner._pinAnswer(raw),
                        icon: const Icon(Icons.push_pin_outlined, size: 16),
                        label: const Text('留在画布'),
                      ),
                    ),
                  if (sources.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        for (final source in sources.cast<Map>())
                          MouseRegion(
                            onEnter: (_) => setState(
                              () =>
                                  _focusSource = '${source['object_id'] ?? ''}',
                            ),
                            onExit: (_) => setState(() => _focusSource = null),
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.my_location_rounded,
                                size: 16,
                              ),
                              label: Text(
                                '${source['label'] ?? l10n.studySourceShow}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => owner._focusSource(
                                StudyAnchor.fromJson(source),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          if (raw['state'] == 'pending')
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                l10n.studyLegacyOperations,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          if (failed)
            GlassSurface(
              depth: GlassDepth.panel,
              radius: Corners.lg,
              shadow: false,
              tint: cs.errorContainer,
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.xs,
                Space.xs,
                Space.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: cs.onErrorContainer,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      '${raw['error'] ?? l10n.studyTurnInterrupted}',
                      style: tt.bodySmall?.copyWith(color: cs.onErrorContainer),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.busy
                        ? null
                        : () => widget.onRetry?.call('${raw['question']}'),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onErrorContainer,
                    ),
                    child: Text(l10n.studyTurnRetry),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _composerPane(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sources = widget.sources.cast<Map>();
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        setState(() => _hover = true);
        return true;
      },
      onLeave: (_) => setState(() => _hover = false),
      onAcceptWithDetails: (v) {
        setState(() => _hover = false);
        widget.onDrop(v.data);
      },
      builder: (context, _, _) => GlassSurface(
        key: _composer,
        depth: GlassDepth.float,
        radius: Corners.xl,
        selected: _hover,
        padding: const EdgeInsets.fromLTRB(
          Space.sm,
          Space.sm,
          Space.sm,
          Space.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sources.isNotEmpty || widget.loading)
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.xs,
                        ),
                        children: [
                          for (final s in sources)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: Space.xs,
                              ),
                              child: _SourcePill(
                                source: s,
                                reading:
                                    _readingNow(
                                      widget.live,
                                      widget.sources,
                                    ).contains(
                                      '${(s['anchor'] as Map?)?['object_id']}',
                                    ),
                                onFocus: () => owner._focusSource(
                                  StudyAnchor.fromJson(s['anchor'] as Map),
                                ),
                                onEditTime:
                                    s['kind'] == 'video' &&
                                        !widget.busy &&
                                        widget.onEditVideo != null
                                    ? () => widget.onEditVideo!(s)
                                    : null,
                                onRemove:
                                    widget.busy || widget.onRemoveSource == null
                                    ? null
                                    : () => widget.onRemoveSource!(s),
                                onHover: (on) => setState(
                                  () => _focusSource = on
                                      ? '${(s['anchor'] as Map?)?['object_id']}'
                                      : null,
                                ),
                              ),
                            ),
                          if (widget.loading)
                            const Center(
                              child: SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.allowImages != null)
                      Tooltip(
                        message: l10n.studyAllowImagesHint,
                        child: FilterChip(
                          avatar: const Icon(
                            Icons.visibility_outlined,
                            size: 16,
                          ),
                          label: Text(l10n.studyAllowImages),
                          selected: widget.allowImages!,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: widget.busy ? null : widget.onAllowImages,
                        ),
                      ),
                    if (widget.onInspectSources != null)
                      IconButton(
                        tooltip: l10n.studyInspectSources,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onInspectSources,
                        icon: const Icon(Icons.manage_search_rounded, size: 20),
                      ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: l10n.studyPickSources,
                  onPressed: widget.busy ? null : widget.onPickSources,
                  icon: Icon(
                    Icons.add_circle_outline_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Focus(
                    // Enter sends, Shift+Enter breaks the line; an open IME
                    // composition keeps Enter for itself.
                    canRequestFocus: false,
                    onKeyEvent: (_, e) {
                      if (e is! KeyDownEvent ||
                          (e.logicalKey != LogicalKeyboardKey.enter &&
                              e.logicalKey != LogicalKeyboardKey.numpadEnter) ||
                          HardwareKeyboard.instance.isShiftPressed ||
                          widget.input.value.composing.isValid) {
                        return KeyEventResult.ignored;
                      }
                      _send();
                      return KeyEventResult.handled;
                    },
                    child: TextField(
                      controller: widget.input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      style: tt.bodyLarge?.copyWith(height: 1.4),
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) => widget.onDraft?.call(),
                      decoration: InputDecoration(
                        hintText: _hover
                            ? l10n.studyComposerDrop
                            : l10n.studyComposerHint,
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: Space.md,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
                AnimatedSwitcher(
                  duration: Motion.short4,
                  transitionBuilder: (c, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(
                      scale: Tween(begin: .25, end: 1.0).animate(a),
                      child: c,
                    ),
                  ),
                  child: widget.busy
                      ? IconButton.filledTonal(
                          key: const ValueKey('stop'),
                          tooltip: l10n.studyStop,
                          onPressed: widget.onStop,
                          icon: const Icon(Icons.stop_rounded),
                        )
                      : IconButton.filled(
                          key: const ValueKey('send'),
                          tooltip: l10n.studySend,
                          onPressed: widget.loading ? null : _send,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                ),
              ],
            ),
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  0,
                  Space.md,
                  Space.xs,
                ),
                child: Text(
                  widget.error!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A bound material in the composer: tap to find it on the canvas.
class _SourcePill extends StatelessWidget {
  const _SourcePill({
    required this.source,
    required this.reading,
    required this.onFocus,
    required this.onHover,
    this.onRemove,
    this.onEditTime,
  });
  final Map source;
  final bool reading;
  final VoidCallback onFocus;
  final ValueChanged<bool> onHover;
  final VoidCallback? onRemove, onEditTime;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final a = source['anchor'] as Map? ?? const {};
    final page = a['page'];
    final label = '${source['label']}';
    final range = source['kind'] == 'video'
        ? l10n.studyVideoRange(
            ((a['time_start_ms'] as num? ?? 0) / 1000).round(),
            ((a['time_end_ms'] as num? ?? 0) / 1000).round(),
          )
        : null;
    final detail = page != null ? l10n.studySourcePage(page) : range;
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: AnimatedContainer(
        duration: Motion.short4,
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(
              color: reading ? cs.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          color: reading
              ? cs.primaryContainer
              : cs.onSurface.withValues(alpha: .06),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onFocus,
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                Space.sm + 2,
                0,
                onRemove == null ? Space.md : 0,
                0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _sourceIcon(source),
                    size: 16,
                    color: reading
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.xs + 2),
                  Tooltip(
                    message: label,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelMedium?.copyWith(
                          color: reading ? cs.onPrimaryContainer : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(width: Space.xs),
                    GestureDetector(
                      onTap: onEditTime,
                      child: Text(
                        detail,
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          decoration: onEditTime == null
                              ? null
                              : TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dotted,
                        ),
                      ),
                    ),
                  ],
                  if (onRemove != null)
                    IconButton(
                      tooltip: l10n.studyRemoveSource,
                      visualDensity: VisualDensity.compact,
                      iconSize: 14,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onRemove,
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft breathing dot for a step in progress (still under reduced motion).
class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});
  final Color color;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.disableAnimationsOf(context)
        ? _c.value = 1
        : _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(
      begin: .35,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _c, curve: Motion.standard)),
    child: ScaleTransition(
      scale: Tween(
        begin: .7,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _c, curve: Motion.standard)),
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        child: const SizedBox.square(dimension: 8),
      ),
    ),
  );
}

/// Threads from bound cards to the composer. A thread at rest is a faint
/// dotted line; the one being read flows toward the composer and its card
/// glows; after an answer, a light travels the cited threads once.
class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.owner,
    required this.stage,
    required this.composer,
    required this.bound,
    required this.reading,
    required this.cited,
    required this.focus,
    required this.busy,
    required this.flow,
    required this.scheme,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final StudyCanvasState owner;
  final GlobalKey stage, composer;
  final Set<String> bound, reading, cited;
  final String? focus;
  final bool busy;
  final Animation<double> flow;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final d = owner.document;
    final stageBox = stage.currentContext?.findRenderObject() as RenderBox?;
    final box = composer.currentContext?.findRenderObject() as RenderBox?;
    if (d == null ||
        stageBox == null ||
        box == null ||
        !box.hasSize ||
        !box.attached) {
      return;
    }
    final top = box.localToGlobal(Offset.zero, ancestor: stageBox);
    final target = top & box.size;
    final ids = {...bound, if (focus != null && focus!.isNotEmpty) focus!};
    final cards = [
      for (final c in d.cards)
        if (ids.contains(c.id) && d.visible(c.layer)) c,
    ];
    if (cards.isEmpty) return;
    final view = Offset.zero & size;
    for (var i = 0; i < cards.length; i++) {
      final c = cards[i];
      final r = Rect.fromLTWH(
        c.rect.left * d.zoom + d.camera.dx,
        c.rect.top * d.zoom + d.camera.dy,
        c.rect.width * d.zoom,
        c.rect.height * d.zoom,
      );
      if (!r.overlaps(view.inflate(80))) continue;
      final end = Offset(
        target.left + target.width * (i + 1) / (cards.length + 1),
        target.top + 1,
      );
      final start = r.bottom < end.dy - 24
          ? Offset(end.dx.clamp(r.left + 20, r.right - 20), r.bottom)
          : Offset(
              r.right < end.dx ? r.right : r.left,
              r.center.dy.clamp(r.top + 20, r.bottom - 20),
            );
      final lift = (end.dy - start.dy).abs() * .5 + 40;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx,
          start.dy + lift,
          end.dx,
          end.dy - lift,
          end.dx,
          end.dy,
        );
      final active = reading.contains(c.id) || c.id == focus;
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = active ? 2 : 1.25
        ..color = scheme.primary.withValues(alpha: active ? .85 : .32);
      _dashed(
        canvas,
        path,
        line,
        phase: active && busy ? flow.value * 12 : 0,
        dash: active ? 8 : 2,
        gap: active ? 6 : 5,
      );
      canvas.drawCircle(
        start,
        active ? 4 : 3,
        Paint()..color = scheme.primary.withValues(alpha: active ? .9 : .5),
      );
      if (active) {
        final glow = .35 + .3 * math.sin(flow.value * math.pi * 2).abs();
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            r.inflate(4),
            Radius.circular(Corners.md * d.zoom + 4),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = scheme.primary.withValues(alpha: busy ? glow : .5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      // After an answer: a light runs once from each cited card to the chat.
      if (!busy && cited.contains(c.id) && flow.value > 0 && flow.value < 1) {
        final metric = path.computeMetrics().firstOrNull;
        final at = metric?.getTangentForOffset(
          metric.length * Curves.easeInOut.transform(flow.value),
        );
        if (at != null) {
          canvas.drawCircle(
            at.position,
            5,
            Paint()
              ..color = scheme.primary
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
          );
        }
      }
    }
  }

  static void _dashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double phase,
    required double dash,
    required double gap,
  }) {
    for (final m in path.computeMetrics()) {
      var d = -phase % (dash + gap);
      while (d < m.length) {
        final s = math.max(0.0, d);
        final e = math.min(m.length, d + dash);
        if (e > s) canvas.drawPath(m.extractPath(s, e), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_FlowPainter o) =>
      !setEquals(o.bound, bound) ||
      !setEquals(o.reading, reading) ||
      !setEquals(o.cited, cited) ||
      o.focus != focus ||
      o.busy != busy ||
      o.scheme != scheme;
}
