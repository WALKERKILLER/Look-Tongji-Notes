import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../../widgets/look_markdown.dart';
import 'note_reader.dart';

/// Markdown note editor with live preview. Saves through lookd, which writes
/// the note as a Markdown file with front matter and indexes it.
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    this.note,
    this.courseId = '',
    this.lectureId = '',
    this.timestamp,
    this.onSaved,
    this.onSeek,
    this.onClose,
    this.edit = false,
  });
  final Note? note;
  final String courseId, lectureId;

  /// Returns the current playback time in ms, enabling "insert timestamp".
  final int Function()? timestamp;
  final ValueChanged<Note>? onSaved;

  /// Handles timestamp taps in the preview (the player seeks in place).
  final void Function(TimeRef)? onSeek;
  final VoidCallback? onClose;

  /// Open in writing mode even when the note has content.
  final bool edit;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? '');
  // Existing notes open in reading mode so timestamps are tappable.
  late bool _preview = !widget.edit && (widget.note?.body ?? '').trim().isNotEmpty;
  bool _saving = false;
  bool _dirty = false;
  String? _id;

  @override
  void initState() {
    super.initState();
    _id = widget.note?.id;
    _title.addListener(_mark);
    _body.addListener(_mark);
  }

  String get _lectureId => widget.lectureId.isNotEmpty ? widget.lectureId : widget.note?.lectureId ?? '';

  void _mark() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _insertTimestamp() {
    final ms = widget.timestamp!();
    final s = ms ~/ 1000;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    final tag = h > 0 ? '[${two(h)}:${two(m)}:${two(sec)}] ' : '[${two(m)}:${two(sec)}] ';
    final sel = _body.selection;
    final text = _body.text;
    final at = sel.isValid ? sel.start : text.length;
    final prefix = at > 0 && text[at - 1] != '\n' ? '\n' : '';
    final ins = '$prefix$tag';
    _body.value = TextEditingValue(
      text: text.replaceRange(at, sel.isValid ? sel.end : at, ins),
      selection: TextSelection.collapsed(offset: at + ins.length),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final r = await context.read<AppState>().api.put('/api/notes', {
        'id': ?_id,
        'course_id': widget.note?.courseId ?? widget.courseId,
        'lecture_id': widget.note?.lectureId ?? widget.lectureId,
        'title': _title.text.trim().isEmpty ? '未命名笔记' : _title.text.trim(),
        'body': _body.text,
        'source': widget.note?.source.isNotEmpty == true ? widget.note!.source : 'user',
      });
      final n = Note((r as Map).cast<String, dynamic>()..['body'] = _body.text);
      _id = n.id;
      setState(() => _dirty = false);
      widget.onSaved?.call(n);
      if (mounted) showSnack(context, '笔记已保存');
    } catch (e) {
      if (mounted) showSnack(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        if (widget.onClose != null) IconButton(onPressed: widget.onClose, icon: const Icon(Icons.arrow_back_rounded), tooltip: '返回'),
        Expanded(
          child: TextField(
            controller: _title,
            style: tt.titleLarge,
            decoration: const InputDecoration(hintText: '标题', border: InputBorder.none, filled: false, isDense: true),
          ),
        ),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.edit_outlined, size: 18), tooltip: '编辑'),
            ButtonSegment(value: true, icon: Icon(Icons.visibility_outlined, size: 18), tooltip: '预览'),
          ],
          selected: {_preview},
          onSelectionChanged: (s) => setState(() => _preview = s.first),
        ),
      ]),
      const SizedBox(height: Space.sm),
      Expanded(
        child: AnimatedSwitcher(
          duration: Motion.medium1,
          child: _preview
              ? Container(
                  key: const ValueKey('p'),
                  padding: const EdgeInsets.all(Space.lg),
                  decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(Corners.lg)),
                  child: SingleChildScrollView(
                    child: LookMarkdown(
                      _body.text.isEmpty ? '_（空）_' : _body.text,
                      style: tt.bodyMedium?.copyWith(height: 1.7),
                      lectureId: _lectureId,
                      baseDir: widget.note == null ? '' : p.posix.dirname(widget.note!.path),
                      onRef: (r) => openRef(context, r, lectureId: _lectureId, onSeek: widget.onSeek),
                    ),
                  ),
                )
              : TextField(
                  key: const ValueKey('e'),
                  controller: _body,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: tt.bodyMedium?.copyWith(height: 1.6),
                  decoration: InputDecoration(
                    hintText: '支持 Markdown。${widget.timestamp != null ? '点“插入时间”记录当前播放位置，' : ''}内容保存在课程库的 notes 文件夹。',
                    alignLabelWithHint: true,
                  ),
                ),
        ),
      ),
      const SizedBox(height: Space.sm),
      Row(children: [
        if (widget.timestamp != null)
          TextButton.icon(onPressed: _insertTimestamp, icon: const Icon(Icons.more_time_rounded, size: 18), label: const Text('插入时间')),
        const Spacer(),
        AnimatedOpacity(
          opacity: _dirty ? 1 : 0,
          duration: Motion.short4,
          child: Text('未保存', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        const SizedBox(width: Space.sm),
        FilledButton.icon(
          onPressed: _saving || !_dirty && _id != null ? null : _save,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded, size: 18),
          label: const Text('保存'),
        ),
      ]),
    ]);
  }
}
