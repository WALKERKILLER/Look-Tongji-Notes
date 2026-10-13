import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';

const _tokenPage = 'https://mineru.net/apiManage/token';

String _date(DateTime d) => '${d.year}年${d.month}月${d.day}日';

/// MinerU courseware parsing: API token, options and today's page quota.
/// The token stays sealed in lookd; only its last four characters come back.
class MinerUSettings extends StatefulWidget {
  const MinerUSettings({super.key});
  @override
  State<MinerUSettings> createState() => _MinerUSettingsState();
}

class _MinerUSettingsState extends State<MinerUSettings> {
  Map<String, dynamic>? _st;
  final _token = TextEditingController();
  bool _editing = false, _busy = false, _obscure = true;
  String? _test;
  bool? _testOk;

  Api get _api => context.read<AppState>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = (await _api.get('/api/mineru') as Map).cast<String, dynamic>();
      if (mounted) setState(() => _st = r);
    } catch (_) {}
  }

  Future<void> _put(Map<String, dynamic> body) async {
    try {
      final r = (await _api.put('/api/mineru', body) as Map).cast<String, dynamic>();
      if (mounted) setState(() => _st = r);
    } catch (e) {
      if (mounted) showSnack(context, '保存失败：$e');
    }
  }

  Future<void> _saveToken() async {
    final t = _token.text.trim();
    if (t.isEmpty) return;
    setState(() => _busy = true);
    await _put({'token': t});
    _token.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editing = false;
    });
    _runTest();
  }

  Future<void> _runTest() async {
    setState(() {
      _busy = true;
      _test = null;
      _testOk = null;
    });
    try {
      final r = (await _api.post('/api/mineru/test', null, const Duration(seconds: 30)) as Map).cast<String, dynamic>();
      _testOk = r['ok'] == true;
      _test = _testOk! ? '连接正常' : '${r['error']}';
    } catch (e) {
      _testOk = false;
      _test = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final st = _st;
    if (st == null) return const Padding(padding: EdgeInsets.all(Space.lg), child: Center(child: CircularProgressIndicator()));
    final configured = st['configured'] == true;
    final opts = ((st['options'] as Map?) ?? const {}).cast<String, dynamic>();
    final used = (st['today_pages'] as num?)?.toInt() ?? 0;
    final daily = (st['daily_pages'] as num?)?.toInt() ?? 1000;
    final files = (st['today_files'] as num?)?.toInt() ?? 0;
    final exp = (st['token_exp'] as num?)?.toInt() ?? 0;
    final recent = jsonList(st['recent']).map((e) => (e as Map).cast<String, dynamic>()).toList();
    final expAt = exp > 0 ? DateTime.fromMillisecondsSinceEpoch(exp * 1000) : null;
    final expDays = expAt?.difference(DateTime.now()).inDays;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Text('上传的课件（PDF、PPT、Word、图片）交给 MinerU 解析成 Markdown，保留公式、表格和图片，可以全文阅读，也能让助手引用。',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.6)),
      ),
      const SizedBox(height: Space.sm),
      // Token card
      Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Corners.lg)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(Corners.sm), child: Image.asset('assets/brands/mineru.png', width: 36, height: 36)),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('MinerU', style: tt.titleMedium),
                Text(
                  configured ? '精准解析 · Token ••••${st['token_tail'] ?? ''}' : '未配置 Token · 使用免登录的轻量解析',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ]),
            ),
            if (configured && !_editing) ...[
              TextButton(onPressed: _busy ? null : _runTest, child: const Text('测试')),
              IconButton(tooltip: '更换 Token', onPressed: () => setState(() => _editing = true), icon: const Icon(Icons.edit_outlined)),
            ],
          ]),
          if (expAt != null && !_editing)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm, left: 48),
              child: Text(
                expDays! < 0 ? 'Token 已于 ${_date(expAt)} 过期，请重新生成' : 'Token 有效期至 ${_date(expAt)}${expDays < 14 ? '（还剩 $expDays 天）' : ''}',
                style: tt.bodySmall?.copyWith(color: expDays < 14 ? cs.error : cs.onSurfaceVariant),
              ),
            ),
          if (_test != null && !_editing)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm, left: 48),
              child: Row(children: [
                Icon(_testOk! ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 16, color: _testOk! ? cs.primary : cs.error),
                const SizedBox(width: Space.xs),
                Expanded(child: Text(_test!, style: tt.bodySmall?.copyWith(color: _testOk! ? cs.primary : cs.error))),
              ]),
            ),
          AnimatedSize(
            duration: Motion.medium2,
            curve: Motion.emphasized,
            alignment: Alignment.topCenter,
            child: !configured || _editing
                ? Padding(
                    padding: const EdgeInsets.only(top: Space.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        controller: _token,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        onSubmitted: (_) => _saveToken(),
                        decoration: InputDecoration(
                          labelText: 'API Token',
                          hintText: '在 MinerU 官网「API 管理」中创建',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      Row(children: [
                        TextButton.icon(
                          onPressed: () => launchUrl(Uri.parse(_tokenPage)),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text('获取 Token'),
                        ),
                        const Spacer(),
                        if (configured) ...[
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    await _put({'token': ''});
                                    if (mounted) setState(() => _editing = false);
                                  },
                            style: TextButton.styleFrom(foregroundColor: cs.error),
                            child: const Text('移除'),
                          ),
                          TextButton(onPressed: () => setState(() => _editing = false), child: const Text('取消')),
                        ],
                        const SizedBox(width: Space.xs),
                        FilledButton(onPressed: _busy ? null : _saveToken, child: const Text('保存')),
                      ]),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
      const SizedBox(height: Space.lg),
      // Quota
      if (configured) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('今日额度', style: tt.titleSmall),
          const Spacer(),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '$used', style: tt.titleMedium?.copyWith(color: used >= daily ? cs.error : cs.onSurface)),
              TextSpan(text: ' / $daily 页', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ]),
        const SizedBox(height: Space.sm),
        LinearProgressIndicator(
          value: (used / daily).clamp(0.0, 1.0),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          color: used >= daily ? cs.error : null,
        ),
        const SizedBox(height: Space.xs),
        Text(
          '今天解析了 $files 个文件。高优先级额度每天 $daily 页，超出后排队变慢；单文件上限 ${fmtBytes((st['max_bytes'] as num?) ?? 0)}、${st['max_pages'] ?? 200} 页。额度由本机按解析结果统计，以官网为准。',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: Space.lg),
      ] else ...[
        Text('轻量解析不需要 Token，但单文件限 10 MB、20 页，输出不含图片。配置 Token 后使用精准解析（每天 1000 页高优先级额度）。',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: Space.lg),
      ],
      // Options
      if (configured) ...[
        Text('解析模型', style: tt.titleSmall),
        const SizedBox(height: Space.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'vlm', label: Text('VLM 精准'), icon: Icon(Icons.auto_awesome_outlined)),
            ButtonSegment(value: 'pipeline', label: Text('Pipeline'), icon: Icon(Icons.account_tree_outlined)),
          ],
          selected: {'${opts['model'] ?? 'vlm'}'},
          onSelectionChanged: (v) => _put({'options': {...opts, 'model': v.first}}),
        ),
        const SizedBox(height: Space.xs),
        Text(
          opts['model'] == 'pipeline' ? 'Pipeline：传统版面分析，速度快、更稳定，适合排版简单的讲义。' : 'VLM：视觉大模型，公式、表格和复杂版面效果更好，推荐。',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('强制 OCR'),
          subtitle: const Text('扫描版或文字无法复制的 PDF 打开'),
          value: opts['ocr'] == true,
          onChanged: (v) => _put({'options': {...opts, 'ocr': v}}),
        ),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('上传后自动解析'),
        subtitle: const Text('关闭后需要在课件卡片上手动点「解析」'),
        value: st['auto'] == true,
        onChanged: (v) => _put({'auto': v}),
      ),
      if (recent.isNotEmpty) ...[
        const SizedBox(height: Space.sm),
        Text('最近解析', style: tt.titleSmall),
        const SizedBox(height: Space.xs),
        for (final u in recent.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(u['ok'] == true ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 16, color: u['ok'] == true ? cs.primary : cs.error),
              const SizedBox(width: Space.sm),
              Expanded(child: Text('${u['file']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall)),
              Text(
                [
                  if (u['ok'] == true) '${u['pages']} 页',
                  u['mode'] == 'flash' ? '轻量' : '精准',
                  fmtRelative(DateTime.fromMillisecondsSinceEpoch(((u['at'] as num?) ?? 0).toInt() * 1000)),
                ].join(' · '),
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ]),
          ),
      ],
    ]);
  }
}
