import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/states.dart';

/// One-way export of the library into an Obsidian vault
/// (`POST /api/library/obsidian`, settings `obsidian.*`).
class ObsidianSettings extends StatefulWidget {
  const ObsidianSettings({super.key, required this.server, required this.put});
  final Map<String, dynamic> server;
  final Future<void> Function(String key, Object? value) put;
  @override
  State<ObsidianSettings> createState() => _ObsidianSettingsState();
}

class _ObsidianSettingsState extends State<ObsidianSettings> {
  final _vault = TextEditingController();
  final _folder = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void didUpdateWidget(ObsidianSettings old) {
    super.didUpdateWidget(old);
    _fill();
  }

  /// Takes the saved values once they arrive, without clobbering typing.
  void _fill() {
    if (_vault.text.isEmpty) _vault.text = '${widget.server['obsidian.vault'] ?? ''}';
    if (_folder.text.isEmpty) _folder.text = '${widget.server['obsidian.folder'] ?? ''}';
  }

  @override
  void dispose() {
    _vault.dispose();
    _folder.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final dir = await getDirectoryPath(confirmButtonText: '选择');
    if (dir == null || !mounted) return;
    _vault.text = dir;
    await _saveAndTell();
  }

  /// Saves vault and folder in one request; throws when that fails.
  Future<void> _save(String vault, String folder) =>
      context.read<AppState>().api.put('/api/settings', {'obsidian.vault': vault, 'obsidian.folder': folder});

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
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Obsidian', style: tt.titleSmall),
      const SizedBox(height: Space.xs),
      Text('把课程库单向导出到 Obsidian 仓库的子文件夹：一个总的“课程库”页，每门课一个文件夹，里面分“笔记”（按节次分文件夹，含引用的 PPT、课件）和“转写稿”。时间戳点击后回到 Look Studio；在 Obsidian 里改过的文件不会被覆盖。',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: Space.md),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _vault,
            decoration: const InputDecoration(labelText: 'Obsidian 仓库文件夹（绝对路径）', isDense: true),
            onSubmitted: (_) => _saveAndTell(quiet: true),
          ),
        ),
        IconButton(tooltip: '选择文件夹', onPressed: _pick, icon: const Icon(Icons.folder_open_rounded)),
      ]),
      const SizedBox(height: Space.md),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _folder,
            decoration: const InputDecoration(labelText: '导出到仓库内的文件夹', hintText: 'LookStudio', isDense: true),
            onSubmitted: (_) => _saveAndTell(quiet: true),
          ),
        ),
        const SizedBox(width: Space.sm),
        FilledButton.tonal(onPressed: _saveAndTell, child: const Text('保存')),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('笔记变化后自动导出'),
        subtitle: const Text('保存或删除笔记后几秒内刷新导出'),
        value: widget.server['obsidian.auto'] == true,
        onChanged: (v) => widget.put('obsidian.auto', v),
      ),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.ios_share_rounded),
          label: const Text('立即导出'),
        ),
        if (Platform.isLinux)
          OutlinedButton.icon(
            onPressed: _registerLinks,
            icon: const Icon(Icons.link_rounded),
            label: const Text('注册 lookstudio:// 链接'),
          ),
      ]),
    ]);
  }
}
