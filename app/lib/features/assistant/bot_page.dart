import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import 'assistant_controller.dart';
import 'bot_avatar.dart';
import '../../l10n/l10n.dart';

// The resident bot's page: who it is, what it remembers and how it learns
// (docs/specs/0007-resident-bot-and-course-agents.md).

final _memoryKinds = <(String, String, IconData)>[
  ('profile.md', l10n.memoryAboutYou, Icons.person_outline_rounded),
  ('preferences.md', l10n.memoryPreferences, Icons.tune_rounded),
  ('routines/', l10n.memoryRoutines, Icons.route_outlined),
  ('courses/', l10n.commonCourses, Icons.school_outlined),
  ('notes/', l10n.commonNotes, Icons.sticky_note_2_outlined),
];

(String, IconData) _kindOf(String path) {
  for (final (prefix, label, icon) in _memoryKinds) {
    if (path == prefix || (prefix.endsWith('/') && path.startsWith(prefix))) return (label, icon);
  }
  return (l10n.commonOther, Icons.description_outlined);
}

class BotPage extends StatefulWidget {
  const BotPage({super.key});
  @override
  State<BotPage> createState() => _BotPageState();
}

class _BotPageState extends State<BotPage> {
  late final AssistantController _a = context.read<AssistantController>();
  final _name = TextEditingController();
  final _persona = TextEditingController();
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _runs = [];
  bool _loading = true;
  Object? _error;
  BotMood? _preview;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    _name.text = _a.botName;
    _persona.text = '${_a.bot['persona'] ?? ''}';
    _a.memoryChanged.addListener(_load);
    _load();
    if (_a.bot.isEmpty) _a.loadBot().then((_) => _syncFields());
  }

  @override
  void dispose() {
    _a.memoryChanged.removeListener(_load);
    _previewTimer?.cancel();
    _name.dispose();
    _persona.dispose();
    super.dispose();
  }

  void _syncFields() {
    if (!mounted) return;
    _name.text = _a.botName;
    _persona.text = '${_a.bot['persona'] ?? ''}';
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([_a.memoryFiles(), _a.memoryRuns()]);
      if (!mounted) return;
      setState(() {
        _files = r[0];
        _runs = r[1];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  Future<void> _patch(Map<String, dynamic> patch) async {
    try {
      await _a.updateBot(patch);
      _flash(BotMood.happy);
    } catch (e) {
      if (mounted) showSnack(context, e is ApiError ? e.message : '$e');
      _syncFields();
    }
  }

  void _flash(BotMood mood) {
    setState(() => _preview = mood);
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _preview = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AssistantController>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final memory = (a.bot['memory'] as Map?) ?? const {};
    final pad = context.isCompact ? Space.pageCompact : Space.page;
    return Scaffold(
      appBar: AppBar(title: Text(a.botName)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: pad.copyWith(bottom: Space.xxl), children: [
            _hero(context, a),
            _Section(l10n.botSectionLook),
            TextField(
              controller: _name,
              maxLength: 12,
              decoration: InputDecoration(labelText: l10n.botName, border: OutlineInputBorder()),
              onSubmitted: (v) => _patch({'name': v}),
              onTapOutside: (_) {
                if (_name.text.trim() != a.botName && _name.text.trim().isNotEmpty) _patch({'name': _name.text});
              },
            ),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (final e in kBotShapes.entries)
                _ShapeOption(
                  shape: e.key,
                  label: e.value.$2,
                  color: a.botColor,
                  selected: a.botShape == e.key,
                  onTap: () => _patch({'shape': e.key}),
                ),
            ]),
            const SizedBox(height: Space.lg),
            Text(l10n.commonColor, style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (final k in kBotColorKeys)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: botColors(cs, k).$1, radius: 8),
                  label: Text(botColorLabel(k)),
                  selected: a.botColor == k,
                  onSelected: (_) => _patch({'color': k}),
                ),
            ]),
            _Section(l10n.botSectionPersona),
            TextField(
              controller: _persona,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: l10n.botPersonaHint,
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: ListenableBuilder(
                listenable: _persona,
                builder: (context, _) => FilledButton.tonal(
                  onPressed: _persona.text.trim() == '${a.bot['persona'] ?? ''}' ? null : () => _patch({'persona': _persona.text}),
                  child: Text(l10n.commonSave),
                ),
              ),
            ),
            _Section(l10n.botSectionMemory, trailing: [
              IconButton(tooltip: l10n.memoryAdd, onPressed: () => _edit(null), icon: const Icon(Icons.add_rounded)),
              const SizedBox(width: Space.xs),
              FilledButton.tonalIcon(
                onPressed: a.consolidating
                    ? null
                    : () async {
                        try {
                          await a.consolidateNow();
                        } catch (e) {
                          if (context.mounted) showSnack(context, e is ApiError ? e.message : '$e');
                        }
                      },
                icon: a.consolidating
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bedtime_outlined, size: 18),
                label: Text(a.consolidating ? l10n.memoryConsolidating : l10n.memoryConsolidateNow),
              ),
            ]),
            Text(l10n.memoryIntro(a.botName),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.6)),
            const SizedBox(height: Space.md),
            if (_loading)
              const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(l10n.memoryReadFailed(_error is ApiError ? (_error as ApiError).message : _error!), style: tt.bodySmall?.copyWith(color: cs.error))
            else if (_files.isEmpty)
              _EmptyMemory(name: a.botName)
            else
              _memoryList(context),
            _Section(l10n.memoryRuns),
            if (_runs.isEmpty)
              Text(l10n.memoryRunsEmpty, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))
            else
              for (final r in _runs.take(20)) _RunTile(run: r),
            _Section(l10n.pluginCategoryTutor),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.memoryAuto),
              subtitle: Text(l10n.memoryAutoHint),
              value: memory['auto'] != false,
              onChanged: (v) => _patch({'memory': {'auto': v}}),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.memoryFromCourses),
              subtitle: Text(l10n.memoryFromCoursesHint),
              value: memory['learn_from_courses'] == true,
              onChanged: (v) => _patch({'memory': {'learn_from_courses': v}}),
            ),
            const SizedBox(height: Space.lg),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l10n.botRestartTitle),
                    content: Text(l10n.botRestartBody(a.botName)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.botRestart)),
                    ],
                  ),
                );
                if (ok == true) await a.resetBot();
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(l10n.botRestartChat),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, AssistantController a) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final mood = _preview ?? a.mood;
    final last = (a.bot['last_run'] as Map?)?['at'] as num?;
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Space.xl, horizontal: Space.lg),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Corners.xlIncreased)),
        child: Column(children: [
          Semantics(
            button: true,
            label: l10n.botMoodLabel(a.botName, kBotMoodLabels[mood]!),
            child: GestureDetector(
              onTap: () => _flash(BotMood.happy),
              onLongPress: () => _flash(BotMood.confused),
              child: BotAvatar(size: 132, shape: a.botShape, color: a.botColor, mood: mood),
            ),
          ),
          const SizedBox(height: Space.md),
          Text(a.botName, style: tt.headlineSmall),
          const SizedBox(height: Space.xs),
          Text(
            [
              _files.isEmpty ? l10n.memoryEmptyShort : l10n.memoryCount(_files.length),
              if (a.consolidating) l10n.memoryWorking else if (last != null) l10n.memoryLastRun(fmtRelative(DateTime.fromMillisecondsSinceEpoch(last.toInt()))),
            ].join(' · '),
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }

  Widget _memoryList(BuildContext context) {
    final app = context.read<AppState>();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final f in _files) {
      groups.putIfAbsent(_kindOf('${f['path']}').$1, () => []).add(f);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xs),
          child: Text(g.key, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ),
        for (final f in g.value) _memoryTile(context, f, app),
      ],
    ]);
  }

  Widget _memoryTile(BuildContext context, Map<String, dynamic> f, AppState app) {
    final cs = Theme.of(context).colorScheme;
    final path = '${f['path']}';
    var title = '${f['title'] ?? ''}';
    if (title.isEmpty && path.startsWith('courses/')) title = app.course(path.substring(8).replaceAll('.md', ''))?.title ?? '';
    if (title.isEmpty) title = path;
    final desc = '${f['description'] ?? ''}';
    final when = '${f['when'] ?? ''}';
    final updated = DateTime.fromMillisecondsSinceEpoch(((f['updated'] as num?) ?? 0).toInt());
    return Card.filled(
      color: cs.surfaceContainer,
      margin: const EdgeInsets.only(bottom: Space.sm),
      child: ListTile(
        leading: Icon(_kindOf(path).$2, color: cs.onSurfaceVariant),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([if (desc.isNotEmpty) desc, if (when.isNotEmpty) l10n.memoryWhen(when), fmtRelative(updated)].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(tooltip: l10n.commonDelete, icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(path, title)),
        onTap: () => _edit(path),
      ),
    );
  }

  Future<void> _delete(String path, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.memoryDeleteTitle),
        content: Text(l10n.memoryDeleteBody(title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _a.deleteMemory(path);
    } catch (e) {
      if (mounted) showSnack(context, e is ApiError ? e.message : '$e');
    }
  }

  Future<void> _edit(String? path) async {
    Map<String, dynamic>? file;
    if (path != null) {
      try {
        file = await _a.readMemory(path);
      } catch (e) {
        if (mounted) showSnack(context, e is ApiError ? e.message : '$e');
        return;
      }
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => MemoryEditor(
        path: path,
        content: '${file?['content'] ?? ''}',
        save: (p, content) => _a.writeMemory(p, content, baseHash: file?['hash'] as String?),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {this.trailing = const []});
  final String title;
  final List<Widget> trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ...trailing,
        ]),
      );
}

