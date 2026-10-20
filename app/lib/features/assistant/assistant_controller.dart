import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/activity_tracker.dart';
import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import 'bot_avatar.dart';

/// One rendered piece of an assistant turn.
class ChatBlock {
  ChatBlock.text([this.text = '']) : kind = 'text';
  ChatBlock.thinking([this.text = '']) : kind = 'thinking';
  ChatBlock.tool({required this.id, required this.name, this.args}) : kind = 'tool', text = '';

  final String kind; // text | thinking | tool
  String text;
  String id = '';
  String name = '';
  Object? args;
  bool running = false;
  bool error = false;
  String result = '';
  Map<String, dynamic>? details;
  int ms = 0;

  List<Map<String, dynamic>> get actions =>
      ((details?['actions'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  /// An app operation the bot ran (`details.app`): open, player, prefs or done.
  Map<String, dynamic>? get appOp => (details?['app'] as Map?)?.cast<String, dynamic>();

  /// A change waiting on a card (`details.proposal`), with its current state.
  Map<String, dynamic>? get proposal => (details?['proposal'] as Map?)?.cast<String, dynamic>();
}

class ChatMessage {
  ChatMessage.user(this.text) : role = 'user';
  ChatMessage.assistant() : role = 'assistant', text = '';

  final String role;
  final String text;
  final List<ChatBlock> blocks = [];
  bool streaming = false;
  String? error;
  String? status;
  String? model;
  Map<String, dynamic>? usage;

  ChatBlock? get lastBlock => blocks.isEmpty ? null : blocks.last;
}

class ChatSession {
  ChatSession(this.j);
  final Map<String, dynamic> j;
  String get id => '${j['id']}';
  String get title => '${j['title'] ?? '新对话'}';
  String get kind => '${j['kind'] ?? 'chat'}';
  String get courseId => '${j['course_id'] ?? ''}';
  String get course => '${j['course'] ?? ''}';
  DateTime get modified => DateTime.tryParse('${j['modified']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  int get messages => (j['messages'] as num?)?.toInt() ?? 0;
}

/// Talks to the embedded Pi agent host (proxied by lookd under /agent).
class AssistantController extends ChangeNotifier {
  AssistantController(this.app, this.screen, this.players) {
    app.addListener(_onApp);
    _events = app.events.listen(_onAppEvent);
  }
  final AppState app;
  final ScreenContext screen;
  final PlayerHub players;

  List<ChatSession> sessions = [];
  String? sessionId;
  List<ChatMessage> messages = [];
  bool loadingSession = false;

  /// Token, cost and context usage of the open session (from Pi's session stats).
  Map<String, dynamic>? stats;
  bool compacting = false;
  Map<String, dynamic>? models;
  Object? modelsError;
  StreamSubscription? _stream;
  StreamSubscription? _events;
  bool _wasReady = false;
  bool _disposed = false;

  bool get ready => app.agentReady;
  bool get busy => messages.isNotEmpty && messages.last.streaming;
  String get agentState => '${app.agent['state'] ?? 'starting'}';
  String get agentError => '${app.agent['error'] ?? ''}';

  Map<String, dynamic>? get selected => models?['selected'] as Map<String, dynamic>?;
  String get modelLabel {
    final s = selected;
    if (s == null) return '未选择模型';
    return '${s['model']}';
  }

  String get thinking => '${(models?['prefs'] as Map?)?['thinking'] ?? 'medium'}';

  void _onApp() {
    if (ready && !_wasReady) {
      _wasReady = true;
      unawaited(refreshSessions());
      unawaited(loadModels());
      unawaited(loadBot(openThread: view == 'bot' && sessionId == null && messages.isEmpty));
      if (_appState != null) unawaited(pushAppState(_appState!));
    } else if (!ready) {
      _wasReady = false;
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ---- models ----

  Future<void> loadModels() async {
    try {
      models = (await app.api.get('/agent/models') as Map).cast<String, dynamic>();
      modelsError = null;
    } catch (e) {
      modelsError = e;
    }
    notifyListeners();
  }

  Future<void> setPrefs(Map<String, dynamic> patch) async {
    models = (await app.api.put('/agent/prefs', patch) as Map).cast<String, dynamic>();
    notifyListeners();
  }

  Future<void> setKey(String provider, String key) async {
    models = (await app.api.put('/agent/providers/${Uri.encodeComponent(provider)}/key', {'api_key': key}) as Map).cast<String, dynamic>();
    notifyListeners();
  }

  Future<void> upsertProvider(String id, Map<String, dynamic> body) async {
    models = (await app.api.put('/agent/providers/${Uri.encodeComponent(id)}', body) as Map).cast<String, dynamic>();
    notifyListeners();
  }

  Future<void> removeProvider(String id) async {
    models = (await app.api.delete('/agent/providers/${Uri.encodeComponent(id)}') as Map).cast<String, dynamic>();
    notifyListeners();
  }

  /// Model IDs offered by an endpoint, enriched with models.dev metadata.
  Future<List<Map<String, dynamic>>> discover({String? provider, String? baseUrl, String? api, String? apiKey, String? catalogId}) async {
    final r = await app.api.post('/agent/discover', {
      'provider': ?provider,
      'base_url': ?baseUrl,
      'api': ?api,
      'api_key': ?apiKey,
      'catalog_id': ?catalogId,
    }) as Map;
    return jsonList(r['models']).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  List<Map<String, dynamic>>? _catalog;

  /// models.dev provider directory (cached by the agent host for a day).
  Future<List<Map<String, dynamic>>> catalogProviders({bool refresh = false}) async {
    if (_catalog != null && !refresh) return _catalog!;
    final r = await app.api.get('/agent/catalog/providers', refresh ? {'refresh': '1'} : null) as Map;
    return _catalog = jsonList(r['providers']).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  Future<List<Map<String, dynamic>>> catalogModels(String id) async {
    final r = await app.api.get('/agent/catalog/providers/${Uri.encodeComponent(id)}/models') as Map;
    return jsonList(r['models']).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// Metadata of the selected model from the provider registry.
  Map<String, dynamic>? get selectedModelInfo {
    final s = selected;
    if (s == null) return null;
    for (final p in jsonList(models?['providers']).whereType<Map>()) {
      if (p['id'] != s['provider']) continue;
      for (final m in jsonList(p['models']).whereType<Map>()) {
        if (m['id'] == s['model']) return m.cast<String, dynamic>();
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> testProvider(String id, String model) async =>
      (await app.api.post('/agent/providers/${Uri.encodeComponent(id)}/test', {'model': model}) as Map).cast<String, dynamic>();

  /// Copies custom providers and API keys from the Pi CLI; returns a summary.
  Future<String> importPi() async {
    final r = (await app.api.post('/agent/import/pi') as Map).cast<String, dynamic>();
    models = (r['models'] as Map).cast<String, dynamic>();
    notifyListeners();
    final imp = (r['imported'] as Map?) ?? const {};
    return '导入了 ${imp['providers'] ?? 0} 个服务商、${imp['keys'] ?? 0} 个密钥';
  }

  // ---- the resident bot (docs/specs/0007-resident-bot-and-course-agents.md) ----

  /// GET /agent/bot: name, shape, color, persona, session_id, memory switches.
  Map<String, dynamic> bot = const {};
  String get botName => '${bot['name'] ?? '小 Look'}';
  String get botShape => '${bot['shape'] ?? 'pebble'}';
  String get botColor => '${bot['color'] ?? 'theme'}';
  bool consolidating = false;

  /// 'bot' shows the bot's single thread; 'sessions' course agents and chats.
  String view = 'bot';

  /// The course of a course agent not yet started (it starts with the first message).
  ({String id, String title})? pendingCourse;

  /// The course of the open conversation, when it is a course agent.
  ({String id, String title})? course;

  bool composerFocused = false;
  DateTime? _happyUntil, _confusedUntil;
  Timer? _moodTimer;

  /// Memory files changed (by the bot or a consolidation run); the bot page reloads.
  final memoryChanged = ValueNotifier<int>(0);

  final _appOps = StreamController<Map<String, dynamic>>.broadcast();

  /// App operations from tool results as they happen (never from history).
  Stream<Map<String, dynamic>> get appOps => _appOps.stream;

  BotMood get mood {
    final now = DateTime.now();
    if (busy) {
      final r = messages.last;
      if (r.blocks.any((b) => b.kind == 'tool' && b.running)) return BotMood.working;
      final b = r.lastBlock;
      if (b != null && b.kind == 'text' && b.text.isNotEmpty) return BotMood.talking;
      return BotMood.thinking;
    }
    if (_confusedUntil != null && now.isBefore(_confusedUntil!)) return BotMood.confused;
    if (_happyUntil != null && now.isBefore(_happyUntil!)) return BotMood.happy;
    if (consolidating) return BotMood.dreaming;
    if (pendingProposals > 0) return BotMood.notify;
    if (composerFocused) return BotMood.listening;
    return BotMood.idle;
  }

  /// Cards in the open conversation that still wait for the user.
  int get pendingProposals {
    var n = 0;
    for (final m in messages) {
      for (final b in m.blocks) {
        if (b.proposal?['state'] == 'pending') n++;
      }
    }
    return n;
  }

  void _flash({bool happy = false, bool confused = false}) {
    final until = DateTime.now().add(const Duration(milliseconds: 2400));
    if (happy) _happyUntil = until;
    if (confused) _confusedUntil = until;
    _moodTimer?.cancel();
    _moodTimer = Timer(const Duration(milliseconds: 2500), notifyListeners);
  }

  void setComposerFocused(bool v) {
    if (v == composerFocused) return;
    composerFocused = v;
    notifyListeners();
  }

  void _onAppEvent(Map<String, dynamic> e) {
    if (e['type'] != 'bot_event') return;
    final d = (e['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (d['kind']) {
      case 'consolidating':
        consolidating = true;
      case 'consolidated':
      case 'failed':
        consolidating = false;
        memoryChanged.value++;
        unawaited(loadBot());
      case 'memory_changed':
        memoryChanged.value++;
    }
    notifyListeners();
  }

  Future<void> loadBot({bool openThread = false}) async {
    try {
      bot = (await app.api.get('/agent/bot') as Map).cast<String, dynamic>();
      consolidating = bot['consolidating'] == true;
      notifyListeners();
      final id = bot['session_id'];
      if (openThread && id is String && id.isNotEmpty && view == 'bot' && sessionId == null) await openSession(id);
    } catch (_) {}
  }

  Future<void> updateBot(Map<String, dynamic> patch) async {
    bot = (await app.api.put('/agent/bot', patch) as Map).cast<String, dynamic>();
    notifyListeners();
  }

  /// Starts a new bot thread; memory stays.
  Future<void> resetBot() async {
    bot = (await app.api.post('/agent/bot/reset') as Map).cast<String, dynamic>();
    if (view == 'bot') _clear();
    notifyListeners();
  }

  Future<void> consolidateNow() async {
    bot = (await app.api.post('/agent/bot/memory/consolidate') as Map).cast<String, dynamic>();
    consolidating = bot['consolidating'] == true;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> memoryFiles() async =>
      jsonList(await app.api.get('/agent/bot/memory')).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  Future<Map<String, dynamic>> readMemory(String path) async =>
      (await app.api.get('/agent/bot/memory/file', {'path': path}) as Map).cast<String, dynamic>();

  Future<void> writeMemory(String path, String content, {String? baseHash}) async {
    await app.api.put('/agent/bot/memory/file', {'path': path, 'content': content, 'base_hash': ?baseHash});
    memoryChanged.value++;
  }

  Future<void> deleteMemory(String path) async {
    await app.api.call('DELETE', '/agent/bot/memory/file?path=${Uri.encodeQueryComponent(path)}');
    memoryChanged.value++;
  }

  Future<List<Map<String, dynamic>>> memoryRuns() async =>
      jsonList(await app.api.get('/agent/bot/memory/runs')).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  Map<String, dynamic>? _appState;

  /// Sends the app preferences the bot may read (PUT /agent/app-state).
  Future<void> pushAppState(Map<String, dynamic> prefs) async {
    _appState = prefs;
    if (!ready) return;
    try {
      await app.api.put('/agent/app-state', prefs);
    } catch (_) {}
  }

  /// Shows the bot's thread.
  Future<void> showBot() async {
    if (busy) return;
    view = 'bot';
    pendingCourse = null;
    _clear();
    notifyListeners();
    final id = bot['session_id'];
    if (id is String && id.isNotEmpty) await openSession(id);
  }

  /// Shows course agents and chats, starting from a new conversation.
  void showSessions() {
    if (busy) return;
    view = 'sessions';
    _clear();
    notifyListeners();
    unawaited(refreshSessions());
  }

  /// Opens the latest conversation of a course's agent, or prepares a new one.
  Future<void> openCourseAgent(String courseId, String title, {bool fresh = false}) async {
    if (busy) return;
    view = 'sessions';
    await refreshSessions();
    final latest = fresh ? null : sessions.where((s) => s.kind == 'course' && s.courseId == courseId).firstOrNull;
    if (latest != null) {
      pendingCourse = null;
      await openSession(latest.id);
      return;
    }
    _clear();
    pendingCourse = (id: courseId, title: title);
    course = pendingCourse;
    notifyListeners();
  }

  void _clear() {
    sessionId = null;
    messages = [];
    stats = null;
    course = null;
  }

  Future<Map<String, dynamic>> _proposal(ChatBlock b, String action) async {
    final id = '${b.proposal?['id']}';
    final r = (await app.api.post('/agent/proposals/$id/$action') as Map).cast<String, dynamic>();
    final p = {...?b.proposal, 'state': r['state']};
    b.details = {...?b.details, 'proposal': p};
    notifyListeners();
    final result = (r['result'] as Map?)?.cast<String, dynamic>();
    if (result?['app'] is Map) _appOps.add({'op': 'prefs', 'set': result!['app'], 'silent': true});
    return r;
  }

  Future<void> applyProposal(ChatBlock b) async {
    await _proposal(b, 'apply');
    _flash(happy: true);
  }

  Future<void> dismissProposal(ChatBlock b) => _proposal(b, 'dismiss');

  Future<void> undoProposal(ChatBlock b) => _proposal(b, 'undo');

  /// Undoes an operation applied at once (its chip's 撤销).
  Future<void> undoApplied(ChatBlock b) async {
    final id = '${b.appOp?['proposal_id'] ?? ''}';
    if (id.isEmpty) return;
    final r = (await app.api.post('/agent/proposals/$id/undo') as Map).cast<String, dynamic>();
    b.details = {...?b.details, 'app': {...?b.appOp, 'undone': true}};
    final result = (r['result'] as Map?)?.cast<String, dynamic>();
    if (result?['app'] is Map) _appOps.add({'op': 'prefs', 'set': result!['app'], 'silent': true});
    notifyListeners();
  }

  // ---- sessions ----

  Future<void> refreshSessions() async {
    try {
      sessions = jsonList(await app.api.get('/agent/sessions')).map((e) => ChatSession((e as Map).cast<String, dynamic>())).toList();
      notifyListeners();
    } catch (_) {}
  }

  void newChat() {
    if (busy) return;
    if (view == 'bot') view = 'sessions';
    _clear();
    final c = screen.value;
    // A new conversation on a course or lecture page starts as that course's agent.
    pendingCourse = (c['course_id'] ?? '').isNotEmpty ? (id: c['course_id']!, title: c['course'] ?? '') : null;
    course = pendingCourse;
    notifyListeners();
  }

  /// A new conversation that is not bound to a course.
  void newPlainChat() {
    if (busy) return;
    view = 'sessions';
    _clear();
    pendingCourse = null;
    notifyListeners();
  }

  Future<void> openSession(String id) async {
    if (busy || id == sessionId) return;
    sessionId = id;
    loadingSession = true;
    messages = [];
    notifyListeners();
    try {
      final r = (await app.api.get('/agent/sessions/$id') as Map).cast<String, dynamic>();
      messages = _fromHistory(jsonList(r['messages']));
      stats = (r['stats'] as Map?)?.cast<String, dynamic>();
      view = r['kind'] == 'bot' && id == bot['session_id'] ? 'bot' : 'sessions';
      final cid = '${r['course_id'] ?? ''}';
      course = cid.isEmpty ? null : (id: cid, title: '${r['course'] ?? ''}');
      pendingCourse = null;
    } catch (e) {
      messages = [ChatMessage.assistant()..error = '无法打开对话：$e'];
    }
    loadingSession = false;
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    await app.api.delete('/agent/sessions/$id');
    sessions.removeWhere((s) => s.id == id);
    if (sessionId == id) newPlainChat();
    notifyListeners();
  }

  List<ChatMessage> _fromHistory(List raw) {
    final out = <ChatMessage>[];
    final toolIndex = <String, ChatBlock>{};
    for (final m in raw.whereType<Map>()) {
      switch (m['role']) {
        case 'user':
          out.add(ChatMessage.user('${m['text'] ?? ''}'));
        case 'assistant':
          // Consecutive assistant/tool messages render as one turn.
          final turn = out.isNotEmpty && out.last.role == 'assistant' ? out.last : (ChatMessage.assistant()..also(out.add));
          for (final b in jsonList(m['blocks']).whereType<Map>()) {
            switch (b['type']) {
              case 'text':
                if ('${b['text']}'.trim().isNotEmpty) turn.blocks.add(ChatBlock.text('${b['text']}'));
              case 'thinking':
                if ('${b['text']}'.trim().isNotEmpty) turn.blocks.add(ChatBlock.thinking('${b['text']}'));
              case 'tool':
                final tb = ChatBlock.tool(id: '${b['id']}', name: '${b['name']}', args: b['args']);
                toolIndex[tb.id] = tb;
                turn.blocks.add(tb);
            }
          }
          if (m['error'] != null) turn.error = '${m['error']}';
          if (m['usage'] is Map) turn.usage = (m['usage'] as Map).cast<String, dynamic>();
          turn.model = m['model']?.toString();
        case 'tool':
          final tb = toolIndex['${m['id']}'];
          if (tb != null) {
            tb.result = '${m['text'] ?? ''}';
            tb.error = m['error'] == true;
            if (m['details'] is Map) tb.details = (m['details'] as Map).cast<String, dynamic>();
          }
      }
    }
    return out;
  }

  // ---- chat ----

  Map<String, String> _context() {
    final c = <String, String>{...screen.value};
    final p = players.value;
    if (p != null) {
      c['player_lecture_id'] = p.lectureId;
      c['player_position'] = '${fmtClock(p.positionMs)} (${p.positionMs ~/ 1000}s)';
    }
    c['now'] = DateTime.now().toIso8601String().substring(0, 16);
    return c;
  }

  Future<void> send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || busy || !ready) return;
    ActivityTracker.instance?.count('ask', lectureId: players.value?.lectureId ?? '');
    final reply = ChatMessage.assistant()..streaming = true;
    messages = [...messages, ChatMessage.user(msg), reply];
    notifyListeners();

    final done = Completer<void>();
    _stream = app.api.sse('/agent/chat', method: 'POST', body: {
      'session_id': ?sessionId,
      if (sessionId == null && view == 'bot') 'agent': 'bot',
      if (sessionId == null && view != 'bot') 'course_id': ?pendingCourse?.id,
      'message': msg,
      'context': _context(),
    }).listen(
      (e) => _onEvent(reply, e),
      onError: (Object e) {
        reply.error = e is ApiError ? e.message : '$e';
        _finish(reply);
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        _finish(reply);
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    unawaited(refreshSessions());
  }

  void _onEvent(ChatMessage r, Map<String, dynamic> e) {
    switch (e['type']) {
      case 'start':
        sessionId = '${e['session_id']}';
        r.model = e['model']?.toString();
        if (e['kind'] == 'bot') bot = {...bot, 'session_id': sessionId};
        if (pendingCourse != null) {
          course = pendingCourse;
          pendingCourse = null;
        }
      case 'block':
        r.blocks.add(e['kind'] == 'thinking' ? ChatBlock.thinking() : ChatBlock.text());
        r.status = null;
      case 'text':
        final b = r.lastBlock;
        if (b == null || b.kind != 'text') r.blocks.add(ChatBlock.text());
        r.lastBlock!.text += '${e['delta']}';
      case 'thinking':
        final b = r.lastBlock;
        if (b == null || b.kind != 'thinking') r.blocks.add(ChatBlock.thinking());
        r.lastBlock!.text += '${e['delta']}';
      case 'tool_call':
        r.blocks.add(ChatBlock.tool(id: '${e['id']}', name: '${e['name']}', args: e['args']));
      case 'tool_start':
        final b = _tool(r, '${e['id']}') ?? (ChatBlock.tool(id: '${e['id']}', name: '${e['name']}', args: e['args'])..also(r.blocks.add));
        b.running = true;
      case 'tool_end':
        final b = _tool(r, '${e['id']}');
        if (b != null) {
          b.running = false;
          b.error = e['error'] == true;
          b.result = '${e['text'] ?? ''}';
          b.ms = (e['ms'] as num?)?.toInt() ?? 0;
          if (e['details'] is Map) b.details = (e['details'] as Map).cast<String, dynamic>();
          final op = b.appOp;
          if (op != null && !b.error) _appOps.add(op);
        }
      case 'message_end':
        if (e['usage'] is Map) {
          final u = (e['usage'] as Map).cast<String, dynamic>();
          final prev = r.usage;
          r.usage = prev == null
              ? u
              : {
                  'input': ((prev['input'] as num?) ?? 0) + ((u['input'] as num?) ?? 0),
                  'output': ((prev['output'] as num?) ?? 0) + ((u['output'] as num?) ?? 0),
                  'cost': ((prev['cost'] as num?) ?? 0) + ((u['cost'] as num?) ?? 0),
                };
        }
        if (e['error'] != null) r.error = '${e['error']}';
      case 'status':
        r.status = '${e['text']}';
      case 'error':
        r.error = '${e['message']}';
      case 'done':
        if (e['stats'] is Map) stats = (e['stats'] as Map).cast<String, dynamic>();
    }
    notifyListeners();
  }

  ChatBlock? _tool(ChatMessage r, String id) {
    for (final b in r.blocks.reversed) {
      if (b.kind == 'tool' && b.id == id) return b;
    }
    return null;
  }

  void _finish(ChatMessage r) {
    if (r.streaming) r.error == null ? _flash(happy: true) : _flash(confused: true);
    r.streaming = false;
    r.status = null;
    for (final b in r.blocks) {
      b.running = false;
    }
    _stream = null;
    notifyListeners();
  }

  Future<void> stop() async {
    final id = sessionId;
    if (id != null) {
      try {
        await app.api.post('/agent/sessions/$id/abort');
      } catch (_) {}
    }
    await _stream?.cancel();
    if (messages.isNotEmpty) _finish(messages.last);
  }

  /// Summarises older turns so the conversation fits the context window again.
  Future<void> compact() async {
    final id = sessionId;
    if (id == null || busy || compacting) return;
    compacting = true;
    notifyListeners();
    try {
      final r = await app.api.post('/agent/sessions/$id/compact') as Map;
      stats = (r['stats'] as Map?)?.cast<String, dynamic>();
    } finally {
      compacting = false;
      notifyListeners();
    }
  }

  /// Regenerate: resend the last user message in a fresh turn.
  Future<void> retryLast() async {
    final last = messages.lastWhere((m) => m.role == 'user', orElse: () => ChatMessage.user(''));
    if (last.text.isEmpty) return;
    await send(last.text);
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_onApp);
    _stream?.cancel();
    _events?.cancel();
    _moodTimer?.cancel();
    _appOps.close();
    memoryChanged.dispose();
    super.dispose();
  }
}

extension _Also<T> on T {
  void also(void Function(T) f) => f(this);
}
