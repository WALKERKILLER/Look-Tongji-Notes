import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../assistant/assistant_controller.dart';
import '../assistant/assistant_panel.dart';
import 'practice_page.dart';

// Practice quizzes (docs/specs/0002-tutor-quiz-cards.md).

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class QuizOption {
  QuizOption(Map j)
      : text = '${j['text'] ?? ''}',
        rationale = '${j['rationale'] ?? ''}';
  final String text, rationale;
}

class QuizQuestion {
  QuizQuestion(Map j)
      : stem = '${j['stem'] ?? ''}',
        options = [for (final o in (j['options'] as List? ?? const [])) QuizOption(o as Map)],
        answer = _int(j['answer']),
        hint = '${j['hint'] ?? ''}',
        topic = '${j['topic'] ?? ''}',
        ref = '${j['ref'] ?? ''}';
  final String stem, hint, topic, ref;
  final List<QuizOption> options;
  final int answer;
}

class QuizScore {
  QuizScore(Map j)
      : correct = _int(j['correct']),
        total = _int(j['total']),
        answers = (j['answers'] as List?)?.map(_int).toList();
  final int correct, total;
  final List<int>? answers;
  String get label => '$correct/$total';
}

class Quiz {
  Quiz(Map<String, dynamic> j)
      : id = '${j['id'] ?? ''}',
        title = '${j['title'] ?? ''}',
        lectureId = '${j['lecture_id'] ?? ''}',
        lectureTitle = '${j['lecture_title'] ?? ''}',
        difficulty = '${j['difficulty'] ?? 'medium'}',
        source = '${j['source'] ?? ''}',
        count = _int(j['count']),
        attempts = _int(j['attempts']),
        questions = [for (final q in (j['questions'] as List? ?? const [])) QuizQuestion(q as Map)],
        best = j['best'] is Map ? QuizScore(j['best'] as Map) : null,
        last = j['last'] is Map ? QuizScore(j['last'] as Map) : null;
  final String id, title, lectureId, lectureTitle, difficulty, source;
  final int count, attempts;
  final List<QuizQuestion> questions;
  final QuizScore? best, last;

  String get meta => [if (lectureTitle.isNotEmpty) lectureTitle, '$count 题', difficultyLabel(difficulty)].join(' · ');
}

String difficultyLabel(String d) => switch (d) {
      'easy' => '简单',
      'hard' => '困难',
      _ => '中等',
    };

/// Sends [prompt] to the assistant and shows it in a sheet over the current
/// screen, so the student keeps their place.
Future<void> askInSheet(BuildContext context, String prompt) async {
  final a = context.read<AssistantController>();
  if (!a.ready || a.busy) {
    showSnack(context, a.busy ? '助手正在回复，请稍后再试' : '助手还没有就绪');
    return;
  }
  unawaited(a.send(prompt));
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: AssistantPanel(docked: true, embedded: true)),
  );
}

Future<void> openPractice(BuildContext context, String quizId) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PracticePage(quizId: quizId)));

/// A practice set: in chat after the assistant writes one, under a lecture and
/// in the library. With [live] it loads the latest scores and follows changes.
class QuizCard extends StatefulWidget {
  const QuizCard({super.key, required this.quiz, this.live = false, this.dense = false});
  final Quiz quiz;
  final bool live;

  /// One row with a compact action, for lists.
  final bool dense;

  @override
  State<QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<QuizCard> {
  late Quiz _quiz = widget.quiz;
  bool _gone = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    if (!widget.live) return;
    _refresh();
    _sub = context.read<AppState>().events.listen((e) {
      if (e['type'] == 'quizzes_changed' && (e['data'] as Map?)?['id'] == _quiz.id) _refresh();
    });
  }