class _ShapeOption extends StatelessWidget {
  const _ShapeOption({required this.shape, required this.label, required this.color, required this.selected, required this.onTap});
  final String shape, label, color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Corners.lg),
        child: AnimatedContainer(
          duration: Motion.medium2,
          curve: Motion.emphasized,
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          decoration: BoxDecoration(
            color: selected ? cs.secondaryContainer : cs.surfaceContainer,
            borderRadius: BorderRadius.circular(selected ? Corners.xl : Corners.lg),
          ),
          child: Column(children: [
            BotAvatar(size: 48, shape: shape, color: color, animate: selected, followPointer: false),
            const SizedBox(height: Space.xs),
            Text(label, style: tt.labelMedium?.copyWith(color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _EmptyMemory extends StatelessWidget {
  const _EmptyMemory({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(Corners.lg)),
      child: Text(l10n.memoryEmpty(name), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});
  final Map<String, dynamic> run;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = '${run['status']}';
    final changes = [for (final c in (run['changes'] as List?) ?? const []) (c as Map).cast<String, dynamic>()];
    final at = DateTime.fromMillisecondsSinceEpoch(((run['at'] as num?) ?? 0).toInt());
    final (title, icon, color) = switch (status) {
      'ok' => (l10n.memoryRunChanged(changes.length), Icons.task_alt_rounded, cs.primary),
      'error' => (l10n.memoryRunUnfinished, Icons.error_outline_rounded, cs.error),
      _ => (l10n.memoryRunNothing, Icons.check_rounded, cs.onSurfaceVariant),
    };
    final cost = ((run['cost'] as num?) ?? 0).toDouble();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text([fmtRelative(at), l10n.memoryRunScope(run['sessions'] ?? 0, run['turns'] ?? 0), if (cost > 0) fmtUsd(cost)].join(' · ')),
        if ('${run['summary'] ?? ''}'.isNotEmpty) Text('${run['summary']}', style: tt.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
        if (changes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              for (final c in changes)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${{'created': l10n.commonNew, 'updated': l10n.memoryUpdated, 'appended': l10n.memoryAppended}[c['action']] ?? c['action']} ${c['path']}'),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Edits one memory file; a new file picks its kind and name first.
class MemoryEditor extends StatefulWidget {
  const MemoryEditor({super.key, required this.path, required this.content, required this.save});
  final String? path;
  final String content;
  final Future<void> Function(String path, String content) save;
  @override
  State<MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<MemoryEditor> {
  late final _text = TextEditingController(text: widget.content);
  final _slug = TextEditingController();
  String _kind = 'notes/';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _slug.dispose();
    super.dispose();
  }

  String? get _path {
    if (widget.path != null) return widget.path;
    if (!_kind.endsWith('/')) return _kind;
    final slug = _slug.text.trim();
    return RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(slug) ? '$_kind$slug.md' : null;
  }

  Future<void> _save() async {
    final p = _path;
    if (p == null) {
      setState(() => _error = l10n.memoryFileNameInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(p, _text.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ApiError ? e.message.split('\n').first : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.path == null ? l10n.memoryAdd : widget.path!, style: tt.titleMedium),
        const SizedBox(height: Space.md),
        if (widget.path == null) ...[
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final (k, label, icon) in _memoryKinds) ButtonSegment(value: k, label: Text(label), icon: Icon(icon, size: 18))],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          if (_kind.endsWith('/')) ...[
            const SizedBox(height: Space.md),
            TextField(
              controller: _slug,
              decoration: InputDecoration(labelText: l10n.memoryFileName, prefixText: _kind, suffixText: '.md', border: const OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: Space.md),
        ],
        Flexible(
          child: TextField(
            controller: _text,
            minLines: 8,
            maxLines: 18,
            style: tt.bodyMedium?.copyWith(fontFamily: 'monospace', height: 1.5),
            decoration: InputDecoration(
              hintText: l10n.memoryFileHint,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text(_error!, style: tt.bodySmall?.copyWith(color: cs.error))),
        const SizedBox(height: Space.md),
        Row(children: [
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
          const SizedBox(width: Space.sm),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? l10n.commonSaving : l10n.commonSave)),
        ]),
      ]),
    );
  }
}
