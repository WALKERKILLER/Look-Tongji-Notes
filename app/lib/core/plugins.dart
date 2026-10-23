import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_state.dart';
import '../l10n/l10n.dart';

/// One place a plugin appears outside the chat: an action on a surface, a
/// note view, an exporter or a page (docs/specs/0004-plugin-platform.md).
class PluginEntry {
  PluginEntry(this.plugin, this.kind, Map e)
      : id = '${e['id']}',
        title = '${e['title']}',
        icon = '${e['icon'] ?? 'extension'}',
        action = '${e['action']}',
        surface = '${e['surface'] ?? ''}',
        scope = '${e['scope'] ?? ''}';
  final Map<String, dynamic> plugin;

  /// actions, noteViews, exporters or pages.
  final String kind;
  final String id, title, icon, action, surface, scope;
  String get pluginId => '${plugin['id']}';
  String get pluginTitle => '${plugin['title']}';
}

/// Installed plugins and the plugin routes of the agent host.
class PluginStore extends ChangeNotifier {
  PluginStore(this.app) {
    app.addListener(_onApp);
    _onApp();
  }
  final AppState app;

  List<Map<String, dynamic>> installed = [];
  bool allowThirdParty = false;
  bool loaded = false;
  Object? error;
  StreamSubscription? _sub;
  final _notices = StreamController<String>.broadcast();

  /// Short messages from plugins (`look.notify`), shown as snackbars.
  Stream<String> get notices => _notices.stream;

  bool get ready => app.agentReady;

  void _onApp() {
    if (_sub != null || !app.agentReady) return;
    _sub = app.events.listen((e) {
      if (e['type'] != 'plugin_event') return;
      final d = (e['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      switch (d['kind']) {
        case 'status':
          setStatus('${d['plugin']}', d['status']);
        case 'notify':
          final p = byId('${d['plugin']}');
          _notices.add(p == null ? '${d['text']}' : l10n.pluginContextLine(p['title'], d['text']));
      }
    });
    load();
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _sub?.cancel();
    _notices.close();
    super.dispose();
  }

  Map<String, dynamic>? byId(String id) {
    for (final p in installed) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  /// Plugins that are loaded and working.
  Iterable<Map<String, dynamic>> get active => installed.where((p) => p['state'] == 'enabled');

  /// Plugins waiting for consent or failing to load.
  int get attention => installed.where((p) => p['state'] == 'needs_consent' || p['state'] == 'error').length;

  void setStatus(String id, Object? status) {
    final p = byId(id);
    if (p == null) return;
    p['status'] = status;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final r = (await app.api.get('/agent/plugins') as Map).cast<String, dynamic>();
      installed = [for (final p in jsonList(r['plugins'])) (p as Map).cast<String, dynamic>()];
      allowThirdParty = r['allow_third_party'] == true;
      error = null;
    } catch (e) {
      error = e;
    }
    loaded = true;
    notifyListeners();
  }

  /// Contributions of active plugins. [kind] is a key of `contributes`.
  List<PluginEntry> entries(String kind, {String? surface, String? scope}) => [
        for (final p in active)
          for (final e in jsonList((p['contributes'] as Map?)?[kind]))
            if (e is Map && (surface == null || e['surface'] == surface) && (scope == null || e['scope'] == scope)) PluginEntry(p, kind, e),
      ];

  /// The plugin owning a prefixed tool name (`<id>__<tool>`).
  Map<String, dynamic>? toolPlugin(String name) {
    final i = name.indexOf('__');
    return i <= 0 ? null : byId(name.substring(0, i));
  }

  String? toolLabel(String name) {
    for (final t in jsonList(toolPlugin(name)?['tools'])) {
      if (t is Map && t['name'] == name) return '${t['label']}';
    }
    return null;
  }

  /// Whether an active plugin renders `look-view` blocks of [kind] in Markdown.
  bool rendersBlock(String kind) => active.any((p) => jsonList((p['contributes'] as Map?)?['blocks']).contains(kind));

  Future<Map<String, dynamic>> catalog() async => (await app.api.get('/agent/plugins/catalog') as Map).cast<String, dynamic>();

  /// Fetches and validates a package; nothing is installed until [confirm].
  Future<Map<String, dynamic>> preview(String source) async =>
      (await app.api.post('/agent/plugins/install', {'source': source}, const Duration(minutes: 5)) as Map).cast<String, dynamic>();

  Future<Map<String, dynamic>> confirm(String token) async {
    final r = (await app.api.post('/agent/plugins/install/confirm', {'token': token}, const Duration(minutes: 6)) as Map).cast<String, dynamic>();
    _replace(r);
    return r;
  }

  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> body) async {
    final r = (await app.api.put('/agent/plugins/$id', body) as Map).cast<String, dynamic>();
    _replace(r);
    return r;
  }

