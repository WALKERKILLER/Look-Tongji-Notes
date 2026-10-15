import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/plugins.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../practice/quiz.dart' show askInSheet;
import 'plugin_views.dart';

// Plugin management and the marketplace (docs/specs/0004-plugin-platform.md).

const _surfaceLabels = {
  'note.toolbar': '笔记工具栏',
  'lecture.menu': '课次菜单',
  'course.menu': '课程菜单',
  'schedule.item': '日程条目',
  'assignment.actions': '作业页',
  'composer.plus': '输入框的「+」菜单',
};

const _scopeLabels = {'note': '笔记', 'course': '课程', 'library': '课程库', 'schedule': '日程'};

Future<T?> _push<T>(BuildContext context, Widget page) => Navigator.of(context, rootNavigator: true).push<T>(MaterialPageRoute(builder: (_) => page));

String _err(Object e) => e is ApiError ? e.message : '$e';

/// The 插件 section in 设置.
class PluginSettingsSection extends StatelessWidget {
  const PluginSettingsSection({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    final on = store.active.length;
    final attention = store.installed.where((p) => p['state'] == 'needs_consent' || p['state'] == 'error').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.extension_outlined),
        title: const Text('已安装的插件'),
        subtitle: Text(!store.ready
            ? '助手启动后可用'
            : store.installed.isEmpty
                ? '还没有安装插件'
                : '$on 个已启用${attention > 0 ? ' · $attention 个需要处理' : ''}'),
        trailing: attention > 0 ? Badge(label: Text('$attention')) : const Icon(Icons.chevron_right_rounded),
        enabled: store.ready,
        onTap: () => _push(context, const PluginsPage()),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.storefront_outlined),
        title: const Text('插件市场'),
        subtitle: const Text('引导式提问、思维导图、闪卡复习……让助手学会新本事'),
        trailing: const Icon(Icons.chevron_right_rounded),
        enabled: store.ready,
        onTap: () => _push(context, const PluginMarketPage()),
      ),
    ]);
  }
}

