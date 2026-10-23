import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/plugins.dart';
import '../../shell.dart';
import '../../theme/tokens.dart';
import '../../widgets/horizontal_scroller.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import '../practice/quiz.dart' show askInSheet;
import 'plugin_views.dart';
import '../../l10n/l10n.dart';

// The 插件 tab: discover, install and manage plugins
// (docs/specs/0004-plugin-platform.md).

final _surfaceLabels = {
  'note.toolbar': l10n.pluginSlotNoteToolbar,
  'lecture.menu': l10n.pluginSlotLectureMenu,
  'course.menu': l10n.pluginSlotCourseMenu,
  'schedule.item': l10n.pluginSlotScheduleItem,
  'assignment.actions': l10n.pluginSlotAssignment,
  'composer.plus': l10n.pluginSlotComposer,
};

final _scopeLabels = {'note': l10n.commonNotes, 'course': l10n.commonCourses, 'library': l10n.commonLibrary, 'schedule': l10n.commonSchedule};

String _err(Object e) => e is ApiError ? e.message : '$e';

/// The view of the 插件 tab: 0 发现, 1 已安装. Links elsewhere set it before
/// switching to the tab.
final pluginsView = ValueNotifier<int>(0);

/// Shows the 插件 tab, closing the assistant first when it covers the window.
void openPlugins(BuildContext context, {bool installed = false}) {
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  pluginsView.value = installed ? 1 : 0;
  ShellNav.goTo(Tabs.plugins);
}

bool _needsAttention(Map p) => p['state'] == 'needs_consent' || p['state'] == 'error';

/// Turns third-party plugins on (after a warning) or off.
Future<void> _setThirdParty(BuildContext context, bool v) async {
  final store = context.read<PluginStore>();
  if (v) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: Text(l10n.pluginsAllowThirdPartyTitle),
        content: Text(l10n.pluginsAllowThirdPartyBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonAllow)),
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

/// The 插件 section in 设置: shortcuts into the 插件 tab.
class PluginSettingsSection extends StatelessWidget {
  const PluginSettingsSection({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    final on = store.active.length;
    final attention = store.attention;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.extension_outlined),
        title: Text(l10n.pluginsInstalled),
        subtitle: Text(!store.ready
            ? l10n.pluginsAfterAssistant
            : store.installed.isEmpty
                ? l10n.pluginsNoneInstalled
                : l10n.pluginsEnabledSummary(on, attention > 0 ? l10n.pluginsAttentionSuffix(attention) : '')),
        trailing: attention > 0 ? Badge(label: Text('$attention')) : const Icon(Icons.chevron_right_rounded),
        enabled: store.ready,
        onTap: () => openPlugins(context, installed: true),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.explore_outlined),
        title: Text(l10n.pluginsDiscover),
        subtitle: Text(l10n.pluginsTagline),
        trailing: const Icon(Icons.chevron_right_rounded),
        enabled: store.ready,
        onTap: () => openPlugins(context),
      ),
    ]);
  }
}

/// Keeps every child of an [AnimatedSwitcher] filling the area.
Widget _fill(Widget? current, List<Widget> previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]);

