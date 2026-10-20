import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/lookd_service.dart';
import '../../core/open_path.dart';
import '../../core/profile.dart';
import '../../theme/prefs.dart';
import '../../theme/tokens.dart';
import '../../widgets/report_screen.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../assistant/assistant_controller.dart';
import '../plugins/plugins_page.dart';
import '../profile/profile_dialog.dart';
import '../../shell.dart';
import '../assistant/runtime_setup.dart';
import '../usage/usage_page.dart';
import 'asr_settings.dart';
import 'mineru_settings.dart';
import 'models_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> _server = {};
  final _courseTpl = TextEditingController();
  final _lectureTpl = TextEditingController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _loadServer();
    // Keep the "expires in" label fresh.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _courseTpl.dispose();
    _lectureTpl.dispose();
    super.dispose();
  }

  Future<void> _loadServer() async {
    try {
      final r = (await context.read<AppState>().api.get('/api/settings') as Map?) ?? {};
      if (!mounted) return;
      setState(() => _server = r.cast<String, dynamic>());
      final tpl = _server['library.templates'];
      _courseTpl.text = tpl is Map ? '${tpl['course'] ?? '{title}'}' : '{title}';
      _lectureTpl.text = tpl is Map ? '${tpl['lecture'] ?? '{date} {title}'}' : '{date} {title}';
    } catch (_) {}
  }

  Future<void> _put(String key, Object? value) async {
    setState(() => _server[key] = value);
    try {
      final r = await context.read<AppState>().api.put('/api/settings', {key: value}) as Map?;
      if (r != null && mounted) setState(() => _server = r.cast<String, dynamic>());
    } catch (e) {
      if (mounted) showSnack(context, '保存失败：$e');
    }
  }

  num _num(String k, num d) => (_server[k] as num?) ?? d;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final tt = Theme.of(context).textTheme;
    final pad = compact ? Space.lg : Space.xl;
    return ReportScreen(
      value: const {'screen': '设置'},
      child: ListView(padding: EdgeInsets.fromLTRB(pad, compact ? Space.xl : Space.xxl, pad, Space.huge), children: [
        ContentWidth(
          max: 800,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('设置', style: compact ? tt.headlineMedium : tt.displaySmall),
            const SizedBox(height: Space.xl),
            const _AccountSection(),
            _Section(title: '外观', icon: Icons.palette_outlined, children: [const _Appearance()]),
            _Section(title: '播放', icon: Icons.play_circle_outline_rounded, children: [const _PlayerSettings()]),
            _Section(title: '助手', icon: Icons.auto_awesome_outlined, children: [const _AssistantSettings()]),
            _Section(title: '插件', icon: Icons.extension_outlined, children: [const PluginSettingsSection()]),
            _Section(title: '下载', icon: Icons.download_outlined, children: [_downloads(context)]),
            _Section(title: '转写', icon: Icons.graphic_eq_rounded, children: [AsrSettings(server: _server, put: _put)]),
            _Section(
              title: '课件解析',
              icon: Icons.description_outlined,
              leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.asset('assets/brands/mineru.png', width: 18, height: 18)),
              children: const [MinerUSettings()],
            ),
            _Section(title: '课程库', icon: Icons.folder_outlined, children: [_library(context)]),
            _Section(title: '诊断', icon: Icons.monitor_heart_outlined, children: [const _Diagnostics()]),
          ]),
        ),
      ]),
    );
  }

  Widget _downloads(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final conns = _num('download.max_conns', 8).toDouble();
    final par = _num('download.video_parallel', 2).toDouble();
    final limit = _num('download.rate_limit', 0).toInt();
    final stream = '${_server['download.stream'] ?? ''}';
    const limits = [(0, '不限'), (2 << 20, '2 MB/s'), (5 << 20, '5 MB/s'), (10 << 20, '10 MB/s'), (20 << 20, '20 MB/s')];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SliderTile(
        title: '单个视频的并发连接',
        subtitle: '分段并行下载，支持断点续传；校园网瓶颈时增加连接帮助有限',
        value: conns,
        min: 1,
        max: 16,
        divisions: 15,
        label: '${conns.round()} 路',
        onChanged: (v) => setState(() => _server['download.max_conns'] = v.round()),
        onChangeEnd: (v) => _put('download.max_conns', v.round()),
      ),
      _SliderTile(
        title: '同时下载的视频数',
        value: par,
        min: 1,
        max: 4,
        divisions: 3,
        label: '${par.round()} 个',
        onChanged: (v) => setState(() => _server['download.video_parallel'] = v.round()),
        onChangeEnd: (v) => _put('download.video_parallel', v.round()),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('总速度上限'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final (v, l) in limits) ChoiceChip(label: Text(l), selected: limit == v, onSelected: (_) => _put('download.rate_limit', v)),
          ]),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('下载哪个画面'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Wrap(spacing: Space.sm, children: [
            for (final (v, l) in const [('', '自动'), ('屏幕', '屏幕'), ('教师', '教师'), ('学生', '学生')])
              ChoiceChip(label: Text(l), selected: stream == v, onSelected: (_) => _put('download.stream', v)),
          ]),
        ),
      ),
      Text('自动：优先屏幕（含 PPT），没有时用第一个画面。', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }

  Widget _library(BuildContext context) {
    final daemon = context.watch<LookdService>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('位置'),
        subtitle: Text(daemon.libraryRoot),
        trailing: IconButton(tooltip: '打开', onPressed: () => openPath(daemon.libraryRoot), icon: const Icon(Icons.open_in_new_rounded)),
      ),
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
            await _put('library.templates', {'course': _courseTpl.text.trim(), 'lecture': _lectureTpl.text.trim()});
            if (context.mounted) showSnack(context, '模板已保存');
          },
          child: const Text('保存'),
        ),
      ]),
      const SizedBox(height: Space.lg),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.ios_share_rounded),
        title: const Text('导出为 Look-Tongji-Notes 技能格式'),
        subtitle: const Text('以硬链接生成 raw/<课程>/<节次>/原始数据/ 目录，不额外占空间'),
        onTap: () => _export(context),
      ),
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
          child: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(labelText: '目标目录（绝对路径）', hintText: '/home/me/Look-Tongji-Notes'),
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children, this.leading});
  final String title;
  final IconData icon;

  /// Replaces [icon], e.g. with a brand mark.
  final Widget? leading;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
          child: Row(children: [
            leading ?? Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: Space.sm),
            Text(title, style: tt.titleSmall?.copyWith(color: cs.primary)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, Space.lg),
          decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(Corners.xl)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ]),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.label,
    required this.onChanged,
    this.onChangeEnd,
  });
  final String title;
  final String? subtitle;
  final double value, min, max;
  final int? divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: tt.bodyLarge)),
          Text(label, style: tt.labelLarge?.copyWith(color: cs.primary)),
        ]),
        if (subtitle != null) Text(subtitle!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: label, onChanged: onChanged, onChangeEnd: onChangeEnd),
      ]),
    );
  }
}