/// Installed plugins, the third-party switch and plugin catalogs.
class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});
  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  @override
  void initState() {
    super.initState();
    context.read<PluginStore>().load();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pad = context.isCompact ? Space.lg : Space.xl;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _push(context, const PluginMarketPage()),
        icon: const Icon(Icons.storefront_outlined),
        label: const Text('插件市场'),
      ),
      body: CustomScrollView(slivers: [
        const SliverAppBar.large(title: Text('插件')),
        if (!store.loaded)
          const SliverFillRemaining(child: CenteredLoader())
        else if (store.error != null && store.installed.isEmpty)
          SliverFillRemaining(child: ErrorState(error: store.error!, onRetry: store.load))
        else ...[
          if (store.installed.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.extension_outlined,
                title: '还没有插件',
                body: '插件让助手学会新本事：换一种方式讲题、把笔记画成导图、连接你常用的工具。',
                action: FilledButton.icon(onPressed: () => _push(context, const PluginMarketPage()), icon: const Icon(Icons.storefront_outlined), label: const Text('逛逛插件市场')),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverList.list(children: [
                for (final p in store.installed)
                  ContentWidth(max: 800, child: Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: _InstalledTile(plugin: p))),
              ]),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, Space.xl, pad, 120),
            sliver: SliverToBoxAdapter(
              child: ContentWidth(
                max: 800,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm), child: Text('来源', style: tt.titleSmall?.copyWith(color: cs.primary))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.sm),
                    decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(Corners.xl)),
                    child: const _SourceSettings(),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _InstalledTile extends StatelessWidget {
  const _InstalledTile({required this.plugin});
  final Map<String, dynamic> plugin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final store = context.read<PluginStore>();
    final state = '${plugin['state']}';
    final (badge, badgeColor) = switch (state) {
      'needs_consent' => ('需要授权', cs.tertiary),
      'error' => ('出错', cs.error),
      'disabled' => ('已停用', cs.outline),
      _ => ('', cs.primary),
    };
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Corners.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _push(context, PluginDetailPage(entry: plugin)),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(children: [
            PluginGlyph(icon: plugin['icon'], size: 48, muted: state == 'disabled'),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text('${plugin['title']}', style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (plugin['official'] == true) ...[const SizedBox(width: Space.xs), Icon(Icons.verified_rounded, size: 16, color: cs.primary)],
                  if (badge.isNotEmpty) ...[
                    const SizedBox(width: Space.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
                      decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Corners.full)),
                      child: Text(badge, style: tt.labelSmall?.copyWith(color: badgeColor)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(state == 'error' ? '${plugin['error']}' : '${plugin['summary']}',
                    style: tt.bodySmall?.copyWith(color: state == 'error' ? cs.error : cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: Space.md),
            Switch(
              value: plugin['enabled'] == true,
              onChanged: (v) async {
                try {
                  await store.update('${plugin['id']}', {'enabled': v});
                } catch (e) {
                  if (context.mounted) showSnack(context, _err(e));
                }
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _SourceSettings extends StatelessWidget {
  const _SourceSettings();

  Future<void> _toggle(BuildContext context, bool v) async {
    final store = context.read<PluginStore>();
    if (v) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.shield_outlined),
          title: const Text('允许第三方插件？'),
          content: const Text('第三方插件不是 Look Studio 发布的，与助手运行在同一进程中。只安装你信任的作者的插件；每次安装前都会列出它需要的权限。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('允许')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await store.setThirdParty(v);
    } catch (e) {
      if (context.mounted) showSnack(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.public_rounded),
        title: const Text('允许第三方插件'),
        subtitle: const Text('从插件目录、npm、Git 或本地文件夹安装'),
        value: store.allowThirdParty,
        onChanged: (v) => _toggle(context, v),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.library_add_outlined),
        title: const Text('插件目录'),
        subtitle: const Text('添加 look-catalog.json 链接或 GitHub 仓库'),
        enabled: store.allowThirdParty,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showDialog(context: context, builder: (_) => const _CatalogsDialog()),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.drive_folder_upload_outlined),
        title: const Text('从其他来源安装'),
        subtitle: const Text('本地文件夹、npm 包或 Git 仓库'),
        enabled: store.allowThirdParty,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showDialog(context: context, builder: (_) => const _SourceDialog()),
      ),
    ]);
  }
}

class _SourceDialog extends StatefulWidget {
  const _SourceDialog();
  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  final _text = TextEditingController();
  int _kind = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _source => switch (_kind) { 0 => 'path:${_text.text.trim()}', 1 => 'npm:${_text.text.trim()}', _ => 'git:${_text.text.trim()}' };

  @override
  Widget build(BuildContext context) {
    final hints = ['/home/me/my-plugin', '@scope/look-plugin@1.0.0', 'https://github.com/me/plugin#v1.0.0'];
    return AlertDialog(
      title: const Text('从其他来源安装'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('文件夹'), icon: Icon(Icons.folder_outlined)),
              ButtonSegment(value: 1, label: Text('npm')),
              ButtonSegment(value: 2, label: Text('Git')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _text,
            autofocus: true,
            decoration: InputDecoration(
              hintText: hints[_kind],
              helperText: _kind == 0 ? null : '需要写明固定版本',
              suffixIcon: _kind == 0
                  ? IconButton(
                      tooltip: '选择文件夹',
                      icon: const Icon(Icons.folder_open_outlined),
                      onPressed: () async {
                        final dir = await getDirectoryPath();
                        if (dir != null) _text.text = dir;
                      },
                    )
                  : null,
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ListenableBuilder(
          listenable: _text,
          builder: (context, _) => FilledButton(
            onPressed: _text.text.trim().isEmpty
                ? null
                : () {
                    final nav = Navigator.of(context);
                    final source = _source;
                    nav.pop();
                    installPlugin(nav.context, source);
                  },
            child: const Text('下一步'),
          ),
        ),
      ],
    );
  }
}

class _CatalogsDialog extends StatefulWidget {
  const _CatalogsDialog();
  @override
  State<_CatalogsDialog> createState() => _CatalogsDialogState();
}

class _CatalogsDialogState extends State<_CatalogsDialog> {
  final _url = TextEditingController();
  List<Map<String, dynamic>> _catalogs = [];
  List _errors = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await context.read<PluginStore>().catalog();
      if (!mounted) return;
      setState(() {
        _catalogs = [for (final x in jsonList(c['catalogs'])) (x as Map).cast<String, dynamic>()];
        _errors = jsonList(c['errors']);
      });
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<PluginStore>();
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('插件目录'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.verified_rounded), title: Text('Look Studio 官方'), subtitle: Text('随应用提供')),
          for (final c in _catalogs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public_rounded),
              title: Text('${c['url']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: _errors.any((e) => e is Map && e['url'] == c['url'])
                  ? Text('加载失败：${(_errors.firstWhere((e) => e is Map && e['url'] == c['url']) as Map)['error']}', style: TextStyle(color: cs.error))
                  : null,
              trailing: IconButton(
                tooltip: '移除',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _busy ? null : () => _run(() => store.removeCatalog('${c['url']}')),
              ),
            ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _url,
            decoration: InputDecoration(
              hintText: 'owner/repo 或 https://…/look-catalog.json',
              suffixIcon: IconButton(
                tooltip: '添加',
                icon: const Icon(Icons.add_rounded),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await store.addCatalog(_url.text.trim());
                          _url.clear();
                        }),
              ),
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('完成'))],
    );
  }
}

