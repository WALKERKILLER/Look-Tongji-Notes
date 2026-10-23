import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';

const _kinds = [
  ('video', Icons.movie_outlined, '视频', '多路分段并发下载，可断点续传'),
  ('slides', Icons.slideshow_outlined, 'PPT 截图', '按时间戳命名，可与视频同步'),
  ('transcript', Icons.subject_rounded, '语音转写', '必剪 / 剪映免费识别，分段并行，带时间戳'),
];

/// Lets the user pick what to fetch for one or more lectures; [kinds]
/// preselects the options (else the last choice).
Future<void> showDownloadSheet(BuildContext context, List<String> lectureIds, {String? title, List<String> kinds = const []}) async {
  final sp = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  final suggested = kinds.where((k) => _kinds.any((e) => e.$1 == k)).toList();
  final saved = suggested.isNotEmpty ? suggested : sp.getStringList('download.kinds') ?? ['video', 'slides'];
  var deleteVideo = false;
  try {
    final st = await context.read<AppState>().api.get('/api/settings');
    deleteVideo = st is Map && st['transcript.delete_video'] == true;
  } catch (_) {}
  if (!context.mounted) return;
  final picked = await showModalBottomSheet<List<String>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _Sheet(count: lectureIds.length, title: title, initial: saved.toSet(), deleteVideo: deleteVideo),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await sp.setStringList('download.kinds', picked);
  try {
    final jobs = await context.read<AppState>().enqueue(lectureIds, picked);
    if (context.mounted) showSnack(context, '已加入 ${jobs.length} 个任务');
  } catch (e) {
    if (context.mounted) showSnack(context, '加入失败：$e');
  }
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.count, required this.initial, this.title, this.deleteVideo = false});
  final int count;
  final bool deleteVideo;
  final String? title;
  final Set<String> initial;
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late final Set<String> _sel = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ffmpeg = context.select<AppState, bool>((a) => a.health['ffmpeg'] != false);
    // Options that cannot run show as off and are not sent.
    final picked = [for (final (k, _, _, _) in _kinds) if (_sel.contains(k) && (k != 'transcript' || ffmpeg)) k];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.count == 1 ? (widget.title ?? '下载这节课') : '下载 ${widget.count} 节课', style: tt.headlineSmall),
          const SizedBox(height: Space.xs),
          Text('文件保存在课程库里，按课程与日期整理', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: Space.lg),
          for (final (k, icon, label, hint) in _kinds)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: _Option(
                icon: icon,
                label: label,
                hint: k == 'transcript' && !ffmpeg ? '需要安装 ffmpeg' : hint,
                selected: _sel.contains(k),
                enabled: k != 'transcript' || ffmpeg,
                onTap: () => setState(() => _sel.contains(k) ? _sel.remove(k) : _sel.add(k)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, 0),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text('平台不提供课件。在播放器的「资料 → 课件」里上传，MinerU 会解析成可检索的文字。',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ]),
          ),
          AnimatedSize(
            duration: Motion.medium2,
            curve: Motion.emphasized,
            alignment: Alignment.topCenter,
            child: widget.deleteVideo && _sel.contains('transcript') && ffmpeg
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Row(children: [
                      Icon(Icons.auto_delete_outlined, size: 18, color: cs.tertiary),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          _sel.contains('video') ? '已开启「转写完成后删除视频」：视频会在文字稿生成后被删除' : '已开启「转写完成后删除视频」：本地已有的视频会在转写完成后删除',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: picked.isEmpty ? null : () => Navigator.pop(context, picked),
            icon: const Icon(Icons.download_rounded),
            label: Text(picked.isEmpty ? '选择要下载的内容' : '开始下载'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ]),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.label, required this.hint, required this.selected, required this.enabled, required this.onTap});
  final IconData icon;
  final String label, hint;
  final bool selected, enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final on = selected && enabled;
    return AnimatedContainer(
      duration: Motion.medium1,
      curve: Motion.emphasized,
      decoration: BoxDecoration(
        color: on ? cs.secondaryContainer : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(on ? Corners.xl : Corners.lg),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Corners.lg),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Row(children: [
                Icon(icon, color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: tt.titleSmall?.copyWith(color: on ? cs.onSecondaryContainer : cs.onSurface)),
                    Text(hint, style: tt.bodySmall?.copyWith(color: on ? cs.onSecondaryContainer.withValues(alpha: 0.8) : cs.onSurfaceVariant)),
                  ]),
                ),
                AnimatedSwitcher(
                  duration: Motion.short4,
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: on
                      ? Icon(Icons.check_circle_rounded, key: const ValueKey(1), color: cs.primary)
                      : Icon(Icons.circle_outlined, key: const ValueKey(0), color: cs.outline),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
