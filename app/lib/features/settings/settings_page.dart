import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
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
import '../assistant/bot_avatar.dart';
import '../assistant/bot_page.dart';
import '../assistant/runtime_setup.dart';
import '../usage/usage_page.dart';
import '../canvas/canvas_page.dart';
import 'about_page.dart';
import 'asr_settings.dart';
import 'data_settings.dart';
import 'diagnostics.dart';
import 'knowledge_settings.dart';
import 'mineru_settings.dart';
import 'models_page.dart';
import 'settings_common.dart';
import 'watch_settings.dart';
import '../../l10n/l10n.dart';

/// Opens a settings category from elsewhere (the bot's `open_page settings`).
abstract final class SettingsNav {
  static final section = ValueNotifier<String?>(null);
  static void open(String section) => SettingsNav.section.value = section;
}

/// One row in the list pane and the pane it opens.
class _Category {
  const _Category(this.id, this.title, this.icon, this.summary, this.items);
  final String id, title, summary;
  final IconData icon;

  /// What the pane holds, for search.
  final List<String> items;
}

final _categories = [
  _Category('account', l10n.settingsAccount, Icons.account_circle_outlined, l10n.settingsAccountHint,
      [l10n.authTongji, l10n.authRenewNow, l10n.authSignOut, l10n.settingsProfileKeyword, 'Canvas', l10n.commonSchool, l10n.settingsCanvasKeyword]),
  _Category('appearance', l10n.settingsAppearance, Icons.palette_outlined, l10n.settingsAppearanceHint, [
    l10n.settingsDarkMode, l10n.settingsThemeColor, l10n.settingsSystemAccent, l10n.settingsSchemeStyle, l10n.settingsContrast, l10n.settingsFont, l10n.settingsTextSize, l10n.settingsCompact, l10n.settingsReduceMotion, //
    l10n.settingsDefaultSpeed, l10n.settingsBoostSpeed, l10n.settingsSeekStepKeyword, l10n.settingsSubtitleSize, l10n.settingsResume, l10n.settingsShowSubtitles, l10n.settingsSlidesFollow, l10n.settingsShortcuts,
  ]),
  _Category('assistant', l10n.settingsAssistant, Icons.auto_awesome_outlined, l10n.settingsAssistantHint, [
    l10n.settingsModels, l10n.settingsVisionModel, l10n.settingsBotKeyword, l10n.settingsRuntimeKeyword, l10n.settingsUsage, l10n.commonScheduledTasks, //
    l10n.settingsDockKeyword, l10n.settingsBubblesKeyword, l10n.settingsShowThinking, l10n.settingsStreamAnimation, l10n.settingsChatTextSize, l10n.commonPlugins,
  ]),
  _Category('transfer', l10n.settingsTransfer, Icons.download_outlined, l10n.settingsTransferHint, [
    l10n.settingsConnectionsKeyword, l10n.settingsVideoParallel, l10n.settingsRateLimit, l10n.settingsStream, //
    l10n.assetAsr, l10n.settingsAsrChannels, l10n.settingsLocalModels, l10n.asrDeleteVideo, l10n.settingsMineru,
  ]),
  _Category('knowledge', l10n.settingsKnowledge, Icons.local_library_outlined, l10n.settingsKnowledgeHint,
      ['Obsidian', 'Notion', l10n.settingsLibraryLocation, l10n.knowledgeFolderTemplates, l10n.settingsSkillExport]),
  _Category('data', l10n.settingsData, Icons.cloud_sync_outlined, l10n.settingsDataHint, [
    'WebDAV', l10n.webdavJianguoyun, 'Nextcloud', l10n.dataSyncTitle, l10n.commonAutoSync, l10n.settingsSyncMedia, l10n.backupExport, l10n.backupRestore, l10n.storageTitle, l10n.settingsCleanCache, l10n.storageCompact,
  ]),
  _Category('notifications', l10n.commonNotifications, Icons.notifications_outlined, l10n.settingsNotificationsHint, [l10n.settingsWatchKeyword, l10n.watchCheckNow, l10n.settingsRemindersKeyword]),
  _Category('diagnostics', l10n.settingsDiagnostics, Icons.monitor_heart_outlined, l10n.settingsDiagnosticsHint, [l10n.settingsDaemonKeyword, 'ffmpeg', 'Pi Agent', l10n.diagDaemonLog, l10n.diagAgentLog, l10n.settingsRestartKeyword]),
  _Category('about', l10n.settingsAbout, Icons.info_outline_rounded, l10n.settingsAboutHint,
      [l10n.aboutCheckUpdates, l10n.aboutRepo, l10n.aboutFeedback, 'GitHub', 'OTA']),
];

