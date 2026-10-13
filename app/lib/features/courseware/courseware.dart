import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../library/note_reader.dart';

const kCoursewareExts = ['pdf', 'ppt', 'pptx', 'doc', 'docx', 'xls', 'xlsx', 'png', 'jpg', 'jpeg', 'webp'];

/// Lets the user pick documents and uploads them to a lecture. lookd queues
/// MinerU parsing when automatic parsing is on.
Future<int> pickAndUploadCourseware(BuildContext context, String lectureId) async {
  final files = await openFiles(acceptedTypeGroups: const [XTypeGroup(label: '课件', extensions: kCoursewareExts)]);
  if (files.isEmpty || !context.mounted) return 0;
  final api = context.read<AppState>().api;
  var ok = 0;
  var queued = false;
  for (final f in files) {
    try {
      final file = File(f.path);
      final r = await api.upload('/api/lectures/$lectureId/courseware', {'name': p.basename(f.path)}, file.openRead(), await file.length());
      ok++;
      queued = queued || (r is Map && r['parse_queued'] == true);
    } catch (e) {
      if (context.mounted) showSnack(context, '${p.basename(f.path)} 上传失败：$e');
    }
  }
  if (ok > 0 && context.mounted) showSnack(context, queued ? '已上传 $ok 个文件，正在用 MinerU 解析' : '已上传 $ok 个文件');
  return ok;
}

/// File-type badge: the extension on a tonal square.
class FileBadge extends StatelessWidget {
  const FileBadge({super.key, required this.ext});
  final String ext;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (ext) {
      'pdf' => (cs.errorContainer, cs.onErrorContainer),
      'ppt' || 'pptx' => (cs.tertiaryContainer, cs.onTertiaryContainer),
      'doc' || 'docx' => (cs.primaryContainer, cs.onPrimaryContainer),
      'xls' || 'xlsx' => (cs.secondaryContainer, cs.onSecondaryContainer),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      width: 40,
      height: 46,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(Corners.xs),
          topRight: Radius.circular(Corners.md),
          bottomLeft: Radius.circular(Corners.xs),
          bottomRight: Radius.circular(Corners.xs),
        ),
      ),
      child: Text(ext.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: 10)),
    );
  }
}

/// Uploaded courseware of a lecture with parse state and actions.
class CoursewareList extends StatelessWidget {
  const CoursewareList({super.key, required this.lectureId, required this.files, required this.onChanged});
  final String lectureId;
  final List<CoursewareFile> files;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final job = app.jobFor(lectureId, 'parse');
    final parsing = job != null && job.active;
    if (files.isEmpty) {
      return EmptyState(
        icon: Icons.upload_file_rounded,
        title: '上传这节课的课件',
        body: 'Look 不提供课件。把老师发的 PDF、PPT、Word 传上来，MinerU 会把它解析成文字，可以全文阅读，助手也能引用。',
        action: FilledButton.tonalIcon(
          onPressed: () async {
            if (await pickAndUploadCourseware(context, lectureId) > 0) onChanged();
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('选择文件'),
        ),
      );
    }
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.xxl), children: [
      Row(children: [
        Expanded(
          child: Text(parsing ? job.stage.isEmpty ? '正在解析…' : job.stage : '${files.length} 个文件', style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
        ),
        TextButton.icon(
          onPressed: () async {
            if (await pickAndUploadCourseware(context, lectureId) > 0) onChanged();
          },
          icon: const Icon(Icons.upload_rounded, size: 18),
          label: const Text('上传'),
        ),
      ]),
      if (parsing) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: LinearProgressIndicator(value: job.progress > 0 ? job.progress : null, borderRadius: BorderRadius.circular(2))),
      for (final f in files) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: _FileCard(lectureId: lectureId, file: f, parsing: parsing, onChanged: onChanged)),
    ]);
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.lectureId, required this.file, required this.parsing, required this.onChanged});
  final String lectureId;
  final CoursewareFile file;
  final bool parsing;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final app = context.read<AppState>();
    final (status, color) = switch (file.parseState) {
      'done' => ('已解析${file.pages > 0 ? ' ${file.pages} 页' : ''}', cs.primary),
      'failed' => ('解析失败', cs.error),
      _ => (parsing ? '等待解析' : '未解析', cs.onSurfaceVariant),
    };
    Future<void> parse() async {
      await app.enqueue([lectureId], ['parse']);
      if (context.mounted) showSnack(context, '已加入解析队列');
    }

    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(Corners.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: file.parsed ? () => showParsed(context, file, lectureId) : () => openPath('${app.daemon.libraryRoot}/${file.path}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.xs, Space.md),
          child: Row(children: [
            FileBadge(ext: file.ext),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleSmall),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: fmtBytes(file.bytes)),
                    const TextSpan(text: ' · '),
                    TextSpan(text: status, style: TextStyle(color: color)),
                  ]),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (file.parseState == 'failed' && file.parseError.isNotEmpty)
                  Text(file.parseError, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.error)),
              ]),
            ),
            if (!file.parsed && !parsing) IconButton(tooltip: '用 MinerU 解析', onPressed: parse, icon: const Icon(Icons.document_scanner_outlined)),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (v) async {
                switch (v) {
                  case 'read':
                    showParsed(context, file, lectureId);
                  case 'open':
                    openPath('${app.daemon.libraryRoot}/${file.path}');
                  case 'parse':
                    parse();
                  case 'delete':
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('删除课件？'),
                        content: Text('「${file.name}」和它的解析结果会从课程库中删除。'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await app.api.delete('/api/lectures/$lectureId/courseware?path=${Uri.encodeQueryComponent(file.path)}');
                      onChanged();
                    }
                }
              },
              itemBuilder: (_) => [
                if (file.parsed) const PopupMenuItem(value: 'read', child: Text('阅读解析结果')),
                const PopupMenuItem(value: 'open', child: Text('打开原文件')),
                if (!parsing) PopupMenuItem(value: 'parse', child: Text(file.parsed ? '重新解析' : '解析')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// Opens the parsed Markdown in the courseware reader.
Future<void> showParsed(BuildContext context, CoursewareFile file, String lectureId) => openCoursewareReader(context, file, lectureId: lectureId);
