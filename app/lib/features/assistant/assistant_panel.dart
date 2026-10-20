import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/plugins.dart';
import '../../shell.dart';
import '../../theme/prefs.dart';
import '../../theme/tokens.dart';
import '../../widgets/loading.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../courses/course_page.dart';
import '../courses/download_sheet.dart';
import '../../widgets/look_markdown.dart';
import '../library/note_reader.dart';
import '../player/player_page.dart';
import '../plugins/plugin_views.dart';
import '../plugins/plugins_page.dart';
import '../practice/quiz.dart';
import '../schedule/schedule_widgets.dart';
import '../settings/model_meta.dart';
import '../settings/models_page.dart';
import '../settings/provider_presets.dart';
import '../usage/usage_page.dart';
import 'assistant_controller.dart';
import 'bot_avatar.dart';
import 'bot_ops.dart';
import 'bot_page.dart';
import 'bot_widgets.dart';
import 'runtime_setup.dart';

const _toolLabels = {
  'app_guide': ('查阅功能说明', Icons.menu_book_outlined),
  'current_context': ('读取当前界面', Icons.visibility_outlined),
  'list_courses': ('查看课程', Icons.school_outlined),
  'list_lectures': ('查看课次', Icons.event_note_outlined),
  'read_transcript': ('阅读文字稿', Icons.subject_rounded),
  'lecture_info': ('查看课次详情', Icons.info_outline_rounded),
  'search_library': ('搜索课程库', Icons.manage_search_rounded),
  'list_notes': ('查看笔记', Icons.notes_rounded),
  'read_note': ('阅读笔记', Icons.description_outlined),
  'save_note': ('保存笔记', Icons.save_outlined),
  'suggest_actions': ('准备操作', Icons.touch_app_outlined),
  'find_tools': ('加载工具', Icons.extension_outlined),
  'mark_schedule': ('标记日程', Icons.event_available_outlined),
  'list_schedule': ('查看日程', Icons.event_note_outlined),
  'update_schedule': ('修改日程', Icons.edit_calendar_outlined),
  'read_timeline': ('读取大纲', Icons.view_timeline_outlined),
  'generate_timeline': ('生成大纲', Icons.view_timeline_outlined),
  'save_timeline': ('保存大纲', Icons.view_timeline_outlined),
  'list_courseware': ('查看课件', Icons.folder_open_outlined),
  'read_courseware': ('阅读课件', Icons.article_outlined),
  'search_courseware': ('搜索课件', Icons.plagiarism_outlined),
  'view_slides': ('查看 PPT', Icons.slideshow_outlined),
  'view_images': ('查看插图', Icons.image_outlined),
  'create_quiz': ('生成练习', Icons.quiz_outlined),
  'list_quizzes': ('查看练习', Icons.quiz_outlined),
  'read_quiz_results': ('查看作答', Icons.fact_check_outlined),
  'open_page': ('打开页面', Icons.open_in_new_rounded),
  'player': ('控制播放', Icons.smart_display_outlined),
  'read_settings': ('读取设置', Icons.tune_rounded),
  'change_settings': ('调整设置', Icons.tune_rounded),
  'manage_downloads': ('管理下载', Icons.downloading_rounded),
  'download': ('准备下载', Icons.download_outlined),
  'delete_files': ('准备删除文件', Icons.delete_sweep_outlined),
  'manage_course': ('整理课程', Icons.school_outlined),
  'sync_courses': ('同步课程', Icons.sync_rounded),
  'propose_task': ('准备定时任务', Icons.schedule_rounded),
  'toggle_plugin': ('准备开关插件', Icons.extension_outlined),
  'memory_list': ('翻看记忆', Icons.psychology_alt_outlined),
  'memory_read': ('回想', Icons.psychology_alt_outlined),
  'memory_write': ('记下来', Icons.edit_note_rounded),
  'memory_edit': ('改记忆', Icons.edit_note_rounded),
  'memory_append': ('记下来', Icons.edit_note_rounded),
  'memory_delete': ('忘掉', Icons.auto_delete_outlined),
};

/// Opens the assistant: docks it on wide windows, full screen on phones.
void openAssistantPanel(BuildContext context) {
  if (context.sizeClass.index >= SizeClass.expanded.index) {
    context.read<UiPrefs>().update((p) => p.assistantDocked = true);
    return;
  }
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const Scaffold(body: SafeArea(child: AssistantPanel(docked: false))),
  ));
}

/// Opens a course's agent in the assistant (the course page's 课程助手).
Future<void> openCourseAssistant(BuildContext context, String courseId, String title) async {
  final a = context.read<AssistantController>();
  openAssistantPanel(context);
  await a.openCourseAgent(courseId, title);
}

/// Shows the assistant over the current screen in a sheet, so the user keeps
/// their place (practice, task history).
Future<void> showAssistantSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: AssistantPanel(docked: true, embedded: true)),
    );

/// Resident assistant: docked beside the shell on wide windows, full screen on
/// phones, and as a tab inside the player.
class AssistantPanel extends StatefulWidget {
  const AssistantPanel({super.key, required this.docked, this.embedded = false});
  final bool docked;

  /// Inside another surface (player tab): no close/undock controls.
  final bool embedded;

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _history = false;
  bool _atBottom = true;
  StreamSubscription? _ops;