/// The plugin's icon on a tonal, softly scalloped shape.
class PluginGlyph extends StatelessWidget {
  const PluginGlyph({super.key, required this.icon, this.size = 48, this.muted = false, this.color, this.onColor});
  final Object? icon;
  final double size;
  final bool muted;
  final Color? color, onColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: muted ? cs.surfaceContainerHighest : (color ?? cs.primaryContainer),
        shape: size >= 64
            ? const StarBorder(points: 9, innerRadiusRatio: 0.86, pointRounding: 0.55, valleyRounding: 0.45)
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(size * 0.32)),
      ),
      child: Icon(pluginIcon(icon), size: size * 0.5, color: muted ? cs.outline : (onColor ?? cs.onPrimaryContainer)),
    );
  }
}

/// Browse plugins from the official and added catalogs.
class PluginMarketPage extends StatefulWidget {
  const PluginMarketPage({super.key});
  @override
  State<PluginMarketPage> createState() => _PluginMarketPageState();
}

class _PluginMarketPageState extends State<PluginMarketPage> {
  Map<String, dynamic>? _data;
  Object? _error;
  String _query = '';
  String _category = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<PluginStore>().catalog();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<Map<String, dynamic>> get _all => [for (final p in jsonList(_data?['plugins'])) (p as Map).cast<String, dynamic>()];