// ---------------------------------------------------------------- account

class _AccountSection extends StatelessWidget {
  const _AccountSection();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final a = app.auth;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = a.realname.isNotEmpty ? a.realname : a.username;
    final exp = a.expiresAt;
    final (statusText, statusColor) = switch (a.status) {
      'active' => ('已登录', cs.primary),
      'renewing' => ('正在续期…', cs.tertiary),
      'needs_password' => ('需要重新登录', cs.error),
      _ => ('未登录', cs.onSurfaceVariant),
    };
    final method = switch (a.method) {
      'password' => '密码登录',
      'sso' => '统一认证静默续期',
      'stored' => '已保存的密码续期',
      'cache' => '从本地会话恢复',
      final m => m,
    };
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(Corners.xlIncreased)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Tooltip(
            message: '编辑个人资料',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => showProfileDialog(context),
              child: const UserAvatar(size: 56),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(userDisplayName(context), style: tt.titleLarge?.copyWith(color: cs.onSecondaryContainer), overflow: TextOverflow.ellipsis)),
                IconButton(
                  tooltip: '编辑昵称和头像',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showProfileDialog(context),
                  icon: Icon(Icons.edit_outlined, size: 18, color: cs.onSecondaryContainer),
                ),
              ]),
              Text([if (context.watch<UserProfile>().nickname.isNotEmpty) name, a.username, '同济大学'].join(' · '),
                  style: tt.bodyMedium?.copyWith(color: cs.onSecondaryContainer.withValues(alpha: 0.8))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(Corners.full)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(statusText, style: tt.labelMedium),
            ]),
          ),
        ]),
        const SizedBox(height: Space.lg),
        Text(
          [
            if (exp != null) '凭证 ${fmtUntil(exp)}后到期，会在到期前自动续期',
            if (a.renewedAt != null) '上次续期 ${fmtRelative(a.renewedAt!)}（$method）',
            a.remember ? '已在本机加密保存密码，统一认证失效时用于自动登录' : '未保存密码：统一认证会话失效后需要手动登录',
          ].join('\n'),
          style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer, height: 1.7),
        ),
        if (a.error.isNotEmpty) Text(a.error, style: tt.bodySmall?.copyWith(color: cs.error)),
        const SizedBox(height: Space.md),
        Wrap(spacing: Space.sm, children: [
          FilledButton.tonalIcon(
            onPressed: a.status == 'renewing'
                ? null
                : () async {
                    try {
                      await app.api.post('/api/auth/renew');
                      if (context.mounted) showSnack(context, '已续期');
                    } catch (e) {
                      if (context.mounted) showSnack(context, '续期失败：$e');
                    }
                  },
            icon: const Icon(Icons.autorenew_rounded),
            label: const Text('立即续期'),
          ),
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('退出登录？'),
                  content: const Text('会清除本机保存的会话和密码。已下载的文件不受影响。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
                  ],
                ),
              );
              if (ok == true) await app.logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('退出登录'),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- appearance