  @override
  void initState() {
    super.initState();
    final assistant = context.read<AssistantController>();
    _focus.addListener(() => assistant.setComposerFocused(_focus.hasFocus));
    // A full-screen panel steps aside when the bot opens a tab behind it.
    if (!widget.docked && !widget.embedded) {
      _ops = assistant.appOps.listen((op) {
        const tabs = {'home', 'courses', 'course', 'note', 'schedule', 'downloads', 'library', 'tasks', 'plugins', 'settings'};
        if (!mounted || op['op'] != 'open' || !tabs.contains(op['target'])) return;
        final route = ModalRoute.of(context);
        if (route != null) Navigator.of(context).removeRoute(route);
      });
    }
    _scroll.addListener(() {
      final b = !_scroll.hasClients || _scroll.position.pixels <= 48;
      if (b != _atBottom) setState(() => _atBottom = b);
    });
    final a = context.read<AssistantController>();
    if (a.ready && a.models == null) a.loadModels();
    if (a.ready && a.sessions.isEmpty) a.refreshSessions();
  }

  @override
  void dispose() {
    _ops?.cancel();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final a = context.read<AssistantController>();
    final t = _input.text;
    if (t.trim().isEmpty || a.busy) return;
    _input.clear();
    a.send(t);
    _toBottom();
  }

