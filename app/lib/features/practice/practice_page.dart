import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/activity_tracker.dart';
import '../../core/app_state.dart';
import '../../theme/prefs.dart';
import '../../theme/tokens.dart';
import '../../widgets/heatmap.dart' show fmtMinutes;
import '../../widgets/look_markdown.dart';
import '../../widgets/states.dart';
import '../library/note_reader.dart' show openRef;
import 'quiz.dart';

/// Loads or saves practice data; a seam for widget tests.
typedef QuizFetch = Future<dynamic> Function(String method, String path, [Object? body]);

/// Full-screen practice: one question at a time, feedback after each answer,
/// and a summary at the end. With [only], retakes just those questions and
/// records no attempt.
class PracticePage extends StatefulWidget {
  const PracticePage({super.key, required this.quizId, this.only, this.fetch});
  final String quizId;
  final List<int>? only;
  final QuizFetch? fetch;
  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  Quiz? _quiz;
  Object? _error;
  late final List<int> _order;
  var _pos = 0;
  final _answers = <int, int>{}; // question index → chosen option
  final _hints = <int>{};
  final _started = DateTime.now();
  DateTime? _finishedAt;
  bool _reviewing = false; // looking back at a question from the summary
  QuizScore? _best;
  bool _saving = false;
  final _focus = FocusNode(debugLabel: 'practice');

