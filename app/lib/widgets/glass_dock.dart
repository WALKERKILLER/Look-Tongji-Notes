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
/// or on a tap. The selection indicator stretches toward its destination
/// before the trailing edge follows, so moving between tabs reads as one
/// continuous drop of colour.
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
      child: GlassSurface(
        radius: Corners.full,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: GlassNavDock.height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTheme.merge(
                    data: IconThemeData(color: cs.onSecondaryContainer),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: cs.secondaryContainer,
                        shape: const StadiumBorder(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                          vertical: Space.xs,
                        ),
                        child: item.selectedIcon,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
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

class _BarState extends State<_Bar> with SingleTickerProviderStateMixin {
  late final _move = AnimationController(
    vsync: this,
    duration: Motion.medium4,
    value: 1,
  );
  late int _from = widget.selected;

  @override
  void didUpdateWidget(_Bar old) {
    super.didUpdateWidget(old);
    if (old.selected == widget.selected) return;
    _from = old.selected;
    MediaQuery.disableAnimationsOf(context)
        ? _move.value = 1
        : _move.forward(from: 0);
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final n = widget.items.length;
    return GlassSurface(
      radius: Corners.full,
      child: SizedBox(
        height: GlassNavDock.height,
        child: LayoutBuilder(
          builder: (context, box) {
            final slot = box.maxWidth / n;
            final pill = (slot - Space.xs).clamp(32.0, 56.0);
            double left(int i) => i * slot + (slot - pill) / 2;
            return Stack(
              children: [
                if (widget.selected >= 0)
                  AnimatedBuilder(
                    animation: _move,
                    builder: (context, _) {
                      final from = _from < 0 ? widget.selected : _from;
                      final a = left(from), b = left(widget.selected);
                      // The leading edge runs ahead; the trailing one follows.
                      final lead = Motion.emphasizedDecelerate.transform(
                        _move.value,
                      );
                      final trail = Motion.emphasized.transform(_move.value);
                      final rightward = b >= a;
                      final l = rightward
                          ? a + (b - a) * trail
                          : a + (b - a) * lead;
                      final r =
                          (rightward
                              ? a + (b - a) * lead
                              : a + (b - a) * trail) +
                          pill;
                      return Positioned(
                        left: l,
                        width: r - l,
                        top: 10,
                        height: 32,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: cs.secondaryContainer,
                            shape: const StadiumBorder(),
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
                          labelStyle: tt.labelSmall!,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onSelected(i);
                          },
                          color: i == widget.selected
                              ? cs.onSecondaryContainer
                              : cs.onSurfaceVariant,
                          labelColor: i == widget.selected
                              ? cs.onSurface
                              : cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.color,
    required this.labelColor,
    required this.labelStyle,
  });
  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color color, labelColor;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: item.label,
    excludeSemantics: true,
    child: Tooltip(
      message: item.label,
      waitDuration: const Duration(milliseconds: 800),
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 32,
              child: Center(
                child: IconTheme.merge(
                  data: IconThemeData(color: color, size: 24),
                  child: selected ? item.selectedIcon : item.icon,
                ),
              ),
            ),
            const SizedBox(height: Space.xxs),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: labelStyle.copyWith(
                color: labelColor,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
