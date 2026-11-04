import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/glass.dart';
import '../theme/tokens.dart';

/// One destination in the [GlassNavDock].
class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final Widget icon, selectedIcon;
  final String label;
}

/// The phone's navigation: a Material 3 navigation bar floating as a glass
/// pill over the page, with an accessory (the assistant) beside it.
///
/// Behaviour follows the floating tab bars of iOS 26 and M3's flexible
/// navigation bar: content scrolls beneath it, it shrinks to the current
/// destination while the page scrolls down and returns on the way back up
/// or on a tap. The selection is a lens inset evenly in the pill, so its
/// corners stay concentric with the pill's. Between tabs the lens stretches
/// toward its destination before the trailing edge follows; pressing and
/// sliding along the dock carries the lens under the finger, ticks at each
/// destination and selects the one it is let go on.
class GlassNavDock extends StatelessWidget {
  const GlassNavDock({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.accessory,
    this.minimized = false,
    this.onExpand,
  });

  /// Height of the pill, the M3 flexible navigation bar's.
  static const double height = 64;

  /// Gap between the pill and the lens on every side.
  static const double inset = Space.xs;

  /// The lens's corner: the pill's less [inset], so the two are concentric.
  static const double lensRadius = height / 2 - inset;

  /// Room the dock takes above the system inset, for page padding.
  static const double clearance = height + Space.md;

  final List<GlassNavItem> items;

  /// -1 when the current page is not one of [items].
  final int selected;
  final ValueChanged<int> onSelected;
  final Widget? accessory;
  final bool minimized;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final current = selected < 0 ? null : items[selected];
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AnimatedSwitcher(
                duration: reduce ? Duration.zero : Motion.medium2,
                switchInCurve: Motion.emphasizedDecelerate,
                switchOutCurve: Motion.emphasizedAccelerate,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                    scale: Tween(begin: .92, end: 1.0).animate(a),
                    alignment: AlignmentDirectional.centerStart.resolve(
                      Directionality.of(context),
                    ),
                    child: child,
                  ),
                ),
                child: minimized && current != null
                    ? _Collapsed(
                        key: const ValueKey('dock-min'),
                        item: current,
                        onTap: onExpand,
                      )
                    : _Bar(
                        key: const ValueKey('dock-bar'),
                        items: items,
                        selected: selected,
                        onSelected: onSelected,
                      ),
              ),
            ),
          ),
          if (accessory != null) ...[
            const SizedBox(width: Space.sm),
            SizedBox.square(dimension: height, child: accessory),
          ],
        ],
      ),
    );
  }
}

