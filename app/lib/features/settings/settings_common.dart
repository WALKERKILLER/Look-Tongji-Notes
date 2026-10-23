import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/api.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';

/// lookd's settings (`/api/settings`), shared by the settings panes and the
/// pages they open so both stay in step.
class ServerSettings extends ChangeNotifier {
  ServerSettings(this._api);
  final Api _api;
  Map<String, dynamic> values = {};

  Future<void> load() async {
    final r = (await _api.get('/api/settings') as Map?) ?? {};
    values = r.cast<String, dynamic>();
    notifyListeners();
  }

  /// Shows [value] at once, then takes what lookd saved.
  Future<void> put(String key, Object? value) async {
    set(key, value);
    final r = await _api.put('/api/settings', {key: value}) as Map?;
    if (r != null) {
      values = r.cast<String, dynamic>();
      notifyListeners();
    }
  }

  /// Changes a value locally, e.g. while a slider is dragged.
  void set(String key, Object? value) {
    values[key] = value;
    notifyListeners();
  }
}

/// A titled group of settings on a tonal container.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children, this.icon, this.leading, this.padding});
  final String title;
  final IconData? icon;

  /// Replaces [icon], e.g. with a brand mark.
  final Widget? leading;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mark = leading ?? (icon == null ? null : Icon(icon, size: 18, color: cs.primary));
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
          child: Row(children: [
            if (mark != null) ...[mark, const SizedBox(width: Space.sm)],
            Text(title, style: tt.titleSmall?.copyWith(color: cs.primary)),
          ]),
        ),
        // Material, not a decorated box, so list tiles' ink shows on it.
        Material(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(Corners.xl),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: padding ?? const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, Space.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ]),
    );
  }
}

/// A third-party mark (assets/brands, see NOTICE) on a neutral tile.
/// Single-colour marks take the theme's text colour.
class BrandMark extends StatelessWidget {
  const BrandMark(this.asset, {super.key, this.size = 40, this.mono = false});
  final String asset;
  final double size;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final logo = size * 0.6;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(size * 0.3)),
      child: asset.endsWith('.svg')
          ? SvgPicture.asset(asset, width: logo, height: logo, colorFilter: mono ? ColorFilter.mode(cs.onSurface, BlendMode.srcIn) : null)
          : ClipRRect(borderRadius: BorderRadius.circular(Corners.xs), child: Image.asset(asset, width: logo, height: logo)),
    );
  }
}

/// The top of an integration's page: its mark, name, a status line and
/// what it does.
class IntegrationHeader extends StatelessWidget {
  const IntegrationHeader({super.key, required this.mark, required this.title, required this.status, required this.body, this.on = false});
  final Widget mark;
  final String title, status, body;

  /// Whether the integration is set up; tints the status.
  final bool on;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        mark,
        const SizedBox(width: Space.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: tt.headlineSmall),
            const SizedBox(height: Space.xxs),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: on ? cs.primary : cs.outline, shape: BoxShape.circle)),
              const SizedBox(width: Space.sm),
              Flexible(child: Text(status, style: tt.bodyMedium?.copyWith(color: on ? cs.primary : cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
            ]),
          ]),
        ),
      ]),
      const SizedBox(height: Space.lg),
      Text(body, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.6)),
    ]);
  }
}

/// Numbered how-to steps.
class SettingsSteps extends StatelessWidget {
  const SettingsSteps(this.steps, {super.key, this.start = 1});
  final List<String> steps;
  final int start;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, s) in steps.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 11, backgroundColor: cs.secondaryContainer, child: Text('${start + i}', style: tt.labelSmall?.copyWith(color: cs.onSecondaryContainer))),
            const SizedBox(width: Space.md),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 1), child: Text(s, style: tt.bodyMedium))),
          ]),
        ),
    ]);
  }
}

/// A full page opened from settings, with a readable column.
class SettingsSubpage extends StatelessWidget {
  const SettingsSubpage({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pad = context.isCompact ? Space.lg : Space.xl;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: EdgeInsets.fromLTRB(pad, Space.sm, pad, Space.huge), children: [
        ContentWidth(max: 760, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
      ]),
    );
  }
}
