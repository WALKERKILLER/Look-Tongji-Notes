import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../l10n/l10n.dart';

String fmtTokens(num n) {
  if (n <= 0) return '';
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).round()}K';
  return '$n';
}

String fmtPrice(num? v) {
  if (v == null) return '';
  if (v == 0) return '0';
  return v < 0.1 ? v.toStringAsFixed(3) : v < 10 ? v.toStringAsFixed(2) : v.toStringAsFixed(0);
}

/// Capability and limit chips for one model (models.dev / Pi catalog fields).
class ModelBadges extends StatelessWidget {
  const ModelBadges({super.key, required this.m, this.dense = false});
  final Map m;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ctx = (m['context_window'] as num?) ?? 0;
    final out = (m['max_tokens'] as num?) ?? 0;
    final cin = m['cost_in'] as num?;
    final cout = m['cost_out'] as num?;
    final items = <(IconData, String, bool)>[
      if (m['reasoning'] == true) (Icons.psychology_outlined, l10n.modelTagReasoning, true),
      if (m['vision'] == true) (Icons.image_outlined, l10n.modelTagVision, true),
      if (ctx > 0) (Icons.data_array_rounded, l10n.modelTagContext(fmtTokens(ctx)), false),
      if (!dense && out > 0) (Icons.output_rounded, l10n.modelTagOutput(fmtTokens(out)), false),
      if (cin != null && cout != null && (cin > 0 || cout > 0)) (Icons.payments_outlined, '\$${fmtPrice(cin)} / \$${fmtPrice(cout)}', false),
      if (cin == 0 && cout == 0) (Icons.redeem_outlined, l10n.modelTagFree, true),
      if (m['deprecated'] == true) (Icons.history_toggle_off_rounded, l10n.modelTagDeprecated, false),
    ];
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final (icon, text, accent) in items)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: accent ? cs.secondaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Corners.xs),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: accent ? cs.onSecondaryContainer : cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: accent ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
          ]),
        ),
    ]);
  }
}
