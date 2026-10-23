import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Makes a horizontal scrollable usable with a mouse. A vertical wheel
/// keeps scrolling the page, so the row can be dragged with the mouse, and
/// while it is hovered, previous/next buttons appear at the edges that
/// have more content. Touch and trackpads scroll as usual.
///
/// [builder] returns the horizontal scrollable, driven by the controller it
/// is given. For a [CarouselView], set [carousel] (the controller is then a
/// [CarouselController]) and [itemExtent] when it has one, so the buttons
/// move by whole items.
class HorizontalScroller extends StatefulWidget {
  const HorizontalScroller({super.key, required this.builder, this.controller, this.carousel = false, this.itemExtent, this.fade = false, this.buttons = true});
  final Widget Function(ScrollController controller) builder;

  /// Defaults to one owned by this widget.
  final ScrollController? controller;
  final bool carousel;
  final double? itemExtent;

  /// Fades the content out under the edges that have more of it; for chip
  /// rows, not for carousels whose items already shrink at the edges.
  final bool fade;

  /// Previous/next buttons; off where they would cover content that is
  /// read in place (code, tables).
  final bool buttons;

  @override
  State<HorizontalScroller> createState() => _HorizontalScrollerState();
}

class _HorizontalScrollerState extends State<HorizontalScroller> {
  bool _hover = false, _before = false, _after = false;
  ScrollController? _own;

  ScrollController get _controller => widget.controller ?? (_own ??= widget.carousel ? CarouselController() : ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  static const _fadeWidth = 32.0;

  bool _metrics(ScrollMetrics m) {
    if (m.axis != Axis.horizontal) return false;
    final before = m.extentBefore > 1, after = m.extentAfter > 1;
    if (before != _before || after != _after) {
      setState(() {
        _before = before;
        _after = after;
      });
    }
    return false;
  }

  void _step(int dir) {
    final c = _controller;
    if (!c.hasClients) return;
    final p = c.position;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduce ? const Duration(milliseconds: 1) : Motion.long2;
    if (c is CarouselController) {
      final ext = widget.itemExtent;
      final per = ext == null ? 1 : (p.viewportDimension / ext).floor().clamp(1, 1 << 20);
      c.animateToItem(c.leadingItem + dir * per, duration: duration, curve: Motion.emphasized);
      return;
    }
    final to = (p.pixels + dir * p.viewportDimension * 0.8).clamp(p.minScrollExtent, p.maxScrollExtent);
    c.animateTo(to, duration: duration, curve: Motion.emphasized);
  }

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet());
    Widget content = ScrollConfiguration(behavior: behavior, child: widget.builder(_controller));
    if (widget.fade) {
      content = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) {
          final f = (_fadeWidth / r.width).clamp(0.0, 0.5);
          return LinearGradient(
            colors: [
              _before ? Colors.transparent : Colors.black,
              Colors.black,
              Colors.black,
              _after ? Colors.transparent : Colors.black,
            ],
            stops: [0, f, 1 - f, 1],
          ).createShader(r);
        },
        child: content,
      );
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _metrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _metrics(n.metrics),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Stack(alignment: Alignment.center, children: [
            content,
            if (widget.buttons) ...[
              Positioned(left: Space.xs, child: _EdgeButton(back: true, visible: _hover && _before, onPressed: () => _step(-1))),
              Positioned(right: Space.xs, child: _EdgeButton(back: false, visible: _hover && _after, onPressed: () => _step(1))),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A small raised icon button; raised (level 2) so it reads over images.
class _EdgeButton extends StatelessWidget {
  const _EdgeButton({required this.back, required this.visible, required this.onPressed});
  final bool back, visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: visible ? Motion.short4 : Motion.short3,
        curve: visible ? Motion.emphasizedDecelerate : Motion.emphasizedAccelerate,
        child: AnimatedScale(
          scale: visible ? 1 : 0.8,
          duration: Motion.medium1,
          curve: Motion.emphasized,
          child: Material(
            color: cs.surfaceContainerHighest,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: cs.shadow.withValues(alpha: 0.4),
            child: IconButton(
              tooltip: back ? '向左滚动' : '向右滚动',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              color: cs.onSurface,
              onPressed: onPressed,
              icon: Icon(back ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
            ),
          ),
        ),
      ),
    );
  }
}
