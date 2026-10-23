import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import 'settings_common.dart';

/// One-way export of the library into an Obsidian vault
/// (`POST /api/library/obsidian`, settings `obsidian.*`).
/// Contract: docs/specs/0012-obsidian-export.md
class ObsidianPage extends StatefulWidget {
  const ObsidianPage({super.key, required this.settings});
  final ServerSettings settings;
  @override
  State<ObsidianPage> createState() => _ObsidianPageState();
}

class _ObsidianPageState extends State<ObsidianPage> {
  final _vault = TextEditingController();
  final _folder = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void didUpdateWidget(ObsidianPage old) {
    super.didUpdateWidget(old);
    _fill();
  }

  /// Takes the saved values once they arrive, without clobbering typing.
  void _fill() {
    if (_vault.text.isEmpty) _vault.text = '${widget.settings.values['obsidian.vault'] ?? ''}';
    if (_folder.text.isEmpty) _folder.text = '${widget.settings.values['obsidian.folder'] ?? ''}';
  }

  @override
  void dispose() {
    _vault.dispose();
    _folder.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final dir = await pickDirectory(context, initial: _vault.text.trim(), title: 'Obsidian 仓库');
    if (dir == null || !mounted) return;
    _vault.text = dir;
    await _saveAndTell();
  }

  /// Saves vault and folder in one request; throws when that fails.
  Future<void> _save(String vault, String folder) async {
    await context.read<AppState>().api.put('/api/settings', {'obsidian.vault': vault, 'obsidian.folder': folder});
    widget.settings
      ..set('obsidian.vault', vault)
      ..set('obsidian.folder', folder);
  }

  Future<void> _saveAndTell({bool quiet = false}) async {
    try {
      await _save(_vault.text.trim(), _folder.text.trim());
      if (!quiet && mounted) showSnack(context, '已保存');
    } catch (e) {
      if (mounted) showSnack(context, '保存失败：$e');
    }
  }

  Future<void> _export() async {
    final vault = _vault.text.trim(), folder = _folder.text.trim();
    if (vault.isEmpty) {
      showSnack(context, '先选择 Obsidian 仓库文件夹');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = context.read<AppState>().api;
      await _save(vault, folder);
      // Export exactly what is on screen, not whatever was saved before.
      final r = await api.post('/api/library/obsidian', {'vault': vault, 'folder': folder}, const Duration(minutes: 5)) as Map;
      if (!mounted) return;
      final conflicts = (r['conflicts'] as List?)?.length ?? 0;
      final parts = ['已导出：新写入 ${r['written']}，未变 ${r['unchanged']}，清理 ${r['removed']}'];
      if (conflicts > 0) parts.add('$conflicts 个文件在 Obsidian 中改过，已保留你的版本（笔记的新版本另存为“(Look Studio)”副本）');
      if (r['vault'] != true) parts.add('目标文件夹不是 Obsidian 仓库（没有 .obsidian），仍已导出');
      showSnack(context, parts.join('；'));
    } catch (e) {
      if (mounted) showSnack(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Makes `lookstudio://` links open this app: a user desktop entry that
  /// handles the scheme, set as the default with xdg-mime.
  Future<void> _registerLinks() async {
    const name = 'cn.lookstudio.look_studio-handler.desktop';
    try {
      final home = Platform.environment['HOME'] ?? '';
      final dir = Directory(p.join(home, '.local', 'share', 'applications'));
      await dir.create(recursive: true);
      final exe = Platform.resolvedExecutable.replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}');
      await File(p.join(dir.path, name)).writeAsString('[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Look Studio\n'
          'Exec="$exe" %u\n'
          'NoDisplay=true\n'
          'MimeType=x-scheme-handler/lookstudio;\n');
      final r = await Process.run('xdg-mime', ['default', name, 'x-scheme-handler/lookstudio']);
      try {
        await Process.run('update-desktop-database', [dir.path]);
      } on ProcessException {
        // Optional; xdg-mime alone is enough on most desktops.
      }
      if (!mounted) return;
      showSnack(context, r.exitCode == 0 ? '已注册：点击 lookstudio:// 链接会打开 Look Studio' : '已写入 $name，但 xdg-mime 失败：${r.stderr}');
    } catch (e) {
      if (mounted) showSnack(context, '注册失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final v = widget.settings.values;
        final vault = '${v['obsidian.vault'] ?? ''}';
        final auto = v['obsidian.auto'] == true;
        return SettingsSubpage(title: 'Obsidian', children: [
          IntegrationHeader(
            mark: const BrandMark('assets/brands/obsidian.svg', size: 56),
            title: 'Obsidian',
            on: vault.isNotEmpty,
            status: vault.isEmpty ? '未设置仓库' : '导出到 ${p.basename(vault)}${auto ? ' · 自动' : ''}',
            body: '把课程库单向导出到 Obsidian 仓库的一个文件夹：总的“课程库”页，每门课一个文件夹，里面分“笔记”（按节次，含引用的 PPT 和课件）和“转写稿”。点击时间戳会回到 Look Studio；在 Obsidian 里改过的文件不会被覆盖。',
          ),
          SettingsGroup(title: '位置', children: [
            const SizedBox(height: Space.sm),
            TextField(
              controller: _vault,
              decoration: InputDecoration(
                labelText: 'Obsidian 仓库',
                hintText: '/home/me/Notes',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(tooltip: '选择文件夹', onPressed: _pick, icon: const Icon(Icons.folder_open_rounded)),
              ),
              onSubmitted: (_) => _saveAndTell(quiet: true),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _folder,
              decoration: const InputDecoration(labelText: '仓库内的文件夹', hintText: 'LookStudio', border: OutlineInputBorder(), helperText: '只写入这个文件夹，仓库里的其他笔记不受影响'),
              onSubmitted: (_) => _saveAndTell(quiet: true),
            ),
            const SizedBox(height: Space.sm),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _saveAndTell, child: const Text('保存位置'))),
          ]),
          SettingsGroup(title: '导出', children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('笔记变化后自动导出'),
              subtitle: const Text('保存或删除笔记后几秒内刷新'),
              value: auto,
              onChanged: (on) async {
                try {
                  await widget.settings.put('obsidian.auto', on);
                } catch (e) {
                  if (context.mounted) showSnack(context, '保存失败：$e');
                }
              },
            ),
            const SizedBox(height: Space.sm),
            Row(children: [
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.ios_share_rounded),
                label: Text(_busy ? '正在导出' : '立即导出'),
              ),
            ]),
          ]),
          if (Platform.isLinux)
            SettingsGroup(title: '回到 Look Studio', children: [
              Text('导出的时间戳和课次链接是 lookstudio:// 链接。注册后，在 Obsidian 里点击会打开对应的课和时刻。',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: Space.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(onPressed: _registerLinks, icon: const Icon(Icons.link_rounded), label: const Text('注册 lookstudio:// 链接')),
              ),
            ]),
        ]);
      },
    );
  }
}
