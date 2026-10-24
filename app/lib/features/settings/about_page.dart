import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/look_logo.dart';
import 'settings_common.dart';

/// The repository Look Studio is built from; its releases carry the app.
const repoSlug = 'WALKERKILLER/Look-Tongji-Notes';
const repoUrl = 'https://github.com/$repoSlug/tree/app';

/// A Look Studio release on GitHub (tag `studio-v<version>`).
class Release {
  Release(this.version, this.page, this.publishedAt, this.assets);
  final String version;
  final String page;
  final DateTime? publishedAt;

  /// Asset file name → download address.
  final Map<String, String> assets;

  /// This platform's installer, or null where the user picks a package
  /// format (Linux) on the release page.
  String? get download {
    final suffix = switch (Platform.operatingSystem) {
      'android' => Abi.current() == Abi.androidX64 ? 'android-x86_64.apk' : 'android-arm64-v8a.apk',
      'windows' => 'windows-x64-setup.exe',
      'macos' => 'macos-universal.dmg',
      _ => null,
    };
    if (suffix == null) return null;
    for (final e in assets.entries) {
      if (e.key.endsWith(suffix)) return e.value;
    }
    return null;
  }
}

/// Orders versions such as `0.2.0` and `0.2.0-beta.1`; a pre-release comes
/// before its release (semantic versioning).
int compareVersions(String a, String b) {
  (List<String>, List<String>) split(String v) {
    final i = v.indexOf('-');
    return (
      (i < 0 ? v : v.substring(0, i)).split('.'),
      i < 0 ? const <String>[] : v.substring(i + 1).split('.'),
    );
  }

  int part(String x, String y) {
    final nx = int.tryParse(x), ny = int.tryParse(y);
    if (nx != null && ny != null) return nx.compareTo(ny);
    if (nx != null) return -1; // numeric identifiers sort first
    if (ny != null) return 1;
    return x.compareTo(y);
  }

  final (ca, pa) = split(a);
  final (cb, pb) = split(b);
  for (var i = 0; i < 3; i++) {
    final c = (int.tryParse(i < ca.length ? ca[i] : '0') ?? 0).compareTo(int.tryParse(i < cb.length ? cb[i] : '0') ?? 0);
    if (c != 0) return c;
  }
  if (pa.isEmpty != pb.isEmpty) return pa.isEmpty ? 1 : -1;
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final c = part(pa[i], pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

/// The newest published release after [current] in GitHub's release list.
/// Pre-releases count only for someone already on a pre-release.
Release? newerRelease(List releases, String current) {
  final pre = current.contains('-');
  Release? best;
  for (final r in releases.cast<Map>()) {
    final tag = '${r['tag_name'] ?? ''}';
    if (r['draft'] == true || !tag.startsWith('studio-v') || (r['prerelease'] == true && !pre)) continue;
    final v = tag.substring('studio-v'.length);
    if (compareVersions(v, current) <= 0 || (best != null && compareVersions(v, best.version) <= 0)) continue;
    best = Release(v, '${r['html_url']}', DateTime.tryParse('${r['published_at']}')?.toLocal(), {
      for (final a in (r['assets'] as List? ?? const []).cast<Map>()) '${a['name']}': '${a['browser_download_url']}',
    });
  }
  return best;
}

Future<List> _fetchReleases() async {
  final r = await http.get(Uri.parse('https://api.github.com/repos/$repoSlug/releases?per_page=30'),
      headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode}');
  return jsonDecode(utf8.decode(r.bodyBytes)) as List;
}

enum _Check { idle, checking, latest, newer, failed }

/// Settings → 关于: version, update check, repository and feedback.
class AboutSection extends StatefulWidget {
  const AboutSection({super.key, this.fetchReleases = _fetchReleases, this.open = _open});

  /// GitHub's release list; replaced in tests.
  final Future<List> Function() fetchReleases;

  /// Opens a web address; replaced in tests.
  final Future<void> Function(String url) open;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class _AboutSectionState extends State<AboutSection> {
  _Check _state = _Check.idle;
  Release? _release;
  Object? _error;

  String get _version => '${context.read<AppState?>()?.health['version'] ?? ''}';

  Future<void> _check() async {
    setState(() => _state = _Check.checking);
    try {
      final r = newerRelease(await widget.fetchReleases(), _version);
      if (mounted) {
        setState(() {
          _release = r;
          _state = r == null ? _Check.latest : _Check.newer;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _state = _Check.failed;
        });
      }
    }
  }

  String get _feedbackUrl {
    final body = l10n.aboutFeedbackBody(_version, '${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    return Uri.https('github.com', '/$repoSlug/issues/new', {'body': body}).toString();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final version = '${context.select<AppState?, Object?>((s) => s?.health['version']) ?? ''}';
    final release = _release;
    final status = switch (_state) {
      _Check.idle => l10n.aboutCheckHint,
      _Check.checking => l10n.aboutChecking,
      _Check.latest => l10n.aboutUpToDate,
      _Check.newer => l10n.aboutNewVersion(release!.version, fmtRelative(release.publishedAt ?? DateTime.now())),
      _Check.failed => l10n.aboutCheckFailed(_error!),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: Space.xxl),
      _Hero(version: version),
      SettingsGroup(title: l10n.aboutUpdates, icon: Icons.system_update_alt_rounded, children: [
        Row(children: [
          Icon(
            switch (_state) { _Check.latest => Icons.check_circle_outline_rounded, _Check.newer => Icons.new_releases_outlined, _Check.failed => Icons.error_outline_rounded, _ => Icons.info_outline_rounded },
            size: 20,
            color: switch (_state) { _Check.newer => cs.primary, _Check.failed => cs.error, _ => cs.onSurfaceVariant },
          ),
          const SizedBox(width: Space.md),
          Expanded(child: Text(status, style: tt.bodyMedium?.copyWith(color: _state == _Check.failed ? cs.error : null))),
        ]),
        const SizedBox(height: Space.md),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          if (release != null && _state == _Check.newer) ...[
            FilledButton.icon(
              onPressed: () => widget.open(release.download ?? release.page),
              icon: const Icon(Icons.download_rounded),
              label: Text(l10n.aboutDownload(release.version)),
            ),
            TextButton(onPressed: () => widget.open(release.page), child: Text(l10n.aboutReleaseNotes)),
          ] else
            FilledButton.tonalIcon(
              onPressed: _state == _Check.checking ? null : _check,
              icon: _state == _Check.checking
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded),
              label: Text(l10n.aboutCheckUpdates),
            ),
        ]),
      ]),
      SettingsGroup(title: l10n.aboutLinks, icon: Icons.link_rounded, padding: const EdgeInsets.symmetric(vertical: Space.sm), children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          leading: const Icon(Icons.code_rounded),
          title: Text(l10n.aboutRepo),
          subtitle: Text('github.com/$repoSlug', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => widget.open(repoUrl),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          leading: const Icon(Icons.feedback_outlined),
          title: Text(l10n.aboutFeedback),
          subtitle: Text(l10n.aboutFeedbackHint),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18),
          onTap: () => widget.open(_feedbackUrl),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          leading: const Icon(Icons.description_outlined),
          title: Text(l10n.aboutLicenses),
          subtitle: Text(l10n.aboutLicensesHint),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Look Studio',
            applicationVersion: version,
            applicationIcon: const Padding(padding: EdgeInsets.all(Space.lg), child: LookLogo(size: 64, label: null)),
          ),
        ),
      ]),
      const SizedBox(height: Space.xl),
      // Quiet on purpose: a text button in the footer, the code only on request.
      Center(
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          onPressed: () => showReward(context),
          icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
          label: Text(l10n.aboutReward),
        ),
      ),
      const SizedBox(height: Space.xl),
    ]);
  }
}

