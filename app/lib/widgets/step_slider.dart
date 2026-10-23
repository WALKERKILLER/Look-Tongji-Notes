import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// A discrete slider over a few named stops (M3 Expressive slider: 16dp
/// track, 4dp bar handle with a gap on both sides, stop indicators), with
/// each stop's label below it. The active track deepens from a light tone of
/// [activeColor] to the full colour, so the position reads as intensity.
///
/// The thumb follows the pointer while dragging and snaps to the nearest
/// stop on release; [onChanged] fires once per committed change.
class StepSlider<T> extends StatefulWidget {
  const StepSlider({
    super.key,
    required this.values,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.activeColor,
    this.inactiveColor,
    this.labelColor,
  }) : assert(values.length == labels.length && values.length > 1);

  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T>? onChanged;
  final String? semanticLabel;

  /// Defaults: primary, secondaryContainer, onSurfaceVariant.
  final Color? activeColor, inactiveColor, labelColor;

  @override
  State<StepSlider<T>> createState() => _StepSliderState<T>();
}

class _StepSliderState<T> extends State<StepSlider<T>> with SingleTickerProviderStateMixin {
  static const _height = 44.0; // handle height and touch target
  static const _inset = 8.0; // keeps the end stops off the rounded track ends

  late final AnimationController _pos = AnimationController(vsync: this, value: _fraction(_index), duration: Motion.medium1);
  late int _shown = _index; // the stop the thumb points at, during drags too
  bool _dragging = false, _focused = false, _hovered = false;
  double _width = 0;

  int get _index => math.max(0, widget.values.indexOf(widget.value));
  int get _last => widget.values.length - 1;
  bool get _enabled => widget.onChanged != null;
  double _fraction(int i) => i / (widget.values.length - 1);

  @override
  void didUpdateWidget(StepSlider<T> old) {
    super.didUpdateWidget(old);
    if (!_dragging && _index != _shown) {
      _shown = _index;
      _animateTo(_index);
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _animateTo(int i) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pos.value = _fraction(i);
    } else {
      _pos.animateTo(_fraction(i), curve: Motion.emphasizedDecelerate);
    }
  }

  double _fractionAt(double dx) => ((dx - _inset) / math.max(1, _width - 2 * _inset)).clamp(0.0, 1.0);

  void _show(int i) {
    if (i == _shown) return;
    HapticFeedback.selectionClick();
    setState(() => _shown = i);
  }

  void _commit(int i) {
    _show(i);
    _animateTo(i);
    if (widget.values[i] != widget.value) widget.onChanged?.call(widget.values[i]);
  }

  void _dragUpdate(double dx) {
    final f = _fractionAt(dx);
    _pos.value = f;
    _show((f * _last).round());
  }

  void _dragEnd() {
    setState(() => _dragging = false);
    _commit(_shown);
  }

