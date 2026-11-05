part of 'study_canvas.dart';

const _paperColors = {
  0xffffffff: '白色',
  0xfffff6dd: '米色',
  0xffeef5e8: '浅绿',
  0xffeef0f4: '浅灰',
};

// Layout and interaction reference: Notein 1.2.607.0 on the user's tablet.
// Independently drawn controls; provenance is retained in drawing-controls.md.
extension _StudyToolbars on StudyCanvasState {
  Widget _action(
    String label,
    IconData icon,
    VoidCallback? action, {
    Key? key,
    bool selected = false,
    bool compact = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    // A chosen tool sits in a tonal pill (M3 selected icon button).
    return IconButton(
      key: key,
      tooltip: label,
      onPressed: action,
      isSelected: selected,
      style: IconButton.styleFrom(
        minimumSize: compact ? const Size(32, 32) : const Size(40, 40),
        padding: EdgeInsets.all(compact ? 5 : 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: selected ? cs.secondaryContainer : Colors.transparent,
        foregroundColor: selected ? cs.onSecondaryContainer : cs.onSurface,
        disabledForegroundColor: cs.onSurface.withValues(alpha: .38),
      ),
      icon: Icon(icon, size: compact ? 20 : 22),
    );
  }

  Widget _divider(bool vertical, {bool compact = false}) => SizedBox(
    width: vertical ? 28 : (compact ? 8 : 16),
    height: vertical ? (compact ? 8 : 16) : 28,
    child: Center(
      child: Container(
        width: vertical ? 28 : 1,
        height: vertical ? 1 : 28,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .14),
      ),
    ),
  );

  Widget _topAction(
    String label,
    IconData icon,
    VoidCallback? action, {
    Key? key,
    bool selected = false,
  }) =>
      _action(label, icon, action, key: key, selected: selected, compact: true);

  /// Height of the top controls; macOS leaves room for the window buttons.
  static const double _topBarHeight = 36;
  double get _topBarsInset => Platform.isMacOS ? 28 : Space.sm;
  bool get _stackTopBars => _viewport.width < 900;
  double get _topBarsBottom =>
      _topBarsInset +
      (_stackTopBars ? 2 * _topBarHeight + Space.sm : _topBarHeight);

  /// Related buttons share one glass capsule, as iOS 26 toolbars group
  /// them; a lone action keeps its own circle. Fewer panes also means fewer
  /// backdrop blurs over a playing video.
  Widget _topButtons(String id, List<List<Widget>> groups, {Key? key}) =>
      SizedBox(
        key: key,
        height: _topBarHeight,
        child: Row(
          key: ValueKey('study-top-$id'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var g = 0; g < groups.length; g++) ...[
              if (g > 0)
                SizedBox(width: _viewport.width < 360 ? Space.xs : Space.sm),
              GlassSurface(
                radius: Corners.full,
                padding: EdgeInsets.symmetric(
                  horizontal: groups[g].length > 1 ? Space.xxs : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in groups[g])
                      SizedBox.square(
                        dimension: _topBarHeight,
                        child: Center(child: a),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _fixedTopBars() {
    // 返回 stands alone; the rest of each side is one group.
    final nav = _navigationActions(), act = _canvasActions();
    final navigation = _topButtons('navigation', [
      nav.take(1).toList(),
      nav.skip(1).toList(),
    ], key: _moduleKey);
    final actions = _topButtons('actions', [
      act.take(act.length - 1).toList(),
      [act.last],
    ]);
    final tools = GlassSurface(
      key: _toolbarKey,
      radius: Corners.full,
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      child: SizedBox(
        key: const ValueKey('study-top-tools'),
        height: _topBarHeight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _toolbarActions(),
          ),
        ),
      ),
    );
    return Positioned(
      top: _topBarsInset,
      left: Space.sm,
      right: Space.sm,
      child: SizedBox(
        key: _topBarKey,
        child: _stackTopBars
            ? Column(
                children: [
                  Row(children: [navigation, const Spacer(), actions]),
                  const SizedBox(height: Space.sm),
                  Align(alignment: Alignment.topCenter, child: tools),
                ],
              )
            : Row(
                children: [
                  navigation,
                  const SizedBox(width: Space.lg),
                  Expanded(child: Center(child: tools)),
                  const SizedBox(width: Space.lg),
                  actions,
                ],
              ),
      ),
    );
  }

  List<Widget> _navigationActions() => [
    _topAction('返回', Icons.arrow_back, widget.onBack),
    _topAction('页面与材料', Icons.view_sidebar_outlined, _pageIndex),
    _topAction(
      l10n.studyShelf,
      Icons.inventory_2_outlined,
      () => _toggleShelf(),
      key: const ValueKey('study-open-shelf'),
      selected: _shelfTab != null,
    ),
    _topAction('手写 / 浏览', Icons.draw_outlined, () {
      if (_ink)
        _chooseTool(StudyTool.select);
      else
        _pickPen(_presetIndex);
    }, selected: _ink),
  ];

  List<Widget> _toolbarActions() {
    final d = document!;
    return [
      _topAction(l10n.commonUndo, Icons.undo, d.canUndo ? d.undo : null),
      _topAction(l10n.studyRedo, Icons.redo, d.canRedo ? d.redo : null),
      _divider(false, compact: true),
      _topAction(
        '箭头：选择对象 / 拖动空白或资料页面移动画布',
        Icons.near_me_outlined,
        () => _chooseTool(StudyTool.select),
        key: const ValueKey('study-tool-select'),
        selected: _tool == StudyTool.select,
      ),
      _topAction(
        l10n.studyHandTool,
        Icons.pan_tool_outlined,
        () => _chooseTool(StudyTool.hand),
        key: const ValueKey('study-tool-hand'),
        selected: _tool == StudyTool.hand,
      ),
      _topAction(
        '套索 / 框选',
        Icons.gesture,
        () => _chooseTool(StudyTool.region),
        key: const ValueKey('study-tool-region'),
        selected: _tool == StudyTool.region,
      ),
      _divider(false, compact: true),
      _topAction('插入文字笔记', Icons.text_fields, () => _text()),
      _topAction('插入图片、PDF 或文件', Icons.image_outlined, () => _import()),
      _topAction('课程资料', Icons.folder_open_outlined, _courseMaterials),
      _divider(false, compact: true),
      _topAction(l10n.studyLayers, Icons.layers_outlined, _layers),
      _topAction('纸张背景', Icons.wallpaper_outlined, _paperSettings),
      if (_remotePending) ...[
        TextButton(
          onPressed: () => _resolveRemote(true),
          child: const Text('保留本机'),
        ),
        TextButton(
          onPressed: () => _resolveRemote(false),
          child: const Text('采用另一端'),
        ),
      ],
    ];
  }

  List<Widget> _canvasActions() => [
    PopupMenuButton<String>(
      tooltip: '添加模块',
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.add, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'video':
            _videoModules();
          case 'file':
            _import();
          case 'course':
            _courseMaterials();
          case 'note':
            _text();
          case 'chat':
            _openConversation(newConversation: true, bind: false);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'video', child: Text('视频')),
        PopupMenuItem(value: 'file', child: Text('文件')),
        PopupMenuItem(value: 'course', child: Text('课程资料')),
        PopupMenuItem(value: 'note', child: Text('笔记')),
        PopupMenuItem(value: 'chat', child: Text('AI 对话')),
      ],
    ),
    _topAction('显示全部卡片', Icons.open_in_full, _fit),
    _topAction(
      _status,
      _saveError != null ? Icons.error_outline : Icons.cloud_done_outlined,
      () => flush(),
    ),
    PopupMenuButton<String>(
      tooltip: widget.ctl.lecture?.shortTitle ?? '画布菜单',
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'classic':
            widget.onClassic();
          case 'links':
            _connectionSettings();
          case 'export':
            exportRecovery();
          case 'fit':
            _fit();
          case 'brush':
            _advancedPenSettings();
          case 'paper':
            _paperSettings();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(widget.ctl.lecture?.shortTitle ?? '学习画布'),
        ),
        const PopupMenuItem(value: 'fit', child: Text('显示全部材料')),
        const PopupMenuItem(value: 'brush', child: Text('画笔与橡皮设置')),
        const PopupMenuItem(value: 'links', child: Text('管理知识关联')),
        const PopupMenuItem(value: 'export', child: Text('导出画布副本')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'classic', child: Text(l10n.studyExitCanvas)),
      ],
    ),
  ];