  bool _matches(Map<String, dynamic> p) {
    if (_category.isNotEmpty && !jsonList(p['categories']).contains(_category)) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return ['title', 'summary', 'description', 'id', 'author'].any((k) => '${p[k] ?? ''}'.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pad = context.isCompact ? Space.lg : Space.xl;
    final shown = _all.where(_matches).toList();
    final featured = _query.isEmpty && _category.isEmpty ? _all.where((p) => p['featured'] == true).toList() : const <Map<String, dynamic>>[];
    final cats = {for (final p in _all) ...jsonList(p['categories']).map((c) => '$c')}.where(pluginCategories.containsKey).toList();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          const SliverAppBar.large(title: Text('插件市场')),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverToBoxAdapter(
              child: ContentWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SearchBar(
                    hintText: '搜索插件',
                    leading: const Padding(padding: EdgeInsets.only(left: Space.sm), child: Icon(Icons.search_rounded)),
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: Space.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      FilterChip(label: const Text('全部'), selected: _category.isEmpty, onSelected: (_) => setState(() => _category = '')),
                      for (final c in cats) ...[
                        const SizedBox(width: Space.sm),
                        FilterChip(label: Text(pluginCategories[c]!), selected: _category == c, onSelected: (on) => setState(() => _category = on ? c : '')),
                      ],
                    ]),
                  ),
                  if (jsonList(_data?['errors']).isNotEmpty) ...[
                    const SizedBox(height: Space.md),
                    Container(
                      padding: const EdgeInsets.all(Space.md),
                      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(Corners.md)),
                      child: Text('有 ${jsonList(_data?['errors']).length} 个插件目录没能加载，可在 插件 → 插件目录 查看', style: tt.bodySmall?.copyWith(color: cs.onErrorContainer)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
          if (_data == null && _error == null)
            const SliverFillRemaining(child: CenteredLoader())
          else if (_error != null)
            SliverFillRemaining(child: ErrorState(error: _error!, onRetry: _load))
          else ...[
            if (featured.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, Space.xl, pad, 0),
                sliver: SliverToBoxAdapter(child: ContentWidth(child: _Featured(plugins: featured, onChanged: _load))),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, Space.xl, pad, Space.sm),
              sliver: SliverToBoxAdapter(
                child: ContentWidth(child: Text(_query.isEmpty && _category.isEmpty ? '全部插件' : '${shown.length} 个结果', style: tt.titleMedium)),
              ),
            ),
            if (shown.isEmpty)
              const SliverToBoxAdapter(child: EmptyState(icon: Icons.search_off_rounded, title: '没有找到插件', body: '换个关键词，或在 插件 → 插件目录 添加更多来源'))
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, Space.huge),
                sliver: SliverToBoxAdapter(
                  child: ContentWidth(
                    child: LayoutBuilder(builder: (context, c) {
                      final cols = (c.maxWidth / 340).floor().clamp(1, 3);
                      final w = (c.maxWidth - (cols - 1) * Space.md) / cols;
                      return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
                        for (final p in shown) SizedBox(width: w, child: _MarketCard(plugin: p, store: store, onChanged: _load)),
                      ]);
                    }),
                  ),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

class _Featured extends StatelessWidget {
  const _Featured({required this.plugins, required this.onChanged});
  final List<Map<String, dynamic>> plugins;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (plugins.length == 1) return SizedBox(height: 220, child: _HeroCard(plugin: plugins.first, onChanged: onChanged));
    return SizedBox(
      height: 220,
      child: CarouselView.weighted(
        flexWeights: const [3, 1],
        itemSnapping: true,
        backgroundColor: cs.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.xl)),
        onTap: (i) => _push(context, PluginDetailPage(entry: plugins[i])).then((_) => onChanged()),
        children: [for (final p in plugins) _HeroCard(plugin: p, onChanged: onChanged, inCarousel: true)],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.plugin, required this.onChanged, this.inCarousel = false});
  final Map<String, dynamic> plugin;
  final VoidCallback onChanged;
  final bool inCarousel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final examples = jsonList(plugin['examples']);
    final body = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corners.xl),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primaryContainer, cs.tertiaryContainer]),
      ),
      padding: const EdgeInsets.all(Space.xl),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 420;
        return Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('精选', style: tt.labelLarge?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
              const SizedBox(height: Space.xs),
              Text('${plugin['title']}', style: tt.headlineSmall?.copyWith(color: cs.onPrimaryContainer), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: Space.sm),
              Text('${plugin['summary']}', style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (examples.isNotEmpty && c.maxHeight > 150) ...[
                const SizedBox(height: Space.md),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
                  decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(Corners.full)),
                  child: Text('“${examples.first}”', style: tt.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ]),
          ),
          if (wide) ...[const SizedBox(width: Space.xl), PluginGlyph(icon: plugin['icon'], size: 112, color: cs.surface.withValues(alpha: 0.7), onColor: cs.primary)],
        ]);
      }),
    );
    if (inCarousel) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Corners.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: () => _push(context, PluginDetailPage(entry: plugin)).then((_) => onChanged()), child: body),
    );
  }
}

