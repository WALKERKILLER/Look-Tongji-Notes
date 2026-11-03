import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';

Future<String?> openLocalCourseDialog(
  BuildContext context,
  Api api, {
  String? courseId,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => LocalCourseDialog(api: api, courseId: courseId),
);

class LocalCourseDialog extends StatefulWidget {
  const LocalCourseDialog({
    super.key,
    required this.api,
    this.courseId,
    this.pickFiles,
  });
  final Api api;
  final String? courseId;
  final Future<List<XFile>> Function()? pickFiles;
  @override
  State<LocalCourseDialog> createState() => _LocalCourseDialogState();
}

class _LocalCourseDialogState extends State<LocalCourseDialog> {
  final _title = TextEditingController();
  final _teacher = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<XFile> _files = [];
  late String? _course = widget.courseId;
  bool _busy = false;
  int _done = 0;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _teacher.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final files =
          await (widget.pickFiles?.call() ??
              openFiles(
                acceptedTypeGroups: [
                  const XTypeGroup(
                    label: 'Video',
                    extensions: ['mp4', 'mov', 'm4v', 'mkv', 'webm'],
                  ),
                ],
              ));
      if (!mounted || files.isEmpty) return;
      setState(() {
        _files = [...files]..sort((a, b) => a.name.compareTo(b.name));
        _done = 0;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_course == null) {
        final course = await widget.api.createLocalCourse(
          _title.text.trim(),
          teacher: _teacher.text.trim(),
        );
        _course = '${course['id']}';
        if (!mounted) return;
      }
      while (_done < _files.length) {
        final file = _files[_done];
        final length = await file.length();
        if (length > 4 << 30) throw FormatException(l10n.localVideoLimit);
        await widget.api.importLocalVideo(
          _course!,
          file.name,
          file.openRead(),
          length,
        );
        if (!mounted) return;
        setState(() => _done++);
      }
      if (mounted) Navigator.pop(context, _course);
    } catch (e) {
      if (mounted)
        setState(
          () => _error =
              '${_done < _files.length ? '${_files[_done].name}：' : ''}$e',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.courseId == null ? l10n.localCourseCreate : l10n.localVideosAdd,
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.courseId == null) ...[
                  TextFormField(
                    controller: _title,
                    autofocus: true,
                    enabled: !_busy && _course == null,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: l10n.localCourseName,
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? l10n.localCourseNameRequired
                        : null,
                  ),
                  TextFormField(
                    controller: _teacher,
                    enabled: !_busy && _course == null,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: l10n.localCourseTeacher,
                    ),
                  ),
                  const SizedBox(height: Space.md),
                ],
                Text(l10n.localCourseImportHint),
                const SizedBox(height: Space.md),
                OutlinedButton.icon(
                  onPressed: _busy || _done > 0 ? null : _pick,
                  icon: const Icon(Icons.video_library_outlined),
                  label: Text(l10n.localVideosChoose),
                ),
                if (_files.isNotEmpty) ...[
                  const SizedBox(height: Space.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, f) in _files.indexed)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: Space.xs,
                              ),
                              child: Text(
                                '${i < _done ? '✓' : '${i + 1}.'} ${f.name}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: Space.md),
                  LinearProgressIndicator(
                    value: _files.isEmpty ? null : _done / _files.length,
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    '${l10n.localVideosImporting} $_done / ${_files.length}',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: Space.md),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (_course != null) Text(l10n.localVideosPartialSaved),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _course),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _busy || (widget.courseId != null && _files.isEmpty)
              ? null
              : _save,
          child: Text(
            _error != null
                ? l10n.commonRetry
                : widget.courseId == null && _course == null
                ? l10n.localCourseCreate
                : l10n.localVideosAdd,
          ),
        ),
      ],
    ),
  );
}