/// The 插件 tab. 发现 browses the catalogs and opens a plugin in a side pane;
/// 已安装 lists installed plugins beside the selected one's detail. Narrow
/// windows push the detail instead.
class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});
  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  Map<String, dynamic>? _catalog;
  Object? _catalogError;
  bool _fetching = false;
  String _query = '';
  String _category = '';
  String? _picked; // 发现: the plugin in the side pane
  Map<String, dynamic>? _shown; // 发现: the pane's content, kept while it closes
  String? _selected; // 已安装: the plugin beside the list

  @override
  void initState() {
    super.initState();
    pluginsView.addListener(_onView);
    final store = context.read<PluginStore>();
    if (store.ready) {
      store.load();
      _loadCatalog();
    }
  }

  @override
  void dispose() {
    pluginsView.removeListener(_onView);
    super.dispose();
  }

  void _onView() => setState(() {});

  Future<void> _loadCatalog() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final c = await context.read<PluginStore>().catalog();
      if (!mounted) return;
      setState(() {
        _catalog = c;
        _catalogError = null;
        if (_shown != null) _shown = _listing('${_shown!['id']}') ?? _shown;
      });
    } catch (e) {
      if (mounted) setState(() => _catalogError = e);
    } finally {
      _fetching = false;
    }
  }

  Future<void> _refresh() => Future.wait([context.read<PluginStore>().load(), _loadCatalog()]);

  List<Map<String, dynamic>> get _listings => [for (final p in jsonList(_catalog?['plugins'])) (p as Map).cast<String, dynamic>()];

  Map<String, dynamic>? _listing(String id) => _listings.where((p) => p['id'] == id).firstOrNull;

  bool _matches(Map<String, dynamic> p) {
    if (_category.isNotEmpty && !jsonList(p['categories']).contains(_category)) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return ['title', 'summary', 'description', 'id', 'author'].any((k) => '${p[k] ?? ''}'.toLowerCase().contains(q));
  }

  void _openDetail(Map<String, dynamic> entry) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PluginDetailPage(entry: entry, onChanged: _loadCatalog))).then((_) => _loadCatalog());

  Future<void> _install(Map<String, dynamic> p) async {
    if (await installPlugin(context, '${p['source']}')) _loadCatalog();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    if (store.ready && _catalog == null && _catalogError == null && !_fetching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _catalog == null) _loadCatalog();
      });
    }
    return Scaffold(
      body: LayoutBuilder(builder: (context, box) {
        final compact = box.maxWidth < 600;
        final wide = box.maxWidth >= 880;
        final pad = compact ? Space.lg : Space.xl;
        final view = pluginsView.value;
        final Widget body;
        if (!store.ready) {
          body = EmptyState(icon: Icons.extension_outlined, title: l10n.pluginsAfterAssistant, body: l10n.pluginsNeedAssistant);
        } else if (view == 0) {
          body = _discover(store, pad, box.maxWidth, wide);
        } else {
          body = _installed(store, pad, box.maxWidth, wide);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(store, pad, compact),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.medium2,
              switchInCurve: Motion.emphasizedDecelerate,
              switchOutCurve: Motion.emphasizedAccelerate,
              layoutBuilder: _fill,
              child: KeyedSubtree(key: ValueKey(view), child: body),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _header(PluginStore store, double pad, bool compact) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final n = store.installed.length;
    final on = store.active.length;
    final attention = store.attention;
    final updates = _listings.where((p) => p['update'] == true).length;
    final sub = n == 0
        ? l10n.pluginsSubtitle
        : [
            l10n.pluginsInstalledCount(n),
            on == n ? l10n.commonAllEnabled : l10n.pluginsEnabledCount(on),
            if (attention > 0) l10n.pluginsAttentionCount(attention),
            if (updates > 0) l10n.pluginsUpdatesCount(updates),
          ].join(' · ');
    return ContentWidth(
      max: kMaxContentWidth + 200,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, compact ? Space.xl : Space.xxl, pad, Space.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.commonPlugins, style: compact ? tt.headlineMedium : tt.displaySmall),
          const SizedBox(height: Space.xs),
          Text(sub, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: Space.lg),
          Row(children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, icon: Icon(Icons.explore_outlined), label: Text(l10n.pluginsDiscoverTab)),
                ButtonSegment(
                  value: 1,
                  icon: Badge(isLabelVisible: attention > 0, child: const Icon(Icons.extension_outlined)),
                  label: Text(n == 0 ? l10n.commonInstalled : l10n.pluginsInstalledTab(n)),
                ),
              ],
              selected: {pluginsView.value},
              onSelectionChanged: (v) => pluginsView.value = v.first,
            ),
            const Spacer(),
            _SourcesMenu(compact: compact, onChanged: _refresh),
          ]),
        ]),
      ),
    );
  }

  /// The detail of [entry] in a tonal pane, cross-fading between plugins.
  Widget _pane(Map<String, dynamic> entry, {VoidCallback? onClose}) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: Corners.all(Corners.xl),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: Motion.medium2,
        switchInCurve: Motion.emphasizedDecelerate,
        switchOutCurve: Motion.emphasizedAccelerate,
        layoutBuilder: _fill,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0.02, 0), end: Offset.zero).animate(a), child: child),
        ),
        child: PluginDetailView(key: ValueKey(entry['id']), entry: entry, embedded: true, onClose: onClose, onChanged: _loadCatalog),
      ),
    );
  }

  Widget _discover(PluginStore store, double pad, double width, bool wide) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (_catalog == null) return _catalogError == null ? const CenteredLoader() : ErrorState(error: _catalogError!, onRetry: _loadCatalog);
    final all = _listings;
    final filtering = _query.trim().isNotEmpty || _category.isNotEmpty;
    final shown = all.where(_matches).toList();
    final featured = filtering ? const <Map<String, dynamic>>[] : all.where((p) => p['featured'] == true).toList();
    final cats = {for (final p in all) ...jsonList(p['categories']).map((c) => '$c')}.where(pluginCategories.containsKey).toList();
    final errors = jsonList(_catalog!['errors']);
    // Official plugins first, then one section per added catalog.
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final p in shown) {
      groups.putIfAbsent(p['official'] == true ? '' : '${p['catalog'] ?? l10n.pluginsOtherSource}', () => []).add(p);
    }
    void open(Map<String, dynamic> p) {
      if (!wide) return _openDetail(p);
      setState(() {
        _picked = '${p['id']}';
        _shown = p;
      });
    }

    Widget grid(List<Map<String, dynamic>> plugins) => LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 300).floor().clamp(1, 4);
          final w = (c.maxWidth - (cols - 1) * Space.md) / cols;
          return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
            for (final p in plugins)
              SizedBox(
                width: w,
                child: _MarketCard(
                  plugin: p,
                  installed: store.byId('${p['id']}') != null,
                  selected: wide && _picked == p['id'],
                  onTap: () => open(p),
                  onInstall: () => _install(p),
                ),
              ),
          ]);
        });

    final list = RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: EdgeInsets.fromLTRB(pad, 0, pad, Space.huge), children: [
        SearchBar(
          hintText: l10n.pluginsSearch,
          constraints: const BoxConstraints(minHeight: 52, maxWidth: 640),
          leading: const Padding(padding: EdgeInsets.only(left: Space.sm), child: Icon(Icons.search_rounded)),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: Space.md),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          FilterChip(label: Text(l10n.commonAll), selected: _category.isEmpty, onSelected: (_) => setState(() => _category = '')),
          for (final c in cats) FilterChip(label: Text(pluginCategories[c]!), selected: _category == c, onSelected: (on) => setState(() => _category = on ? c : '')),
        ]),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          _Banner(
            icon: Icons.cloud_off_rounded,
            text: l10n.pluginsCatalogErrors(errors.length),
            action: TextButton(onPressed: () => showDialog(context: context, builder: (_) => const _CatalogsDialog()).then((_) => _loadCatalog()), child: Text(l10n.commonView)),
            error: true,
          ),
        ],
        if (featured.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          _Featured(plugins: featured, onOpen: open),
        ],
        if (shown.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: Space.xxl),
            child: EmptyState(icon: Icons.search_off_rounded, title: l10n.pluginsNoMatch, body: l10n.pluginsNoMatchBody),
          ),
        for (final MapEntry(key: name, value: plugins) in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, 0, Space.md),
            child: Row(children: [
              Icon(name.isEmpty ? Icons.verified_rounded : Icons.public_rounded, size: 20, color: name.isEmpty ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Flexible(child: Text(name.isEmpty ? l10n.pluginsOfficial : name, style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: Space.sm),
              Text('${plugins.length}', style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          grid(plugins),
        ],
        if (!store.allowThirdParty && !filtering) ...[
          const SizedBox(height: Space.xxl),
          _Banner(
            icon: Icons.add_link_rounded,
            text: l10n.pluginsMoreHint,
            action: TextButton(onPressed: () => _setThirdParty(context, true).then((_) => _loadCatalog()), child: Text(l10n.commonAllow)),
          ),
        ],
      ]),
    );
    if (!wide) return ContentWidth(max: kMaxContentWidth + 200, child: list);
    final paneW = width >= 1280 ? 440.0 : 380.0;
    return ContentWidth(
      max: kMaxContentWidth + 200,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: list),
        AnimatedContainer(
          duration: Motion.medium4,
          curve: Motion.emphasized,
          width: _picked == null ? 0 : paneW + pad,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: paneW + pad,
              maxWidth: paneW + pad,
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 0, pad, pad),
                child: _shown == null ? null : _pane(_shown!, onClose: () => setState(() => _picked = null)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _installed(PluginStore store, double pad, double width, bool wide) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (!store.loaded) return const CenteredLoader();
    if (store.error != null && store.installed.isEmpty) return ErrorState(error: store.error!, onRetry: store.load);
    if (store.installed.isEmpty) {
      return EmptyState(
        icon: Icons.extension_outlined,
        title: l10n.pluginsNoneInstalled,
        body: l10n.pluginsEmptyBody,
        action: FilledButton.icon(onPressed: () => pluginsView.value = 0, icon: const Icon(Icons.explore_outlined), label: Text(l10n.pluginsGoDiscover)),
      );
    }
    final groups = [
      (l10n.commonNeedsAttention, store.installed.where(_needsAttention).toList()),
      (l10n.commonEnabled, store.installed.where((p) => p['state'] == 'enabled').toList()),
      (l10n.commonDisabled, store.installed.where((p) => p['state'] == 'disabled').toList()),
    ];
    final flat = [for (final (_, items) in groups) ...items];
    final sel = flat.firstWhere((p) => p['id'] == _selected, orElse: () => flat.first);
    Future<void> toggle(Map<String, dynamic> p, bool v) async {
      try {
        await store.update('${p['id']}', {'enabled': v});
      } catch (e) {
        if (mounted) showSnack(context, _err(e));
      }
    }

    List<Widget> rows({required bool cards}) => [
          for (final (title, items) in groups)
            if (items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.md, 0, Space.sm),
                child: Text('$title · ${items.length}', style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
              ),
              for (final p in items)
                Padding(
                  padding: EdgeInsets.only(bottom: cards ? Space.sm : Space.xs),
                  child: _InstalledRow(
                    plugin: p,
                    card: cards,
                    update: _listing('${p['id']}')?['update'] == true,
                    selected: !cards && p == sel,
                    onTap: cards ? () => _openDetail(_listing('${p['id']}') ?? p) : () => setState(() => _selected = '${p['id']}'),
                    onToggle: cards && p['state'] != 'needs_consent' ? (v) => toggle(p, v) : null,
                  ),
                ),
            ],
        ];

    if (!wide) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: EdgeInsets.fromLTRB(pad, 0, pad, 120), children: [
          ContentWidth(max: 760, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows(cards: true))),
        ]),
      );
    }
    return ContentWidth(
      max: kMaxContentWidth + 200,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad - Space.sm, 0, pad, pad),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: width >= 1200 ? 380 : 320,
            child: ListView(padding: const EdgeInsets.only(bottom: Space.xl), children: rows(cards: false)),
          ),
          const SizedBox(width: Space.md),
          Expanded(child: _pane(_listing('${sel['id']}') ?? sel)),
        ]),
      ),
    );
  }
}