  void _toBottom() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: Motion.medium2, curve: Motion.emphasized);
  }

  void runAction(Map<String, dynamic> act) {
    final players = context.read<PlayerHub>();
    final lectureId = '${act['lecture_id'] ?? ''}';
    final courseId = '${act['course_id'] ?? ''}';
    final secs = (act['seconds'] as num?)?.toInt();
    final root = Navigator.of(context, rootNavigator: true);
    void leaveFullscreenPanel() {
      if (!widget.docked && !widget.embedded) Navigator.of(context).maybePop();
    }

    switch (act['kind']) {
      case 'seek':
        final p = players.value;
        if (p != null && (lectureId.isEmpty || p.lectureId == lectureId)) {
          p.seekTo((secs ?? 0) * 1000);
          leaveFullscreenPanel();
        } else if (lectureId.isNotEmpty) {
          leaveFullscreenPanel();
          root.push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: lectureId, startMs: (secs ?? 0) * 1000)));
        }
      case 'open_lecture':
        if (lectureId.isEmpty) return;
        leaveFullscreenPanel();
        root.push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: lectureId, startMs: secs == null ? null : secs * 1000)));
      case 'open_course':
        if (courseId.isEmpty) return;
        leaveFullscreenPanel();
        if (widget.embedded) root.maybePop();
        ShellNav.push(Tabs.courses, CoursePage(courseId: courseId));
      case 'open_note':
        final id = '${act['note_id'] ?? ''}';
        if (id.isEmpty) return;
        leaveFullscreenPanel();
        if (widget.embedded) root.maybePop();
        ShellNav.push(Tabs.library, NotePage(noteId: id));
      case 'download':
        if (lectureId.isEmpty) return;
        showDownloadSheet(context, [lectureId]);
      case 'open_schedule':
        leaveFullscreenPanel();
        if (widget.embedded) root.maybePop();
        ShellNav.goTo(Tabs.schedule);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AssistantController>();
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      _header(context, a),
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: _body(context, a)),
          // Session history slides over the conversation.
          AnimatedPositioned(
            duration: Motion.medium4,
            curve: Motion.emphasized,
            top: 0,
            bottom: 0,
            left: _history ? 0 : -400,
            width: 320,
            child: IgnorePointer(ignoring: !_history, child: _historyPanel(context, a)),
          ),
          if (!_atBottom)
            Positioned(
              right: Space.lg,
              bottom: Space.md,
              child: FloatingActionButton.small(
                heroTag: null,
                backgroundColor: cs.surfaceContainerHighest,
                onPressed: _toBottom,
                child: const Icon(Icons.arrow_downward_rounded),
              ),
            ),
        ]),
      ),
      if (a.ready) _composer(context, a),
    ]);
  }

  Widget _header(BuildContext context, AssistantController a) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isBot = a.view == 'bot';
    final course = a.course ?? a.pendingCourse;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, Space.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SizedBox(width: Space.xs),
          Tooltip(
            message: '${a.botName} · ${kBotMoodLabels[a.mood]}',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const BotPage())),
              child: Padding(
                padding: const EdgeInsets.all(Space.xs),
                child: BotAvatar(size: 36, shape: a.botShape, color: a.botColor, mood: a.mood),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          Flexible(
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              segments: [
                ButtonSegment(value: 'bot', label: Text(a.botName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const ButtonSegment(value: 'sessions', label: Text('会话')),
              ],
              selected: {a.view},
              onSelectionChanged: a.busy
                  ? null
                  : (v) {
                      setState(() => _history = false);
                      v.first == 'bot' ? a.showBot() : a.showSessions();
                    },
            ),
          ),
          const Spacer(),
          if (!isBot) IconButton(tooltip: '新会话', onPressed: a.busy ? null : a.newChat, icon: const Icon(Icons.add_comment_outlined)),
          if (!widget.embedded)
          IconButton(
            tooltip: widget.docked ? '收起' : '关闭',
            onPressed: () {
              if (widget.docked) {
                context.read<UiPrefs>().update((p) => p.assistantDocked = false);
              } else {
                Navigator.of(context).maybePop();
              }
            },
            icon: Icon(widget.docked ? Icons.last_page_rounded : Icons.close_rounded, color: cs.onSurfaceVariant),
          ),
        ]),
        const SizedBox(height: Space.xs),
        Row(children: [
          if (!isBot)
            IconButton(
              tooltip: '全部会话',
              isSelected: _history,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() => _history = !_history);
                if (_history) a.refreshSessions();
              },
              icon: const Icon(Icons.forum_outlined),
            )
          else
            const SizedBox(width: Space.sm),
          if (!isBot && course != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: Chip(
                  avatar: Icon(Icons.school_outlined, size: 16, color: cs.onSecondaryContainer),
                  label: Text(course.title.isEmpty ? '课程助手' : course.title, overflow: TextOverflow.ellipsis),
                  backgroundColor: cs.secondaryContainer,
                  labelStyle: tt.labelMedium?.copyWith(color: cs.onSecondaryContainer),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          Flexible(child: _ModelChip(a: a)),
          if (a.stats?['context'] is Map) _ContextMeter(a: a),
        ]),
      ]),
    );
  }

  Widget _historyPanel(BuildContext context, AssistantController a) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 2,
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(Corners.xl)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.sm),
          child: Row(children: [
            Expanded(child: Text('全部会话', style: tt.titleSmall)),
            IconButton(onPressed: () => setState(() => _history = false), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Expanded(child: _sessionList(context, a)),
      ]),
    );
  }

  /// Course agents grouped by course, then other chats and scheduled runs.
  Widget _sessionList(BuildContext context, AssistantController a) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final groups = <String, List<ChatSession>>{};
    for (final s in a.sessions.where((s) => s.kind != 'bot')) {
      final g = switch (s.kind) {
        'course' => s.course.isEmpty ? '课程助手' : s.course,
        'task' => '定时任务',
        _ => '其他对话',
      };
      groups.putIfAbsent(g, () => []).add(s);
    }
    final order = [
      ...groups.keys.where((k) => k != '其他对话' && k != '定时任务'),
      if (groups.containsKey('其他对话')) '其他对话',
      if (groups.containsKey('定时任务')) '定时任务',
    ];
    if (order.isEmpty) return Center(child: Text('还没有会话', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      children: [
        for (final g in order) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xs),
            child: Text(g, style: tt.labelLarge?.copyWith(color: cs.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          for (final s in groups[g]!) _sessionTile(context, a, s),
        ],
      ],
    );
  }

  Widget _sessionTile(BuildContext context, AssistantController a, ChatSession s) {
    final cs = Theme.of(context).colorScheme;
    final on = s.id == a.sessionId;
    return ListTile(
      selected: on,
      selectedTileColor: cs.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.full)),
      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${fmtRelative(s.modified)} · ${s.messages} 条'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded, size: 20),
        tooltip: '删除',
        onPressed: () => a.deleteSession(s.id),
      ),
      onTap: () {
        a.openSession(s.id);
        setState(() => _history = false);
      },
    );
  }

  Widget _body(BuildContext context, AssistantController a) {
    if (!a.ready) {
      if (a.agentState != 'disabled' && a.agentState != 'crashed') return const CenteredLoader(label: '正在启动助手');
      final cs = Theme.of(context).colorScheme;
      return ListView(padding: const EdgeInsets.all(Space.lg), children: [
        Text('助手没有启动', style: Theme.of(context).textTheme.titleMedium),
        if (a.agentError.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(a.agentError, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
        const SizedBox(height: Space.lg),
        const Center(child: RuntimeSetupCard()),
      ]);
    }
    if (a.models != null && a.selected == null) {
      return EmptyState(
        icon: Icons.key_outlined,
        title: '先配置一个模型',
        body: '助手通过 Pi SDK 调用你自己的模型服务。填入 API Key，或导入 Pi CLI 的配置。',
        action: FilledButton.icon(
          onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const ModelsPage())),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('配置模型'),
        ),
      );
    }
    if (a.loadingSession) return const CenteredLoader();
    if (a.messages.isEmpty) return _welcome(context, a);
    final prefs = context.watch<UiPrefs>();
    final msgs = a.messages.reversed.toList();
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * prefs.chatTextScale)),
      child: SelectionArea(
        child: ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
          itemCount: msgs.length,
          itemBuilder: (context, i) {
            final m = msgs[i];
            final isLast = i == 0;
            return m.role == 'user'
                ? _UserBubble(text: m.text)
                : _AssistantTurn(msg: m, last: isLast, onAction: runAction, onRetry: isLast && !m.streaming ? a.retryLast : null);
          },
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context, AssistantController a) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screen = context.watch<ScreenContext>().value;
    final inPlayer = context.watch<PlayerHub>().value != null;
    final isBot = a.view == 'bot';
    final course = a.pendingCourse ?? a.course;
    final suggestions = isBot
        ? [
            if (inPlayer) '把播放速度调到 1.5 倍',
            if ((screen['course_id'] ?? '').isNotEmpty) '下载这门课最近三节的视频和转写',
            '把界面字号调大一点',
            '记住：我更喜欢先给结论的简短回答',
            '每周日晚上帮我复习本周的课',
            '暂停所有下载',
          ]
        : [
            if (inPlayer) ...['总结这节课到目前为止讲了什么', '把这节课整理成一份复习笔记', '刚才提到的概念在哪些课里出现过？'],
            if (!inPlayer && course != null) ...['这门课最近几节讲了什么？', '帮我挑出还没看的课', '出一组题考考我这门课的重点'],
            '这个 App 能帮我做什么？',
            '最近有哪些课还没看？',
            '在我的课程库里搜索“期中”',
          ];
    final (title, body) = isBot
        ? ('我是 ${a.botName}', '我会记住你告诉我的事，也能替你在应用里动手：调设置、整理课程、管理下载、安排定时任务。下载和删除这类操作会先给你一张卡片确认。')
        : course != null
            ? ('${course.title.isEmpty ? '课程' : '《${course.title}》'}助手', '这个会话只围绕这门课：讲解、找知识点、整理笔记、出题。关于你的偏好来自 ${a.botName} 的记忆。')
            : ('有什么可以帮你？', '我能读取课表、文字稿和笔记，帮你整理内容、定位知识点。下载由你点按钮决定。');
    return ListView(padding: const EdgeInsets.all(Space.xl), children: [
      const SizedBox(height: Space.lg),
      Center(
        child: isBot
            ? GestureDetector(
                onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const BotPage())),
                child: BotAvatar(size: 112, shape: a.botShape, color: a.botColor, mood: a.mood),
              )
            : Container(
                width: 72,
                height: 72,
                decoration: ShapeDecoration(
                  color: course != null ? cs.secondaryContainer : cs.tertiaryContainer,
                  shape: const StarBorder(points: 6, innerRadiusRatio: 0.72, pointRounding: 0.6, valleyRounding: 0.4),
                ),
                child: Icon(course != null ? Icons.school_rounded : Icons.auto_awesome_rounded,
                    color: course != null ? cs.onSecondaryContainer : cs.onTertiaryContainer, size: 30),
              ),
      ),
      const SizedBox(height: Space.lg),
      Text(title, style: tt.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: Space.xs),
      Text(body, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5), textAlign: TextAlign.center),
      if (!isBot && course == null && (screen['course_id'] ?? '').isNotEmpty) ...[
        const SizedBox(height: Space.md),
        Center(
          child: FilledButton.tonalIcon(
            onPressed: () => a.openCourseAgent(screen['course_id']!, screen['course'] ?? '', fresh: true),
            icon: const Icon(Icons.school_outlined, size: 18),
            label: Text('改为「${screen['course'] ?? '当前课程'}」的课程助手', overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      const SizedBox(height: Space.xl),
      for (final s in suggestions.take(isBot ? 4 : 5))
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Corners.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(Corners.lg),
              onTap: () {
                _input.text = s;
                _send();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                child: Row(children: [
                  Expanded(child: Text(s, style: tt.bodyMedium)),
                  Icon(Icons.north_east_rounded, size: 16, color: cs.onSurfaceVariant),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _composer(BuildContext context, AssistantController a) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screen = context.watch<ScreenContext>().value;
    final player = context.watch<PlayerHub>().value;
    final ctxLabel = player != null ? '正在播放 · 助手可见当前进度' : '当前：${screen['course'] ?? screen['screen'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.md),
      child: Container(
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(Corners.xl)),
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.sm, Space.sm, Space.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const SizedBox(width: Space.md),
            Icon(player != null ? Icons.play_circle_outline_rounded : Icons.my_location_rounded, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(child: Text(ctxLabel, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          _ModeChips(context_: {'session_id': a.sessionId}),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _PlusMenu(
              context_: {'session_id': a.sessionId},
              onPrompt: (p) {
                if (a.busy) return;
                a.send(p);
                _toBottom();
              },
            ),
            Expanded(
              child: CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.enter): _send},
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '问点什么… (Shift+Enter 换行)',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            ListenableBuilder(
              listenable: _input,
              builder: (context, _) => AnimatedSwitcher(
                duration: Motion.short4,
                transitionBuilder: (c, an) => ScaleTransition(scale: an, child: c),
                child: a.busy
                    ? IconButton.filledTonal(key: const ValueKey('stop'), tooltip: '停止', onPressed: a.stop, icon: const Icon(Icons.stop_rounded))
                    : IconButton.filled(
                        key: const ValueKey('send'),
                        tooltip: '发送 (Enter)',
                        onPressed: _input.text.trim().isEmpty ? null : _send,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// The composer's "+" menu: plugin actions for the chat, and the way to
/// manage plugins.
class _PlusMenu extends StatelessWidget {
  const _PlusMenu({required this.context_, required this.onPrompt});
  final Map<String, dynamic> context_;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    final entries = store.entries('actions', surface: 'composer.plus');
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final e in entries)
          MenuItemButton(
            leadingIcon: Icon(pluginIcon(e.icon), size: 20),
            trailingIcon: (store.byId(e.pluginId)?['status'] as Map?)?['active'] == true ? Icon(Icons.check_rounded, size: 18, color: cs.primary) : null,
            onPressed: () => runPluginEntry(context, e, context_, onPrompt: onPrompt),
            child: Text(e.title),
          ),
        if (entries.isNotEmpty) const Divider(height: Space.sm),
        MenuItemButton(
          leadingIcon: const Icon(Icons.explore_outlined, size: 20),
          onPressed: store.ready ? () => openPlugins(context) : null,
          child: const Text('发现插件'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.extension_outlined, size: 20),
          onPressed: store.ready ? () => openPlugins(context, installed: true) : null,
          child: Text('管理插件', style: tt.bodyMedium),
        ),
      ],
      builder: (context, c, _) => Padding(
        padding: const EdgeInsets.only(right: Space.xs, bottom: 2),
        child: IconButton(
          tooltip: '更多功能',
          visualDensity: VisualDensity.compact,
          onPressed: () => c.isOpen ? c.close() : c.open(),
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ),
    );
  }
}

/// Composer modes that plugins switched on (a toggle action whose status is
/// `{active: true}`), each removable in place.
class _ModeChips extends StatelessWidget {
  const _ModeChips({required this.context_});
  final Map<String, dynamic> context_;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    final on = [
      for (final e in store.entries('actions', surface: 'composer.plus'))
        if ((store.byId(e.pluginId)?['status'] as Map?)?['active'] == true) e,
    ];
    return AnimatedSize(
      duration: Motion.medium2,
      curve: Motion.emphasized,
      alignment: Alignment.topLeft,
      child: on.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, 0, 0),
              child: Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
                for (final e in on)
                  InputChip(
                    avatar: Icon(pluginIcon(e.icon), size: 18),
                    label: Text(e.title),
                    selected: true,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    deleteButtonTooltipMessage: '关闭',
                    onDeleted: () => runPluginEntry(context, e, context_),
                    onPressed: () {},
                  ),
              ]),
            ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.a});
  final AssistantController a;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final providers = jsonProviders(a.models);
    final sel = a.selected;
    return MenuAnchor(
      menuChildren: [
        for (final p in providers.where((p) => p['configured'] == true))
          SubmenuButton(
            leadingIcon: ProviderLogo(providerId: '${p['id']}', name: '${p['name']}', size: 22),
            menuChildren: [
              for (final m in (p['models'] as List).cast<Map>().where((m) => m['available'] == true).take(12))
                MenuItemButton(
                  leadingIcon: Icon(sel != null && sel['provider'] == p['id'] && sel['model'] == m['id'] ? Icons.check_rounded : null, size: 18),
                  trailingIcon: m['reasoning'] == true ? const Icon(Icons.psychology_outlined, size: 16) : null,
                  onPressed: () => a.setPrefs({'provider': p['id'], 'model': m['id']}),
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: Text('${m['name']}', overflow: TextOverflow.ellipsis)),
                ),
            ],
            child: Text('${p['name']}'),
          ),
        if (sel?['reasoning'] == true) ...[
          const Divider(),
          SubmenuButton(
            leadingIcon: const Icon(Icons.psychology_outlined, size: 18),
            menuChildren: [
              for (final (k, l) in const [('off', '关闭'), ('minimal', '最少'), ('low', '低'), ('medium', '中'), ('high', '高'), ('xhigh', '最高')])
                MenuItemButton(
                  leadingIcon: Icon(a.thinking == k ? Icons.check_rounded : null, size: 18),
                  onPressed: () => a.setPrefs({'thinking': k}),
                  child: Text(l),
                ),
            ],
            child: const Text('思考强度'),
          ),
        ],
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.search_rounded, size: 18),
          onPressed: () => showModelPicker(context),
          child: const Text('搜索全部模型…'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.tune_rounded, size: 18),
          onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const ModelsPage())),
          child: const Text('模型设置…'),
        ),
      ],
      builder: (context, m, _) => ActionChip(
        avatar: sel == null ? Icon(Icons.bolt_rounded, size: 16, color: cs.primary) : ProviderLogo(providerId: '${sel['provider']}', size: 20),
        label: Text(a.modelLabel, overflow: TextOverflow.ellipsis),
        onPressed: () {
          if (a.models == null) a.loadModels();
          m.isOpen ? m.close() : m.open();
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.full)),
        side: BorderSide.none,
        backgroundColor: cs.surfaceContainerHigh,
      ),
    );
  }
}

