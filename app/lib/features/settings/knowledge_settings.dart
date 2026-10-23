import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/lookd_service.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import 'notion_page.dart';
import 'obsidian_settings.dart';
import 'settings_common.dart';

/// The 知识库 pane: where the library lives, and where it goes.
class KnowledgeSettings extends StatefulWidget {
  const KnowledgeSettings({super.key, required this.settings});
  final ServerSettings settings;
  @override
  State<KnowledgeSettings> createState() => _KnowledgeSettingsState();
}

class _KnowledgeSettingsState extends State<KnowledgeSettings> {
  final _courseTpl = TextEditingController();
  final _lectureTpl = TextEditingController();
  Map<String, dynamic> _notion = const {};
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _fill();
    widget.settings.addListener(_fill);
    _loadNotion();
    _sub = context.read<AppState>().events.listen((e) {
      if ('${e['type']}'.startsWith('notion_') && e['type'] != 'notion_progress') _loadNotion();
    });
  }

  @override
  void dispose() {
    widget.settings.removeListener(_fill);
    _sub?.cancel();
    _courseTpl.dispose();
    _lectureTpl.dispose();
    super.dispose();
  }

  /// Takes the saved templates once they arrive, without clobbering typing.
  void _fill() {
    final tpl = widget.settings.values['library.templates'];
    if (_courseTpl.text.isEmpty) _courseTpl.text = tpl is Map ? '${tpl['course'] ?? '{title}'}' : '{title}';
    if (_lectureTpl.text.isEmpty) _lectureTpl.text = tpl is Map ? '${tpl['lecture'] ?? '{date} {title}'}' : '{date} {title}';
  }

  Future<void> _loadNotion() async {
    try {
      final r = await context.read<AppState>().api.get('/api/notion') as Map;
      if (mounted) setState(() => _notion = r.cast<String, dynamic>());
    } catch (_) {}
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) => _loadNotion());

  @override
  Widget build(BuildContext context) {
    final daemon = context.watch<LookdService>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final v = widget.settings.values;
    final vault = '${v['obsidian.vault'] ?? ''}';
    final notionOn = _notion['connected'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsGroup(title: '连接到笔记应用', padding: const EdgeInsets.symmetric(vertical: Space.sm), children: [
        _IntegrationTile(
          mark: const BrandMark('assets/brands/obsidian.svg'),
          title: 'Obsidian',
          subtitle: vault.isEmpty ? '导出到本地仓库，时间戳可点回 Look Studio' : '${p.basename(vault)} / ${v['obsidian.folder'] ?? ''}${v['obsidian.auto'] == true ? ' · 自动导出' : ''}',
          on: vault.isNotEmpty,
          onTap: () => _open(ObsidianPage(settings: widget.settings)),
        ),
        _IntegrationTile(
          mark: const BrandMark(notionLogo, mono: true),
          title: 'Notion',
          subtitle: notionSummary(_notion),
          on: notionOn,
          error: notionOn && '${(_notion['last'] as Map?)?['error'] ?? ''}'.isNotEmpty,
          onTap: () => _open(const NotionPage()),
        ),
      ]),
      SettingsGroup(title: '课程库', children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('位置'),
          subtitle: Text(daemon.libraryRoot),
          trailing: IconButton(tooltip: '打开', onPressed: () => openPath(daemon.libraryRoot), icon: const Icon(Icons.open_in_new_rounded)),
        ),
        const SizedBox(height: Space.sm),
        Text('文件夹命名模板', style: tt.titleSmall),
        const SizedBox(height: Space.xs),
        Text('课程可用 {title} {teacher} {term} {id}；课次可用 {date} {title} {sub_id} {lecturer}。只影响之后新建的文件夹。',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: Space.md),
        Row(children: [
          Expanded(child: TextField(controller: _courseTpl, decoration: const InputDecoration(labelText: '课程文件夹', isDense: true))),
          const SizedBox(width: Space.md),
          Expanded(child: TextField(controller: _lectureTpl, decoration: const InputDecoration(labelText: '课次文件夹', isDense: true))),
          const SizedBox(width: Space.sm),
          FilledButton.tonal(
            onPressed: () async {
              try {
                await widget.settings.put('library.templates', {'course': _courseTpl.text.trim(), 'lecture': _lectureTpl.text.trim()});
                if (context.mounted) showSnack(context, '模板已保存');
              } catch (e) {
                if (context.mounted) showSnack(context, '保存失败：$e');
              }
            },
            child: const Text('保存'),
          ),
        ]),
        const SizedBox(height: Space.md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.ios_share_rounded),
          title: const Text('导出为 Look-Tongji-Notes 技能格式'),
          subtitle: const Text('以硬链接生成 raw/<课程>/<节次>/原始数据/ 目录，不额外占空间'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _export(context),
        ),
      ]),
    ]);
  }

  Future<void> _export(BuildContext context) async {
    final ctl = TextEditingController();
    final root = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出到技能目录'),
        content: SizedBox(
          width: 440,
          child: FolderField(
            controller: ctl,
            autofocus: true,
            label: '目标文件夹',
            helper: 'Look-Tongji-Notes 技能所在的文件夹',
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('导出')),
        ],
      ),
    );
    if (root == null || root.isEmpty || !context.mounted) return;
    try {
      final r = await context.read<AppState>().api.post('/api/library/export', {'root': root}) as Map;
      if (context.mounted) showSnack(context, '已导出 ${r['exported']} 节课');
    } catch (e) {
      if (context.mounted) showSnack(context, '导出失败：$e');
    }
  }
}

class _IntegrationTile extends StatelessWidget {
  const _IntegrationTile({required this.mark, required this.title, required this.subtitle, required this.on, required this.onTap, this.error = false});
  final Widget mark;
  final String title, subtitle;
  final bool on, error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.xs),
      leading: mark,
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: error ? TextStyle(color: cs.error) : null),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (on)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
            decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(Corners.full)),
            child: Text('已连接', style: tt.labelSmall?.copyWith(color: cs.onSecondaryContainer)),
          ),
        const SizedBox(width: Space.xs),
        const Icon(Icons.chevron_right_rounded),
      ]),
      onTap: onTap,
    );
  }
}
