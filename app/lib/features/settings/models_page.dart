import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../theme/tokens.dart';
import '../../widgets/horizontal_scroller.dart';
import '../../widgets/states.dart';
import '../assistant/assistant_controller.dart';
import 'add_provider_page.dart';
import 'model_meta.dart';
import 'provider_presets.dart';
import 'provider_setup_page.dart';

const kThinkingLevels = [('off', '关闭'), ('minimal', '最少'), ('low', '低'), ('medium', '中'), ('high', '高'), ('xhigh', '最高')];

List<Map<String, dynamic>> providersOf(Map<String, dynamic>? models) =>
    jsonList(models?['providers']).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

/// Overview of the Pi SDK model pipeline: the default model, providers the
/// user has set up, and the entry to the guided "add provider" flow.
class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});
  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  @override
  void initState() {
    super.initState();
    context.read<AssistantController>().loadModels();
  }

  void _add() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddProviderPage()));

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AssistantController>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final m = a.models;
    final mine = providersOf(m).where((p) => p['configured'] == true || p['custom'] == true).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('模型'),
        actions: [
          MenuAnchor(
            menuChildren: [
              if (m?['pi_cli_available'] == true)
                MenuItemButton(
                  leadingIcon: const Icon(Icons.download_for_offline_outlined),
                  onPressed: () async {
                    try {
                      final s = await a.importPi();
                      if (context.mounted) showSnack(context, s);
                    } catch (e) {
                      if (context.mounted) showSnack(context, '$e');
                    }
                  },
                  child: const Text('导入 Pi CLI 配置'),
                ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.cloud_sync_outlined),
                onPressed: () async {
                  try {
                    await a.catalogProviders(refresh: true);
                    if (context.mounted) showSnack(context, '已更新 models.dev 目录');
                  } catch (e) {
                    if (context.mounted) showSnack(context, '$e');
                  }
                },
                child: const Text('更新 models.dev 目录'),
              ),
            ],
            builder: (context, c, _) => IconButton(onPressed: () => c.isOpen ? c.close() : c.open(), icon: const Icon(Icons.more_vert_rounded)),
          ),
        ],
      ),
      floatingActionButton: m == null ? null : FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('添加服务商')),
      body: !a.ready
          ? const EmptyState(icon: Icons.smart_toy_outlined, title: '助手还没启动', body: '启动后才能读取 Pi SDK 的模型注册表')
          : m == null
              ? (a.modelsError != null ? ErrorState(error: a.modelsError!, onRetry: a.loadModels) : const CenteredLoader())
              : ListView(padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 120), children: [
                  ContentWidth(
                    max: 820,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (a.selected != null) _CurrentCard(a: a) else _Onboarding(onStart: _add),
                      if (m['error'] != null) ...[
                        const SizedBox(height: Space.md),
                        Card(
                          color: cs.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(Space.lg),
                            child: Text('配置文件有误：${m['error']}', style: TextStyle(color: cs.onErrorContainer)),
                          ),
                        ),
                      ],
                      const SizedBox(height: Space.xl),
                      Row(children: [
                        Expanded(child: Text('已添加的服务商', style: tt.titleMedium)),
                        TextButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('添加')),
                      ]),
                      const SizedBox(height: Space.sm),
                      if (mine.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: Space.lg),
                          child: Text('还没有服务商。点“添加服务商”，从 30 多家预设或 models.dev 目录里选择。',
                              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        ),
                      for (final p in mine)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: _ProviderTile(p: p, selected: a.selected?['provider'] == p['id']),
                        ),
                    ]),
                  ),
                ]),
    );
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding({required this.onStart});
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const steps = [
      (Icons.storefront_outlined, '选择服务商', '30+ 预设，或 models.dev 收录的 200 多家'),
      (Icons.key_outlined, '填入 API Key', '只保存在本机，可一键测试连接'),
      (Icons.checklist_rounded, '挑选模型', '从服务商拉取模型列表，自动补全价格和上下文长度'),
    ];
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(Corners.xlIncreased)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('给助手接上一个模型', style: tt.headlineSmall?.copyWith(color: cs.onPrimaryContainer)),
        const SizedBox(height: Space.lg),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(children: [
              CircleAvatar(radius: 16, backgroundColor: cs.primary, child: Text('${i + 1}', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600))),
              const SizedBox(width: Space.md),
              Icon(steps[i].$1, color: cs.onPrimaryContainer),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${steps[i].$2}  ', style: tt.titleSmall?.copyWith(color: cs.onPrimaryContainer)),
                  TextSpan(text: steps[i].$3, style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
                ])),
              ),
            ]),
          ),
        const SizedBox(height: Space.sm),
        FilledButton.icon(onPressed: onStart, icon: const Icon(Icons.arrow_forward_rounded), label: const Text('开始')),
      ]),
    );
  }
}

class _CurrentCard extends StatefulWidget {
  const _CurrentCard({required this.a});
  final AssistantController a;
  @override
  State<_CurrentCard> createState() => _CurrentCardState();
}

class _CurrentCardState extends State<_CurrentCard> {
  late final _persona = TextEditingController(text: '${(widget.a.models?['prefs'] as Map?)?['persona'] ?? ''}');

