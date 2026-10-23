import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import 'settings_common.dart';
import '../../l10n/l10n.dart';

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
    final dir = await pickDirectory(context, initial: _vault.text.trim(), title: l10n.obsidianVault);
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
      if (!quiet && mounted) showSnack(context, l10n.commonSaved);
    } catch (e) {
      if (mounted) showSnack(context, l10n.commonSaveFailed(e));
    }
  }

  Future<void> _export() async {
    final vault = _vault.text.trim(), folder = _folder.text.trim();
    if (vault.isEmpty) {
      showSnack(context, l10n.obsidianChooseVaultFirst);
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
      final parts = [l10n.obsidianExported(r['written'], r['unchanged'], r['removed'])];
      if (conflicts > 0) parts.add(l10n.obsidianConflicts(conflicts));
      if (r['vault'] != true) parts.add(l10n.obsidianNotVault);
      showSnack(context, parts.join(l10n.listSemicolon));
    } catch (e) {
      if (mounted) showSnack(context, l10n.commonExportFailed(e));
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
      showSnack(context, r.exitCode == 0 ? l10n.linkRegistered : l10n.linkRegisterPartial(name, r.stderr));
    } catch (e) {
      if (mounted) showSnack(context, l10n.linkRegisterFailed(e));
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
            status: vault.isEmpty ? l10n.obsidianNoVault : l10n.obsidianStatus(p.basename(vault), auto ? l10n.commonAutoSuffix : ''),
            body: l10n.obsidianBody,
          ),
          SettingsGroup(title: l10n.commonLocation, children: [
            const SizedBox(height: Space.sm),
            TextField(
              controller: _vault,
              decoration: InputDecoration(
                labelText: l10n.obsidianVault,
                hintText: '/home/me/Notes',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(tooltip: l10n.pickerChooseFolder, onPressed: _pick, icon: const Icon(Icons.folder_open_rounded)),
              ),
              onSubmitted: (_) => _saveAndTell(quiet: true),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _folder,
              decoration: InputDecoration(labelText: l10n.obsidianFolder, hintText: 'LookStudio', border: OutlineInputBorder(), helperText: l10n.obsidianFolderHelper),
              onSubmitted: (_) => _saveAndTell(quiet: true),
            ),
            const SizedBox(height: Space.sm),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _saveAndTell, child: Text(l10n.obsidianSaveLocation))),
          ]),
          SettingsGroup(title: l10n.commonExport, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.obsidianAutoExport),
              subtitle: Text(l10n.obsidianAutoExportHint),
              value: auto,
              onChanged: (on) async {
                try {
                  await widget.settings.put('obsidian.auto', on);
                } catch (e) {
                  if (context.mounted) showSnack(context, l10n.commonSaveFailed(e));
                }
              },
            ),
            const SizedBox(height: Space.sm),
            Row(children: [
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.ios_share_rounded),
                label: Text(_busy ? l10n.commonExporting : l10n.commonExportNow),
              ),
            ]),
          ]),
          if (Platform.isLinux)
            SettingsGroup(title: l10n.obsidianBackLinks, children: [
              Text(l10n.obsidianBackLinksBody,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: Space.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(onPressed: _registerLinks, icon: const Icon(Icons.link_rounded), label: Text(l10n.linkRegister)),
              ),
            ]),
        ]);
      },
    );
  }
}