/// The logo, name, a line on what the app does, and the version (selectable,
/// marked 预览版 on a pre-release).
class _Hero extends StatelessWidget {
  const _Hero({required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(children: [
      const LookLogo(size: 88),
      const SizedBox(height: Space.lg),
      Text('Look Studio', style: tt.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: Space.xs),
      Text(l10n.aboutTagline, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
      const SizedBox(height: Space.md),
      DecoratedBox(
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Corners.full)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: SelectableText(l10n.aboutVersion(version.isEmpty ? '—' : version), style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
            if (version.contains('-')) ...[
              const SizedBox(width: Space.sm),
              Text(l10n.aboutPreview, style: tt.labelLarge?.copyWith(color: cs.tertiary)),
            ],
          ]),
        ),
      ),
    ]);
  }
}

/// The author's WeChat tip code: a bottom sheet on phones, a dialog elsewhere.
Future<void> showReward(BuildContext context) {
  if (context.isCompact) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const SingleChildScrollView(child: Center(child: _Reward(sheet: true))),
    );
  }
  return showDialog<void>(context: context, builder: (_) => const Dialog(child: _Reward(sheet: false)));
}

class _Reward extends StatelessWidget {
  const _Reward({required this.sheet});
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.xl, sheet ? 0 : Space.xl, Space.xl, Space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.aboutRewardTitle, style: tt.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          Text(l10n.aboutRewardBody, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          const SizedBox(height: Space.xl),
          // The code keeps its own dark card; a hairline separates it from dark surfaces.
          Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Corners.lg),
              border: Border.all(color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Corners.lg),
              child: Image.asset('assets/reward.png', width: 240, height: 240, fit: BoxFit.contain, filterQuality: FilterQuality.medium, semanticLabel: l10n.aboutRewardImage),
            ),
          ),
          if (sheet) ...[
            const SizedBox(height: Space.lg),
            Text(l10n.aboutRewardPhoneHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          ] else ...[
            const SizedBox(height: Space.lg),
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonClose))),
          ],
        ]),
      ),
    );
  }
}