/// Ring showing how full the model's context window is, from Pi session stats.
class _ContextMeter extends StatelessWidget {
  const _ContextMeter({required this.a});
  final AssistantController a;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = (a.stats!['context'] as Map);
    final window = (c['window'] as num?) ?? 0;
    final used = (c['tokens'] as num?) ?? 0;
    var pct = (c['percent'] as num?)?.toDouble() ?? (window > 0 ? used / window * 100 : 0);
    if (pct <= 1 && used > 0 && window > 0 && used / window > 0.01) pct *= 100;
    final frac = (pct / 100).clamp(0.0, 1.0);
    final color = frac > 0.85 ? cs.error : frac > 0.6 ? cs.tertiary : cs.primary;
    final tokens = (a.stats!['tokens'] as Map?) ?? const {};
    final cost = (a.stats!['cost'] as num?) ?? 0;
    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('上下文 ${fmtTokens(used)} / ${fmtTokens(window)}（${pct.round()}%）', style: tt.titleSmall),
            const SizedBox(height: 4),
            Text('本对话累计 输入 ${fmtTokens((tokens['input'] as num?) ?? 0)} · 输出 ${fmtTokens((tokens['output'] as num?) ?? 0)}'
                '${((tokens['cacheRead'] as num?) ?? 0) > 0 ? ' · 缓存命中 ${fmtTokens(tokens['cacheRead'] as num)}' : ''}',
                style: tt.bodySmall),
            if (cost > 0) Text('估算费用 \$${cost.toStringAsFixed(4)}', style: tt.bodySmall),
            const SizedBox(height: 4),
            Text('接近上限时 Pi 会自动压缩较早的对话。', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.compress_rounded, size: 18),
          onPressed: a.busy || a.compacting ? null : a.compact,
          child: const Text('立即压缩上下文'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.insights_outlined, size: 18),
          onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const UsagePage())),
          child: const Text('查看用量'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.schedule_rounded, size: 18),
          onPressed: () {
            // Close the assistant when it covers the window, then show the tab.
            Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
            ShellNav.goTo(Tabs.tasks);
          },
          child: const Text('定时任务'),
        ),
      ],
      builder: (context, m, _) => IconButton(
        tooltip: '上下文用量 ${pct.round()}%',
        onPressed: () => m.isOpen ? m.close() : m.open(),
        icon: a.compacting
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
            : SizedBox(
                width: 22,
                height: 22,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: frac),
                  duration: Motion.long2,
                  curve: Motion.emphasized,
                  builder: (_, v, _) => CircularProgressIndicator(
                    value: v,
                    strokeWidth: 3,
                    color: color,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ),
      ),
    );
  }
}