class _MarketCard extends StatelessWidget {
  const _MarketCard({required this.plugin, required this.store, required this.onChanged});
  final Map<String, dynamic> plugin;
  final PluginStore store;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final installed = store.byId('${plugin['id']}') != null;
    final update = plugin['update'] == true;
    final cats = jsonList(plugin['categories']).map((c) => pluginCategories['$c']).whereType<String>().take(2);
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Corners.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _push(context, PluginDetailPage(entry: plugin)).then((_) => onChanged()),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: SizedBox(
            height: 132,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                PluginGlyph(icon: plugin['icon'], size: 44),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${plugin['title']}', style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(children: [
                      if (plugin['official'] == true) ...[Icon(Icons.verified_rounded, size: 14, color: cs.primary), const SizedBox(width: 2)],
                      Flexible(
                        child: Text(plugin['official'] == true ? '官方' : '${plugin['author'] ?? plugin['catalog'] ?? ''}',
                            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ]),
                ),
              ]),
              const SizedBox(height: Space.md),
              Expanded(child: Text('${plugin['summary']}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Row(children: [
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
                      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(Corners.full)),
                      child: Text(c, style: tt.labelSmall?.copyWith(color: cs.onSecondaryContainer)),
                    ),
                  ),
                const Spacer(),
                if (installed && !update)
                  Row(children: [Icon(Icons.check_circle_rounded, size: 16, color: cs.primary), const SizedBox(width: 4), Text('已安装', style: tt.labelMedium?.copyWith(color: cs.primary))])
                else
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => installPlugin(context, '${plugin['source']}').then((_) => onChanged()),
                    child: Text(update ? '更新' : '安装'),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Fetches [source], asks for consent with the exact permissions, installs.
Future<bool> installPlugin(BuildContext context, String source) async {
  final store = context.read<PluginStore>();
  final nav = Navigator.of(context, rootNavigator: true);
  Map<String, dynamic> preview;
  showDialog(context: context, barrierDismissible: false, useRootNavigator: true, builder: (_) => const _Busy(label: '正在获取插件…'));
  try {
    preview = await store.preview(source);
  } catch (e) {
    nav.pop();
    if (context.mounted) showSnack(context, '没能获取插件：${_err(e)}');
    return false;
  }
  nav.pop();
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(context: context, useRootNavigator: true, builder: (_) => ConsentDialog(preview: preview));
  if (ok != true || !context.mounted) return false;
  showDialog(context: context, barrierDismissible: false, useRootNavigator: true, builder: (_) => const _Busy(label: '正在安装…'));
  try {
    final p = await store.confirm('${preview['token']}');
    nav.pop();
    if (context.mounted) {
      showSnack(context, p['state'] == 'error' ? '已安装，但加载失败：${p['error']}' : '已安装「${p['title']}」');
    }
    return true;
  } catch (e) {
    nav.pop();
    if (context.mounted) showSnack(context, '安装失败：${_err(e)}');
    return false;
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: Space.xl), Expanded(child: Text(label))])),
      );
}

/// Lists exactly what an install or update grants before anything happens.
class ConsentDialog extends StatelessWidget {
  const ConsentDialog({super.key, required this.preview});
  final Map<String, dynamic> preview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final m = (preview['manifest'] as Map).cast<String, dynamic>();
    final update = preview['update'] as Map?;
    final added = {for (final p in jsonList(update?['added_permissions'])) '$p'};
    final perms = [for (final p in jsonList(m['permissions'])) (p as Map).cast<String, dynamic>()];
    final official = preview['official'] == true;
    return AlertDialog(
      icon: PluginGlyph(icon: m['icon'], size: 56),
      title: Text(update == null ? '安装「${m['title']}」？' : '更新「${m['title']}」？'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              [if (official) 'Look Studio 官方' else if ('${m['author'] ?? ''}'.isNotEmpty) '${m['author']}', 'v${m['version']}', if (update != null) '当前 v${update['from']}'].join(' · '),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (!official) ...[
              const SizedBox(height: Space.lg),
              Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(Corners.md)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.shield_outlined, size: 18, color: cs.onTertiaryContainer),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text('第三方插件，来源：${preview['source']}。它与助手运行在同一进程中，请确认你信任作者。',
                        style: tt.bodySmall?.copyWith(color: cs.onTertiaryContainer)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: Space.lg),
            Text(perms.isEmpty ? '不需要额外权限' : '它将可以', style: tt.titleSmall),
            for (final p in perms)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(permissionIcons[p['id']] ?? Icons.key_outlined,
                    color: sensitivePermissions.contains(p['id']) ? cs.tertiary : cs.onSurfaceVariant),
                title: Text('${p['label']}', style: sensitivePermissions.contains(p['id']) ? tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600) : null),
                subtitle: p['detail'] == null ? null : Text('${p['detail']}'),
                trailing: added.contains(p['id']) ? Text('新增', style: tt.labelSmall?.copyWith(color: cs.tertiary)) : null,
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(update == null ? '安装' : '更新')),
      ],
    );
  }
}