  QuizFetch get _fetch =>
      widget.fetch ??
      (method, path, [body]) {
        final api = context.read<AppState>().api;
        return method == 'GET' ? api.get(path) : api.post(path, body);
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final q = Quiz(((await _fetch('GET', '/api/quizzes/${widget.quizId}')) as Map).cast<String, dynamic>());
      if (!mounted) return;
      setState(() {
        _quiz = q;
        _order = widget.only?.where((i) => i >= 0 && i < q.questions.length).toList() ?? [for (var i = 0; i < q.questions.length; i++) i];
        _best = q.best;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  int get _current => _order[_pos];
  bool get _done => _finishedAt != null && !_reviewing;

  void _choose(int option) {
    final q = _quiz!.questions[_current];
    if (_answers.containsKey(_current) || option >= q.options.length) return;
    setState(() => _answers[_current] = option);
  }

  void _go(int delta) {
    final next = _pos + delta;
    if (next < 0) return;
    if (delta > 0 && !_answers.containsKey(_current)) return;
    if (next >= _order.length) {
      _finishedAt == null ? _finish() : setState(() => _reviewing = false);
      return;
    }
    setState(() => _pos = next);
  }

  Future<void> _finish() async {
    setState(() => _finishedAt = DateTime.now());
    if (widget.only != null) return;
    final q = _quiz!;
    setState(() => _saving = true);
    try {
      final r = await _fetch('POST', '/api/quizzes/${q.id}/attempts', {
        'started_at': _started.millisecondsSinceEpoch ~/ 1000,
        'answers': [for (var i = 0; i < q.questions.length; i++) _answers[i] ?? -1],
      });
      final best = (r as Map)['best'];
      if (mounted && best is Map) setState(() => _best = QuizScore(best));
    } catch (e) {
      if (mounted) showSnack(context, '成绩没有保存：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _explain() {
    final q = _quiz!;
    final x = q.questions[_current];
    final a = _answers[_current]!;
    String opt(int i) => '${String.fromCharCode(65 + i)}「${x.options[i].text}」';
    askInSheet(
      context,
      '讲解练习「${q.title}」第 ${_pos + 1} 题：${x.stem}\n'
      '选项：${[for (var i = 0; i < x.options.length; i++) opt(i)].join('；')}\n'
      '我选了 ${opt(a)}，正确答案是 ${opt(x.answer)}。${a == x.answer ? '请讲讲背后的原理，帮我巩固。' : '请解释为什么错，以及我可能混淆了什么。'}'
      '${x.ref.isEmpty ? '' : '出处：${x.ref}'}',
    );
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || _quiz == null || _done) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final digit = const [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ].indexOf(k);
    if (digit >= 0) {
      _choose(digit);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.arrowRight) {
      _go(1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final q = _quiz;
    final Widget body;
    if (q == null) {
      body = _error == null ? const CenteredLoader() : ErrorState(error: _error!, onRetry: _load);
    } else if (_done) {
      body = _Summary(
        quiz: q,
        order: _order,
        answers: _answers,
        elapsed: _finishedAt!.difference(_started),
        best: widget.only == null ? _best : null,
        saving: _saving,
        retake: widget.only != null,
        onRetryWrong: (wrong) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PracticePage(quizId: q.id, only: wrong, fetch: widget.fetch))),
        onMore: () => askInSheet(context, '根据我在练习「${q.title}」（id ${q.id}）中做错的题，针对这些知识点再出一组练习题。'),
        onReview: (i) => setState(() {
          _reviewing = true;
          _pos = _order.indexOf(i);
        }),
      );
    } else {
      body = _QuestionView(
        key: ValueKey(_current),
        quiz: q,
        index: _current,
        number: _pos + 1,
        chosen: _answers[_current],
        hint: _hints.contains(_current),
        onChoose: _choose,
        onHint: () => setState(() => _hints.add(_current)),
        onExplain: _explain,
        onPrev: _pos > 0 ? () => _go(-1) : null,
        onNext: () => _go(1),
        last: _pos == _order.length - 1,
        reviewing: _reviewing,
        onSummary: () => setState(() => _reviewing = false),
      );
    }
    final reduce = context.watch<UiPrefs>().reduceMotion;
    final answered = _quiz == null ? 0 : _order.where(_answers.containsKey).length;
    return ActivityRegion(
      kind: 'practice',
      lectureId: q?.lectureId ?? '',
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _key,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(tooltip: '关闭', onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close_rounded)),
            title: Text(q == null ? '练习' : (widget.only != null ? '重做错题 · ${q.title}' : q.title), maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (q != null && !_done)
                Padding(
                  padding: const EdgeInsets.only(right: Space.lg),
                  child: Text('${_pos + 1} / ${_order.length}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ),
            ],
            bottom: q == null || _done
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: answered / math.max(1, _order.length)),
                      duration: reduce ? Duration.zero : Motion.medium2,
                      curve: Motion.emphasized,
                      builder: (_, v, _) => LinearProgressIndicator(value: v),
                    ),
                  ),
          ),
          body: AnimatedSwitcher(
            duration: reduce ? Duration.zero : Motion.medium2,
            switchInCurve: Motion.emphasizedDecelerate,
            switchOutCurve: Motion.emphasizedAccelerate,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a), child: child),
            ),
            child: KeyedSubtree(key: ValueKey(q == null ? 'load' : _done ? 'done' : 'q$_current'), child: body),
          ),
        ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    super.key,
    required this.quiz,
    required this.index,
    required this.number,
    required this.chosen,
    required this.hint,
    required this.onChoose,
    required this.onHint,
    required this.onExplain,
    required this.onPrev,
    required this.onNext,
    required this.last,
    required this.reviewing,
    required this.onSummary,
  });
  final bool reviewing;
  final VoidCallback onSummary;
  final Quiz quiz;
  final int index, number;
  final int? chosen;
  final bool hint, last;
  final ValueChanged<int> onChoose;
  final VoidCallback onHint, onExplain, onNext;
  final VoidCallback? onPrev;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final x = quiz.questions[index];
    final answered = chosen != null;
    final ref = LookRef.parse(x.ref);
    return ListView(padding: const EdgeInsets.fromLTRB(0, Space.xl, 0, Space.xxxl), children: [
      ContentWidth(
        max: 720,
        child: Padding(
          padding: context.isCompact ? Space.pageCompact : Space.page,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('第 $number 题', style: tt.labelLarge?.copyWith(color: cs.primary)),
              if (x.topic.isNotEmpty) ...[
                const SizedBox(width: Space.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
                  decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: Corners.all(Corners.full)),
                  child: Text(x.topic, style: tt.labelSmall?.copyWith(color: cs.onSecondaryContainer)),
                ),
              ],
            ]),
            const SizedBox(height: Space.md),
            LookMarkdown(x.stem, style: tt.titleMedium?.copyWith(height: 1.6), lectureId: quiz.lectureId, onRef: (r) => openRef(context, r, lectureId: quiz.lectureId)),
            const SizedBox(height: Space.xl),
            for (var i = 0; i < x.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: OptionRow(
                  letter: String.fromCharCode(65 + i),
                  option: x.options[i],
                  lectureId: quiz.lectureId,
                  state: !answered
                      ? OptionState.open
                      : i == x.answer
                          ? OptionState.correct
                          : i == chosen
                              ? OptionState.wrong
                              : OptionState.other,
                  onTap: answered ? null : () => onChoose(i),
                ),
              ),
            if (x.hint.isNotEmpty && !answered)
              Align(
                alignment: Alignment.centerLeft,
                child: hint
                    ? Container(
                        margin: const EdgeInsets.only(top: Space.xs),
                        padding: const EdgeInsets.all(Space.md),
                        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: Corners.all(Corners.md)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.lightbulb_outline_rounded, size: 18, color: cs.onSurfaceVariant),
                          const SizedBox(width: Space.sm),
                          Expanded(child: LookMarkdown(x.hint, style: tt.bodyMedium, lectureId: quiz.lectureId, onRef: (r) => openRef(context, r, lectureId: quiz.lectureId))),
                        ]),
                      )
                    : TextButton.icon(onPressed: onHint, icon: const Icon(Icons.lightbulb_outline_rounded, size: 18), label: const Text('提示')),
              ),
            const SizedBox(height: Space.lg),
            Row(children: [
              if (answered) ...[
                TextButton.icon(onPressed: onExplain, icon: const Icon(Icons.forum_outlined, size: 18), label: const Text('讲解')),
                if (ref != null)
                  TextButton.icon(
                    onPressed: () => openRef(context, ref, lectureId: quiz.lectureId),
                    icon: const Icon(Icons.travel_explore_rounded, size: 18),
                    label: const Text('查看出处'),
                  ),
              ],
              const Spacer(),
              if (onPrev != null) IconButton(tooltip: '上一题', onPressed: onPrev, icon: const Icon(Icons.arrow_back_rounded)),
              const SizedBox(width: Space.xs),
              if (reviewing && !last) ...[
                OutlinedButton(onPressed: onSummary, child: const Text('返回总结')),
                const SizedBox(width: Space.sm),
              ],
              FilledButton(onPressed: answered ? onNext : null, child: Text(last ? (reviewing ? '返回总结' : '完成') : '下一题')),
            ]),
          ]),
        ),
      ),
    ]);
  }
}

