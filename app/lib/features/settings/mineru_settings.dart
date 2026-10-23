import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';
import '../../l10n/l10n.dart';

const _tokenPage = 'https://mineru.net/apiManage/token';

String _date(DateTime d) => l10n.dateYearMonthDay(d.year, d.month, d.day);

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
      if (mounted) showSnack(context, l10n.commonSaveFailed(e));
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
      _test = _testOk! ? l10n.commonConnectionOk : '${r['error']}';
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
        child: Text(l10n.mineruIntro,
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
                  configured ? l10n.mineruPrecise(st['token_tail'] ?? '') : l10n.mineruLite,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ]),
            ),
            if (configured && !_editing) ...[
              TextButton(onPressed: _busy ? null : _runTest, child: Text(l10n.commonTest)),
              IconButton(tooltip: l10n.mineruChangeToken, onPressed: () => setState(() => _editing = true), icon: const Icon(Icons.edit_outlined)),
            ],
          ]),
          if (expAt != null && !_editing)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm, left: 48),
              child: Text(
                expDays! < 0 ? l10n.mineruTokenExpired(_date(expAt)) : l10n.mineruTokenExpires(_date(expAt), expDays < 14 ? l10n.mineruTokenDaysLeft(expDays) : ''),
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
                          hintText: l10n.mineruTokenHint,
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
                          label: Text(l10n.mineruGetToken),
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
                            child: Text(l10n.commonRemove),
                          ),
                          TextButton(onPressed: () => setState(() => _editing = false), child: Text(l10n.commonCancel)),
                        ],
                        const SizedBox(width: Space.xs),
                        FilledButton(onPressed: _busy ? null : _saveToken, child: Text(l10n.commonSave)),
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
          Text(l10n.mineruQuotaToday, style: tt.titleSmall),
          const Spacer(),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '$used', style: tt.titleMedium?.copyWith(color: used >= daily ? cs.error : cs.onSurface)),
              TextSpan(text: l10n.mineruQuotaPages(daily), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
          l10n.mineruQuotaBody(files, daily, fmtBytes((st['max_bytes'] as num?) ?? 0), st['max_pages'] ?? 200),
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: Space.lg),
      ] else ...[
        Text(l10n.mineruLiteBody,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: Space.lg),
      ],
      // Options
      if (configured) ...[
        Text(l10n.mineruModel, style: tt.titleSmall),
        const SizedBox(height: Space.sm),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'vlm', label: Text(l10n.mineruVlm), icon: Icon(Icons.auto_awesome_outlined)),
            ButtonSegment(value: 'pipeline', label: Text('Pipeline'), icon: Icon(Icons.account_tree_outlined)),
          ],
          selected: {'${opts['model'] ?? 'vlm'}'},
          onSelectionChanged: (v) => _put({'options': {...opts, 'model': v.first}}),
        ),
        const SizedBox(height: Space.xs),
        Text(
          opts['model'] == 'pipeline' ? l10n.mineruPipelineHint : l10n.mineruVlmHint,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.mineruForceOcr),
          subtitle: Text(l10n.mineruForceOcrHint),
          value: opts['ocr'] == true,
          onChanged: (v) => _put({'options': {...opts, 'ocr': v}}),
        ),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.mineruAutoParse),
        subtitle: Text(l10n.mineruAutoParseHint),
        value: st['auto'] == true,
        onChanged: (v) => _put({'auto': v}),
      ),
      if (recent.isNotEmpty) ...[
        const SizedBox(height: Space.sm),
        Text(l10n.mineruRecent, style: tt.titleSmall),
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
                  if (u['ok'] == true) l10n.commonPages(u['pages']),
                  u['mode'] == 'flash' ? l10n.mineruModeLite : l10n.mineruModePrecise,
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
