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

const _apiLabels = {
  'openai-completions': 'OpenAI Chat Completions 兼容',
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
      _name = '自定义服务';
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
        _offeredFrom = '服务商';
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
      showSnack(context, '至少选择一个模型');
      return;
    }
    if (_isNew && _needsKey && key.isEmpty && !_configured) {
      showSnack(context, '请先填写 API Key');
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
      if (mounted) showSnack(context, '已保存 $_name');
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
        _test = '${r['model']} 响应正常 · ${r['latency_ms']} ms';
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
        title: Text(_builtin ? '移除 $_name 的密钥？' : '删除 $_name？'),
        content: Text(_builtin ? '内置服务商仍会保留在目录中，填入密钥即可重新使用。' : '会删除这个服务及其模型配置。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
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
        title: Text(_isNew ? '添加 $_name' : _name),
        actions: [
          if (!_isNew) IconButton(tooltip: '删除', onPressed: _remove, icon: const Icon(Icons.delete_outline_rounded)),
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
                            ? 'Pi SDK 内置服务商'
                            : (_apiLabels[_api] ?? _api),
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: Space.xl),
            _Step(
              n: 1,
              title: '连接',
              done: _configured,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_needsKey)
                  TextField(
                    controller: _key,
                    obscureText: !_showKey,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: _configured ? '已保存（${_registered?['key_hint'] ?? ''}），输入新值以替换' : '粘贴你的密钥',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: '粘贴',
                          onPressed: () async {
                            final d = await Clipboard.getData(Clipboard.kTextPlain);
                            if (d?.text != null) setState(() => _key.text = d!.text!.trim());
                          },
                          icon: const Icon(Icons.content_paste_rounded),
                        ),
                        IconButton(
                          tooltip: _showKey ? '隐藏' : '显示',
                          onPressed: () => setState(() => _showKey = !_showKey),
                          icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ]),
                    ),
                  )
                else
                  Text('本地服务通常不需要密钥。确认服务已在本机启动。', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                if (_keyUrl.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => openPath(_keyUrl),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(_needsKey ? '还没有密钥？去 $_name 获取' : '下载 $_name'),
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
                        Text('高级', style: tt.labelLarge?.copyWith(color: cs.primary)),
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
                              decoration: const InputDecoration(labelText: '接口协议'),
                              items: [for (final e in _apiLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                              onChanged: (v) => setState(() => _api = v ?? _api),
                            ),
                            const SizedBox(height: Space.sm),
                            TextField(
                              controller: _id,
                              enabled: _isNew,
                              decoration: const InputDecoration(labelText: '服务 ID', helperText: '本地标识，字母数字及 . _ -'),
                            ),
                          ]),
                  ),
                ],
              ]),
            ),
            _Step(n: 2, title: '模型', done: _builtin ? _configured : _chosen.isNotEmpty, child: _builtin ? _builtinModels(context) : _customModels(context)),
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
                      _builtin ? '保存后会测试一次连接' : '已选 ${_chosen.length} 个模型 · 保存后测试连接',
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
            label: Text(_isNew ? '保存并测试' : '保存'),
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
      Text('Pi SDK 已内置这家的模型目录，填好密钥即可使用。点模型可设为助手默认。', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
      if (list.length > 80) Text('还有 ${list.length - 80} 个，搜索以缩小范围', style: tt.bodySmall),
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
          hintText: '搜索模型',
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
        Text('已选择', style: tt.labelLarge),
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
          label: Text(canFetch ? '从服务商获取模型列表' : '填写密钥后获取模型列表'),
        ),
        if (_catalogId != null)
          OutlinedButton.icon(
            onPressed: _loadingModels ? null : _fromCatalog,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('从 models.dev 选择'),
          ),
      ]),
      if (_modelsError != null) ...[
        const SizedBox(height: Space.sm),
        Text(_modelsError!, style: tt.bodySmall?.copyWith(color: cs.error)),
        if (_catalogId != null) Text('这家服务可能不提供模型列表接口，可以改从 models.dev 目录选择或手动添加。', style: tt.bodySmall),
      ],
      if (offered != null) ...[
        const SizedBox(height: Space.md),
        Row(children: [
          Expanded(child: _searchField(context)),
          const SizedBox(width: Space.sm),
          Text('${offered.length} 个 · 来自$_offeredFrom', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: Space.xs),
        Container(
          constraints: const BoxConstraints(maxHeight: 440),
          decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(Corners.lg)),
          child: offered.isEmpty
              ? Padding(padding: const EdgeInsets.all(Space.lg), child: Text('没有匹配的模型', style: tt.bodyMedium))
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
                      subtitle: m['known'] == false ? Text('models.dev 未收录', style: tt.labelSmall?.copyWith(color: cs.outline)) : ModelBadges(m: m, dense: true),
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
            decoration: const InputDecoration(isDense: true, labelText: '手动添加模型 ID', hintText: '例如 deepseek-chat'),
          ),
        ),
        const SizedBox(width: Space.sm),
        IconButton.filledTonal(onPressed: _addManual, icon: const Icon(Icons.add_rounded)),
      ]),
      const SizedBox(height: Space.xs),
      Text('价格（美元 / 百万 token）、上下文长度和能力标签来自 models.dev，保存时写入 Pi 的模型配置，用于上下文管理和用量统计。',
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