/// Where plugins come from: the third-party switch, catalogs and other
/// sources, as a menu beside the view switcher.
class _SourcesMenu extends StatelessWidget {
  const _SourcesMenu({required this.compact, required this.onChanged});
  final bool compact;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PluginStore>();
    final third = store.allowThirdParty;
    return MenuAnchor(
      alignmentOffset: const Offset(0, Space.xs),
      menuChildren: [
        CheckboxMenuButton(
          value: third,
          onChanged: store.ready ? (v) => _setThirdParty(context, v ?? false).then((_) => onChanged()) : null,
          child: Text(l10n.pluginsAllowThirdParty),
        ),
        const Divider(height: Space.sm),
        MenuItemButton(
          leadingIcon: const Icon(Icons.library_add_outlined, size: 20),
          onPressed: third ? () => showDialog(context: context, builder: (_) => const _CatalogsDialog()).then((_) => onChanged()) : null,
          child: Text(l10n.pluginsCatalogs),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.drive_folder_upload_outlined, size: 20),
          onPressed: third ? () => showDialog(context: context, builder: (_) => const _SourceDialog()) : null,
          child: Text(l10n.pluginsInstallFrom),
        ),
        const Divider(height: Space.sm),
        MenuItemButton(
          leadingIcon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: store.ready ? onChanged : null,
          child: Text(l10n.commonRefresh),
        ),
      ],
      builder: (context, c, _) {
        void toggle() => c.isOpen ? c.close() : c.open();
        return compact
            ? IconButton.filledTonal(tooltip: l10n.pluginsSources, onPressed: toggle, icon: const Icon(Icons.tune_rounded))
            : FilledButton.tonalIcon(onPressed: toggle, icon: const Icon(Icons.tune_rounded), label: Text(l10n.pluginsSourcesTab));
      },
    );
  }
}

