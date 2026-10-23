import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/course_visuals.dart';
import '../../l10n/l10n.dart';

class CourseCard extends StatefulWidget {
  const CourseCard({super.key, required this.course, required this.onTap, this.onMenu});
  final Course course;
  final VoidCallback onTap;
  final void Function(Offset globalPos)? onMenu;

  @override
  State<CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<CourseCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final s = courseScheme(context, c);
    final teachers = c.teachers.isNotEmpty ? c.teachers.join(l10n.listSeparator) : c.teacher;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.medium1,
        curve: Motion.emphasized,
        decoration: BoxDecoration(
          color: _hover ? Color.alphaBlend(s.primary.withValues(alpha: 0.06), cs.surfaceContainer) : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(_hover ? Corners.xlIncreased : Corners.xl),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Corners.xl),
            onTap: widget.onTap,
            onSecondaryTapUp: widget.onMenu == null ? null : (d) => widget.onMenu!(d.globalPosition),
            onLongPress: widget.onMenu == null
                ? null
                : () {
                    final box = context.findRenderObject() as RenderBox;
                    widget.onMenu!(box.localToGlobal(box.size.center(Offset.zero)));
                  },
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Generative cover: the course's organic signature, morphing on hover.
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, 0),
                child: SizedBox(
                  height: 108,
                  child: Stack(fit: StackFit.expand, children: [
                    Hero(
                      tag: 'art-${c.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Corners.xl - Space.xs),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: _hover ? 1 : 0),
                          duration: Motion.long4,
                          curve: Motion.emphasized,
                          builder: (_, t, _) => CourseArt(course: c, t: t),
                        ),
                      ),
                    ),
                    Positioned(
                      top: Space.sm,
                      right: Space.sm,
                      child: Row(children: [
                        if (c.pinned) _Tag(scheme: s, icon: Icons.push_pin_rounded),
                        if (c.localLectures > 0) ...[
                          const SizedBox(width: Space.xs),
                          _Tag(scheme: s, icon: Icons.download_done_rounded, text: '${c.localLectures}'),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.title, style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [if (teachers.isNotEmpty) teachers, c.termLabel].join(' · '),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.md),
                  Row(children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: c.progress.clamp(0.0, 1.0),
                        color: s.primary,
                        backgroundColor: s.primaryContainer.withValues(alpha: 0.5),
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Text(l10n.courseLectureCount(c.lectureTotal), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.scheme, required this.icon, this.text});
  final ColorScheme scheme;
  final IconData icon;
  final String? text;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: text == null ? 6 : 8, vertical: 4),
        decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.82), borderRadius: BorderRadius.circular(Corners.full)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: scheme.primary),
          if (text != null) ...[
            const SizedBox(width: 3),
            Text(text!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface)),
          ],
        ]),
      );
}