List<Map<String, dynamic>> jsonProviders(Map<String, dynamic>? models) =>
    ((models?['providers'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bubble = Flexible(
      child: Container(
        margin: const EdgeInsets.only(top: Space.lg, bottom: Space.sm, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(Corners.xl),
            topRight: Radius.circular(Corners.xl),
            bottomLeft: Radius.circular(Corners.xl),
            bottomRight: Radius.circular(Corners.sm),
          ),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onPrimaryContainer, height: 1.5)),
      ),
    );
    return Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.end, children: [
      bubble,
      const Padding(padding: EdgeInsets.only(left: Space.sm, bottom: Space.sm), child: UserAvatar(size: 28)),
    ]);
  }
}

class _AssistantTurn extends StatelessWidget {
  const _AssistantTurn({required this.msg, required this.last, required this.onAction, this.onRetry});
  final ChatMessage msg;
  final bool last;
  final ValueChanged<Map<String, dynamic>> onAction;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final prefs = context.watch<UiPrefs>();
    final children = <Widget>[];
    // Bare timestamps refer to the lecture the turn's tools worked on, else the open player.
    var ctxLecture = '';
    for (final b in msg.blocks) {
      var a = b.args;
      if (a is String) a = a.startsWith('{') ? (() { try { return jsonDecode(a as String); } catch (_) { return null; } })() : null;
      if (b.kind == 'tool' && a is Map && a['lecture_id'] != null) ctxLecture = '${a['lecture_id']}';
    }
    for (var i = 0; i < msg.blocks.length; i++) {
      final b = msg.blocks[i];
      final live = msg.streaming && i == msg.blocks.length - 1;
      switch (b.kind) {
        case 'thinking':
          if (prefs.showThinking && b.text.trim().isNotEmpty) children.add(_ThinkingBlock(block: b, live: live));
        case 'tool':
          children.add(_ToolCard(block: b));
          if (b.actions.isNotEmpty) children.add(_Actions(actions: b.actions, onAction: onAction));
          final d = b.details;
          final op = b.appOp;
          if (op != null && !b.error) children.add(_appChip(context, b, op));
          final proposal = b.proposal;
          if (proposal != null) {
            final a = context.read<AssistantController>();
            children.add(ProposalCard(
              key: ValueKey(proposal['id']),
              proposal: proposal,
              onApply: () => a.applyProposal(b),
              onDismiss: () => a.dismissProposal(b),
              onUndo: () => a.undoProposal(b),
            ));
          }
          if (d?['schedule'] is Map && b.name == 'mark_schedule') {
            children.add(ScheduleChatCard(data: (d!['schedule'] as Map).cast<String, dynamic>(), duplicate: d['duplicate'] == true));
          }
          if (b.name == 'view_slides' && d?['slides'] is List) {
            children.add(_SlideStrip(lectureId: '${d!['lecture_id'] ?? ''}', slides: [for (final x in d['slides'] as List) (x as num).toInt()], mode: '${d['mode'] ?? ''}'));
          }
          if (b.name == 'create_quiz' && d?['quiz'] is Map) {
            final q = Quiz((d!['quiz'] as Map).cast<String, dynamic>());
            children.add(QuizCard(key: ValueKey(q.id), quiz: q, live: true));
          }
          if (b.name == 'save_note' && d?['note'] is Map) {
            children.add(_NoteCard(note: (d!['note'] as Map).cast<String, dynamic>(), onAction: onAction));
          }
          if (d?['view'] is Map) children.add(PluginView(view: (d!['view'] as Map).cast<String, dynamic>()));
          if (d?['timeline'] is List && (d!['timeline'] as List).isNotEmpty) {
            children.add(_OutlineCard(lectureId: '${d['lecture_id'] ?? ''}', chapters: jsonList(d['timeline']), onAction: onAction));
          }
        default:
          if (b.text.isNotEmpty) {
            children.add(LookMarkdown(
              b.text,
              style: tt.bodyMedium?.copyWith(height: 1.65),
              lectureId: ctxLecture,
              onRef: (r) => openRef(context, r,
                  lectureId: ctxLecture,
                  onSeek: (t) => onAction({'kind': 'seek', 'lecture_id': t.lectureId.isNotEmpty ? t.lectureId : ctxLecture, 'seconds': t.seconds})),
              isStreaming: live,
              animation: prefs.reduceMotion ? GptMarkdownAnimation.none : prefs.streamAnimation,
              codeBuilder: (context, name, code, closed) => (closed ? lookViewBlock(context, name, code) : null) ?? _CodeBlock(lang: name, code: code),
            ));
          }
      }
    }
    if (msg.streaming && (msg.blocks.isEmpty || msg.status != null)) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(children: [
          const ExpressiveLoader(size: 22),
          const SizedBox(width: Space.sm),
          Text(msg.status ?? '正在思考…', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ));
    }
    if (msg.error != null) {
      children.add(Container(
        margin: const EdgeInsets.only(top: Space.sm),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(Corners.md)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline_rounded, size: 18, color: cs.onErrorContainer),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(msg.error!, style: tt.bodySmall?.copyWith(color: cs.onErrorContainer))),
        ]),
      ));
    }
    if (!msg.streaming) children.add(_Footer(msg: msg, onRetry: onRetry));

    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final c in children) Padding(padding: const EdgeInsets.only(bottom: Space.xs), child: c),
    ]);
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.sm),
      child: prefs.chatBubbles
          ? Container(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xs),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(Corners.sm),
                  topRight: Radius.circular(Corners.xl),
                  bottomLeft: Radius.circular(Corners.xl),
                  bottomRight: Radius.circular(Corners.xl),
                ),
              ),
              child: content,
            )
          : content,
    );
  }
}