class _Appearance extends StatelessWidget {
  const _Appearance();
  @override
  Widget build(BuildContext context) {
    final p = context.watch<UiPrefs>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return FutureBuilder(
      future: DynamicColorPlugin.getAccentColor(),
      builder: (context, snap) {
        final hasSystem = snap.data != null;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: Space.sm),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('跟随系统')),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('浅色')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('深色')),
            ],
            selected: {p.themeMode},
            onSelectionChanged: (s) => p.update((x) => x.themeMode = s.first),
          ),
          const SizedBox(height: Space.md),
          if (hasSystem)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: p.dynamicColor,
              onChanged: (v) => p.update((x) => x.dynamicColor = v),
              title: const Text('使用系统强调色'),
              subtitle: const Text('从桌面主题取色生成配色'),
            ),
          AnimatedOpacity(
            opacity: hasSystem && p.dynamicColor ? 0.4 : 1,
            duration: Motion.medium1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('主题色', style: tt.titleSmall),
              const SizedBox(height: Space.sm),
              Wrap(spacing: Space.md, runSpacing: Space.md, children: [
                for (final (name, c) in kSeedPalette)
                  Tooltip(
                    message: name,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => p.update((x) {
                        x.seed = c;
                        x.dynamicColor = false;
                      }),
                      child: AnimatedContainer(
                        duration: Motion.medium1,
                        curve: Motion.emphasized,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(p.seed.toARGB32() == c.toARGB32() ? Corners.md : 22),
                          border: Border.all(color: p.seed.toARGB32() == c.toARGB32() ? cs.onSurface : Colors.transparent, width: 2),
                        ),
                        child: p.seed.toARGB32() == c.toARGB32() ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: Space.lg),
          Text('配色风格', style: tt.titleSmall),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final e in kVariantLabels.entries)
              ChoiceChip(label: Text(e.value), selected: p.variant == e.key, onSelected: (_) => p.update((x) => x.variant = e.key)),
          ]),
          const SizedBox(height: Space.lg),
          Text('对比度', style: tt.titleSmall),
          const SizedBox(height: Space.sm),
          SegmentedButton<ContrastLevel>(
            segments: [for (final c in ContrastLevel.values) ButtonSegment(value: c, label: Text(c.label))],
            selected: {p.contrast},
            onSelectionChanged: (s) => p.update((x) => x.contrast = s.first),
          ),
          const SizedBox(height: Space.lg),
          DropdownMenu<String?>(
            label: const Text('字体'),
            initialSelection: p.fontFamily,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [for (final (l, f) in kFontChoices) DropdownMenuEntry(value: f, label: l)],
            onSelected: (v) => p.update((x) => x.fontFamily = v),
          ),
          _SliderTile(
            title: '文字大小',
            value: p.textScale,
            min: 0.85,
            max: 1.3,
            divisions: 9,
            label: '${(p.textScale * 100).round()}%',
            onChanged: (v) => p.update((x) => x.textScale = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.compactDensity,
            onChanged: (v) => p.update((x) => x.compactDensity = v),
            title: const Text('紧凑布局'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.reduceMotion,
            onChanged: (v) => p.update((x) => x.reduceMotion = v),
            title: const Text('减少动画'),
          ),
        ]);
      },
    );
  }
}