/// A one-line note with an action, in a tonal container.
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.action, this.error = false});
  final IconData icon;
  final String text;
  final Widget action;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (bg, fg) = error ? (cs.errorContainer, cs.onErrorContainer) : (cs.surfaceContainer, cs.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
      decoration: BoxDecoration(color: bg, borderRadius: Corners.all(Corners.lg)),
      child: Row(children: [
        Icon(icon, size: 20, color: fg),
        const SizedBox(width: Space.md),
        Expanded(child: Text(text, style: tt.bodyMedium?.copyWith(color: fg))),
        const SizedBox(width: Space.sm),
        action,
      ]),
    );
  }
}

/// "已启用" / "需要授权" / "出错" / "已停用" / "可更新" as a small pill.
class _PluginPill extends StatelessWidget {
  const _PluginPill({required this.plugin, this.update = false});
  final Map<String, dynamic> plugin;
  final bool update;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final (label, bg, fg) = switch ('${plugin['state']}') {
      'needs_consent' => (l10n.pluginsNeedsGrant, cs.tertiaryContainer, cs.onTertiaryContainer),
      'error' => (l10n.pluginsErrored, cs.errorContainer, cs.onErrorContainer),
      'disabled' => (l10n.commonDisabled, cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ when update => (l10n.pluginsUpdatable, cs.primary, cs.onPrimary),
      _ => (l10n.commonEnabled, cs.primaryContainer, cs.onPrimaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
      decoration: BoxDecoration(color: bg, borderRadius: Corners.all(Corners.full)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: Space.xs),
        Text(label, style: tt.labelMedium?.copyWith(color: fg)),
      ]),
    );
  }
}

/// An installed plugin: a card with a switch on narrow windows ([card]), a
/// selectable row beside the detail pane otherwise.
class _InstalledRow extends StatelessWidget {
  const _InstalledRow({required this.plugin, required this.onTap, this.onToggle, this.card = false, this.update = false, this.selected = false});
  final Map<String, dynamic> plugin;
  final VoidCallback onTap;
  final ValueChanged<bool>? onToggle;
  final bool card, update, selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = '${plugin['state']}';
    final error = state == 'error';
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? cs.secondaryContainer : card ? cs.surfaceContainerLow : Colors.transparent,
        borderRadius: Corners.all(card ? Corners.xl : Corners.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(Space.md, Space.md, card ? Space.sm : Space.md, Space.md),
            child: Row(children: [
              PluginGlyph(icon: plugin['icon'], id: plugin['id'], size: 44, muted: state == 'disabled'),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text('${plugin['title']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium?.copyWith(color: state == 'disabled' ? cs.onSurfaceVariant : null)),
                    ),
                    if (plugin['official'] == true) ...[const SizedBox(width: Space.xs), Icon(Icons.verified_rounded, size: 16, color: cs.primary)],
                  ]),
                  const SizedBox(height: Space.xxs),
                  Text(error ? '${plugin['error']}' : '${plugin['summary']}',
                      maxLines: card ? 2 : 1, overflow: TextOverflow.ellipsis, style: tt.bodyMedium?.copyWith(color: error ? cs.error : cs.onSurfaceVariant)),
                  if (_needsAttention(plugin) || update) ...[
                    const SizedBox(height: Space.xs),
                    _PluginPill(plugin: plugin, update: update),
                  ],
                ]),
              ),
              if (onToggle != null) Switch(value: plugin['enabled'] == true, onChanged: onToggle),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The plugin's icon on a tonal, softly scalloped shape. With [id] the tone