  Future<void> _paperSettings() async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) {
          void change(VoidCallback action) {
            _update(action);
            refresh(() {});
            unawaited(_saveLayout());
          }

          return AlertDialog(
            title: const Text('纸张背景'),
            content: SizedBox(
              width: 280,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final entry in const {
                          'blank': '空白',
                          'ruled': '横线',
                          'dots': '点阵',
                          'grid': '方格',
                        }.entries)
                          Semantics(
                            selected: _paperStyle == entry.key,
                            child: InkWell(
                              onTap: () =>
                                  change(() => _paperStyle = entry.key),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 126,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _paperStyle == entry.key
                                        ? StudyChrome.of(context).accent
                                        : StudyChrome.of(context).line,
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    CustomPaint(
                                      size: const Size(108, 48),
                                      painter: _Paper(
                                        style: entry.key,
                                        color: _paperColor,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(entry.value),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('底色'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in _paperColors.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            backgroundColor: Color(entry.key),
                            selectedColor: Color(entry.key),
                            selected: _paperColor == entry.key,
                            onSelected: (_) =>
                                change(() => _paperColor = entry.key),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pageIndex() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (c) => Dialog(
        child: SizedBox(
          width: 360,
          height: math.min(620, MediaQuery.sizeOf(c).height - 48),
          child: Column(
            children: [
              const ListTile(title: Text('页面与材料')),
              Expanded(
                child: ListView(
                  children: [
                    for (final card in document!.cards)
                      ListTile(
                        leading: Icon(
                          card.type == 'pdf' || card.type == 'pdfdoc'
                              ? Icons.picture_as_pdf_outlined
                              : card.type == 'lecture' || card.type == 'video'
                              ? Icons.play_circle_outline
                              : Icons.description_outlined,
                        ),
                        title: Text(
                          card.title.isEmpty ? card.type : card.title,
                          maxLines: 2,
                        ),
                        onTap: () => Navigator.pop(c, card.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final card = document!.cards.where((c) => c.id == selected).firstOrNull;
    if (card == null) return;
    document!.camera =
        _viewport.center(Offset.zero) - card.rect.center * document!.zoom;
    _cameraChanged();
  }
}
