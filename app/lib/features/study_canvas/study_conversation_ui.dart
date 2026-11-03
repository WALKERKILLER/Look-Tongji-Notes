part of 'study_canvas.dart';

extension _StudyModules on StudyCanvasState {
  Map<String, dynamic> _selectedQuery() {
    final ids = {..._selection, if (_detail.objectId != null) _detail.objectId!}
        .where(
          (id) => document!.cards.any(
            (c) =>
                c.id == id &&
                c.type != 'conversation' &&
                document!.visible(c.layer),
          ),
        )
        .take(12)
        .toList();
    return {
      'revision': document!.revision,
      'objects': ids,
      'selection': _detail.json(),
      'selections': {
        if (_detail.objectId?.isNotEmpty == true && _detail.strokeIds.isEmpty)
          _detail.objectId!: _detail.json(),
      },
      'object_pages': {
        for (final card in document!.cards)
          if (ids.contains(card.id) && card.type == 'pdfdoc')
            card.id: card.page,
      },
      'include_video': ids.contains('lecture'),
      'video_ms': widget.ctl.position.value.inMilliseconds,
      'object_video_ms': {
        for (final id in ids)
          if (_localVideoTimes.containsKey(id)) id: _localVideoTimes[id],
      },
    };
  }

  Future<void> _openConversation({
    bool newConversation = false,
    bool bind = true,
  }) async {
    if (document == null || !document!.editable(document!.activeLayer)) return;
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
    StudyCard? card;
    if (!newConversation)
      card = document!.cards
          .where((c) => c.id == _activeConversation && c.type == 'conversation')
          .firstOrNull;
    if (card == null) {
      final p = _world(_viewport.center(Offset.zero));
      var rect = Rect.fromLTWH(p.dx, p.dy - 200, 520, 620);
      for (
        var i = 0;
        i < 80 && document!.cards.any((c) => c.rect.inflate(20).overlaps(rect));
        i++
      ) {
        rect = rect.shift(const Offset(120, 80));
      }
      card = StudyCard(
        id: studyId(),
        type: 'conversation',
        layer: document!.activeLayer,
        rect: rect,
        title: 'AI 对话',
        conversationId: studyId(),
      );
      document!.checkpoint();
      document!.cards.add(card);
      document!.changed();
      _initialConversations[card.id] = {'query': query, 'visuals': visual};
    } else {
      final state = _conversationKeys[card.id]?.currentState;
      if (bind) await state?.bind(query, visual);
    }
    _activeConversation = card.id;
    _tool = StudyTool.select;
    document!.camera =
        _viewport.center(Offset.zero) - card.rect.center * document!.zoom;
    _cameraChanged();
    _update(() {});
  }