/// One plugin: what it does, what it may do, where it appears, settings.
class PluginDetailPage extends StatefulWidget {
  const PluginDetailPage({super.key, required this.entry});

  /// A catalog entry or an installed plugin.
  final Map<String, dynamic> entry;
  @override
  State<PluginDetailPage> createState() => _PluginDetailPageState();
}

class _PluginDetailPageState extends State<PluginDetailPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showSnack(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final id = '${widget.entry['id']}';
    final installed = store.byId(id);
    final p = installed ?? widget.entry;
    final state = '${installed?['state'] ?? ''}';
    final perms = [for (final x in jsonList(p['permissions'])) if (x is Map) x.cast<String, dynamic>()];
    final contributes = (p['contributes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final places = [
      for (final a in jsonList(contributes['actions'])) if (a is Map) ('${a['title']}', _surfaceLabels['${a['surface']}'] ?? '${a['surface']}', a['icon']),
      for (final a in jsonList(contributes['noteViews'])) if (a is Map) ('${a['title']}', '笔记的「换种方式看」', a['icon']),
      for (final a in jsonList(contributes['exporters'])) if (a is Map) ('${a['title']}', '${_scopeLabels['${a['scope']}'] ?? ''}导出菜单', a['icon']),
      for (final a in jsonList(contributes['pages'])) if (a is Map) ('${a['title']}', '插件页面', a['icon']),
    ];
    final examples = jsonList(p['examples']);
    final schema = (p['settings'] as Map?)?.cast<String, dynamic>();
    final hasSettings = installed != null && ((schema?['properties'] as Map?)?.isNotEmpty ?? false);
    final pad = context.isCompact ? Space.lg : Space.xl;

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm), child: Text(title, style: tt.titleSmall?.copyWith(color: cs.primary))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(Corners.xl)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ]),
        );

    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: EdgeInsets.fromLTRB(pad, 0, pad, Space.huge), children: [
        ContentWidth(
          max: 760,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              PluginGlyph(icon: p['icon'], size: 88, muted: state == 'disabled'),
              const SizedBox(width: Space.xl),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['title']}', style: tt.headlineMedium),
                  const SizedBox(height: Space.xs),
                  Row(children: [
                    if (p['official'] == true) ...[Icon(Icons.verified_rounded, size: 16, color: cs.primary), const SizedBox(width: 4)],
                    Flexible(
                      child: Text(
                        [p['official'] == true ? 'Look Studio 官方' : '${p['author'] ?? ''}', if ('${p['version'] ?? ''}'.isNotEmpty) 'v${p['version']}']
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: Space.xl),
            Text('${p['summary']}', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w400)),
            const SizedBox(height: Space.lg),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (installed == null)
                FilledButton.icon(
                  onPressed: _busy || widget.entry['source'] == null ? null : () => _run(() => installPlugin(context, '${widget.entry['source']}')),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('安装'),
                )
              else ...[
                if (state == 'needs_consent')
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _consentUpdate(context, installed),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('查看并授权'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _run(() => store.update(id, {'enabled': installed['enabled'] != true})),
                    icon: Icon(installed['enabled'] == true ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded),
                    label: Text(installed['enabled'] == true ? '停用' : '启用'),
                  ),
                if (widget.entry['update'] == true)
                  FilledButton.icon(onPressed: _busy ? null : () => _run(() => installPlugin(context, '${widget.entry['source']}')), icon: const Icon(Icons.upgrade_rounded), label: const Text('更新')),
                OutlinedButton.icon(onPressed: _busy ? null : () => _uninstall(context, installed), icon: const Icon(Icons.delete_outline_rounded), label: const Text('卸载')),
              ],
            ]),
            if (state == 'enabled' && jsonList(contributes['pages']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                  for (final pg in jsonList(contributes['pages']))
                    if (pg is Map)
                      ActionChip(
                        avatar: Icon(pluginIcon(pg['icon']), size: 18),
                        label: Text('打开「${pg['title']}」'),
                        onPressed: () => runPluginEntry(context, PluginEntry(installed!, 'pages', pg), const {}),
                      ),
                ]),
              ),
            if (state == 'error')
              Padding(
                padding: const EdgeInsets.only(top: Space.lg),
                child: Container(
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(Corners.md)),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
                    const SizedBox(width: Space.sm),
                    Expanded(child: SelectableText('${installed?['error']}', style: tt.bodySmall?.copyWith(color: cs.onErrorContainer))),
                  ]),
                ),
              ),
            if ('${p['description'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              Text('${p['description']}', style: tt.bodyLarge?.copyWith(height: 1.6, color: cs.onSurfaceVariant)),
            ],
            if (examples.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              Text('试试这样问', style: tt.titleSmall),
              const SizedBox(height: Space.sm),
              Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                for (final e in examples)
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text('$e'),
                    onPressed: state == 'enabled' ? () => askInSheet(context, '$e') : null,
                  ),
              ]),
            ],
            section('权限', [
              if (perms.isEmpty)
                const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.lock_outline_rounded), title: Text('不需要额外权限'), subtitle: Text('只在对话中提供指导与工具'))
              else
                for (final x in perms)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(permissionIcons[x['id']] ?? Icons.key_outlined, color: sensitivePermissions.contains(x['id']) ? cs.tertiary : null),
                    title: Text('${x['label']}'),
                    subtitle: x['detail'] == null ? null : Text('${x['detail']}'),
                  ),
            ]),
            if (places.isNotEmpty)
              section('会出现在', [
                for (final (title, where, icon) in places)
                  ListTile(contentPadding: EdgeInsets.zero, leading: Icon(pluginIcon(icon)), title: Text(title), subtitle: Text(where)),
              ]),
            if (hasSettings)
              section('设置', [
                PluginSettingsForm(
                  key: ValueKey('$id-${installed['version']}'),
                  schema: schema!,
                  values: (installed['settings_values'] as Map?)?.cast<String, dynamic>() ?? const {},
                  onSave: (v) => _run(() async {
                    await store.update(id, {'settings': v});
                    if (context.mounted) showSnack(context, '设置已保存');
                  }),
                ),
              ]),
            if (installed != null && (jsonList(installed['tools']).isNotEmpty || jsonList(installed['skills']).isNotEmpty))
              section('助手获得的能力', [
                for (final t in jsonList(installed['tools']))
                  ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.build_outlined), title: Text('${(t as Map)['label']}'), subtitle: Text('${t['name']}')),
                for (final k in jsonList(installed['skills']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text('${(k as Map)['name']}'),
                    subtitle: '${k['description'] ?? ''}'.isEmpty ? null : Text('${k['description']}'),
                  ),
              ]),
            const SizedBox(height: Space.xl),
            Wrap(spacing: Space.lg, runSpacing: Space.xs, children: [
              if ('${p['license'] ?? ''}'.isNotEmpty) Text('许可：${p['license']}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              if ('${p['source'] ?? ''}'.isNotEmpty) Text('来源：${p['source']}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              if ('${p['homepage'] ?? ''}'.startsWith('https://'))
                InkWell(
                  onTap: () => launchUrl(Uri.parse('${p['homepage']}')),
                  child: Text('主页', style: tt.bodySmall?.copyWith(color: cs.primary, decoration: TextDecoration.underline, decorationColor: cs.primary)),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Future<void> _consentUpdate(BuildContext context, Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConsentDialog(preview: {
        'official': p['official'],
        'source': p['source'],
        'manifest': p,
        'update': {'from': p['version'], 'added_permissions': [for (final x in jsonList(p['needs_permissions'])) (x as Map)['id']]},
      }),
    );
    if (ok == true && context.mounted) await _run(() => context.read<PluginStore>().update('${p['id']}', {'grant': true}));
  }

  Future<void> _uninstall(BuildContext context, Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('卸载「${p['title']}」？'),
        content: const Text('插件保存的数据会一起删除。已经生成的笔记、练习等内容不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('卸载')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final nav = Navigator.of(context);
    await _run(() async {
      await context.read<PluginStore>().uninstall('${p['id']}');
      if (widget.entry['source'] == null) nav.pop();
    });
  }
}

/// A form for a manifest's settings schema (the JSON Schema subset).
class PluginSettingsForm extends StatefulWidget {
  const PluginSettingsForm({super.key, required this.schema, required this.values, required this.onSave});
  final Map<String, dynamic> schema;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onSave;
  @override
  State<PluginSettingsForm> createState() => _PluginSettingsFormState();
}

class _PluginSettingsFormState extends State<PluginSettingsForm> {
  late final Map<String, dynamic> _v = {...widget.values};
  final Map<String, TextEditingController> _text = {};
  final Map<String, String?> _errors = {};

  Map<String, Map<String, dynamic>> get _props => {
        for (final e in ((widget.schema['properties'] as Map?) ?? const {}).entries) '${e.key}': (e.value as Map).cast<String, dynamic>(),
      };

  @override
  void initState() {
    super.initState();
    for (final MapEntry(:key, :value) in _props.entries) {
      if (value['type'] == 'boolean' || value['enum'] != null) continue;
      final cur = _v[key] ?? value['default'];
      _text[key] = TextEditingController(text: cur == null ? '' : (cur is List ? cur.join(', ') : '$cur'));
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Object? _parse(Map<String, dynamic> p, String s) {
    s = s.trim();
    switch (p['type']) {
      case 'integer':
        return int.tryParse(s);
      case 'number':
        return num.tryParse(s);
      case 'array':
        final items = s.split(RegExp(r'[,，\s]+')).where((x) => x.isNotEmpty);
        final t = (p['items'] as Map?)?['type'];
        return [for (final x in items) t == 'string' ? x : (t == 'integer' ? int.tryParse(x) : num.tryParse(x))];
      default:
        return s;
    }
  }

  void _save() {
    final out = <String, dynamic>{..._v};
    _errors.clear();
    for (final MapEntry(:key, :value) in _text.entries) {
      final p = _props[key]!;
      final v = _parse(p, value.text);
      if (v == null || (v is List && v.contains(null))) {
        _errors[key] = '请输入${p['type'] == 'string' ? '文字' : '数字'}';
      } else if (v is num && ((p['minimum'] is num && v < p['minimum']) || (p['maximum'] is num && v > p['maximum']))) {
        _errors[key] = '应在 ${p['minimum'] ?? ''}–${p['maximum'] ?? ''} 之间';
      } else {
        out[key] = v;
      }
    }
    setState(() {});
    if (_errors.isEmpty) widget.onSave(out);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final MapEntry(:key, value: p) in _props.entries)
        if (p['type'] == 'boolean')
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${p['title'] ?? key}'),
            subtitle: p['description'] == null ? null : Text('${p['description']}'),
            value: (_v[key] ?? p['default']) == true,
            onChanged: (v) => setState(() => _v[key] = v),
          )
        else if (p['enum'] is List)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${p['title'] ?? key}'),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (p['description'] != null) Text('${p['description']}'),
              const SizedBox(height: Space.sm),
              Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                for (final o in p['enum'] as List)
                  ChoiceChip(label: Text('$o'), selected: (_v[key] ?? p['default']) == o, onSelected: (_) => setState(() => _v[key] = o)),
              ]),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: TextField(
              controller: _text[key],
              keyboardType: p['type'] == 'string' ? TextInputType.text : TextInputType.number,
              inputFormatters: p['type'] == 'integer' ? [FilteringTextInputFormatter.digitsOnly] : null,
              decoration: InputDecoration(
                labelText: '${p['title'] ?? key}',
                helperText: p['description'] == null ? null : '${p['description']}',
                errorText: _errors[key],
                suffixIcon: p['format'] == 'path'
                    ? IconButton(
                        tooltip: '选择文件夹',
                        icon: const Icon(Icons.folder_open_outlined),
                        onPressed: () async {
                          final dir = await getDirectoryPath();
                          if (dir != null) _text[key]!.text = dir;
                        },
                      )
                    : null,
              ),
            ),
          ),
      const SizedBox(height: Space.sm),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(onPressed: _save, child: Text('保存设置', style: tt.labelLarge)),
      ),
    ]);
  }
}