/// rotates among primary, secondary and tertiary so neighbours differ.
class PluginGlyph extends StatelessWidget {
  const PluginGlyph({super.key, required this.icon, this.id, this.size = 48, this.muted = false, this.color, this.onColor});
  final Object? icon, id;
  final double size;
  final bool muted;
  final Color? color, onColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = muted
        ? (cs.surfaceContainerHighest, cs.outline)
        : color != null
            ? (color!, onColor ?? cs.onPrimaryContainer)
            : switch (id == null ? 0 : '$id'.codeUnits.fold(0, (a, b) => a + b) % 3) {
                0 => (cs.primaryContainer, cs.onPrimaryContainer),
                1 => (cs.secondaryContainer, cs.onSecondaryContainer),
                _ => (cs.tertiaryContainer, cs.onTertiaryContainer),
              };
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: bg,
        shape: size >= 64
            ? const StarBorder(points: 9, innerRadiusRatio: 0.86, pointRounding: 0.55, valleyRounding: 0.45)
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(size * 0.32)),
      ),
      child: Icon(pluginIcon(icon), size: size * 0.5, color: fg),
    );
  }
}

class _Featured extends StatelessWidget {
  const _Featured({required this.plugins, required this.onOpen});
  final List<Map<String, dynamic>> plugins;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (plugins.length == 1) return SizedBox(height: 220, child: _HeroCard(plugin: plugins.first, onOpen: onOpen));
    return SizedBox(
      height: 220,
      child: HorizontalScroller(
        carousel: true,
        builder: (c) => CarouselView.weighted(
          controller: c as CarouselController,
          flexWeights: const [3, 1],
          itemSnapping: true,
          backgroundColor: cs.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.xl)),
          onTap: (i) => onOpen(plugins[i]),
          children: [for (final p in plugins) _HeroCard(plugin: p, onOpen: onOpen, inCarousel: true)],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.plugin, required this.onOpen, this.inCarousel = false});
  final Map<String, dynamic> plugin;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final bool inCarousel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final examples = jsonList(plugin['examples']);
    final body = Container(
      decoration: BoxDecoration(
        borderRadius: Corners.all(Corners.xl),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primaryContainer, cs.tertiaryContainer]),
      ),
      padding: const EdgeInsets.all(Space.xl),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 420;
        return Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(l10n.pluginsFeatured, style: tt.labelLarge?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
              const SizedBox(height: Space.xs),
              Text('${plugin['title']}', style: tt.headlineSmall?.copyWith(color: cs.onPrimaryContainer), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: Space.sm),
              Flexible(child: Text('${plugin['summary']}', style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer), maxLines: c.maxHeight > MediaQuery.textScalerOf(context).scale(120) ? 2 : 1, overflow: TextOverflow.ellipsis)),
              if (examples.isNotEmpty && c.maxHeight > MediaQuery.textScalerOf(context).scale(150)) ...[
                const SizedBox(height: Space.md),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
                  decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.6), borderRadius: Corners.all(Corners.full)),
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
      borderRadius: Corners.all(Corners.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: () => onOpen(plugin), child: body),
    );
  }
}

