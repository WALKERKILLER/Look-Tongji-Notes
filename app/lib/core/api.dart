import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiError implements Exception {
  ApiError(this.status, this.message, {this.captcha = false});
  final int status;
  final String message;
  final bool captcha;
  @override
  String toString() => message;
}

typedef ApiCall = Future<dynamic> Function(
  String method,
  String path, [
  Object? body,
]);

/// HTTP client for lookd (and the agent host behind /agent).
class Api {
  Api(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  final _client = http.Client();

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path')
          .replace(queryParameters: query?.isEmpty ?? true ? null : query);

  /// URL usable by media players and image loaders.
  String fileUrl(String rel) =>
      '$baseUrl/files/${rel.split('/').map(Uri.encodeComponent).join('/')}?token=$token';

  /// One request by method; paths may carry a query string. Widgets take
  /// this as an [ApiCall] so tests can answer without a daemon.
  Future<dynamic> call(String method, String path, [Object? body]) {
    final u = Uri.parse(path);
    return _send(
      method,
      u.path,
      body: method == 'GET' || method == 'DELETE' ? null : body ?? const {},
      query: u.queryParameters,
    );
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final req = http.Request(method, uri(path, query))
      ..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final streamed = await _client
        .send(req)
        .timeout(timeout ?? const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    final text = utf8.decode(res.bodyBytes);
    dynamic data;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      data = text;
    }
    if (res.statusCode >= 400) {
      final msg = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'HTTP ${res.statusCode}';
      throw ApiError(
        res.statusCode,
        msg,
        captcha: data is Map && data['captcha'] == true,
      );
    }
    return data;
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body, Duration? timeout]) =>
      _send('POST', path, body: body ?? const {}, timeout: timeout);
  Future<dynamic> put(String path, Object body) =>
      _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) =>
      _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> previewFolderSync(Map<String, dynamic> settings) =>
      post('/api/sync/folder/preview', settings);
  Future<dynamic> configureFolderSync(Map<String, dynamic> settings) =>
      put('/api/sync', {'kind': 'folder', ...settings});
  Future<dynamic> syncNow() => post('/api/sync/run');
  Future<dynamic> libraryCatalog({String? courseId}) => get(
    '/api/library/catalog${courseId == null ? '' : '?course_id=${Uri.encodeComponent(courseId)}'}',
  );
  Future<dynamic> createLocalCourse(String title, {String teacher = ''}) =>
      post('/api/local-courses', {'title': title, 'teacher': teacher});
  Future<dynamic> importLocalVideo(
    String course,
    String name,
    Stream<List<int>> data,
    int length,
  ) => upload(
    '/api/courses/${Uri.encodeComponent(course)}/local-videos',
    {'name': name},
    data,
    length,
  );
  Future<dynamic> studyConversation(String lecture, String id) => get(
    '/api/lectures/${Uri.encodeComponent(lecture)}/study-canvas/conversations/${Uri.encodeComponent(id)}',
  );
  Future<dynamic> saveStudyConversation(
    String lecture,
    String id,
    Map data,
  ) => put(
    '/api/lectures/${Uri.encodeComponent(lecture)}/study-canvas/conversations/${Uri.encodeComponent(id)}',
    data,
  );
  Future<dynamic> importStudyMaterial(String lecture, String path) => post(
    '/api/lectures/${Uri.encodeComponent(lecture)}/study-canvas/material',
    {'path': path},
  );
  String studyMediaUrl(String id, String object) => uri(
    '/api/lectures/${Uri.encodeComponent(id)}/study-canvas/media-file/${Uri.encodeComponent(object)}',
    {'token': token},
  ).toString();
  Future<dynamic> prepareStudyMedia(String id, Map query) => post(
    '/api/lectures/${Uri.encodeComponent(id)}/study-canvas/media',
    query,
  );
  Future<dynamic> studyMediaTask(String id, String task) => get(
    '/api/lectures/${Uri.encodeComponent(id)}/study-canvas/media/${Uri.encodeComponent(task)}',
  );
  Future<dynamic> cancelStudyMedia(String id, String task) => delete(
    '/api/lectures/${Uri.encodeComponent(id)}/study-canvas/media/${Uri.encodeComponent(task)}',
  );
  Future<dynamic> studyPDFPage(String id, String source, int page) => get(
    '/api/lectures/${Uri.encodeComponent(id)}/study-canvas/pdf-page?source=${Uri.encodeComponent(source)}&page=$page',
  );
  Future<dynamic> studyCanvas(String id) =>
      get('/api/lectures/${Uri.encodeComponent(id)}/study-canvas');
  Future<dynamic> studyContext(String id, Map<String, dynamic> selection) =>
      post(
        '/api/lectures/${Uri.encodeComponent(id)}/study-canvas/context',
        selection,
      );
  Future<dynamic> startCanvasRun(Map<String, dynamic> request) =>
      post('/agent/canvas/runs', request);
  Future<dynamic> canvasRun(String id) =>
      get('/agent/canvas/runs/${Uri.encodeComponent(id)}');
  Future<dynamic> cancelCanvasRun(String id) =>
      delete('/agent/canvas/runs/${Uri.encodeComponent(id)}');

  /// Whole-document saves retain objects[].pdf_column and page-bound ink.
  Future<dynamic> saveStudyCanvas(String id, Map<String, dynamic> document) =>
      put('/api/lectures/${Uri.encodeComponent(id)}/study-canvas', document);
  Future<dynamic> importStudyAsset(
    String id,
    String name,
    Stream<List<int>> data,
    int length,
  ) => upload(
    '/api/lectures/${Uri.encodeComponent(id)}/study-canvas/assets',
    {'name': name},
    data,
    length,
  );
  Future<dynamic> importStudyCourseware(String id, String path) => post(
    '/api/lectures/${Uri.encodeComponent(id)}/study-canvas/assets?path=${Uri.encodeComponent(path)}',
  );
  Future<dynamic> transcriptReview(String id) =>
      get('/agent/transcript-review/${Uri.encodeComponent(id)}');
  Future<dynamic> startTranscriptReview(String id) =>
      post('/agent/transcript-review/${Uri.encodeComponent(id)}');
  Future<dynamic> cancelTranscriptReview(String id) =>
      delete('/agent/transcript-review/${Uri.encodeComponent(id)}');
  Future<dynamic> dismissTranscriptSuggestion(String id, String suggestionId) =>
      patch('/api/lectures/${Uri.encodeComponent(id)}/transcript-review', {
        'suggestion_id': suggestionId,
      });

  Future<dynamic> nasSnapshot() => get('/api/nas');
  String nasFileUrl(String id) => uri(
    '/api/nas/files/${Uri.encodeComponent(id)}',
    {'token': token},
  ).toString();

  /// Streams a file as the raw request body (courseware upload).
  Future<dynamic> upload(
    String path,
    Map<String, String> query,
    Stream<List<int>> data,
    int length,
  ) async {
    final req = http.StreamedRequest('POST', uri(path, query))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/octet-stream'
      ..contentLength = length;
    unawaited(data.pipe(req.sink));
    final res = await http.Response.fromStream(
      await _client.send(req).timeout(const Duration(minutes: 10)),
    );
    final text = utf8.decode(res.bodyBytes);
    dynamic out;
    try {
      out = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      out = text;
    }
    if (res.statusCode >= 400)
      throw ApiError(
        res.statusCode,
        out is Map && out['error'] != null
            ? '${out['error']}'
            : 'HTTP ${res.statusCode}',
      );
    return out;
  }

  /// Streams a response into [dest] through a temporary file, reporting the
  /// bytes written so far (backup export).
  Future<int> download(
    String path,
    Map<String, String> query,
    File dest, {
    void Function(int bytes)? onProgress,
  }) async {
    final req = http.Request('GET', uri(path, query))
      ..headers['Authorization'] = 'Bearer $token';
    final res = await _client.send(req).timeout(const Duration(minutes: 2));
    if (res.statusCode >= 400) {
      final text = await res.stream.bytesToString();
      String msg = 'HTTP ${res.statusCode}';
      try {
        final m = jsonDecode(text);
        if (m is Map && m['error'] != null) msg = '${m['error']}';
      } catch (_) {}
      throw ApiError(res.statusCode, msg);
    }
    final tmp = File('${dest.path}.part');
    final sink = tmp.openWrite();
    var n = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        n += chunk.length;
        onProgress?.call(n);
      }
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      await tmp.delete().catchError((_) => tmp);
      rethrow;
    }
    if (await dest.exists())
      await dest.delete(); // Windows cannot rename over a file
    await tmp.rename(dest.path);
    return n;
  }

  /// Server-Sent Events as decoded JSON objects. Cancel the subscription to
  /// close the connection.
  Stream<Map<String, dynamic>> sse(
    String path, {
    String method = 'GET',
    Object? body,
  }) {
    late StreamController<Map<String, dynamic>> ctrl;
    http.Client? client;
    ctrl = StreamController(
      onListen: () async {
        client = http.Client();
        try {
          final req = http.Request(method, uri(path))..headers.addAll(_headers);
          req.headers['Accept'] = 'text/event-stream';
          if (body != null) req.body = jsonEncode(body);
          final res = await client!.send(req);
          if (res.statusCode >= 400) {
            final text = await res.stream.bytesToString();
            String msg = 'HTTP ${res.statusCode}';
            try {
              msg = (jsonDecode(text) as Map)['error']?.toString() ?? msg;
            } catch (_) {}
            ctrl.addError(ApiError(res.statusCode, msg));
            await ctrl.close();
            return;
          }
          final buf = StringBuffer();
          await for (final chunk in res.stream.transform(utf8.decoder)) {
            buf.write(chunk);
            var s = buf.toString();
            int idx;
            while ((idx = s.indexOf('\n\n')) >= 0) {
              final block = s.substring(0, idx);
              s = s.substring(idx + 2);
              final data = block
                  .split('\n')
                  .where((l) => l.startsWith('data: '))
                  .map((l) => l.substring(6))
                  .join('\n');
              if (data.isNotEmpty) {
                try {
                  ctrl.add(jsonDecode(data) as Map<String, dynamic>);
                } catch (_) {}
              }
            }
            buf
              ..clear()
              ..write(s);
          }
          await ctrl.close();
        } catch (e) {
          if (!ctrl.isClosed) {
            ctrl.addError(e);
            await ctrl.close();
          }
        }
      },
      onCancel: () => client?.close(),
    );
    return ctrl.stream;
  }
}

/// Go encodes empty slices as null; treat that as an empty list.
List jsonList(dynamic v) => v is List ? v : const [];