  Future<void> uninstall(String id) async {
    await app.api.delete('/agent/plugins/$id');
    installed.removeWhere((p) => p['id'] == id);
    notifyListeners();
  }

  Future<void> setThirdParty(bool allow) async {
    final r = await app.api.put('/agent/plugins/third-party', {'allow': allow}) as Map;
    allowThirdParty = r['allow_third_party'] == true;
    notifyListeners();
  }

  Future<void> addCatalog(String url) => app.api.post('/agent/plugins/catalogs', {'url': url});
  Future<void> removeCatalog(String url) => app.api.post('/agent/plugins/catalogs/remove', {'url': url});

  /// Runs a contributed action; the result holds one of view, prompt, open
  /// or toast (and optionally a new status).
  Future<Map<String, dynamic>> run(PluginEntry e, Map<String, dynamic> context) async {
    final r = (await app.api.post('/agent/plugins/${e.pluginId}/actions/${e.action}', {'context': context}, const Duration(seconds: 75)) as Map).cast<String, dynamic>();
    if (r['state'] is Map) setStatus(e.pluginId, r['state']);
    return r;
  }

  void _replace(Map<String, dynamic> p) {
    final i = installed.indexWhere((x) => x['id'] == p['id']);
    if (i < 0) {
      installed = [...installed, p];
    } else {
      installed[i] = p;
    }
    notifyListeners();
  }
}

/// Material icons a manifest may name; anything else shows the puzzle piece.
const pluginIcons = <String, IconData>{
  'extension': Icons.extension_outlined,
  'psychology_alt': Icons.psychology_alt_outlined,
  'account_tree': Icons.account_tree_outlined,
  'hub': Icons.hub_outlined,
  'schema': Icons.schema_outlined,
  'insights': Icons.insights_outlined,
  'show_chart': Icons.show_chart_rounded,
  'functions': Icons.functions_rounded,
  'calculate': Icons.calculate_outlined,
  'style': Icons.style_outlined,
  'layers': Icons.layers_outlined,
  'quiz': Icons.quiz_outlined,
  'school': Icons.school_outlined,
  'menu_book': Icons.menu_book_outlined,
  'auto_stories': Icons.auto_stories_outlined,
  'edit_note': Icons.edit_note_rounded,
  'sticky_note_2': Icons.sticky_note_2_outlined,
  'checklist': Icons.checklist_rounded,
  'task_alt': Icons.task_alt_rounded,
  'assignment': Icons.assignment_outlined,
  'code': Icons.code_rounded,
  'terminal': Icons.terminal_rounded,
  'data_object': Icons.data_object_rounded,
  'bug_report': Icons.bug_report_outlined,
  'smart_toy': Icons.smart_toy_outlined,
  'event': Icons.event_outlined,
  'calendar_month': Icons.calendar_month_outlined,
  'sync': Icons.sync_rounded,
  'cloud_sync': Icons.cloud_sync_outlined,
  'link': Icons.link_rounded,
  'output': Icons.output_rounded,
  'download': Icons.download_outlined,
  'image': Icons.image_outlined,
  'palette': Icons.palette_outlined,
  'lightbulb': Icons.lightbulb_outline_rounded,
  'translate': Icons.translate_rounded,
  'record_voice_over': Icons.record_voice_over_outlined,
  'timeline': Icons.timeline_rounded,
  'bubble_chart': Icons.bubble_chart_outlined,
  'science': Icons.science_outlined,
};

IconData pluginIcon(Object? name) => pluginIcons['$name'] ?? Icons.extension_outlined;

final pluginCategories = {
  'notes': l10n.commonNotes,
  'visualize': l10n.pluginCategoryVisualize,
  'review': l10n.pluginCategoryReview,
  'programming': l10n.pluginCategoryProgramming,
  'connector': l10n.pluginCategoryConnector,
  'tutor': l10n.pluginCategoryTutor,
  'assignment': l10n.commonAssignments,
};

const permissionIcons = <String, IconData>{
  'library.read': Icons.local_library_outlined,
  'library.write': Icons.edit_note_rounded,
  'views': Icons.dashboard_customize_outlined,
  'localhost': Icons.lan_outlined,
  'exec': Icons.terminal_rounded,
  'workspace': Icons.create_new_folder_outlined,
  'network': Icons.public_rounded,
  'folder': Icons.folder_open_outlined,
};

/// Permissions that reach outside the app are shown with emphasis.
const sensitivePermissions = {'exec', 'network', 'folder', 'localhost'};