class _Collapsed extends StatelessWidget {
  const _Collapsed({super.key, required this.item, this.onTap});
  final GlassNavItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: GlassSurface(
        radius: Corners.full,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(GlassNavDock.inset),
            // The lens alone, holding the current destination.
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: cs.secondaryContainer,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(GlassNavDock.lensRadius),
                ),
              ),
              child: SizedBox(
                height: GlassNavDock.height - 2 * GlassNavDock.inset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconTheme.merge(
                        data: IconThemeData(
                          color: cs.onSecondaryContainer,
                          size: 24,
                        ),
                        child: item.selectedIcon,
                      ),
                      const SizedBox(width: Space.sm),
                      MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Text(
                          item.label,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: cs.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatefulWidget {
  const _Bar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });
  final List<GlassNavItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> with TickerProviderStateMixin {
  // The lens's move between destinations, and its swell while held.
  late final _move = AnimationController(
    vsync: this,
    duration: Motion.medium4,
    value: 1,
  );
  late final _lift = AnimationController(
    vsync: this,
    duration: Motion.short4,
  );

  double _slot = 0, _width = 0;

  /// Where the lens's start edge set off from, and the destination it is
  /// heading to. A scrub sets both before the page catches up.
  double? _from;
  late int _to = widget.selected;

  /// The finger, measured from the start edge, while scrubbing.
  double? _finger;
  int? _over;

  @override
  void didUpdateWidget(_Bar old) {
    super.didUpdateWidget(old);
    if (widget.selected != _to) _glide(_edges().$1, widget.selected);
  }

  @override
  void dispose() {
    _move.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _glide(double from, int to) {
    _from = from;
    _to = to;
    MediaQuery.disableAnimationsOf(context)
        ? _move.value = 1
        : _move.forward(from: 0);
  }

  /// The lens's start and end edges, measured from the start of the row.
  (double, double) _edges() {
    final w = _slot;
    if (_finger case final x?) {
      final s = (x - w / 2).clamp(0.0, w * (widget.items.length - 1));
      return (s, s + w);
    }
    if (_to < 0) return (0, 0);
    final b = _to * w, a = _from ?? b;
    // The leading edge runs ahead; the trailing one follows.
    final lead = Motion.emphasizedDecelerate.transform(_move.value);
    final trail = Motion.emphasized.transform(_move.value);
    return b >= a
        ? (a + (b - a) * trail, a + (b - a) * lead + w)
        : (a + (b - a) * lead, a + (b - a) * trail + w);
  }

  double _fromStart(Offset local) =>
      Directionality.of(context) == TextDirection.rtl
      ? _width - local.dx
      : local.dx;

  int _slotAt(double x) =>
      (x / _slot).floor().clamp(0, widget.items.length - 1);

  void _hold(Offset local) {
    if (_slot <= 0) return;
    final x = _fromStart(local);
    _move.stop();
    HapticFeedback.selectionClick();
    _lift.forward();
    setState(() {
      _finger = x;
      _over = _slotAt(x);
    });
  }

  void _slide(Offset local) {
    if (_finger == null) return;
    final x = _fromStart(local), i = _slotAt(x);
    if (i != _over) HapticFeedback.selectionClick();
    setState(() {
      _finger = x;
      _over = i;
    });
  }

  void _letGo() {
    final i = _over;
    if (i == null) return;
    final from = _edges().$1;
    _lift.reverse();
    setState(() {
      _finger = _over = null;
      _glide(from, i);
    });
    if (i != widget.selected) widget.onSelected(i);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final n = widget.items.length;
    final current = _over ?? _to;
    return GlassSurface(
      radius: Corners.full,
      child: SizedBox(
        height: GlassNavDock.height,
        child: Padding(
          padding: const EdgeInsets.all(GlassNavDock.inset),
          child: LayoutBuilder(
            builder: (context, box) {
              _width = box.maxWidth;
              _slot = box.maxWidth / n;
              return GestureDetector(
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragStart: (d) => _hold(d.localPosition),
                onHorizontalDragUpdate: (d) => _slide(d.localPosition),
                onHorizontalDragEnd: (_) => _letGo(),
                onHorizontalDragCancel: _letGo,
                onLongPressStart: (d) => _hold(d.localPosition),
                onLongPressMoveUpdate: (d) => _slide(d.localPosition),
                onLongPressEnd: (_) => _letGo(),
                child: Stack(
                  children: [
                    if (_to >= 0 || _finger != null)
                      AnimatedBuilder(
                        animation: Listenable.merge([_move, _lift]),
                        builder: (context, _) {
                          final (s, e) = _edges();
                          final lift = Motion.emphasized.transform(
                            _lift.value,
                          );
                          return PositionedDirectional(
                            start: s,
                            width: e - s,
                            top: 0,
                            bottom: 0,
                            child: Transform.scale(
                              scale: 1 + .06 * lift,
                              child: DecoratedBox(
                                key: const ValueKey('dock-lens'),
                                decoration: ShapeDecoration(
                                  // Thinner while held, so what it passes over shows.
                                  color: cs.secondaryContainer.withValues(
                                    alpha: 1 - .28 * lift,
                                  ),
                                  shape: RoundedSuperellipseBorder(
                                    borderRadius: BorderRadius.circular(
                                      GlassNavDock.lensRadius,
                                    ),
                                  ),
                                  shadows: [
                                    if (lift > 0)
                                      BoxShadow(
                                        color: cs.shadow.withValues(
                                          alpha: .16 * lift,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 2),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: _Destination(
                              item: widget.items[i],
                              selected: i == widget.selected,
                              lit: i == current,
                              labelStyle: tt.labelMedium!,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onSelected(i);
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.item,
    required this.selected,
    required this.lit,
    required this.onTap,
    required this.labelStyle,
  });
  final GlassNavItem item;

  /// [selected] is the current page; [lit] is under the lens, which a scrub
  /// moves ahead of the selection.
  final bool selected, lit;
  final VoidCallback onTap;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = lit ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(GlassNavDock.lensRadius),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconTheme.merge(
              data: IconThemeData(color: color, size: 24),
              child: lit ? item.selectedIcon : item.icon,
            ),
            const SizedBox(height: Space.xxs),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: labelStyle.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