  Future<void> _chooseConversation(StudyCard source) async {
    _selection
      ..clear()
      ..add(source.id);
    _detail.clear();
    final conversations = document!.cards
        .where((c) => c.type == 'conversation')
        .toList();
    if (conversations.isNotEmpty) {
      final target = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('加入哪个 AI 对话？'),
          children: [
            for (final card in conversations)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, card.id),
                child: Text(card.title),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'new'),
              child: const Text('新建 AI 对话'),
            ),
          ],
        ),
      );
      if (target == null || !mounted) return;
      _activeConversation = target == 'new' ? null : target;
    }
    await _openConversation();
  }

  Future<void> _courseMaterials() async {
    final course = widget.ctl.lecture?.courseId;
    if (course == null) {
      _toast('课程信息尚未加载，请稍后重试');
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _CourseMaterials(
        api: widget.api,
        course: course,
        current: widget.ctl.lectureId,
      ),
    );
    if (chosen != null && mounted)
      await _import(courseware: chosen, wholeCourse: true);
  }

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final raw = prefs.getString('study.notein-layout.v2');
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map;
      _update(() {
        _moduleSmall = data['modules_small'] == true;
        _paperStyle =
            const {'blank', 'ruled', 'dots', 'grid'}.contains(data['paper'])
            ? '${data['paper']}'
            : 'ruled';
        _paperColor = _paperColors.containsKey(data['paper_color'])
            ? data['paper_color'] as int
            : 0xffffffff;
        _toolbarSmall = data['tools_small'] == true;
        _dockSmall = data['pens_small'] == true;
        _toolPlacement = StudyDockPlacement.parse(
          data['tools'],
          _toolPlacement,
        );
        _modulePlacement = StudyDockPlacement.parse(
          data['modules'],
          _modulePlacement,
        );
        _penPlacement = StudyDockPlacement.parse(data['pens'], _penPlacement);
      });
    } catch (_) {
      /* Layout preferences are independent of the course document. */
    }
  }

  Future<void> _saveLayout() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'study.notein-layout.v2',
      jsonEncode({
        'paper': _paperStyle,
        'paper_color': _paperColor,
        'tools': _toolPlacement.json(),
        'modules': _modulePlacement.json(),
        'pens': _penPlacement.json(),
        'modules_small': _moduleSmall,
        'tools_small': _toolbarSmall,
        'pens_small': _dockSmall,
      }),
    );
  }

  Future<void> _videoModules() async {
    final action = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('视频模块'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'lecture'),
            child: const Text('定位当前课程视频'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'import'),
            child: const Text('导入本地视频'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'course'),
            child: const Text('从课程资料选择视频'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'import') await _import();
    if (action == 'course') await _courseMaterials();
    if (action == 'lecture') {
      final card = document!.cards.firstWhere((c) => c.type == 'lecture');
      document!.camera =
          _viewport.center(Offset.zero) - card.rect.center * document!.zoom;
      _cameraChanged();
    }
  }
}

class _CourseMaterials extends StatefulWidget {
  const _CourseMaterials({
    required this.api,
    required this.course,
    required this.current,
  });
  final Api api;
  final String course, current;
  @override
  State<_CourseMaterials> createState() => _CourseMaterialsState();
}