  void _step(int delta) {
    if (_enabled) _commit((_shown + delta).clamp(0, _last));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final active = _enabled ? widget.activeColor ?? cs.primary : cs.onSurface.withValues(alpha: 0.38);
    final inactive = _enabled ? widget.inactiveColor ?? cs.secondaryContainer : cs.onSurface.withValues(alpha: 0.12);
    final label = widget.labelColor ?? cs.onSurfaceVariant;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      slider: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      value: widget.labels[_shown],
      increasedValue: _shown < _last ? widget.labels[_shown + 1] : null,
      decreasedValue: _shown > 0 ? widget.labels[_shown - 1] : null,
      onIncrease: _enabled && _shown < _last ? () => _step(1) : null,
      onDecrease: _enabled && _shown > 0 ? () => _step(-1) : null,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.arrowRight): _StepIntent(rtl ? -1 : 1),
          LogicalKeySet(LogicalKeyboardKey.arrowLeft): _StepIntent(rtl ? 1 : -1),
          LogicalKeySet(LogicalKeyboardKey.arrowUp): const _StepIntent(1),
          LogicalKeySet(LogicalKeyboardKey.arrowDown): const _StepIntent(-1),
          LogicalKeySet(LogicalKeyboardKey.home): const _StepIntent(-99),
          LogicalKeySet(LogicalKeyboardKey.end): const _StepIntent(99),
        },
        actions: {_StepIntent: CallbackAction<_StepIntent>(onInvoke: (i) => _step(i.delta))},
        child: LayoutBuilder(builder: (context, c) {
          _width = c.maxWidth;
          // Pointer positions are measured from the start edge.
          double dx(Offset local) => rtl ? _width - local.dx : local.dx;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _enabled ? (d) => _commit((_fractionAt(dx(d.localPosition)) * _last).round()) : null,
              onHorizontalDragStart: _enabled
                  ? (d) {
                      setState(() => _dragging = true);
                      _dragUpdate(dx(d.localPosition));
                    }
                  : null,
              onHorizontalDragUpdate: _enabled ? (d) => _dragUpdate(dx(d.localPosition)) : null,
              onHorizontalDragEnd: _enabled ? (_) => _dragEnd() : null,
              onHorizontalDragCancel: _enabled ? _dragEnd : null,
              child: SizedBox(
                height: _height,
                child: AnimatedBuilder(
                  animation: _pos,
                  builder: (context, _) => CustomPaint(
                    painter: _TrackPainter(
                      fraction: _pos.value,
                      stops: widget.values.length,
                      selected: _shown,
                      inset: _inset,
                      active: active,
                      inactive: inactive,
                      onActive: _enabled ? cs.onPrimary : cs.surface,
                      onInactive: _enabled ? cs.onSecondaryContainer : cs.onSurface.withValues(alpha: 0.38),
                      handleWidth: _dragging ? 2 : 4,
                      focus: _focused ? cs.secondary : (_hovered && _enabled ? active.withValues(alpha: 0.24) : null),
                      rtl: rtl,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.xs),
            _Labels(
              inset: _inset,
              children: [
                for (final (i, l) in widget.labels.indexed)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _enabled ? () => _commit(i) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xxs),
                      child: AnimatedDefaultTextStyle(
                        duration: Motion.short3,
                        style: (tt.labelMedium ?? const TextStyle()).copyWith(
                          color: i == _shown ? (_enabled ? active : label) : label,
                          fontWeight: i == _shown ? FontWeight.w600 : FontWeight.w400,
                        ),
                        child: Text(l, maxLines: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ]);
        }),
      ),
    );
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.delta);
  final int delta;
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.fraction,
    required this.stops,
    required this.selected,
    required this.inset,
    required this.active,
    required this.inactive,
    required this.onActive,
    required this.onInactive,
    required this.handleWidth,
    required this.focus,
    required this.rtl,
  });

  final double fraction, inset, handleWidth;
  final int stops, selected;
  final Color active, inactive, onActive, onInactive;
  final Color? focus;
  final bool rtl;

  static const _track = 16.0, _gap = 6.0, _outer = 8.0, _inner = 2.0, _dot = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final w = size.width;
    final cy = size.height / 2;
    final span = w - 2 * inset;
    final x = inset + fraction * span;
    final top = cy - _track / 2, bottom = cy + _track / 2;

    // Active: from the start edge to the handle, a tonal ramp of one hue
    // over the whole width, so its end colour tells how far it goes.
    final aEnd = x - _gap - handleWidth / 2;
    if (aEnd > 0.5) {
      final r = RRect.fromLTRBAndCorners(0, top, aEnd, bottom,
          topLeft: const Radius.circular(_outer), bottomLeft: const Radius.circular(_outer),
          topRight: const Radius.circular(_inner), bottomRight: const Radius.circular(_inner));
      final shader = LinearGradient(colors: [Color.lerp(inactive, active, 0.45)!, active]).createShader(Rect.fromLTRB(0, top, w, bottom));
      canvas.drawRRect(r, Paint()..shader = shader);
    }
    final iStart = x + _gap + handleWidth / 2;
    if (w - iStart > 0.5) {
      final r = RRect.fromLTRBAndCorners(iStart, top, w, bottom,
          topLeft: const Radius.circular(_inner), bottomLeft: const Radius.circular(_inner),
          topRight: const Radius.circular(_outer), bottomRight: const Radius.circular(_outer));
      canvas.drawRRect(r, Paint()..color = inactive);
    }

    // Stop indicators, hidden where the handle and its gap are.
    for (var i = 0; i < stops; i++) {
      final sx = inset + i / (stops - 1) * span;
      if ((sx - x).abs() < _gap + handleWidth) continue;
      canvas.drawCircle(Offset(sx, cy), _dot, Paint()..color = sx < x ? onActive.withValues(alpha: 0.9) : onInactive.withValues(alpha: 0.7));
    }

    final handle = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, cy), width: handleWidth, height: size.height), Radius.circular(handleWidth / 2));
    if (focus != null) {
      canvas.drawRRect(handle.inflate(3), Paint()
        ..color = focus!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    canvas.drawRRect(handle, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_TrackPainter o) =>
      o.fraction != fraction || o.selected != selected || o.handleWidth != handleWidth || o.focus != focus || o.active != active || o.inactive != inactive || o.stops != stops;
}

/// Lays labels out centred under their stops, kept inside the bounds.
class _Labels extends MultiChildRenderObjectWidget {
  const _Labels({required this.inset, required super.children});
  final double inset;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLabels(inset, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderLabels r) => r
    ..inset = inset
    ..textDirection = Directionality.of(context);
}

class _LabelData extends ContainerBoxParentData<RenderBox> {}

class _RenderLabels extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _LabelData>, RenderBoxContainerDefaultsMixin<RenderBox, _LabelData> {
  _RenderLabels(this._inset, this._dir);
  double _inset;
  TextDirection _dir;
  set inset(double v) {
    if (v != _inset) {
      _inset = v;
      markNeedsLayout();
    }
  }

  set textDirection(TextDirection v) {
    if (v != _dir) {
      _dir = v;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LabelData) child.parentData = _LabelData();
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    final kids = getChildrenAsList();
    final n = kids.length;
    final slot = n > 1 ? (w - 2 * _inset) / (n - 1) : w;
    var h = 0.0;
    for (final (i, c) in kids.indexed) {
      // Each label may use its stop's share of the width, more at the ends.
      final room = i == 0 || i == n - 1 ? slot / 2 + _inset + slot / 2 : slot;
      c.layout(BoxConstraints(maxWidth: math.max(0, room)), parentUsesSize: true);
      h = math.max(h, c.size.height);
      final center = _inset + (n > 1 ? i / (n - 1) : 0.5) * (w - 2 * _inset);
      var left = (center - c.size.width / 2).clamp(0.0, math.max(0.0, w - c.size.width)).toDouble();
      if (_dir == TextDirection.rtl) left = w - left - c.size.width;
      (c.parentData! as _LabelData).offset = Offset(left, 0);
    }
    size = constraints.constrain(Size(w, h));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
