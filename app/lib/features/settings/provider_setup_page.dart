import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/open_path.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../assistant/assistant_controller.dart';
import 'model_meta.dart';
import 'models_page.dart';
import 'provider_presets.dart';
import '../../l10n/l10n.dart';

final _apiLabels = {
  'openai-completions': l10n.apiOpenaiCompatible,
  'openai-responses': 'OpenAI Responses',
  'anthropic-messages': 'Anthropic Messages',
  'google-generative-ai': 'Google Gemini',
};

/// Steps 2–3 of the guided flow: connect (key, endpoint), choose models
/// (pulled from the provider and enriched by models.dev), then save and test.
class ProviderSetupPage extends StatefulWidget {
  const ProviderSetupPage.preset({super.key, required ProviderPreset this.preset})
      : entry = null,
        provider = null;
  const ProviderSetupPage.catalog({super.key, required Map<String, dynamic> this.entry})
      : preset = null,
        provider = null;
  const ProviderSetupPage.existing({super.key, required Map<String, dynamic> this.provider})
      : preset = null,
        entry = null;
  const ProviderSetupPage.blank({super.key})
      : preset = null,
        entry = null,
        provider = null;

  final ProviderPreset? preset;
  final Map<String, dynamic>? entry; // models.dev provider
  final Map<String, dynamic>? provider; // already configured (describe() entry)

  @override
  State<ProviderSetupPage> createState() => _ProviderSetupPageState();
}

class _ProviderSetupPageState extends State<ProviderSetupPage> {
  final _key = TextEditingController();
  final _base = TextEditingController();
  final _id = TextEditingController();
  final _q = TextEditingController();
  final _manual = TextEditingController();
  String _api = 'openai-completions';
  String? _catalogId;
  String _name = '';
  String _keyUrl = '';
  String? _networkLogo;
  bool _builtin = false;
  bool _needsKey = true;
  bool _isNew = true;
  bool _showKey = false;
  bool _advanced = false;

  /// Chosen models for custom endpoints, in insertion order.
  final Map<String, Map<String, dynamic>> _chosen = {};
  List<Map<String, dynamic>>? _offered;
  String _offeredFrom = '';
  bool _loadingModels = false;
  String? _modelsError;