  @override
  void didUpdateWidget(QuizCard old) {
    super.didUpdateWidget(old);
    if (!widget.live) _quiz = widget.quiz;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final r = await context.read<AppState>().api.get('/api/quizzes/${_quiz.id}');
      if (mounted) setState(() => _quiz = Quiz((r as Map).cast<String, dynamic>()));
    } on ApiError catch (e) {
      if (mounted && e.status == 404) setState(() => _gone = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = _quiz;
    final score = _gone ? '已删除' : (q.best == null ? '还没有练习' : '最好 ${q.best!.label} · 练过 ${q.attempts} 次');
    final start = _gone ? null : () => openPractice(context, q.id);
    final icon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: cs.surfaceContainerLowest.withValues(alpha: 0.7), shape: BoxShape.circle),
      child: Icon(Icons.quiz_outlined, size: 20, color: cs.onTertiaryContainer),
    );
    final texts = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(q.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleSmall?.copyWith(color: cs.onTertiaryContainer)),
      const SizedBox(height: 2),
      Text(q.meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onTertiaryContainer.withValues(alpha: 0.8))),
      Text(score, style: tt.labelMedium?.copyWith(color: cs.onTertiaryContainer, fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
    return Material(
      color: cs.tertiaryContainer,
      borderRadius: Corners.all(Corners.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: start,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
          child: widget.dense
              ? Row(children: [icon, const SizedBox(width: Space.md), Expanded(child: texts), const Icon(Icons.chevron_right_rounded)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [icon, const SizedBox(width: Space.md), Expanded(child: texts)]),
                  const SizedBox(height: Space.md),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: cs.tertiary, foregroundColor: cs.onTertiary),
                      onPressed: start,
                      child: Text(q.attempts == 0 ? '开始练习' : '再练一次'),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }
}

/// The practice sets of one lecture (or all, with an empty id), newest first.
class QuizList extends StatefulWidget {
  const QuizList({super.key, this.lectureId = '', this.empty, this.header, this.columns = 1});
  final String lectureId;
  final Widget? empty;

  /// Shown above the list only when there are sets.
  final Widget? header;
  final int columns;
  @override
  State<QuizList> createState() => _QuizListState();
}

class _QuizListState extends State<QuizList> {
  List<Quiz>? _quizzes;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<AppState>().events.listen((e) {
      if (e['type'] == 'quizzes_changed') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = jsonList(await context.read<AppState>().api.get('/api/quizzes', {if (widget.lectureId.isNotEmpty) 'lecture_id': widget.lectureId}));
      if (mounted) setState(() => _quizzes = [for (final q in r) Quiz((q as Map).cast<String, dynamic>())]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final qs = _quizzes;
    if (qs == null) return const SizedBox.shrink();
    if (qs.isEmpty) return widget.empty ?? const SizedBox.shrink();
    final list = LayoutBuilder(builder: (context, c) {
      final cols = widget.columns;
      final w = (c.maxWidth - Space.md * (cols - 1)) / cols;
      return Wrap(spacing: Space.md, runSpacing: Space.sm, children: [
        for (final q in qs) SizedBox(width: w, child: QuizCard(key: ValueKey(q.id), quiz: q, dense: true)),
      ]);
    });
    return widget.header == null ? list : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [widget.header!, list]);
  }
}

/// Asks the assistant for a practice set on a lecture: count, difficulty and
/// an optional focus. [onAsk] receives the prompt.
Future<void> showQuizSheet(BuildContext context, {required String lectureId, required ValueChanged<String> onAsk}) => showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _QuizSheet(lectureId: lectureId, onAsk: onAsk),
    );

class _QuizSheet extends StatefulWidget {
  const _QuizSheet({required this.lectureId, required this.onAsk});
  final String lectureId;
  final ValueChanged<String> onAsk;
  @override
  State<_QuizSheet> createState() => _QuizSheetState();
}

class _QuizSheetState extends State<_QuizSheet> {
  int _count = 10;
  String _difficulty = 'medium';
  final _focus = TextEditingController();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  String get prompt {
    final f = _focus.text.trim();
    return '请为这节课（lecture_id ${widget.lectureId}）出 $_count 道${difficultyLabel(_difficulty)}难度的选择题，保存为练习'
        '${f.isEmpty ? '，覆盖整节课的重点' : '，侧重：$f'}。';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget label(String t) => Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: Text(t, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)));
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('出题练习', style: tt.titleLarge),
        const SizedBox(height: Space.xs),
        Text('助手会先读完字幕并核对 PPT 与课件，每道题都附出处和解析。', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: Space.xl),
        label('题量'),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [for (final n in const [5, 10, 15]) ButtonSegment(value: n, label: Text('$n 题'))],
          selected: {_count},
          onSelectionChanged: (v) => setState(() => _count = v.first),
        ),
        const SizedBox(height: Space.lg),
        label('难度'),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [for (final d in const ['easy', 'medium', 'hard']) ButtonSegment(value: d, label: Text(difficultyLabel(d)))],
          selected: {_difficulty},
          onSelectionChanged: (v) => setState(() => _difficulty = v.first),
        ),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _focus,
          decoration: const InputDecoration(labelText: '侧重（可选）', hintText: '例如：卷积的性质、例题的解法', border: OutlineInputBorder()),
        ),
        const SizedBox(height: Space.xl),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            widget.onAsk(prompt);
          },
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('让助手出题'),
        ),
      ]),
    );
  }
}