/// The bot's section names (agent/src/operate.mjs) → categories.
const _sectionAliases = {
  'account': 'account', 'canvas': 'account', //
  'appearance': 'appearance', 'player': 'appearance',
  'assistant': 'assistant', 'models': 'assistant', 'plugins': 'assistant',
  'downloads': 'transfer', 'transcript': 'transfer', 'courseware': 'transfer',
  'knowledge': 'knowledge', 'obsidian': 'knowledge', 'notion': 'knowledge',
  'data': 'data', 'sync': 'data', 'backup': 'data', 'storage': 'data',
  'notifications': 'notifications',
  'diagnostics': 'diagnostics',
  'about': 'about',
};

/// Width from which the list and the open category sit side by side.
const double _twoPaneWidth = 840;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _settings = ServerSettings(context.read<AppState>().api);
  final _query = TextEditingController();
  String _selected = _categories.first.id;
  bool _twoPane = true;

  @override
  void initState() {
    super.initState();
    _settings.load().catchError((_) {});
    SettingsNav.section.addListener(_deepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _deepLink());
  }

  @override
  void dispose() {
    SettingsNav.section.removeListener(_deepLink);
    _settings.dispose();
    _query.dispose();
    super.dispose();
  }

  void _deepLink() {
    final s = SettingsNav.section.value;
    if (s == null || !mounted) return;
    SettingsNav.section.value = null;
    final id = _sectionAliases[s];
    if (id == null) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _query.clear();
    _open(id);
  }

  /// Saves a setting; failures show as a snackbar.
  Future<void> _put(String key, Object? value) async {
    try {
      await _settings.put(key, value);
    } catch (e) {
      if (mounted) showSnack(context, l10n.commonSaveFailed(e));
    }
  }

  void _open(String id) {
    setState(() => _selected = id);
    if (_twoPane) return;
    final c = _categories.firstWhere((c) => c.id == id);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(c.title)),
        body: _pane(c, header: false),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Route transitions paint a background above the shell's Material, so the
    // category tiles need their own to show selection and ink.
    return ReportScreen(
      value: {'screen': l10n.commonSettings},
      child: Material(type: MaterialType.transparency, child: LayoutBuilder(builder: (context, box) {
        _twoPane = box.maxWidth >= _twoPaneWidth;
        if (!_twoPane) return _list(context);
        final c = _categories.firstWhere((c) => c.id == _selected);
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: box.maxWidth >= 1200 ? 360 : 320, child: _list(context)),
          Expanded(
            child: AnimatedSwitcher(
              duration: context.watch<UiPrefs>().reduceMotion ? Duration.zero : Motion.medium2,
              switchInCurve: Motion.emphasizedDecelerate,
              switchOutCurve: Motion.emphasizedAccelerate,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a), child: child),
              ),
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
              child: KeyedSubtree(key: ValueKey(c.id), child: _pane(c, header: true)),
            ),
          ),
        ]);
      })),
    );
  }

  // ---- list pane ----

  Widget _list(BuildContext context) {
    final compact = context.isCompact;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final q = _query.text.trim().toLowerCase();
    final pad = compact ? Space.lg : Space.xl;
    return ListView(padding: EdgeInsets.fromLTRB(_twoPane ? Space.lg : pad, compact ? Space.xl : Space.xxl, _twoPane ? Space.sm : pad, Space.huge), children: [
      ContentWidth(
        max: 720,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.sm),
            child: Text(l10n.commonSettings, style: compact ? tt.headlineMedium : tt.headlineLarge),
          ),
          const SizedBox(height: Space.lg),
          SearchBar(
            controller: _query,
            hintText: l10n.settingsSearch,
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
            leading: const Icon(Icons.search_rounded),
            trailing: [
              if (q.isNotEmpty) IconButton(tooltip: l10n.commonClear, onPressed: () => setState(_query.clear), icon: const Icon(Icons.close_rounded)),
            ],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.lg),
          if (q.isEmpty)
            for (final c in _categories) _CategoryTile(category: c, selected: _twoPane && c.id == _selected, onTap: () => _open(c.id))
          else
            ..._results(context, q),
        ]),
      ),
    ]);
  }

  List<Widget> _results(BuildContext context, String q) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final hits = [
      for (final c in _categories)
        for (final item in [c.title, ...c.items])
          if (item.toLowerCase().contains(q)) (c, item),
    ];
    if (hits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xl),
          child: Text(l10n.settingsNoMatch(_query.text.trim()), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ];
    }
    return [
      for (final (c, item) in hits)
        ListTile(
          shape: const StadiumBorder(),
          leading: Icon(c.icon, color: cs.onSurfaceVariant),
          title: Text(item),
          subtitle: item == c.title ? null : Text(c.title),
          onTap: () => _open(c.id),
        ),
    ];
  }

  // ---- detail pane ----

  Widget _pane(_Category c, {required bool header}) {
    final pad = context.isCompact ? Space.lg : Space.xl;
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final tt = Theme.of(context).textTheme;
        final cs = Theme.of(context).colorScheme;
        return ListView(
          key: PageStorageKey('settings-${c.id}'),
          padding: EdgeInsets.fromLTRB(header ? Space.lg : pad, header ? Space.xxl : Space.sm, header ? Space.xl : pad, Space.huge),
          children: [
            ContentWidth(
              max: 760,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (header) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: Space.xs),
                    child: Text(c.title, style: tt.headlineSmall),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: Space.xs, top: Space.xs),
                    child: Text(c.summary, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ],
                ..._sections(context, c.id),
              ]),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _sections(BuildContext context, String id) {
    final server = _settings.values;
    return switch (id) {
      'account' => [
          const SizedBox(height: Space.xl),
          const _AccountSection(),
          SettingsGroup(title: l10n.settingsSchoolCanvas, icon: Icons.school_outlined, children: [CanvasSettingsEntry()]),
        ],
      'appearance' => [
          SettingsGroup(title: l10n.settingsAppearanceGroup, icon: Icons.palette_outlined, children: [_Appearance()]),
          SettingsGroup(title: l10n.commonPlay, icon: Icons.play_circle_outline_rounded, children: [_PlayerSettings()]),
        ],
      'assistant' => [
          SettingsGroup(title: l10n.commonAssistant, icon: Icons.auto_awesome_outlined, children: [_AssistantSettings()]),
          SettingsGroup(title: l10n.commonPlugins, icon: Icons.extension_outlined, children: [PluginSettingsSection()]),
        ],
      'transfer' => [
          SettingsGroup(title: l10n.commonDownload, icon: Icons.download_outlined, children: [_downloads(context)]),
          SettingsGroup(title: l10n.assetTranscript, icon: Icons.graphic_eq_rounded, children: [AsrSettings(server: server, put: _put)]),
          SettingsGroup(
            title: l10n.assetParse,
            leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.asset('assets/brands/mineru.png', width: 18, height: 18)),
            children: const [MinerUSettings()],
          ),
        ],
      'knowledge' => [KnowledgeSettings(settings: _settings)],
      'data' => const [DataSettings()],
      'notifications' => [
          SettingsGroup(title: l10n.settingsWatchGroup, icon: Icons.notifications_outlined, children: [WatchSettings(server: server, put: _put)]),
        ],
      'about' => const [AboutSection()],
      _ => const [Diagnostics()],
    };
  }

  num _num(String k, num d) => (_settings.values[k] as num?) ?? d;

  Widget _downloads(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final conns = _num('download.max_conns', 8).toDouble();
    final par = _num('download.video_parallel', 2).toDouble();
    final limit = _num('download.rate_limit', 0).toInt();
    final stream = '${_settings.values['download.stream'] ?? ''}';
    final limits = [(0, l10n.commonUnlimited), (2 << 20, '2 MB/s'), (5 << 20, '5 MB/s'), (10 << 20, '10 MB/s'), (20 << 20, '20 MB/s')];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SliderTile(
        title: l10n.settingsConnections,
        subtitle: l10n.settingsConnectionsHint,
        value: conns,
        min: 1,
        max: 16,
        divisions: 15,
        label: l10n.settingsConnectionsValue(conns.round()),
        onChanged: (v) => _settings.set('download.max_conns', v.round()),
        onChangeEnd: (v) => _put('download.max_conns', v.round()),
      ),
      _SliderTile(
        title: l10n.settingsVideoParallel,
        value: par,
        min: 1,
        max: 4,
        divisions: 3,
        label: l10n.settingsVideoParallelValue(par.round()),
        onChanged: (v) => _settings.set('download.video_parallel', v.round()),
        onChangeEnd: (v) => _put('download.video_parallel', v.round()),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.settingsRateLimit),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final (v, l) in limits) ChoiceChip(label: Text(l), selected: limit == v, onSelected: (_) => _put('download.rate_limit', v)),
          ]),
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.settingsStream),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Wrap(spacing: Space.sm, children: [
            for (final (v, l) in [('', l10n.commonAuto), (l10n.streamScreen, l10n.streamScreen), (l10n.streamTeacher, l10n.streamTeacher), (l10n.streamStudent, l10n.streamStudent)])
              ChoiceChip(label: Text(l), selected: stream == v, onSelected: (_) => _put('download.stream', v)),
          ]),
        ),
      ),
      Text(l10n.settingsStreamHint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}