enum OptionState { open, correct, wrong, other }

/// One answer choice. After answering, the right answer turns primary, a
/// wrong choice turns error (both with an icon and a label), and every
/// option shows why it is right or wrong.
class OptionRow extends StatelessWidget {
  const OptionRow({super.key, required this.letter, required this.option, required this.state, this.onTap, this.lectureId = ''});
  final String letter, lectureId;
  final QuizOption option;
  final OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (bg, fg, border) = switch (state) {
      OptionState.correct => (cs.primaryContainer, cs.onPrimaryContainer, Colors.transparent),
      OptionState.wrong => (cs.errorContainer, cs.onErrorContainer, Colors.transparent),
      OptionState.other => (Colors.transparent, cs.onSurfaceVariant, cs.outlineVariant),
      OptionState.open => (Colors.transparent, cs.onSurface, cs.outlineVariant),
    };
    final badge = switch (state) {
      OptionState.correct => CircleAvatar(radius: 14, backgroundColor: cs.primary, child: Icon(Icons.check_rounded, size: 18, color: cs.onPrimary)),
      OptionState.wrong => CircleAvatar(radius: 14, backgroundColor: cs.error, child: Icon(Icons.close_rounded, size: 18, color: cs.onError)),
      _ => CircleAvatar(
          radius: 14,
          backgroundColor: cs.surfaceContainerHighest,
          child: Text(letter, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
        ),
    };
    final note = switch (state) {
      OptionState.correct => '正确答案',
      OptionState.wrong => '你的选择',
      _ => null,
    };
    final revealed = state != OptionState.open;
    return Semantics(
      button: onTap != null,
      label: '选项 $letter${note == null ? '' : '，$note'}',
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.lg), side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.lg, Space.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              badge,
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: LookMarkdown(option.text, style: tt.bodyLarge?.copyWith(color: fg), lectureId: lectureId, onRef: (r) => openRef(context, r, lectureId: lectureId)),
                  ),
                  if (note != null) Text(note, style: tt.labelMedium?.copyWith(color: fg)),
                  if (revealed && option.rationale.isNotEmpty) ...[
                    const SizedBox(height: Space.xs),
                    LookMarkdown(option.rationale, style: tt.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85), height: 1.5), lectureId: lectureId, onRef: (r) => openRef(context, r, lectureId: lectureId)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.quiz,
    required this.order,
    required this.answers,
    required this.elapsed,
    required this.best,
    required this.saving,
    required this.retake,
    required this.onRetryWrong,
    required this.onMore,
    required this.onReview,
  });
  final Quiz quiz;
  final List<int> order;
  final Map<int, int> answers;
  final Duration elapsed;
  final QuizScore? best;
  final bool saving, retake;
  final ValueChanged<List<int>> onRetryWrong;
  final VoidCallback onMore;
  final ValueChanged<int> onReview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final qs = quiz.questions;
    final wrong = [for (final i in order) if (answers[i] != qs[i].answer) i];
    final correct = order.length - wrong.length;
    final topics = <String, (int, int)>{}; // topic → (right, total)
    for (final i in order) {
      final t = qs[i].topic.isEmpty ? '其他' : qs[i].topic;
      final (r, n) = topics[t] ?? (0, 0);
      topics[t] = (r + (answers[i] == qs[i].answer ? 1 : 0), n + 1);
    }
    final secs = elapsed.inSeconds;
    final time = secs < 60 ? '$secs 秒' : '${fmtMinutes(secs ~/ 60)}${secs % 60 == 0 ? '' : ' ${secs % 60} 秒'}';
    final figs = const [FontFeature.tabularFigures()];

    return ListView(padding: const EdgeInsets.fromLTRB(0, Space.xxl, 0, Space.xxxl), children: [
      ContentWidth(
        max: 720,
        child: Padding(
          padding: context.isCompact ? Space.pageCompact : Space.page,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(retake ? '重做完成' : '练习完成', style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: Space.sm),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$correct', style: tt.displayMedium?.copyWith(fontFeatures: figs, color: cs.onSurface)),
                TextSpan(text: ' / ${order.length}', style: tt.headlineSmall?.copyWith(fontFeatures: figs, color: cs.onSurfaceVariant)),
              ]),
              semanticsLabel: '答对 $correct 题，共 ${order.length} 题',
            ),
            const SizedBox(height: Space.xs),
            Text(
              [
                '正确率 ${(correct * 100 / math.max(1, order.length)).round()}%',
                '用时 $time',
                if (saving) '正在保存' else if (best != null) '最好成绩 ${best!.label}',
              ].join(' · '),
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontFeatures: figs),
            ),
            const SizedBox(height: Space.xl),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              if (wrong.isNotEmpty) ...[
                OutlinedButton.icon(onPressed: () => onRetryWrong(wrong), icon: const Icon(Icons.replay_rounded), label: Text('重做错题 ${wrong.length}')),
                if (!retake) OutlinedButton.icon(onPressed: onMore, icon: const Icon(Icons.auto_awesome_outlined), label: const Text('再出一组（针对错题）')),
              ],
              FilledButton(onPressed: () => Navigator.maybePop(context), child: const Text('完成')),
            ]),
            if (topics.length > 1) ...[
              const SizedBox(height: Space.xxl),
              Text('按知识点', style: tt.titleSmall),
              const SizedBox(height: Space.sm),
              for (final MapEntry(key: t, value: (r, n)) in topics.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Row(children: [
                    Icon(r == n ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 18, color: r == n ? cs.primary : cs.error),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(t, style: tt.bodyMedium)),
                    Text('$r/$n', style: tt.bodyMedium?.copyWith(fontFeatures: figs, color: cs.onSurfaceVariant)),
                  ]),
                ),
            ],
            const SizedBox(height: Space.xl),
            Text('逐题回顾', style: tt.titleSmall),
            const SizedBox(height: Space.xs),
            for (final (n, i) in order.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: answers[i] == qs[i].answer
                    ? Icon(Icons.check_circle_outline_rounded, color: cs.primary, semanticLabel: '答对')
                    : Icon(Icons.cancel_outlined, color: cs.error, semanticLabel: answers[i] == null ? '未作答' : '答错'),
                title: Text('${n + 1}. ${_plain(qs[i].stem)}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onReview(i),
              ),
          ]),
        ),
      ),
    ]);
  }

  static String _plain(String md) => md.replaceAll(RegExp(r'[*_`#>$]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
