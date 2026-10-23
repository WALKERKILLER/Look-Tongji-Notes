import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/activity_tracker.dart';
import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';

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
  DateTime get modified => DateTime.tryParse('${j['modified']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  int get messages => (j['messages'] as num?)?.toInt() ?? 0;
}

/// Talks to the embedded Pi agent host (proxied by lookd under /agent).
class AssistantController extends ChangeNotifier {
  AssistantController(this.app, this.screen, this.players) {
    app.addListener(_onApp);
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

  // ---- sessions ----

  Future<void> refreshSessions() async {
    try {
      sessions = jsonList(await app.api.get('/agent/sessions')).map((e) => ChatSession((e as Map).cast<String, dynamic>())).toList();
      notifyListeners();
    } catch (_) {}
  }

  void newChat() {
    if (busy) return;
    sessionId = null;
    messages = [];
    stats = null;
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
    } catch (e) {
      messages = [ChatMessage.assistant()..error = '无法打开对话：$e'];
    }
    loadingSession = false;
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    await app.api.delete('/agent/sessions/$id');
    sessions.removeWhere((s) => s.id == id);
    if (sessionId == id) newChat();
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
    super.dispose();
  }
}

extension _Also<T> on T {
  void also(void Function(T) f) => f(this);
}