  bool _saving = false;
  String? _test;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final p = widget.preset, e = widget.entry, x = widget.provider;
    if (p != null) {
      _name = p.name;
      _builtin = p.builtin;
      _id.text = p.providerId;
      _base.text = p.baseUrl;
      _api = p.api;
      _catalogId = p.catalog;
      _keyUrl = p.keyUrl;
      _needsKey = p.needsKey;
    } else if (e != null) {
      _name = '${e['name']}';
      _id.text = '${e['id']}';
      _base.text = '${e['base_url']}';
      _api = '${e['api']}';
      _catalogId = '${e['id']}';
      _keyUrl = '${e['doc']}';
      _networkLogo = '${e['logo']}';
    } else if (x != null) {
      _isNew = false;
      _name = presetFor('${x['id']}')?.name ?? '${x['name']}';
      _builtin = x['custom'] != true;
      _id.text = '${x['id']}';
      _base.text = '${x['base_url']}';
      if (_apiLabels.containsKey(x['api'])) _api = '${x['api']}';
      _catalogId = '${x['catalog_id']}'.isEmpty ? presetFor('${x['id']}')?.catalog : '${x['catalog_id']}';
      _keyUrl = presetFor('${x['id']}')?.keyUrl ?? '';
      _needsKey = presetFor('${x['id']}')?.needsKey ?? true;
      if (_catalogId != null) _networkLogo = 'https://models.dev/logos/$_catalogId.svg';
      for (final m in jsonList(x['models']).whereType<Map>()) {
        _chosen['${m['id']}'] = m.cast<String, dynamic>();
      }
    } else {
      _name = l10n.providerCustom;
      _advanced = true;
    }
    // Pre-existing preset that was already added: open in edit mode.
    if (_isNew && p != null) {
      final existing = providersOf(context.read<AssistantController>().models).where((m) => m['id'] == p.providerId).firstOrNull;
      if (existing != null && (existing['configured'] == true || existing['custom'] == true)) {
        _isNew = false;
        for (final m in jsonList(existing['models']).whereType<Map>()) {
          if (!_builtin) _chosen['${m['id']}'] = m.cast<String, dynamic>();
        }
      }
    }
    if (_builtin) _offered = _piModels();
  }

  @override
  void dispose() {
    for (final c in [_key, _base, _id, _q, _manual]) {
      c.dispose();
    }
    super.dispose();
  }

  AssistantController get _a => context.read<AssistantController>();

  Map<String, dynamic>? get _registered => providersOf(_a.models).where((m) => m['id'] == _id.text.trim()).firstOrNull;

  List<Map<String, dynamic>> _piModels() =>
      jsonList(_registered?['models'] ?? providersOf(_a.models).where((m) => m['id'] == _id.text.trim()).firstOrNull?['models'])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

  bool get _configured => _registered?['configured'] == true;

  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final list = await _a.discover(
        provider: _isNew ? null : _id.text.trim(),
        baseUrl: _base.text.trim(),
        api: _api,
        apiKey: _key.text.trim(),
        catalogId: _catalogId,
      );
      setState(() {
        _offered = list;
        _offeredFrom = l10n.providerSource;
      });
    } catch (e) {
      setState(() => _modelsError = e is ApiError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _fromCatalog() async {
    if (_catalogId == null) return;
    setState(() => _loadingModels = true);
    try {
      final list = await _a.catalogModels(_catalogId!);
      setState(() {
        _offered = list;
        _offeredFrom = 'models.dev';
        _modelsError = null;
      });
    } catch (e) {
      setState(() => _modelsError = '$e');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  void _addManual() {
    final id = _manual.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _chosen[id] = _offered?.firstWhere((m) => m['id'] == id, orElse: () => {'id': id}) ?? {'id': id};
      _manual.clear();
    });
  }

  Future<void> _save({bool test = true}) async {
    final id = _id.text.trim();
    final key = _key.text.trim();
    if (!_builtin && _chosen.isEmpty) {
      showSnack(context, l10n.providerPickModel);
      return;
    }
    if (_isNew && _needsKey && key.isEmpty && !_configured) {
      showSnack(context, l10n.providerKeyMissing);
      return;
    }
    setState(() {
      _saving = true;
      _test = null;
    });
    try {
      if (_builtin) {
        if (key.isNotEmpty) await _a.setKey(id, key);
      } else {
        await _a.upsertProvider(id, {
          'base_url': _base.text.trim(),
          'api': _api,
          if (key.isNotEmpty || _isNew) 'api_key': _needsKey ? key : (key.isEmpty ? 'local' : key),
          'catalog_id': ?_catalogId,
          'models': [
            for (final m in _chosen.values)
              {
                'id': m['id'],
                if (m['name'] != null && m['name'] != m['id']) 'name': m['name'],
                'reasoning': m['reasoning'] == true,
                'vision': m['vision'] == true,
                'context_window': ?m['context_window'],
                'max_tokens': ?m['max_tokens'],
                'cost_in': ?m['cost_in'],
                'cost_out': ?m['cost_out'],
                'cache_read': ?m['cache_read'],
              },
          ],
        });
      }
      _isNew = false;
      final models = _builtin ? _piModels().where((m) => m['available'] == true).toList() : _chosen.values.toList();
      if (_a.selected == null && models.isNotEmpty) {
        await _a.setPrefs({'provider': id, 'model': models.first['id']});
      }
      if (mounted) showSnack(context, l10n.providerSaved(_name));
      if (test && models.isNotEmpty) await _runTest('${models.first['id']}');
    } catch (e) {
      if (mounted) showSnack(context, e is ApiError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runTest(String model) async {
    setState(() => _test = null);
    try {
      final r = await _a.testProvider(_id.text.trim(), model);
      setState(() {
        _testOk = true;
        _test = l10n.providerTestOk(r['model'], r['latency_ms']);
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _test = e is ApiError ? e.message : '$e';
      });
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text(_builtin ? l10n.providerRemoveKeyTitle(_name) : l10n.providerDeleteTitle(_name)),
        content: Text(_builtin ? l10n.providerRemoveKeyBody : l10n.providerDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (ok != true) return;
    if (_builtin) {
      await _a.setKey(_id.text.trim(), '');
    } else {
      await _a.removeProvider(_id.text.trim());
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AssistantController>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final preset = widget.preset ?? presetFor(_id.text.trim());
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.providerAddTitle(_name) : _name),
        actions: [
          if (!_isNew) IconButton(tooltip: l10n.commonDelete, onPressed: _remove, icon: const Icon(Icons.delete_outline_rounded)),
          const SizedBox(width: Space.sm),
        ],
      ),
      bottomNavigationBar: _bottomBar(context),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl), children: [
        ContentWidth(
          max: 760,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Identity
            Row(children: [
              ProviderLogo(providerId: _id.text.trim(), name: _name, size: 64, networkLogo: _networkLogo),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name, style: tt.headlineSmall),
                  Text(
                    preset?.blurb.isNotEmpty == true
                        ? preset!.blurb
                        : _builtin
                            ? l10n.providerBuiltIn
                            : (_apiLabels[_api] ?? _api),
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: Space.xl),
            _Step(
              n: 1,
              title: l10n.commonConnect,
              done: _configured,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_needsKey)
                  TextField(
                    controller: _key,
                    obscureText: !_showKey,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: _configured ? l10n.providerKeySaved(_registered?['key_hint'] ?? '') : l10n.providerKeyHint,
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: l10n.commonPaste,
                          onPressed: () async {
                            final d = await Clipboard.getData(Clipboard.kTextPlain);
                            if (d?.text != null) setState(() => _key.text = d!.text!.trim());
                          },
                          icon: const Icon(Icons.content_paste_rounded),
                        ),
                        IconButton(
                          tooltip: _showKey ? l10n.commonHide : l10n.commonShow,
                          onPressed: () => setState(() => _showKey = !_showKey),
                          icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ]),
                    ),
                  )
                else
                  Text(l10n.providerLocalNoKey, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                if (_keyUrl.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => openPath(_keyUrl),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(_needsKey ? l10n.providerGetKey(_name) : l10n.providerDownloadApp(_name)),
                    ),
                  ),
                if (!_builtin) ...[
                  const SizedBox(height: Space.sm),
                  TextField(
                    controller: _base,
                    decoration: const InputDecoration(labelText: 'Base URL', prefixIcon: Icon(Icons.link_rounded)),
                  ),
                  const SizedBox(height: Space.sm),
                  InkWell(
                    borderRadius: BorderRadius.circular(Corners.sm),
                    onTap: () => setState(() => _advanced = !_advanced),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(children: [
                        Text(l10n.commonAdvanced, style: tt.labelLarge?.copyWith(color: cs.primary)),
                        AnimatedRotation(turns: _advanced ? 0.5 : 0, duration: Motion.medium1, child: Icon(Icons.expand_more_rounded, color: cs.primary)),
                      ]),
                    ),
                  ),
                  AnimatedSize(
                    duration: Motion.medium2,
                    curve: Motion.emphasized,
                    child: !_advanced
                        ? const SizedBox(width: double.infinity)
                        : Column(children: [
                            DropdownButtonFormField<String>(
                              initialValue: _api,
                              decoration: InputDecoration(labelText: l10n.providerApi),
                              items: [for (final e in _apiLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                              onChanged: (v) => setState(() => _api = v ?? _api),
                            ),
                            const SizedBox(height: Space.sm),
                            TextField(
                              controller: _id,
                              enabled: _isNew,
                              decoration: InputDecoration(labelText: l10n.providerId, helperText: l10n.providerIdHelper),
                            ),
                          ]),
                  ),
                ],
              ]),
            ),
            _Step(n: 2, title: l10n.commonModel, done: _builtin ? _configured : _chosen.isNotEmpty, child: _builtin ? _builtinModels(context) : _customModels(context)),
          ]),
        ),
      ]),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
        decoration: BoxDecoration(color: cs.surfaceContainer),
        child: Row(children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.medium1,
              child: _test == null
                  ? Text(
                      _builtin ? l10n.providerTestsOnSave : l10n.providerChosenModels(_chosen.length),
                      key: const ValueKey('hint'),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    )
                  : Row(key: ValueKey(_test), children: [
                      Icon(_testOk ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: _testOk ? cs.primary : cs.error, size: 20),
                      const SizedBox(width: Space.sm),
                      Expanded(child: Text(_test!, style: tt.bodySmall?.copyWith(color: _testOk ? cs.onSurface : cs.error), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ]),
            ),
          ),
          const SizedBox(width: Space.md),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
            label: Text(_isNew ? l10n.providerSaveAndTest : l10n.commonSave),
          ),
        ]),
      ),
    );
  }

  Widget _builtinModels(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final a = context.watch<AssistantController>();
    final list = _filter(_piModels());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l10n.providerBuiltInHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Space.sm),
      _searchField(context),
      const SizedBox(height: Space.sm),
      for (final m in list.take(80))
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.sm),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.md)),
          selected: a.selected?['provider'] == _id.text.trim() && a.selected?['model'] == m['id'],
          selectedTileColor: cs.secondaryContainer,
          enabled: m['available'] == true,
          title: Text('${m['name']}'),
          subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: ModelBadges(m: m, dense: true)),
          trailing: Text('${m['id']}' == '${m['name']}' ? '' : '${m['id']}', style: tt.labelSmall?.copyWith(color: cs.outline)),
          onTap: () => a.setPrefs({'provider': _id.text.trim(), 'model': m['id']}),
        ),
      if (list.length > 80) Text(l10n.providerMoreModels(list.length - 80), style: tt.bodySmall),
    ]);
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> l) {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return l;
    return l.where((m) => '${m['id']} ${m['name']}'.toLowerCase().contains(q)).toList();
  }

  Widget _searchField(BuildContext context) => TextField(
        controller: _q,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.modelsSearch,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.full), borderSide: BorderSide.none),
        ),
      );

  Widget _customModels(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final offered = _offered == null ? null : _filter(_offered!);
    final canFetch = !_needsKey || _key.text.trim().isNotEmpty || !_isNew;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_chosen.isNotEmpty) ...[
        Text(l10n.providerChosen, style: tt.labelLarge),
        const SizedBox(height: Space.xs),
        Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
          for (final m in _chosen.values)
            InputChip(
              label: Text('${m['id']}'),
              avatar: m['reasoning'] == true ? const Icon(Icons.psychology_outlined, size: 16) : null,
              onDeleted: () => setState(() => _chosen.remove(m['id'])),
            ),
        ]),
        const SizedBox(height: Space.md),
      ],
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        FilledButton.tonalIcon(
          onPressed: _loadingModels || !canFetch ? null : _fetchModels,
          icon: _loadingModels ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_download_outlined, size: 18),
          label: Text(canFetch ? l10n.providerFetchModels : l10n.providerFetchNeedsKey),
        ),
        if (_catalogId != null)
          OutlinedButton.icon(
            onPressed: _loadingModels ? null : _fromCatalog,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: Text(l10n.providerFromCatalog),
          ),
      ]),
      if (_modelsError != null) ...[
        const SizedBox(height: Space.sm),
        Text(_modelsError!, style: tt.bodySmall?.copyWith(color: cs.error)),
        if (_catalogId != null) Text(l10n.providerNoModelList, style: tt.bodySmall),
      ],
      if (offered != null) ...[
        const SizedBox(height: Space.md),
        Row(children: [
          Expanded(child: _searchField(context)),
          const SizedBox(width: Space.sm),
          Text(l10n.providerOfferedCount(offered.length, _offeredFrom), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: Space.xs),
        Container(
          constraints: const BoxConstraints(maxHeight: 440),
          decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(Corners.lg)),
          child: offered.isEmpty
              ? Padding(padding: const EdgeInsets.all(Space.lg), child: Text(l10n.providerNoMatch, style: tt.bodyMedium))
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  itemCount: offered.length,
                  itemBuilder: (context, i) {
                    final m = offered[i];
                    final on = _chosen.containsKey(m['id']);
                    return CheckboxListTile(
                      dense: true,
                      value: on,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text('${m['id']}', style: tt.bodyMedium),
                      subtitle: m['known'] == false ? Text(l10n.providerNotInCatalog, style: tt.labelSmall?.copyWith(color: cs.outline)) : ModelBadges(m: m, dense: true),
                      onChanged: (v) => setState(() => v == true ? _chosen['${m['id']}'] = m : _chosen.remove(m['id'])),
                    );
                  },
                ),
        ),
      ],
      const SizedBox(height: Space.md),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _manual,
            onSubmitted: (_) => _addManual(),
            decoration: InputDecoration(isDense: true, labelText: l10n.providerManualModel, hintText: l10n.providerManualModelHint),
          ),
        ),
        const SizedBox(width: Space.sm),
        IconButton.filledTonal(onPressed: _addManual, icon: const Icon(Icons.add_rounded)),
      ]),
      const SizedBox(height: Space.xs),
      Text(l10n.providerCatalogNote,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.done, required this.child});
  final int n;
  final String title;
  final bool done;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(Corners.xl)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AnimatedContainer(
              duration: Motion.medium2,
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: done ? cs.primary : cs.secondaryContainer, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: done
                  ? Icon(Icons.check_rounded, size: 16, color: cs.onPrimary)
                  : Text('$n', style: tt.labelLarge?.copyWith(color: cs.onSecondaryContainer)),
            ),
            const SizedBox(width: Space.md),
            Text(title, style: tt.titleMedium),
          ]),
          const SizedBox(height: Space.md),
          child,
        ]),
      ),
    );
  }
}