Widget _appChip(BuildContext context, ChatBlock b, Map<String, dynamic> op) {
  final a = context.read<AssistantController>();
  final undoable = '${op['proposal_id'] ?? ''}'.isNotEmpty;
  final icon = switch (op['op']) {
    'open' => Icons.open_in_new_rounded,
    'player' => Icons.smart_display_outlined,
    _ => Icons.check_circle_outline_rounded,
  };
  return AppOpChip(
    label: appOpLabel(op),
    icon: icon,
    done: op['undone'] == true,
    actionLabel: op['op'] == 'open' ? '返回' : '撤销',
    onAction: op['op'] == 'open'
        ? (BotOps.canGoBack ? () async => BotOps.back() : null)
        : undoable
            ? () => a.undoApplied(b)
            : null,
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.msg, this.onRetry});
  final ChatMessage msg;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final text = msg.blocks.where((b) => b.kind == 'text').map((b) => b.text).join('\n\n');
    final u = msg.usage;
    final meta = [
      if (msg.model != null) msg.model!.split('/').last,
      if (u != null) '${u['input'] ?? 0}→${u['output'] ?? 0} tokens',
    ].join(' · ');
    return Row(children: [
      if (text.isNotEmpty)
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          tooltip: '复制',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            showSnack(context, '已复制');
          },
          icon: const Icon(Icons.copy_rounded),
        ),
      if (onRetry != null)
        IconButton(visualDensity: VisualDensity.compact, iconSize: 16, tooltip: '重新生成', onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
      const SizedBox(width: Space.xs),
      Flexible(child: Text(meta, style: tt.labelSmall?.copyWith(color: cs.outline), overflow: TextOverflow.ellipsis)),
    ]);
  }
}