/// A category row. The account row shows who is signed in.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.selected, required this.onTap});
  final _Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final account = category.id == 'account';
    final auth = account ? context.watch<AppState>().auth : null;
    final leading = account
        ? const UserAvatar(size: 40)
        : AnimatedContainer(
            duration: Motion.medium1,
            curve: Motion.emphasized,
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: selected ? cs.surface.withValues(alpha: 0.6) : cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Corners.md)),
            child: Icon(category.icon, size: 22, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xxs),
      child: ListTile(
        shape: const StadiumBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xxs),
        selected: selected,
        selectedTileColor: cs.secondaryContainer,
        selectedColor: cs.onSecondaryContainer,
        leading: leading,
        title: Text(account ? userDisplayName(context) : category.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          account ? l10n.settingsAccountSummary(auth!.status == 'active' ? l10n.authSignedIn : l10n.authSignedOut) : category.summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
      ),
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
      'active' => (l10n.authSignedIn, cs.primary),
      'renewing' => (l10n.authRenewing, cs.tertiary),
      'needs_password' => (l10n.authNeedsSignIn, cs.error),
      _ => (l10n.authSignedOut, cs.onSurfaceVariant),
    };
    final method = switch (a.method) {
      'password' => l10n.authMethodPassword,
      'sso' => l10n.authMethodSso,
      'stored' => l10n.authMethodSavedPassword,
      'cache' => l10n.authMethodRestored,
      final m => m,
    };
    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(Corners.xlIncreased)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Tooltip(
            message: l10n.profileEdit,
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
                  tooltip: l10n.profileEditTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showProfileDialog(context),
                  icon: Icon(Icons.edit_outlined, size: 18, color: cs.onSecondaryContainer),
                ),
              ]),
              Text([if (context.watch<UserProfile>().nickname.isNotEmpty) name, a.username, a.school == 'fudan' ? l10n.schoolFudan : l10n.schoolTongji].join(' · '),
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
            if (exp != null) l10n.authExpires(fmtUntil(exp)),
            if (a.renewedAt != null) l10n.authLastRenewed(fmtRelative(a.renewedAt!), method),
            a.remember ? l10n.authPasswordSaved : l10n.authPasswordNotSaved,
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
                      if (context.mounted) showSnack(context, l10n.authRenewed);
                    } catch (e) {
                      if (context.mounted) showSnack(context, l10n.authRenewFailed(e));
                    }
                  },
            icon: const Icon(Icons.autorenew_rounded),
            label: Text(l10n.authRenewNow),
          ),
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(l10n.authSignOutTitle),
                  content: Text(l10n.authSignOutBody),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.authSignOutAction)),
                  ],
                ),
              );
              if (ok == true) await app.logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: Text(l10n.authSignOut),
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
            segments: [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text(l10n.themeSystem)),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text(l10n.themeLight)),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text(l10n.themeDark)),
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
              title: Text(l10n.settingsUseSystemAccent),
              subtitle: Text(l10n.settingsUseSystemAccentHint),
            ),
          AnimatedOpacity(
            opacity: hasSystem && p.dynamicColor ? 0.4 : 1,
            duration: Motion.medium1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.settingsThemeColor, style: tt.titleSmall),
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
          Text(l10n.settingsSchemeStyle, style: tt.titleSmall),
          const SizedBox(height: Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final e in kVariantLabels.entries)
              ChoiceChip(label: Text(e.value), selected: p.variant == e.key, onSelected: (_) => p.update((x) => x.variant = e.key)),
          ]),
          const SizedBox(height: Space.lg),
          Text(l10n.settingsContrast, style: tt.titleSmall),
          const SizedBox(height: Space.sm),
          SegmentedButton<ContrastLevel>(
            segments: [for (final c in ContrastLevel.values) ButtonSegment(value: c, label: Text(c.label))],
            selected: {p.contrast},
            onSelectionChanged: (s) => p.update((x) => x.contrast = s.first),
          ),
          const SizedBox(height: Space.lg),
          DropdownMenu<String?>(
            label: Text(l10n.settingsFont),
            initialSelection: p.fontFamily,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [for (final (l, f) in kFontChoices) DropdownMenuEntry(value: f, label: l)],
            onSelected: (v) => p.update((x) => x.fontFamily = v),
          ),
          _SliderTile(
            title: l10n.settingsTextSize,
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
            title: Text(l10n.settingsCompact),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.reduceMotion,
            onChanged: (v) => p.update((x) => x.reduceMotion = v),
            title: Text(l10n.settingsReduceMotion),
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
        title: l10n.settingsDefaultSpeed,
        value: p.defaultSpeed,
        min: 0.5,
        max: 3,
        divisions: 10,
        label: '${p.defaultSpeed}×',
        onChanged: (v) => p.update((x) => x.defaultSpeed = (v * 4).round() / 4),
      ),
      _SliderTile(
        title: l10n.settingsBoostSpeed,
        subtitle: l10n.settingsBoostSpeedHint,
        value: p.boostSpeed,
        min: 1.5,
        max: 4,
        divisions: 10,
        label: '${p.boostSpeed}×',
        onChanged: (v) => p.update((x) => x.boostSpeed = (v * 4).round() / 4),
      ),
      _SliderTile(
        title: l10n.settingsSeekStep,
        value: p.seekStepSec.toDouble(),
        min: 5,
        max: 30,
        divisions: 5,
        label: l10n.commonSecondsValue(p.seekStepSec),
        onChanged: (v) => p.update((x) => x.seekStepSec = v.round()),
      ),
      _SliderTile(
        title: l10n.settingsSubtitleSize,
        value: p.subtitleScale,
        min: 0.8,
        max: 1.6,
        divisions: 8,
        label: '${(p.subtitleScale * 100).round()}%',
        onChanged: (v) => p.update((x) => x.subtitleScale = v),
      ),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.autoResume, onChanged: (v) => p.update((x) => x.autoResume = v), title: Text(l10n.settingsResume)),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.showSubtitles, onChanged: (v) => p.update((x) => x.showSubtitles = v), title: Text(l10n.settingsShowSubtitlesHint)),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.slideFollow, onChanged: (v) => p.update((x) => x.slideFollow = v), title: Text(l10n.settingsSlidesFollowHint)),
      const SizedBox(height: Space.sm),
      Text(l10n.settingsShortcutsBody,
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
        title: Text(l10n.settingsModels),
        subtitle: Text(a.selected == null ? l10n.commonNotConfigured : '${a.selected!['provider']} / ${a.selected!['model']}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const ModelsPage())),
      ),
      _VisionModelTile(a: a),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: BotAvatar(size: 28, shape: a.botShape, color: a.botColor, animate: false),
        title: Text(a.botName),
        subtitle: Text(l10n.settingsBotHint),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const BotPage())),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.terminal_rounded),
        title: Text(l10n.settingsRuntime),
        subtitle: Text(a.ready ? l10n.settingsRuntimeReady : l10n.settingsRuntimeMissing),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showRuntimeSetup(context),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.insights_outlined),
        title: Text(l10n.settingsUsage),
        subtitle: Text(l10n.settingsUsageHint),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const UsagePage())),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.schedule_rounded),
        title: Text(l10n.commonScheduledTasks),
        subtitle: Text(l10n.settingsTasksHint),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => ShellScope.of(context).goTo(Tabs.tasks),
      ),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.assistantDocked, onChanged: (v) => p.update((x) => x.assistantDocked = v), title: Text(l10n.settingsDock)),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.chatBubbles, onChanged: (v) => p.update((x) => x.chatBubbles = v), title: Text(l10n.settingsBubbles)),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: p.showThinking, onChanged: (v) => p.update((x) => x.showThinking = v), title: Text(l10n.settingsShowThinking)),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.settingsStreamAnimation),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final (v, l) in [
              (GptMarkdownAnimation.none, l10n.commonNone),
              (GptMarkdownAnimation.fade, l10n.streamFade),
              (GptMarkdownAnimation.blurIn, l10n.streamBlur),
              (GptMarkdownAnimation.typewriter, l10n.streamTypewriter),
              (GptMarkdownAnimation.wave, l10n.streamWave),
            ])
              ChoiceChip(label: Text(l), selected: p.streamAnimation == v, onSelected: (_) => p.update((x) => x.streamAnimation = v)),
          ]),
        ),
      ),
      _SliderTile(
        title: l10n.settingsChatTextSize,
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
        ? l10n.visionNative(vision.isEmpty ? '' : l10n.visionNativeFallback(vision))
        : vision.isEmpty
            ? l10n.visionNeeded
            : ready
                ? l10n.visionUsing(vision)
                : l10n.visionUnavailable(vision);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.image_search_rounded),
      title: Text(l10n.settingsVisionModel),
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
            child: Text(l10n.settingsVisionModel, style: Theme.of(c).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
            child: Text(l10n.visionBody,
                style: Theme.of(c).textTheme.bodySmall?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: RadioGroup<String>(
              groupValue: current,
              onChanged: (v) => Navigator.pop(c, v),
              child: ListView(children: [
                RadioListTile(value: '', title: Text(l10n.visionNone)),
                for (final (id, name, provider) in options) RadioListTile(value: id, title: Text(name), subtitle: Text(provider)),
                if (options.isEmpty)
                  Padding(padding: EdgeInsets.all(Space.xl), child: Text(l10n.visionNoModels)),
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
      if (context.mounted) showSnack(context, l10n.commonSaveFailed(e));
    }
  }
}