  @override
  void dispose() {
    _persona.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sel = a.selected!;
    final info = a.selectedModelInfo ?? const {};
    final prefs = (a.models?['prefs'] as Map?) ?? const {};
    final providerName = providersOf(a.models).firstWhere((p) => p['id'] == sel['provider'], orElse: () => {'name': sel['provider']})['name'];
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(Corners.xlIncreased)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProviderLogo(providerId: '${sel['provider']}', name: '$providerName', size: 52),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('助手正在使用', style: tt.labelMedium?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
              Text('${info['name'] ?? sel['model']}', style: tt.titleLarge?.copyWith(color: cs.onPrimaryContainer), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('$providerName · ${sel['model']}', style: tt.bodySmall?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.75)), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          FilledButton.tonal(onPressed: () => showModelPicker(context), child: const Text('更换')),
        ]),
        if (info.isNotEmpty) ...[const SizedBox(height: Space.md), ModelBadges(m: info)],
        if (sel['reasoning'] == true) ...[
          const SizedBox(height: Space.lg),
          Text('思考强度', style: tt.labelLarge?.copyWith(color: cs.onPrimaryContainer)),
          const SizedBox(height: Space.sm),
          HorizontalScroller(fade: true, builder: (c) => SingleChildScrollView(
            controller: c,
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final (k, l) in kThinkingLevels) ButtonSegment(value: k, label: Text(l))],
              selected: {a.thinking},
              onSelectionChanged: (s) => a.setPrefs({'thinking': s.first}),
            ),
          )),
        ],
        const SizedBox(height: Space.lg),
        TextField(
          controller: _persona,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: '附加指令（可选）',
            hintText: '例如：回答尽量简短；术语保留英文并附中文解释',
            fillColor: cs.surface.withValues(alpha: 0.7),
            suffixIcon: IconButton(
              tooltip: '保存',
              icon: const Icon(Icons.check_rounded),
              onPressed: () async {
                await a.setPrefs({'persona': _persona.text.trim()});
                if (context.mounted) showSnack(context, '已保存附加指令');
              },
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: prefs['autoTitle'] != false,
          onChanged: (v) => a.setPrefs({'autoTitle': v}),
          title: Text('自动为对话命名', style: TextStyle(color: cs.onPrimaryContainer)),
        ),
      ]),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.p, required this.selected});
  final Map<String, dynamic> p;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final models = jsonList(p['models']);
    final available = models.where((m) => (m as Map)['available'] == true).length;
    final preset = presetFor('${p['id']}');
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(Corners.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Corners.lg),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProviderSetupPage.existing(provider: p))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
          child: Row(children: [
            ProviderLogo(providerId: '${p['id']}', name: '${p['name']}', networkLogo: '${p['catalog_id']}'.isEmpty ? null : 'https://models.dev/logos/${p['catalog_id']}.svg'),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(preset?.name ?? '${p['name']}', style: tt.titleSmall, overflow: TextOverflow.ellipsis)),
                  if (selected) ...[
                    const SizedBox(width: Space.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(Corners.full)),
                      child: Text('使用中', style: tt.labelSmall?.copyWith(color: cs.onPrimary)),
                    ),
                  ],
                ]),
                Text(
                  [
                    p['configured'] == true ? '$available 个可用模型' : '未填写密钥',
                    if ('${p['key_hint']}'.isNotEmpty) '${p['key_hint']}',
                    if (p['custom'] == true) '自定义' else '内置',
                  ].join(' · '),
                  style: tt.bodySmall?.copyWith(color: p['configured'] == true ? cs.onSurfaceVariant : cs.error),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

/// Searchable picker over every usable model of every configured provider.
Future<void> showModelPicker(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => const _ModelPicker(),
  );
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker();
  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  final _q = TextEditingController();
  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AssistantController>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final q = _q.text.trim().toLowerCase();
    final groups = <(Map<String, dynamic>, List<Map<String, dynamic>>)>[];
    for (final p in providersOf(a.models).where((p) => p['configured'] == true)) {
      final ms = jsonList(p['models'])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((m) => m['available'] == true && (q.isEmpty || '${m['id']} ${m['name']} ${p['name']}'.toLowerCase().contains(q)))
          .toList();
      if (ms.isNotEmpty) groups.add((p, ms));
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
          child: SearchBar(
            controller: _q,
            autoFocus: true,
            hintText: '搜索模型',
            leading: const Icon(Icons.search_rounded),
            onChanged: (_) => setState(() {}),
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(child: Text('没有可用的模型', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
              : ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl), children: [
                  for (final (p, ms) in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, Space.xs),
                      child: Row(children: [
                        ProviderLogo(providerId: '${p['id']}', name: '${p['name']}', size: 24),
                        const SizedBox(width: Space.sm),
                        Text(presetFor('${p['id']}')?.name ?? '${p['name']}', style: tt.labelLarge?.copyWith(color: cs.primary)),
                      ]),
                    ),
                    for (final m in ms)
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.lg)),
                        selected: a.selected?['provider'] == p['id'] && a.selected?['model'] == m['id'],
                        selectedTileColor: cs.secondaryContainer,
                        title: Text('${m['name']}'),
                        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: ModelBadges(m: m, dense: true)),
                        onTap: () {
                          a.setPrefs({'provider': p['id'], 'model': m['id']});
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ]),
        ),
      ]),
    );
  }
}