class _ThinkingBlock extends StatefulWidget {
  const _ThinkingBlock({required this.block, required this.live});
  final ChatBlock block;
  final bool live;
  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool? _open;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final open = _open ?? widget.live;
    return AnimatedContainer(
      duration: Motion.medium2,
      curve: Motion.emphasized,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: open ? 1 : 0.6),
        borderRadius: BorderRadius.circular(Corners.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(Corners.lg),
          onTap: () => setState(() => _open = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              widget.live ? const ExpressiveLoader(size: 16) : Icon(Icons.psychology_outlined, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Text(widget.live ? '思考中' : '思考过程', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: Motion.medium1,
                child: Icon(Icons.expand_more_rounded, size: 18, color: cs.onSurfaceVariant),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: Motion.medium2,
          curve: Motion.emphasized,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      reverse: widget.live,
                      child: Text(widget.block.text.trim(), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.6)),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.block});
  final ChatBlock block;
  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final plugins = context.watch<PluginStore>();
    final plugin = plugins.toolPlugin(b.name);
    final (label, icon) = _toolLabels[b.name] ??
        (plugin != null ? ('${plugin['title']} · ${plugins.toolLabel(b.name) ?? b.name}', pluginIcon(plugin['icon'])) : (b.name, Icons.build_outlined));
    final args = b.args == null ? '' : const JsonEncoder.withIndent('  ').convert(b.args);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        borderRadius: BorderRadius.circular(Corners.full),
        onTap: () => setState(() => _open = !_open),
        child: AnimatedContainer(
          duration: Motion.medium1,
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
          decoration: BoxDecoration(
            color: b.error ? cs.errorContainer : cs.secondaryContainer.withValues(alpha: b.running ? 1 : 0.55),
            borderRadius: BorderRadius.circular(Corners.full),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            b.running
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(b.error ? Icons.error_outline_rounded : icon, size: 15, color: b.error ? cs.onErrorContainer : cs.onSecondaryContainer),
            const SizedBox(width: 6),
            Text(label, style: tt.labelMedium?.copyWith(color: b.error ? cs.onErrorContainer : cs.onSecondaryContainer)),
            if (b.ms > 0) Text(' · ${b.ms < 1000 ? '${b.ms}ms' : '${(b.ms / 1000).toStringAsFixed(1)}s'}', style: tt.labelSmall?.copyWith(color: cs.onSecondaryContainer.withValues(alpha: 0.7))),
          ]),
        ),
      ),
      AnimatedSize(
        duration: Motion.medium2,
        curve: Motion.emphasized,
        alignment: Alignment.topLeft,
        child: _open
            ? Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: Space.xs),
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Corners.md)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (args.isNotEmpty && args != '{}') ...[
                    Text('参数', style: tt.labelSmall?.copyWith(color: cs.primary)),
                    Text(args, style: tt.bodySmall?.copyWith(fontFamily: 'monospace')),
                    const SizedBox(height: Space.sm),
                  ],
                  if (b.result.isNotEmpty) ...[
                    Text('结果', style: tt.labelSmall?.copyWith(color: cs.primary)),
                    Text(b.result, style: tt.bodySmall?.copyWith(fontFamily: 'monospace'), maxLines: 30, overflow: TextOverflow.fade),
                  ],
                ]),
              )
            : const SizedBox.shrink(),
      ),
    ]);
  }
}