class _CourseMaterialsState extends State<_CourseMaterials> {
  List<Map>? items;
  String? error;
  String filter = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      items = null;
      error = null;
    });
    try {
      final out = await widget.api.libraryCatalog(courseId: widget.course);
      if (mounted) setState(() => items = (out as List).cast<Map>());
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map>>{};
    for (final item in items ?? <Map>[]) {
      if (!'${item['name']}'.toLowerCase().contains(filter.toLowerCase()))
        continue;
      final group = '${item['lecture'] ?? '课程公共资料'}';
      (groups[group] ??= []).add(item);
    }
    return AlertDialog(
      title: const Text('本课程全部资料'),
      content: SizedBox(
        width: 680,
        height: 460,
        child: Column(
          children: [
            TextField(
              onChanged: (v) => setState(() => filter = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索文件名 · 按课次分组',
              ),
            ),
            Expanded(
              child: error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!),
                          TextButton(onPressed: load, child: const Text('重试')),
                        ],
                      ),
                    )
                  : items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items!.isEmpty
                  ? const Center(child: Text('这门课程还没有本地资料。可先在资料库下载，或通过“文件”导入。'))
                  : ListView(
                      children: [
                        for (final group in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 18, bottom: 4),
                            child: Text(
                              group.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          for (final item in group.value)
                            ListTile(
                              dense: true,
                              title: Text('${item['name']}'),
                              subtitle: Text(
                                '${item['file_type']} ${item['lecture_id'] == widget.current ? ' · 当前课次' : ''}',
                              ),
                              trailing:
                                  const {
                                    'pdf',
                                    'png',
                                    'jpg',
                                    'jpeg',
                                    'webp',
                                    'txt',
                                    'md',
                                    'mp4',
                                    'mov',
                                    'mkv',
                                    'webm',
                                  }.contains(item['file_type'])
                                  ? TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, item['path']),
                                      child: const Text('放入画布'),
                                    )
                                  : const Text(
                                      '暂不支持此格式',
                                      style: TextStyle(fontSize: 11),
                                    ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ConversationBody extends StatefulWidget {
  const _ConversationBody({
    super.key,
    required this.owner,
    required this.card,
    this.initial,
  });
  final StudyCanvasState owner;
  final StudyCard card;
  final Map? initial;
  @override
  State<_ConversationBody> createState() => _ConversationBodyState();
}

class _ConversationBodyState extends State<_ConversationBody> {
  late final owner = widget.owner;
  final input = TextEditingController();
  Map<String, dynamic>? data;
  Map? preview, live;
  final visuals = <String, Map<String, dynamic>>{};
  final visualFingerprints = <String, String>{};
  String? error, runId;
  bool busy = false, loading = false;
  Timer? saveTimer, pollTimer;
  Future<void> saving = Future.value();
  Map<String, dynamic> get query =>
      Map<String, dynamic>.from(data!['query'] as Map);
  List get turns => data!['turns'] as List;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await owner.widget.api.studyConversation(
        owner.widget.ctl.lectureId,
        widget.card.conversationId,
      );
      if (!mounted) return;
      data = Map<String, dynamic>.from(value as Map);
      input.text = '${data!['draft'] ?? ''}';
      for (final t in turns) {
        if (t['state'] == 'running' || t['state'] == 'preparing') {
          t['state'] = 'interrupted';
          t['error'] = '应用已重开，请重试此问题';
        }
      }
      setState(() {});
      if (widget.initial != null && (data!['revision'] as num) == 0)
        await bind(
          Map<String, dynamic>.from(widget.initial!['query'] as Map),
          (widget.initial!['visuals'] as List).cast<Map<String, dynamic>>(),
        );
      else
        await refreshContext();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<bool> save() async {
    saveTimer?.cancel();
    if (data == null) return false;
    bool ok = true;
    final draft = input.text;
    saving = saving.catchError((_) {}).then((_) async {
      final snapshot = jsonDecode(jsonEncode(data!)) as Map;
      snapshot['draft'] = draft;
      try {
        final out = await owner.widget.api.saveStudyConversation(
          owner.widget.ctl.lectureId,
          widget.card.conversationId,
          snapshot,
        );
        data!['revision'] = out['revision'];
      } catch (e) {
        ok = false;
        if (mounted) setState(() => error = '对话保存失败：$e');
      }
    });
    await saving;
    return ok;
  }

  Future<void> bind(
    Map<String, dynamic> added,
    List<Map<String, dynamic>> images,
  ) async {
    if (data == null || busy) return;
    final q = query;
    q['objects'] = {
      <String>[
        ...((q['objects'] as List?) ?? []).cast<String>(),
        ...((added['objects'] as List?) ?? []).cast<String>(),
      ],
    }.expand((v) => v).toSet().take(12).toList();
    if ((added['selection'] as Map?)?.isNotEmpty == true)
      q['selection'] = added['selection'];
    if (added['include_video'] == true) {
      q['include_video'] = true;
      q['video_ms'] = added['video_ms'];
      q.remove('from_ms');
      q.remove('to_ms');
    }
    q['selections'] = {
      ...?q['selections'] as Map?,
      ...?added['selections'] as Map?,
    };
    q['object_pages'] = {
      ...?q['object_pages'] as Map?,
      ...?added['object_pages'] as Map?,
    };
    q['object_video_ms'] = {
      ...?q['object_video_ms'] as Map?,
      ...?added['object_video_ms'] as Map?,
    };
    data!['query'] = q;
    for (final image in images) {
      visuals['${image['source_id']}'] = image;
      visualFingerprints.remove('${image['source_id']}');
    }
    await save();
    await refreshContext();
  }

  Future<void> refreshContext() async {
    if (data == null || !mounted) return;
    setState(() => loading = true);
    try {
      if (!await owner.flush()) throw const FormatException('画布尚未保存，请先重试保存');
      final q = query..['revision'] = owner.document!.revision;
      data!['query'] = q;
      final out = await owner.widget.api.studyContext(
        owner.widget.ctl.lectureId,
        q,
      );
      if (mounted)
        setState(() {
          preview = out as Map;
          for (final source in preview!['sources'] as List) {
            final id = '${source['id']}';
            if (visuals.containsKey(id))
              visualFingerprints.putIfAbsent(
                id,
                () => '${source['anchor']['fingerprint']}',
              );
          }
          error = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          preview = null;
        });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> removeSource(Map source) async {
    final q = query;
    final id = source['anchor']['object_id'];
    if (source['id'] == 'lecture-video') q['include_video'] = false;
    q['objects'] = (q['objects'] as List? ?? []).where((v) => v != id).toList();
    if (source['id'] == 'selected-ink' ||
        (q['selection'] as Map?)?['object_id'] == id)
      q['selection'] = {};
    (q['selections'] as Map?)?.remove(id);
    (q['object_pages'] as Map?)?.remove(id);
    visuals.remove(source['id']);
    data!['query'] = q;
    await save();
    await refreshContext();
  }

  Future<void> start([String? retry]) async {
    final question = (retry ?? input.text).trim();
    if (question.isEmpty || busy || data == null) return;
    setState(() => busy = true);
    await refreshContext();
    if (preview == null || !mounted) {
      if (mounted) setState(() => busy = false);
      return;
    }
    if (data!['allow_images'] == true) {
      for (final source in preview!['sources'] as List) {
        final id = '${source['id']}';
        if (visuals.containsKey(id) &&
            visualFingerprints[id] != '${source['anchor']['fingerprint']}') {
          setState(() {
            busy = false;
            error = '视觉选区已改变，请重新圈选并加入对话';
          });
          return;
        }
      }
    }
    if (turns.length >= 300) {
      setState(() {
        busy = false;
        error = '此对话已达 300 轮，请新建对话';
      });
      return;
    }
    final turn = <String, dynamic>{
      'id': studyId(),
      'question': question,
      'answer': '',
      'context_key': '',
      'state': 'preparing',
    };
    turns.add(turn);
    input.clear();
    setState(() {
      busy = true;
      error = null;
      live = null;
    });
    if (!await save()) {
      setState(() => busy = false);
      return;
    }
    try {
      final out = await owner.widget.api.startCanvasRun({
        'lecture_id': owner.widget.ctl.lectureId,
        'conversation_id': widget.card.conversationId,
        'question': question,
        'selection': query,
        'allow_images': data!['allow_images'] == true,
        'visuals': data!['allow_images'] == true ? visuals.values.toList() : [],
      });
      runId = '${out['id']}';
      turn['id'] = runId;
      turn['state'] = 'running';
      if (!mounted) {
        await owner.widget.api.cancelCanvasRun(runId!);
        return;
      }
      await save();
      await poll(turn);
    } catch (e) {
      turn['state'] = 'error';
      turn['error'] = '$e';
      if (mounted)
        setState(() {
          busy = false;
          error = '$e';
        });
      await save();
    }
  }

  Future<void> poll(Map turn) async {
    try {
      final out = await owner.widget.api.canvasRun(runId!);
      if (!mounted) return;
      setState(() => live = out as Map);
      if (out['state'] == 'done') {
        turn['answer'] = out['answer'];
        turn['context_key'] = out['context_key'];
        turn['state'] = 'done';
        // Keep only answer provenance. Older hosts' operations must never run here.
        turn['result'] = {'sources': out['sources'] ?? []};
        await save();
        if (mounted) setState(() => busy = false);
      } else if (out['state'] == 'error' || out['state'] == 'cancelled') {
        turn['state'] = out['state'];
        turn['error'] = out['error'];
        setState(() => busy = false);
        await save();
      } else {
        pollTimer = Timer(const Duration(milliseconds: 700), () => poll(turn));
      }
    } catch (e) {
      turn['state'] = 'error';
      turn['error'] = '$e';
      if (mounted) setState(() => busy = false);
      await save();
    }
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    pollTimer?.cancel();
    if (busy && runId != null)
      unawaited(
        owner.widget.api.cancelCanvasRun(runId!).catchError((_) => null),
      );
    if (data != null) unawaited(save());
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (data == null)
      return Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  TextButton(onPressed: load, child: const Text('重试加载')),
                ],
              ),
      );
    final sources = preview?['sources'] as List? ?? [];
    final chrome = StudyChrome.of(context);
    return Listener(
      onPointerDown: (_) => owner._activeConversation = widget.card.id,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DragTarget<String>(
              onAcceptWithDetails: (v) {
                final card = owner.document!.cards
                    .where((c) => c.id == v.data)
                    .firstOrNull;
                if (card != null) {
                  owner._selection
                    ..clear()
                    ..add(card.id);
                  owner._detail.clear();
                  bind(owner._selectedQuery(), []);
                }
              },
              builder: (_, __, ___) => Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: chrome.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '本对话的参考资料',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '查看本次资料内容',
                          onPressed: inspectSources,
                          icon: const Icon(Icons.visibility_outlined, size: 17),
                        ),
                        IconButton(
                          tooltip: '选择参考资料',
                          onPressed: busy ? null : pickSources,
                          icon: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                    if (sources.isEmpty)
                      const Text(
                        '未指定资料 · 可普通提问，或添加参考资料',
                        style: TextStyle(fontSize: 11),
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 110),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          children: [
                            for (final source in sources)
                              InputChip(
                                label: Text(
                                  '${source['label']}${source['anchor']['page'] != null ? ' · 第${source['anchor']['page']}页' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () => owner._focusSource(
                                  StudyAnchor.fromJson(source['anchor'] as Map),
                                ),
                                onDeleted: busy
                                    ? null
                                    : () => removeSource(source as Map),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (sources.any((s) => s['kind'] == 'video'))
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final source in sources)
                              if (source['kind'] == 'video')
                                TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => editVideo(source as Map),
                                  icon: const Icon(Icons.schedule, size: 14),
                                  label: Text(
                                    '${((source['anchor']['time_start_ms'] as num? ?? 0) / 1000).toStringAsFixed(0)}–${((source['anchor']['time_end_ms'] as num? ?? 0) / 1000).toStringAsFixed(0)} 秒',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Checkbox(
                          value: data!['allow_images'] == true,
                          onChanged: busy
                              ? null
                              : (v) {
                                  setState(() => data!['allow_images'] = v);
                                  unawaited(save());
                                },
                        ),
                        const Expanded(
                          child: Text(
                            '允许读取指定的视觉选区',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        if (loading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (turns.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Text(
                        l10n.studyConversationEmpty,
                        style: TextStyle(color: chrome.inkSoft),
                      ),
                    ),
                  for (final raw in turns) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 8),
                      child: Text(
                        '你：${raw['question']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if ('${raw['answer'] ?? ''}'.isNotEmpty)
                      SelectionArea(child: LookMarkdown('${raw['answer']}')),
                    if ((raw['result'] as Map?)?['sources'] is List)
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final source
                              in (raw['result'] as Map)['sources'] as List)
                            ActionChip(
                              avatar: const Icon(Icons.link, size: 14),
                              label: Text('${source['label'] ?? '查看来源'}'),
                              onPressed: () => owner._focusSource(
                                StudyAnchor.fromJson(source as Map),
                              ),
                            ),
                        ],
                      ),
                    if (raw['state'] == 'pending')
                      const Text(
                        '历史画布操作已停用，回答仍保留在对话中。',
                        style: TextStyle(fontSize: 11),
                      ),
                    if (raw['error'] != null || raw['state'] == 'interrupted')
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${raw['error'] ?? '任务中断'}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => start('${raw['question']}'),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
            if (error != null)
              Text(
                error!,
                maxLines: 3,
                style: const TextStyle(color: Colors.red, fontSize: 11),
              ),
            if (busy)
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (live?['trace'] as List? ?? []).isEmpty
                          ? '正在准备模型与资料…'
                          : '正在执行：${(live!['trace'] as List).last['tool']}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  TextButton(
                    onPressed: runId == null
                        ? null
                        : () async {
                            await owner.widget.api.cancelCanvasRun(runId!);
                          },
                    child: const Text('取消'),
                  ),
                ],
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      hintText: '提问、解释或整理资料…',
                      counterText: '',
                    ),
                    onChanged: (_) {
                      saveTimer?.cancel();
                      saveTimer = Timer(
                        const Duration(milliseconds: 500),
                        () => save(),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: '发送',
                  onPressed: busy || loading ? null : () => start(),
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> editVideo(Map source) async {
    final a = source['anchor'] as Map;
    final from = TextEditingController(
      text: ((a['time_start_ms'] as num? ?? 0) / 1000).toStringAsFixed(1),
    );
    final to = TextEditingController(
      text: ((a['time_end_ms'] as num? ?? 60000) / 1000).toStringAsFixed(1),
    );
    String? invalid;
    final range = await showDialog<List<int>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('指定视频区间 · 最多 180 秒'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: from,
                  decoration: const InputDecoration(labelText: '开始时间（秒）'),
                ),
                TextField(
                  controller: to,
                  decoration: const InputDecoration(labelText: '结束时间（秒）'),
                ),
                if (invalid != null) Text(invalid!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final x = double.tryParse(from.text),
                    y = double.tryParse(to.text);
                if (x == null ||
                    y == null ||
                    !x.isFinite ||
                    !y.isFinite ||
                    x < 0 ||
                    y <= x ||
                    y - x > 180) {
                  update(() => invalid = '请输入有效的 0–180 秒区间');
                  return;
                }
                Navigator.pop(c, [(x * 1000).round(), (y * 1000).round()]);
              },
              child: const Text('使用此区间'),
            ),
          ],
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      from.dispose();
      to.dispose();
    });
    if (range == null || !mounted) return;
    final q = query;
    if (source['id'] == 'lecture-video') {
      q['from_ms'] = range[0];
      q['to_ms'] = range[1];
    } else {
      q['video_ranges'] = {
        ...?q['video_ranges'] as Map?,
        '${a['object_id']}': range,
      };
    }
    data!['query'] = q;
    await save();
    await refreshContext();
  }

  void inspectSources() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('本次实际可用的资料'),
        content: SizedBox(
          width: 650,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final source in preview?['sources'] as List? ?? []) ...[
                  Text(
                    '${source['label']} · ${source['availability']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SelectableText('${source['text'] ?? ''}'),
                  const Divider(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> pickSources() async {
    final current = (query['objects'] as List? ?? []).cast<String>().toSet();
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('仅引用勾选的资料'),
          content: SizedBox(
            width: 420,
            height: 330,
            child: ListView(
              children: [
                for (final card in owner.document!.cards.where(
                  (v) =>
                      v.type != 'conversation' &&
                      owner.document!.visible(v.layer),
                ))
                  CheckboxListTile(
                    title: Text(card.title),
                    subtitle: Text(card.type),
                    value: current.contains(card.id),
                    onChanged: (v) => update(() {
                      v == true
                          ? current.add(card.id)
                          : current.remove(card.id);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, current),
              child: const Text('使用这些资料'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    data!['query'] = {
      'objects': selected.take(12).toList(),
      'selection': {},
      'include_video': selected.contains('lecture'),
      'video_ms': owner.widget.ctl.position.value.inMilliseconds,
      'object_video_ms': {
        for (final id in selected)
          if (owner._localVideoTimes.containsKey(id))
            id: owner._localVideoTimes[id],
      },
    };
    visuals.clear();
    await save();
    await refreshContext();
  }
}
