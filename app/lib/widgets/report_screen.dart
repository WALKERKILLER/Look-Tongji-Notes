import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';

/// Tells the assistant what the user is looking at while this route is the
/// visible one (top of its navigator and in the selected shell tab).
class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.value, required this.child});
  final Map<String, String> value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    final visible = TickerMode.valuesOf(context).enabled;
    if (current && visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.read<ScreenContext>().set(value);
      });
    }
    return child;
  }
}