/// Chapters the assistant generated, each one a jump into the recording.
class _OutlineCard extends StatelessWidget {
  const _OutlineCard({required this.lectureId, required this.chapters, required this.onAction});
  final String lectureId;
  final List chapters;
  final ValueChanged<Map<String, dynamic>> onAction;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: Space.xs),
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Corners.xl)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.sm),
          child: Text('大纲 · ${chapters.length} 个章节', style: tt.labelLarge?.copyWith(color: cs.primary)),
        ),
        for (final c in chapters.whereType<Map>())
          InkWell(
            onTap: () => onAction({'kind': 'seek', 'lecture_id': lectureId, 'seconds': ((c['start_ms'] as num?) ?? 0) ~/ 1000}),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 56,
                  child: Text(fmtClock(((c['start_ms'] as num?) ?? 0).toInt()),
                      style: tt.labelMedium?.copyWith(color: cs.primary, fontFeatures: const [FontFeature.tabularFigures()], height: 1.6)),
                ),
                Expanded(child: Text('${c['title'] ?? ''}', style: tt.bodyMedium)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Thumbnails of the slides the assistant looked at.
class _SlideStrip extends StatelessWidget {
  const _SlideStrip({required this.lectureId, required this.slides, required this.mode});
  final String lectureId;
  final List<int> slides;
  final String mode;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final api = context.read<AppState>().api;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: slides.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
          itemBuilder: (context, i) => Tooltip(
            message: 'PPT 第 ${slides[i]} 张',
            child: InkWell(
              borderRadius: BorderRadius.circular(Corners.md),
              onTap: () => openRef(context, SlideRef(lectureId, slides[i]), lectureId: lectureId),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Corners.md),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    slideImageUrl(api.baseUrl, api.token, lectureId, slides[i]),
                    fit: BoxFit.cover,
                    cacheHeight: 144,
                    errorBuilder: (_, _, _) => ColoredBox(color: cs.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined, size: 18)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      if (mode == 'described' || mode == 'unavailable')
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text(mode == 'described' ? '由识图模型转写给助手' : '当前模型不能看图，可在 设置 → 助手 → 识图模型 中设置',
              style: tt.labelSmall?.copyWith(color: mode == 'unavailable' ? cs.error : cs.onSurfaceVariant)),
        ),
    ]);
  }
}

/// A note the assistant saved, opening the reader.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onAction});
  final Map<String, dynamic> note;
  final ValueChanged<Map<String, dynamic>> onAction;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(Corners.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onAction({'kind': 'open_note', 'note_id': note['id']}),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
          child: Row(children: [
            Icon(Icons.menu_book_rounded, color: cs.onSecondaryContainer),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${note['title'] ?? '笔记'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleSmall?.copyWith(color: cs.onSecondaryContainer)),
                Text('已保存到课程库 · 点击阅读', style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer.withValues(alpha: 0.8))),
              ]),
            ),
            Icon(Icons.arrow_forward_rounded, color: cs.onSecondaryContainer),
          ]),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.actions, required this.onAction});
  final List<Map<String, dynamic>> actions;
  final ValueChanged<Map<String, dynamic>> onAction;
  @override
  Widget build(BuildContext context) {
    IconData icon(String k) => switch (k) {
          'seek' => Icons.play_circle_outline_rounded,
          'open_lecture' => Icons.ondemand_video_rounded,
          'open_course' => Icons.school_outlined,
          'open_note' => Icons.description_outlined,
          'download' => Icons.download_outlined,
          'open_schedule' => Icons.event_note_outlined,
          _ => Icons.touch_app_outlined,
        };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        for (final a in actions)
          FilledButton.tonalIcon(
            onPressed: () => onAction(a),
            icon: Icon(icon('${a['kind']}'), size: 18),
            label: Text('${a['label'] ?? ''}${a['kind'] == 'seek' && a['seconds'] != null ? ' · ${fmtClock(((a['seconds'] as num) * 1000).round())}' : ''}'),
          ),
      ]),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.lang, required this.code});
  final String lang, code;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: Space.xs),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(Corners.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, 2, 2, 0),
          child: Row(children: [
            Text(lang.isEmpty ? 'code' : lang, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                showSnack(context, '已复制代码');
              },
              icon: const Icon(Icons.copy_rounded),
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
          child: Text(code, style: tt.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.5)),
        ),
      ]),
    );
  }
}
