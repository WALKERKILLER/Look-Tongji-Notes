import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../assistant/assistant_controller.dart';
import 'models_page.dart';
import 'provider_presets.dart';
import 'provider_setup_page.dart';
import '../../l10n/l10n.dart';

/// Step 1 of the guided flow: pick a provider from curated presets, the
/// models.dev directory, or start a blank compatible endpoint.
class AddProviderPage extends StatefulWidget {
  const AddProviderPage({super.key});
  @override
  State<AddProviderPage> createState() => _AddProviderPageState();
}

class _AddProviderPageState extends State<AddProviderPage> {
  final _q = TextEditingController();
  Region? _region;
  List<Map<String, dynamic>>? _catalog;
  String? _catalogError;

  @override
  void initState() {
    super.initState();
    context.read<AssistantController>().catalogProviders().then((v) {
      if (mounted) setState(() => _catalog = v);
    }, onError: (Object e) {
      if (mounted) setState(() => _catalogError = '$e');
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _open(ProviderSetupPage page) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AssistantController>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = _q.text.trim();
    final configured = {for (final p in providersOf(a.models)) if (p['configured'] == true || p['custom'] == true) '${p['id']}'};
    final presets = kProviderPresets.where((p) => (_region == null || p.region == _region) && (q.isEmpty || p.matches(q))).toList();
    final presetCatalogIds = {for (final p in kProviderPresets) ?p.catalog};
    final more = (_catalog ?? const [])
        .where((c) => !presetCatalogIds.contains(c['id']) && _region != Region.local)
        .where((c) => q.isEmpty ? false : '${c['id']} ${c['name']}'.toLowerCase().contains(q.toLowerCase()))
        .toList();
    final moreCount = (_catalog?.length ?? 0) - presetCatalogIds.length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.modelsAddProvider)),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: ContentWidth(
            max: 960,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SearchBar(
                  controller: _q,
                  autoFocus: true,
                  hintText: l10n.addProviderSearchHint,
                  leading: const Icon(Icons.search_rounded),
                  trailing: [if (q.isNotEmpty) IconButton(onPressed: () => setState(_q.clear), icon: const Icon(Icons.close_rounded))],
                  onChanged: (_) => setState(() {}),
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
                ),
                const SizedBox(height: Space.md),
                Wrap(spacing: Space.sm, children: [
                  ChoiceChip(label: Text(l10n.commonAll), selected: _region == null, onSelected: (_) => setState(() => _region = null)),
                  for (final r in Region.values) ChoiceChip(label: Text(r.label), selected: _region == r, onSelected: (_) => setState(() => _region = r)),
                ]),
              ]),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          sliver: SliverToBoxAdapter(
            child: ContentWidth(
              max: 960,
              child: LayoutBuilder(builder: (context, c) {
                final cols = (c.maxWidth / 220).floor().clamp(2, 4);
                final w = (c.maxWidth - Space.sm * (cols - 1)) / cols;
                return Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                  for (final p in presets)
                    SizedBox(
                      width: w,
                      child: _PresetTile(
                        preset: p,
                        added: configured.contains(p.providerId),
                        onTap: () => _open(ProviderSetupPage.preset(preset: p)),
                      ),
                    ),
                ]);
              }),
            ),
          ),
        ),
        if (presets.isEmpty && more.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(_catalog == null ? l10n.addProviderLoadingCatalog : l10n.addProviderNoMatch(q),
                  textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ),
        if (more.isNotEmpty) ...[
          _header(context, l10n.addProviderCatalog, l10n.addProviderMatches(more.length)),
          SliverList.builder(
            itemCount: more.length,
            itemBuilder: (context, i) {
              final c = more[i];
              return ContentWidth(
                max: 960,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.lg)),
                    leading: ProviderLogo(providerId: '${c['id']}', name: '${c['name']}', networkLogo: '${c['logo']}'),
                    title: Text('${c['name']}'),
                    subtitle: Text(l10n.addProviderCatalogEntry(c['models'], c['base_url']), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: configured.contains(c['id']) ? Icon(Icons.check_circle_rounded, color: cs.primary) : const Icon(Icons.chevron_right_rounded),
                    onTap: () => _open(ProviderSetupPage.catalog(entry: c)),
                  ),
                ),
              );
            },
          ),
        ],
        _header(context, l10n.addProviderNotFound, null),
        SliverToBoxAdapter(
          child: ContentWidth(
            max: 960,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Material(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(Corners.lg),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.lg)),
                    leading: CircleAvatar(backgroundColor: cs.tertiaryContainer, child: Icon(Icons.add_link_rounded, color: cs.onTertiaryContainer)),
                    title: Text(l10n.providerCustom),
                    subtitle: Text(l10n.addProviderCompatibleHint),
                    onTap: () => _open(const ProviderSetupPage.blank()),
                  ),
                ),
                const SizedBox(height: Space.md),
                Text(
                  _catalogError != null
                      ? l10n.addProviderCatalogError(_catalogError!)
                      : _catalog == null
                          ? l10n.addProviderCatalogLoading
                          : l10n.addProviderSearchesMore(moreCount),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: Space.huge),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context, String title, String? trailing) => SliverToBoxAdapter(
        child: ContentWidth(
          max: 960,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg + Space.xs, Space.xl, Space.lg, Space.sm),
            child: Row(children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
              const Spacer(),
              if (trailing != null) Text(trailing, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        ),
      );
}

class _PresetTile extends StatefulWidget {
  const _PresetTile({required this.preset, required this.added, required this.onTap});
  final ProviderPreset preset;
  final bool added;
  final VoidCallback onTap;
  @override
  State<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends State<_PresetTile> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.preset;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.medium1,
        curve: Motion.emphasized,
        height: 132,
        decoration: BoxDecoration(
          color: _hover ? cs.surfaceContainerHigh : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(_hover ? Corners.xl : Corners.lg),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Corners.lg),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedScale(scale: _hover ? 1.08 : 1, duration: Motion.medium2, curve: Motion.emphasized, child: ProviderLogo(providerId: p.providerId, size: 44)),
                  const Spacer(),
                  if (widget.added)
                    Icon(Icons.check_circle_rounded, size: 20, color: cs.primary)
                  else
                    Text(p.builtin ? l10n.commonBuiltIn : p.region == Region.local ? l10n.commonLocal : l10n.addProviderCompatible, style: tt.labelSmall?.copyWith(color: cs.outline)),
                ]),
                const Spacer(),
                Text(p.name, style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(p.blurb.isEmpty ? (p.builtin ? l10n.addProviderBuiltInKeyOnly : p.baseUrl) : p.blurb,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