class _MarketCard extends StatelessWidget {
  const _MarketCard({required this.plugin, required this.installed, required this.selected, required this.onTap, required this.onInstall});
  final Map<String, dynamic> plugin;
  final bool installed, selected;
  final VoidCallback onTap, onInstall;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final update = plugin['update'] == true;
    final official = plugin['official'] == true;
    final cats = jsonList(plugin['categories']).map((c) => pluginCategories['$c']).whereType<String>().take(2);
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? cs.surfaceContainer : cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: Corners.all(Corners.xl),
          side: selected ? BorderSide(color: cs.primary, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: SizedBox(
              height: 148,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  PluginGlyph(icon: plugin['icon'], id: plugin['id'], size: 48),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${plugin['title']}', style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Space.xxs),
                      Row(children: [
                        if (official) ...[Icon(Icons.verified_rounded, size: 14, color: cs.primary), const SizedBox(width: Space.xxs)],
                        Flexible(
                          child: Text(official ? l10n.pluginsOfficial : '${plugin['author'] ?? plugin['catalog'] ?? ''}',
                              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ]),
                  ),
                ]),
                const SizedBox(height: Space.md),
                Expanded(child: Text('${plugin['summary']}', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)),
                Row(children: [
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.xs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
                        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: Corners.all(Corners.full)),
                        child: Text(c, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ),
                  const Spacer(),
                  if (installed && !update)
                    Row(children: [
                      Icon(Icons.check_circle_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: Space.xs),
                      Text(l10n.commonInstalled, style: tt.labelLarge?.copyWith(color: cs.primary)),
                    ])
                  else if (update)
                    FilledButton(style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: onInstall, child: Text(l10n.memoryUpdated))
                  else
                    FilledButton.tonal(style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: onInstall, child: Text(l10n.commonInstall)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
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
      title: Text(l10n.pluginsInstallOther),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text(l10n.commonFolder), icon: Icon(Icons.folder_outlined)),
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
              helperText: _kind == 0 ? null : l10n.pluginsPinnedVersion,
              suffixIcon: _kind == 0
                  ? IconButton(
                      tooltip: l10n.pickerChooseFolder,
                      icon: const Icon(Icons.folder_open_outlined),
                      onPressed: () async {
                        final dir = await pickDirectory(context, initial: _text.text.trim());
                        if (dir != null) _text.text = dir;
                      },
                    )
                  : null,
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
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
            child: Text(l10n.commonNext),
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
      title: Text(l10n.pluginsCatalog),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.verified_rounded), title: Text(l10n.pluginsOfficial), subtitle: Text(l10n.pluginsBundled)),
          for (final c in _catalogs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public_rounded),
              title: Text('${c['url']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: _errors.any((e) => e is Map && e['url'] == c['url'])
                  ? Text(l10n.pluginsLoadFailed((_errors.firstWhere((e) => e is Map && e['url'] == c['url']) as Map)['error']), style: TextStyle(color: cs.error))
                  : null,
              trailing: IconButton(
                tooltip: l10n.commonRemove,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _busy ? null : () => _run(() => store.removeCatalog('${c['url']}')),
              ),
            ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _url,
            decoration: InputDecoration(
              hintText: l10n.pluginsCatalogHint,
              suffixIcon: IconButton(
                tooltip: l10n.commonAdd,
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
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonFinished))],
    );
  }
}

/// Fetches [source], asks for consent with the exact permissions, installs.
Future<bool> installPlugin(BuildContext context, String source) async {
  final store = context.read<PluginStore>();
  final nav = Navigator.of(context, rootNavigator: true);
  Map<String, dynamic> preview;
  showDialog(context: context, barrierDismissible: false, useRootNavigator: true, builder: (_) => _Busy(label: l10n.pluginsFetching));
  try {
    preview = await store.preview(source);
  } catch (e) {
    nav.pop();
    if (context.mounted) showSnack(context, l10n.pluginsFetchFailed(_err(e)));
    return false;
  }
  nav.pop();
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(context: context, useRootNavigator: true, builder: (_) => ConsentDialog(preview: preview));
  if (ok != true || !context.mounted) return false;
  showDialog(context: context, barrierDismissible: false, useRootNavigator: true, builder: (_) => _Busy(label: l10n.pluginsInstalling));
  try {
    final p = await store.confirm('${preview['token']}');
    nav.pop();
    if (context.mounted) {
      showSnack(context, p['state'] == 'error' ? l10n.pluginsInstalledLoadFailed(p['error']) : l10n.pluginsInstalledToast(p['title']));
    }
    return true;
  } catch (e) {
    nav.pop();
    if (context.mounted) showSnack(context, l10n.pluginsInstallFailed(_err(e)));
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
      title: Text(update == null ? l10n.pluginsInstallTitle(m['title']) : l10n.pluginsUpdateTitle(m['title'])),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              [if (official) l10n.pluginsOfficial else if ('${m['author'] ?? ''}'.isNotEmpty) '${m['author']}', 'v${m['version']}', if (update != null) l10n.pluginsCurrentVersion(update['from'])].join(' · '),
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
                    child: Text(l10n.pluginsThirdPartyWarning(preview['source']),
                        style: tt.bodySmall?.copyWith(color: cs.onTertiaryContainer)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: Space.lg),
            Text(perms.isEmpty ? l10n.pluginsNoPermissions : l10n.pluginsWillBeAble, style: tt.titleSmall),
            for (final p in perms)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(permissionIcons[p['id']] ?? Icons.key_outlined,
                    color: sensitivePermissions.contains(p['id']) ? cs.tertiary : cs.onSurfaceVariant),
                title: Text('${p['label']}', style: sensitivePermissions.contains(p['id']) ? tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600) : null),
                subtitle: p['detail'] == null ? null : Text('${p['detail']}'),
                trailing: added.contains(p['id']) ? Text(l10n.pluginsNewPermissions, style: tt.labelSmall?.copyWith(color: cs.tertiary)) : null,
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(update == null ? l10n.commonInstall : l10n.memoryUpdated)),
      ],
    );
  }
}