class _PlayerSettings extends StatelessWidget {
  const _PlayerSettings();
  @override
  Widget build(BuildContext context) {
    final p = context.watch<UiPrefs>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SliderTile(
        title: '默认倍速',
        value: p.defaultSpeed,
        min: 0.5,
        max: 3,
        divisions: 10,
        label: '${p.defaultSpeed}×',
        onChanged: (v) => p.update((x) => x.defaultSpeed = (v * 4).round() / 4),
      ),
      _SliderTile(
        title: '长按快进倍速',
        subtitle: '长按画面或按住 → 键临时加速',
        value: p.boostSpeed,
        min: 1.5,
        max: 4,
        divisions: 10,
        label: '${p.boostSpeed}×',
        onChanged: (v) => p.update((x) => x.boostSpeed = (v * 4).round() / 4),
      ),
      _SliderTile(
        title: '快进 / 快退步长',
        value: p.seekStepSec.toDouble(),
        min: 5,
        max: 30,
        divisions: 5,
        label: '${p.seekStepSec} 秒',
        onChanged: (v) => p.update((x) => x.seekStepSec = v.round()),
      ),
      _SliderTile(
        title: '字幕大小',
        value: p.subtitleScale,
        min: 0.8,
        max: 1.6,
        divisions: 8,
        label: '${(p.subtitleScale * 100).round()}%',
        onChanged: (v) => p.update((x) => x.subtitleScale = v),
      ),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.autoResume, onChanged: (v) => p.update((x) => x.autoResume = v), title: const Text('从上次位置继续')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.showSubtitles, onChanged: (v) => p.update((x) => x.showSubtitles = v), title: const Text('有文字稿时显示字幕')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.slideFollow, onChanged: (v) => p.update((x) => x.slideFollow = v), title: const Text('PPT 跟随播放进度')),
      const SizedBox(height: Space.sm),
      Text('快捷键：空格 播放/暂停 · ←/→ 快退/快进 · ↑/↓ 音量 · [ ] 倍速 · F 全屏 · C 字幕 · B 书签 · P 侧栏 · M 静音',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.6)),
    ]);
  }
}

class _AssistantSettings extends StatelessWidget {
  const _AssistantSettings();
  @override
  Widget build(BuildContext context) {
    final p = context.watch<UiPrefs>();
    final a = context.watch<AssistantController>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.memory_rounded),
        title: const Text('模型与服务商'),
        subtitle: Text(a.selected == null ? '未配置' : '${a.selected!['provider']} / ${a.selected!['model']}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const ModelsPage())),
      ),
      _VisionModelTile(a: a),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.terminal_rounded),
        title: const Text('运行环境'),
        subtitle: Text(a.ready ? 'Node.js 与 Pi SDK 已就绪' : '助手未运行 · 检查或安装 Node.js 与 Pi SDK'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showRuntimeSetup(context),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.insights_outlined),
        title: const Text('用量与费用'),
        subtitle: const Text('按模型、用途和对话查看 token 与估算费用'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const UsagePage())),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.schedule_rounded),
        title: const Text('定时任务'),
        subtitle: const Text('让助手按计划复盘、出题、汇总截止事项'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => ShellScope.of(context).goTo(Tabs.tasks),
      ),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.assistantDocked, onChanged: (v) => p.update((x) => x.assistantDocked = v), title: const Text('宽屏时常驻在右侧')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.chatBubbles, onChanged: (v) => p.update((x) => x.chatBubbles = v), title: const Text('回复使用气泡')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.showThinking, onChanged: (v) => p.update((x) => x.showThinking = v), title: const Text('显示思考过程')),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('流式输出动画'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final (v, l) in const [
              (GptMarkdownAnimation.none, '无'),
              (GptMarkdownAnimation.fade, '淡入'),
              (GptMarkdownAnimation.blurIn, '模糊显现'),
              (GptMarkdownAnimation.typewriter, '打字机'),
              (GptMarkdownAnimation.wave, '波浪'),
            ])
              ChoiceChip(label: Text(l), selected: p.streamAnimation == v, onSelected: (_) => p.update((x) => x.streamAnimation = v)),
          ]),
        ),
      ),
      _SliderTile(
        title: '对话文字大小',
        value: p.chatTextScale,
        min: 0.85,
        max: 1.3,
        divisions: 9,
        label: '${(p.chatTextScale * 100).round()}%',
        onChanged: (v) => p.update((x) => x.chatTextScale = v),
      ),
    ]);
  }
}

