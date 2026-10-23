import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/plugins.dart';
import '../../theme/tokens.dart';
import '../../widgets/look_markdown.dart';
import '../../widgets/states.dart';
import '../library/note_reader.dart' show openRef;
import '../practice/quiz.dart' show askInSheet;

/// Renders one declarative view. Plugins send data, never UI code; the app
/// owns every renderer (docs/specs/0004-plugin-platform.md, 视图目录).
typedef PluginViewBuilder = Widget Function(BuildContext context, Map<String, dynamic> data);

final Map<String, PluginViewBuilder> pluginViewBuilders = {
  'checklist': (context, data) => ChecklistView(data: data),
};

/// A view from a tool result, an action or a `look-view` block.
class PluginView extends StatelessWidget {
  const PluginView({super.key, required this.view});
  final Map<String, dynamic> view;

  @override
  Widget build(BuildContext context) {
    final kind = '${view['kind']}';
    final data = view['data'] is Map ? (view['data'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final builder = pluginViewBuilders[kind];
    return builder == null ? _UnknownView(kind: kind, data: data) : builder(context, data);
  }
}

/// Shows a view in a sheet over the current screen.
Future<void> showPluginViewSheet(BuildContext context, Map<String, dynamic> view) => showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (context) {
        final tt = Theme.of(context).textTheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl), children: [
            if (view['title'] != null) Padding(padding: const EdgeInsets.only(bottom: Space.lg), child: Text('${view['title']}', style: tt.titleLarge)),
            PluginView(view: view),
          ]),
        );
      },
    );

/// Runs a contributed entry and presents its result. [onPrompt] replaces the
/// default of asking the assistant in a sheet (the panel itself sends).
Future<void> runPluginEntry(BuildContext context, PluginEntry e, Map<String, dynamic> ctx, {ValueChanged<String>? onPrompt}) async {
  final store = context.read<PluginStore>();
  try {
    final r = await store.run(e, ctx);
    if (!context.mounted) return;
    if (r['toast'] is String) showSnack(context, '${r['toast']}');
    if (r['view'] is Map) {
      await showPluginViewSheet(context, (r['view'] as Map).cast<String, dynamic>());
    } else if (r['prompt'] is String) {
      onPrompt != null ? onPrompt('${r['prompt']}') : await askInSheet(context, '${r['prompt']}');
    } else if (r['open'] is String) {
      final url = '${r['open']}';
      final ref = LookRef.parse(url);
      if (ref != null) {
        openRef(context, ref);
      } else if (url.startsWith('https://') || url.startsWith('http://')) {
        unawaited(launchUrl(Uri.parse(url)));
      }
    }
  } catch (err) {
    if (context.mounted) showSnack(context, '${e.pluginTitle}：${err is ApiError ? err.message : err}');
  }
}

/// A list of items with done states and a progress header.
/// Data: `{title?, items: [{text, done?, note?}]}`.
class ChecklistView extends StatelessWidget {
  const ChecklistView({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final items = [for (final x in jsonList(data['items'])) if (x is Map) x.cast<String, dynamic>()];
    final done = items.where((x) => x['done'] == true).length;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(Corners.lg), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.checklist_rounded, size: 18, color: cs.primary),
          const SizedBox(width: Space.sm),
          Expanded(child: Text('${data['title'] ?? '清单'}', style: tt.titleSmall)),
          Text('$done / ${items.length}', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: Space.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(Corners.full),
          child: LinearProgressIndicator(value: items.isEmpty ? 0 : done / items.length, minHeight: 6, backgroundColor: cs.surfaceContainerHighest),
        ),
        const SizedBox(height: Space.sm),
        for (final x in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(x['done'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: x['done'] == true ? cs.primary : cs.outline),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${x['text'] ?? ''}',
                      style: tt.bodyMedium?.copyWith(
                        color: x['done'] == true ? cs.onSurfaceVariant : cs.onSurface,
                        decoration: x['done'] == true ? TextDecoration.lineThrough : null,
                        decorationColor: cs.onSurfaceVariant,
                      )),
                  if ('${x['note'] ?? ''}'.isNotEmpty) Text('${x['note']}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// A view this app version cannot draw: says so, and keeps the data at hand.
class _UnknownView extends StatelessWidget {
  const _UnknownView({required this.kind, required this.data});
  final String kind;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(Corners.lg), border: Border.all(color: cs.outlineVariant)),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(),
        leading: Icon(Icons.widgets_outlined, color: cs.onSurfaceVariant),
        title: Text('「$kind」视图', style: tt.titleSmall),
        subtitle: const Text('当前版本的应用还不能显示这种视图，更新应用后即可查看'),
        childrenPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        children: [
          SelectableText(const JsonEncoder.withIndent('  ').convert(data), style: tt.bodySmall?.copyWith(fontFamily: 'monospace'), maxLines: 30),
        ],
      ),
    );
  }
}

/// A fenced ```look-view block (`{"kind": ..., "data": ...}`) in Markdown,
/// drawn when an active plugin declares the kind in `contributes.blocks`.
Widget? lookViewBlock(BuildContext context, String lang, String code) {
  if (lang != 'look-view') return null;
  Object? v;
  try {
    v = jsonDecode(code);
  } catch (_) {
    return null;
  }
  if (v is! Map || v['kind'] is! String) return null;
  if (!context.read<PluginStore>().rendersBlock('${v['kind']}')) return null;
  return PluginView(view: v.cast<String, dynamic>());
}

/// A menu of the plugin entries for a surface, e.g. a note's toolbar; empty
/// when no active plugin contributes to it. [noteViews] and [exportScope]
/// add those contributions under their own headings.
class PluginMenuButton extends StatelessWidget {
  const PluginMenuButton({super.key, required this.surface, required this.context_, this.noteViews = false, this.exportScope, this.onPrompt});
  final String surface;
  final Map<String, dynamic> context_;
  final bool noteViews;
  final String? exportScope;
  final ValueChanged<String>? onPrompt;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    final groups = [
      ('', store.entries('actions', surface: surface)),
      if (noteViews) ('换种方式看', store.entries('noteViews')),
      if (exportScope != null) ('导出', store.entries('exporters', scope: exportScope)),
    ].where((g) => g.$2.isNotEmpty).toList();
    if (groups.isEmpty) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    return MenuAnchor(
      menuChildren: [
        for (final (i, (label, entries)) in groups.indexed) ...[
          if (i > 0) const Divider(height: Space.sm),
          if (label.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.xs), child: Text(label, style: tt.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary))),
          for (final e in entries)
            MenuItemButton(
              leadingIcon: Icon(pluginIcon(e.icon), size: 20),
              trailingIcon: Text(e.pluginTitle, style: tt.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              onPressed: () => runPluginEntry(context, e, context_, onPrompt: onPrompt),
              child: Text(e.title),
            ),
        ],
      ],
      builder: (context, c, _) => IconButton(
        tooltip: '插件',
        onPressed: () => c.isOpen ? c.close() : c.open(),
        icon: const Icon(Icons.extension_outlined),
      ),
    );
  }
}