/// One plugin on its own page, pushed over the list on narrow windows.
class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({super.key, required this.entry, this.onChanged});
  final Map<String, dynamic> entry;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: PluginDetailView(
          entry: entry,
          onChanged: onChanged,
          // A plugin that is in no catalog has nothing left to show once removed.
          onUninstalled: entry['catalog'] == null ? () => Navigator.pop(context) : null,
        ),
      );
}

/// What a plugin does, what it may do, where it appears and its settings.
class PluginDetailView extends StatefulWidget {
  const PluginDetailView({super.key, required this.entry, this.embedded = false, this.onClose, this.onChanged, this.onUninstalled});

  /// A catalog listing or an installed plugin.
  final Map<String, dynamic> entry;

  /// Shown in the pane beside a list rather than as its own page.
  final bool embedded;
  final VoidCallback? onClose, onChanged, onUninstalled;
  @override
  State<PluginDetailView> createState() => _PluginDetailViewState();
}

class _PluginDetailViewState extends State<PluginDetailView> {
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
    widget.onChanged?.call();
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
    final update = installed != null && widget.entry['update'] == true;
    final source = widget.entry['source'];
    final perms = [for (final x in jsonList(p['permissions'])) if (x is Map) x.cast<String, dynamic>()];
    final contributes = (p['contributes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final places = [
      for (final a in jsonList(contributes['actions'])) if (a is Map) ('${a['title']}', _surfaceLabels['${a['surface']}'] ?? '${a['surface']}', a['icon']),
      for (final a in jsonList(contributes['noteViews'])) if (a is Map) ('${a['title']}', l10n.pluginsContribAlternative, a['icon']),
      for (final a in jsonList(contributes['exporters'])) if (a is Map) ('${a['title']}', l10n.pluginsContribExport(_scopeLabels['${a['scope']}'] ?? ''), a['icon']),
      for (final a in jsonList(contributes['pages'])) if (a is Map) ('${a['title']}', l10n.pluginsContribPage, a['icon']),
    ];
    final pages = [for (final pg in jsonList(contributes['pages'])) if (pg is Map) pg];
    final examples = jsonList(p['examples']);
    final schema = (p['settings'] as Map?)?.cast<String, dynamic>();
    final hasSettings = installed != null && ((schema?['properties'] as Map?)?.isNotEmpty ?? false);
    final abilities = installed == null ? const [] : [...jsonList(installed['tools']), ...jsonList(installed['skills'])];
    final official = p['official'] == true;
    final homepage = '${p['homepage'] ?? ''}';
    final tile = widget.embedded ? cs.surfaceContainer : cs.surfaceContainerLow;
    final pad = context.isCompact ? Space.lg : Space.xl;
    final meta = [
      official ? l10n.pluginsOfficial : '${p['author'] ?? ''}',
      if ('${p['version'] ?? ''}'.isNotEmpty) 'v${p['version']}',
      if (update) l10n.pluginsVersionAvailable(widget.entry['version']),
    ].where((s) => s.isNotEmpty).join(' · ');

    Widget section(String title, IconData icon, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
              child: Row(children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: Space.sm),
                Text(title, style: tt.titleSmall?.copyWith(color: cs.primary)),
              ]),
            ),
            Material(
              color: tile,
              borderRadius: Corners.all(Corners.xl),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ]),
        );

    return ListView(padding: EdgeInsets.fromLTRB(pad, widget.embedded ? Space.xl : Space.sm, pad, Space.xxxl), children: [
      ContentWidth(
        max: 760,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PluginGlyph(icon: p['icon'], id: id, size: widget.embedded ? 64 : 80, muted: state == 'disabled'),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['title']}', style: tt.headlineSmall),
                const SizedBox(height: Space.xs),
                Wrap(spacing: Space.sm, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (installed != null) _PluginPill(plugin: installed, update: update),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (official) ...[Icon(Icons.verified_rounded, size: 16, color: cs.primary), const SizedBox(width: Space.xs)],
                    Text(meta, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ]),
              ]),
            ),
            if (installed != null && state != 'needs_consent')
              Tooltip(
                message: installed['enabled'] == true ? l10n.commonDisable : l10n.commonEnable,
                child: Switch(value: installed['enabled'] == true, onChanged: _busy ? null : (v) => _run(() => store.update(id, {'enabled': v}))),
              ),
            if (widget.onClose != null) IconButton(tooltip: l10n.commonClose, onPressed: widget.onClose, icon: const Icon(Icons.close_rounded)),
          ]),
          const SizedBox(height: Space.lg),
          Text('${p['summary']}', style: tt.bodyLarge),
          const SizedBox(height: Space.lg),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            if (installed == null)
              FilledButton.icon(
                onPressed: _busy || source == null ? null : () => _run(() => installPlugin(context, '$source')),
                icon: const Icon(Icons.download_rounded),
                label: Text(l10n.commonInstall),
              ),
            if (state == 'needs_consent')
              FilledButton.icon(onPressed: _busy ? null : () => _consentUpdate(context, installed!), icon: const Icon(Icons.verified_user_outlined), label: Text(l10n.pluginsReviewGrant)),
            if (update)
              FilledButton.icon(onPressed: _busy ? null : () => _run(() => installPlugin(context, '$source')), icon: const Icon(Icons.upgrade_rounded), label: Text(l10n.memoryUpdated)),
            if (state == 'enabled')
              for (final pg in pages)
                FilledButton.tonalIcon(
                  onPressed: () => runPluginEntry(context, PluginEntry(installed!, 'pages', pg), const {}),
                  icon: Icon(pluginIcon(pg['icon'])),
                  label: Text('${pg['title']}'),
                ),
            if (installed != null)
              OutlinedButton.icon(onPressed: _busy ? null : () => _uninstall(context, installed), icon: const Icon(Icons.delete_outline_rounded), label: Text(l10n.commonUninstall)),
            if (homepage.startsWith('https://'))
              TextButton.icon(onPressed: () => launchUrl(Uri.parse(homepage)), icon: const Icon(Icons.open_in_new_rounded), label: Text(l10n.pluginsHomepage)),
          ]),
          if (state == 'error')
            Padding(
              padding: const EdgeInsets.only(top: Space.lg),
              child: Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(color: cs.errorContainer, borderRadius: Corners.all(Corners.lg)),
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
            Text(state == 'enabled' ? l10n.pluginsTryAsking : l10n.pluginsTryAfterEnable, style: tt.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
              for (final e in examples)
                if (state == 'enabled')
                  ActionChip(avatar: const Icon(Icons.auto_awesome_outlined, size: 18), label: Text('$e'), onPressed: () => askInSheet(context, '$e'))
                else
                  Chip(avatar: const Icon(Icons.format_quote_rounded, size: 18), label: Text('$e')),
            ]),
          ],
          if (abilities.isNotEmpty)
            section(l10n.pluginsCapabilities, Icons.auto_awesome_outlined, [
              for (final t in jsonList(installed!['tools']))
                ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.build_outlined), title: Text('${(t as Map)['label']}'), subtitle: Text('${t['name']}')),
              for (final k in jsonList(installed['skills']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text('${(k as Map)['name']}'),
                  subtitle: '${k['description'] ?? ''}'.isEmpty ? null : Text('${k['description']}'),
                ),
            ]),
          if (places.isNotEmpty)
            section(l10n.pluginsAppearsIn, Icons.widgets_outlined, [
              for (final (title, where, icon) in places)
                ListTile(contentPadding: EdgeInsets.zero, leading: Icon(pluginIcon(icon)), title: Text(title), subtitle: Text(where)),
            ]),
          section(l10n.pluginsPermissions, Icons.shield_outlined, [
            if (perms.isEmpty)
              ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.lock_outline_rounded), title: Text(l10n.pluginsNoPermissions), subtitle: Text(l10n.pluginsGuidanceOnly))
            else
              for (final x in perms)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(permissionIcons[x['id']] ?? Icons.key_outlined, color: sensitivePermissions.contains(x['id']) ? cs.tertiary : null),
                  title: Text('${x['label']}'),
                  subtitle: x['detail'] == null ? null : Text('${x['detail']}'),
                ),
          ]),
          if (hasSettings)
            section(l10n.commonSettings, Icons.tune_rounded, [
              PluginSettingsForm(
                key: ValueKey('$id-${installed['version']}'),
                schema: schema!,
                values: (installed['settings_values'] as Map?)?.cast<String, dynamic>() ?? const {},
                onSave: (v) => _run(() async {
                  await store.update(id, {'settings': v});
                  if (context.mounted) showSnack(context, l10n.pluginsSettingsSaved);
                }),
              ),
            ]),
          const SizedBox(height: Space.xl),
          Wrap(spacing: Space.lg, runSpacing: Space.xs, children: [
            if ('${p['license'] ?? ''}'.isNotEmpty) Text(l10n.commonLicense(p['license']), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            if ('${p['source'] ?? ''}'.isNotEmpty) Text(l10n.pluginsSource(p['source']), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ]),
      ),
    ]);
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
        title: Text(l10n.pluginsUninstallTitle(p['title'])),
        content: Text(l10n.pluginsUninstallBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonUninstall)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final store = context.read<PluginStore>();
    await _run(() async {
      await store.uninstall('${p['id']}');
      widget.onUninstalled?.call();
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
        _errors[key] = l10n.pluginsSettingRequired(p['type'] == 'string' ? l10n.pluginsSettingText : l10n.pluginsSettingNumber);
      } else if (v is num && ((p['minimum'] is num && v < p['minimum']) || (p['maximum'] is num && v > p['maximum']))) {
        _errors[key] = l10n.pluginsSettingRange(p['minimum'] ?? '', p['maximum'] ?? '');
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
                        tooltip: l10n.pickerChooseFolder,
                        icon: const Icon(Icons.folder_open_outlined),
                        onPressed: () async {
                          final dir = await pickDirectory(context, initial: _text[key]!.text.trim());
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
        child: FilledButton.tonal(onPressed: _save, child: Text(l10n.pluginsSaveSettings, style: tt.labelLarge)),
      ),
    ]);
  }
}
