import 'package:flutter/material.dart';

import '../core/api.dart';
import '../theme/tokens.dart';
import 'loading.dart';
import '../l10n/l10n.dart';

class CenteredLoader extends StatelessWidget {
  const CenteredLoader({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ExpressiveLoader(contained: true),
          if (label != null) ...[
            const SizedBox(height: Space.lg),
            Text(label!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: ShapeDecoration(color: cs.secondaryContainer, shape: const StarBorder(points: 8, innerRadiusRatio: 0.82, pointRounding: 0.55, valleyRounding: 0.45)),
              child: Icon(icon, size: 36, color: cs.onSecondaryContainer),
            ),
            const SizedBox(height: Space.xl),
            Text(title, style: tt.titleLarge, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: Space.sm),
              Text(body!, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: Space.xl), action!],
          ]),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: error is ApiError && (error as ApiError).status == 401 ? l10n.stateSessionExpired : l10n.stateLoadFailed,
        body: error.toString(),
        action: onRetry == null ? null : FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(l10n.commonRetry)),
      );
}

/// Constrains page content to a readable width on large windows.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.max = kMaxContentWidth});
  final Widget child;
  final double max;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
      );
}

/// Brief feedback at the bottom of the window. Snackbars always time out:
/// Flutter keeps a snackbar with an action until dismissed unless `persist`
/// is false, and the root messenger would carry it across pages.
void showSnack(BuildContext context, String msg, {String? action, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      persist: false,
      duration: Duration(seconds: action == null ? 4 : 6),
      action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {}),
    ));
}
