import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/step_slider.dart';
import 'assistant_controller.dart';
import '../../l10n/l10n.dart';

/// Pi's thinking levels, weakest first.
final kThinkingLevels = [('off', l10n.commonClose), ('minimal', l10n.thinkingMinimal), ('low', l10n.thinkingLow), ('medium', l10n.levelMedium), ('high', l10n.levelHigh), ('xhigh', l10n.thinkingMax)];

final _hints = {
  'off': l10n.thinkingHintOff,
  'minimal': l10n.thinkingHintMinimal,
  'low': l10n.thinkingHintLow,
  'medium': l10n.thinkingHintMedium,
  'high': l10n.thinkingHintHigh,
  'xhigh': l10n.thinkingHintMax,
};

/// 思考强度 as a stepped slider with a one-line hint for the chosen level.
/// [onContainer] adapts the colours to a primary container background.
class ThinkingControl extends StatelessWidget {
  const ThinkingControl({super.key, required this.value, required this.onChanged, this.onContainer = false, this.showTitle = true});
  final String value;
  final ValueChanged<String>? onChanged;
  final bool onContainer, showTitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fg = onContainer ? cs.onPrimaryContainer : cs.onSurface;
    final muted = onContainer ? cs.onPrimaryContainer.withValues(alpha: 0.72) : cs.onSurfaceVariant;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (showTitle) ...[
        Text(l10n.thinkingTitle, style: tt.labelLarge?.copyWith(color: fg)),
        const SizedBox(height: Space.xs),
      ],
      StepSlider<String>(
        values: [for (final (k, _) in kThinkingLevels) k],
        labels: [for (final (_, l) in kThinkingLevels) l],
        value: value,
        onChanged: onChanged,
        semanticLabel: l10n.thinkingTitle,
        inactiveColor: onContainer ? cs.onPrimaryContainer.withValues(alpha: 0.1) : null,
        labelColor: muted,
      ),
      const SizedBox(height: Space.sm),
      AnimatedSwitcher(
        duration: Motion.short3,
        child: Text(_hints[value] ?? '', key: ValueKey(value), style: tt.bodySmall?.copyWith(color: muted)),
      ),
    ]);
  }
}

/// The phone variant of the composer's 思考强度 entry: a bottom sheet.
Future<void> showThinkingSheet(BuildContext context, AssistantController a) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: ListenableBuilder(
            listenable: a,
            builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l10n.thinkingTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.xs),
              Text(l10n.thinkingSheetBody, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: Space.xl),
              ThinkingControl(value: a.thinking, showTitle: false, onChanged: (k) => a.setPrefs({'thinking': k})),
            ]),
          ),
        ),
      ),
    );

/// The label of a thinking level, e.g. 中.
String thinkingLabel(String level) => kThinkingLevels.firstWhere((e) => e.$1 == level, orElse: () => kThinkingLevels[3]).$2;
