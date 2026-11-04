import 'package:flutter/material.dart';

import '../theme/glass.dart';
import '../theme/tokens.dart';
import 'glass_dock.dart';

/// The navigation of tablets and desktops: a glass column of destinations
/// between controls pinned to its top and bottom.
///
/// It never overflows or lets controls overlap. On a short window the brand
/// mark steps aside first, then destinations drop their labels (a tooltip
/// keeps each name), and if even that does not fit the destinations scroll,
/// fading out at whichever edge has more. The selection indicator slides
/// between destinations as the phone dock's lens does.
class GlassNavRail extends StatelessWidget {
  const GlassNavRail({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.brand,
    this.leading,
    this.trailing,
  });

  /// The M3 navigation rail's width.
  static const double width = 80;

  /// Window heights below which the brand hides.
  static const double _brandHeight = 600;

  final List<GlassNavItem> items;

  /// -1 when the current page is not one of [items].
  final int selected;
  final ValueChanged<int> onSelected;
  final Widget? brand, leading, trailing;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: Corners.xl,
    child: SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            const SizedBox(height: Space.lg),
            if (brand != null && box.maxHeight >= _brandHeight) ...[
              brand!,
              const SizedBox(height: Space.lg),
            ],
            if (leading != null) ...[leading!, const SizedBox(height: Space.md)],
            Expanded(
              child: _Destinations(
                items: items,
                selected: selected,
                onSelected: onSelected,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(height: Space.md),
              trailing!,
            ],
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    ),
  );
}

class _Destinations extends StatefulWidget {
  const _Destinations({
    required this.items,
    required this.selected,
    required this.onSelected,
  });
  final List<GlassNavItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  State<_Destinations> createState() => _DestinationsState();
}

class _DestinationsState extends State<_Destinations> {
  // M3 rail destinations: a 56 × 32 indicator, the label 4 below it.
  static const double _labelled = 64, _bare = 48;
  static const _indicator = Size(56, 32);

  final _scroll = ScrollController();
  bool _more = false, _less = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _edges(ScrollMetrics m) {
    final more = m.extentAfter > 0.5, less = m.extentBefore > 0.5;
    if (more != _more || less != _less) {
      setState(() {
        _more = more;
        _less = less;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final n = widget.items.length;
        // Labels go before anything scrolls; scrolling is the last resort.
        final labels = box.maxHeight >= n * _labelled;
        final h = labels ? _labelled : _bare;
        final top = labels ? Space.xs : (_bare - _indicator.height) / 2;
        final list = SingleChildScrollView(
          controller: _scroll,
          child: SizedBox(
            height: n * h,
            child: Stack(
              children: [
                if (widget.selected >= 0)
                  AnimatedPositioned(
                    duration: reduce ? Duration.zero : Motion.medium4,
                    curve: Motion.emphasized,
                    top: widget.selected * h + top,
                    left: (GlassNavRail.width - _indicator.width) / 2,
                    width: _indicator.width,
                    height: _indicator.height,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: cs.secondaryContainer,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                Column(
                  children: [
                    for (var i = 0; i < n; i++)
                      SizedBox(
                        height: h,
                        child: _RailItem(
                          item: widget.items[i],
                          selected: i == widget.selected,
                          label: labels,
                          indicatorTop: top,
                          labelStyle: tt.labelMedium!,
                          onTap: () => widget.onSelected(i),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _edges(n.metrics),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _edges(n.metrics),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: _less ? 0 : 1),
                  Colors.white,
                  Colors.white,
                  Colors.white.withValues(alpha: _more ? 0 : 1),
                ],
                stops: [0, Space.xl / r.height, 1 - Space.xl / r.height, 1],
              ).createShader(r),
              child: list,
            ),
          ),
        );
      },
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.label,
    required this.indicatorTop,
    required this.labelStyle,
    required this.onTap,
  });
  final GlassNavItem item;
  final bool selected, label;
  final double indicatorTop;
  final TextStyle labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = IconTheme.merge(
      data: IconThemeData(
        color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
        size: 24,
      ),
      child: selected ? item.selectedIcon : item.icon,
    );
    final body = Column(
      children: [
        SizedBox(height: indicatorTop),
        SizedBox(height: 32, child: Center(child: icon)),
        if (label) ...[
          const SizedBox(height: Space.xs),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle.copyWith(
                color: selected ? cs.onSurface : cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
    final tile = Semantics(
      selected: selected,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(Corners.lg),
          ),
          child: body,
        ),
      ),
    );
    return label ? tile : Tooltip(message: item.label, child: tile);
  }
}