/// Picks the model that transcribes slides and figures for text-only chat
/// models (the assistant's "eyes"; it never takes part in the reasoning).
class _VisionModelTile extends StatelessWidget {
  const _VisionModelTile({required this.a});
  final AssistantController a;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vision = '${(a.models?['prefs'] as Map?)?['vision'] ?? ''}';
    final direct = a.selected?['vision'] == true;
    final ready = a.models?['vision_ready'] == true;
    final subtitle = direct
        ? '当前模型可以直接看 PPT 和插图${vision.isEmpty ? '' : '；换成纯文本模型时使用 $vision'}'
        : vision.isEmpty
            ? '当前模型不能看图。选一个识图模型，助手写笔记时才能核对 PPT 和课件插图'
            : ready
                ? '$vision · 为纯文本模型转写 PPT 和插图'
                : '$vision 不可用（检查服务商密钥）';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.image_search_rounded),
      title: const Text('识图模型'),
      subtitle: Text(subtitle, style: TextStyle(color: !direct && (vision.isEmpty || !ready) ? cs.error : null)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _pick(context, vision),
    );
  }

  Future<void> _pick(BuildContext context, String current) async {
    final options = <(String, String, String)>[];
    for (final p in jsonList(a.models?['providers']).whereType<Map>()) {
      for (final m in jsonList(p['models']).whereType<Map>()) {
        if (m['available'] == true && m['vision'] == true) options.add(('${p['id']}/${m['id']}', '${m['name'] ?? m['id']}', '${p['name'] ?? p['id']}'));
      }
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.7,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Text('识图模型', style: Theme.of(c).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
            child: Text('只用来把 PPT 和课件插图转写成文字，交给不能看图的对话模型。结果按图片缓存，同一张图只识别一次。',
                style: Theme.of(c).textTheme.bodySmall?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: RadioGroup<String>(
              groupValue: current,
              onChanged: (v) => Navigator.pop(c, v),
              child: ListView(children: [
                const RadioListTile(value: '', title: Text('不使用')),
                for (final (id, name, provider) in options) RadioListTile(value: id, title: Text(name), subtitle: Text(provider)),
                if (options.isEmpty)
                  const Padding(padding: EdgeInsets.all(Space.xl), child: Text('已配置的服务商里没有支持图片输入的模型。')),
              ]),
            ),
          ),
        ]),
      ),
    );
    if (picked == null || picked == current) return;
    try {
      await a.setPrefs({'vision': picked});
    } catch (e) {
      if (context.mounted) showSnack(context, '保存失败：$e');
    }
  }
}

class _Diagnostics extends StatelessWidget {
  const _Diagnostics();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final daemon = context.watch<LookdService>();
    final tt = Theme.of(context).textTheme;
    final h = app.health;
    final agent = app.agent;
    Widget row(String k, String v, {bool ok = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 18,
                color: ok ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error),
            const SizedBox(width: Space.sm),
            Text(k, style: tt.bodyMedium),
            const Spacer(),
            Flexible(child: Text(v, style: tt.bodySmall, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row('lookd 后台', daemon.state == DaemonState.ready ? 'v${h['version'] ?? ''} · 端口 ${daemon.port}' : daemon.error ?? '启动中',
          ok: daemon.state == DaemonState.ready),
      row('ffmpeg（转写用）', h['ffmpeg'] == true ? '已安装' : '未找到', ok: h['ffmpeg'] == true),
      row('Pi Agent', '${agent['state']}${agent['error'] != null && '${agent['error']}'.isNotEmpty ? ' · ${agent['error']}' : ''}', ok: app.agentReady),
      const SizedBox(height: Space.md),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        OutlinedButton.icon(
          onPressed: () => _logs(context, '后台日志', daemon.log.join('\n')),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('后台日志'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              final r = await app.api.get('/api/agent/status') as Map;
              if (context.mounted) _logs(context, '助手日志', ((r['logs'] as List?) ?? const []).join('\n'));
            } catch (e) {
              if (context.mounted) showSnack(context, '$e');
            }
          },
          icon: const Icon(Icons.smart_toy_outlined, size: 18),
          label: const Text('助手日志'),
        ),
        TextButton.icon(onPressed: daemon.restart, icon: const Icon(Icons.restart_alt_rounded, size: 18), label: const Text('重启后台')),
      ]),
    ]);
  }

  void _logs(BuildContext context, String title, String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 640,
          height: 420,
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(text.isEmpty ? '（空）' : text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            child: const Text('复制'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }
}

