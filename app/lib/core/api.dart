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

typedef ApiCall = Future<dynamic> Function(String method, String path, [Object? body]);

/// HTTP client for lookd (and the agent host behind /agent).
class Api {
  Api(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  final _client = http.Client();

  Map<String, String> get _headers => {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query?.isEmpty ?? true ? null : query);

  /// URL usable by media players and image loaders.
  String fileUrl(String rel) => '$baseUrl/files/${rel.split('/').map(Uri.encodeComponent).join('/')}?token=$token';

  /// One request by method; paths may carry a query string. Widgets take
  /// this as an [ApiCall] so tests can answer without a daemon.
  Future<dynamic> call(String method, String path, [Object? body]) {
    final u = Uri.parse(path);
    return _send(method, u.path, body: method == 'GET' || method == 'DELETE' ? null : body ?? const {}, query: u.queryParameters);
  }

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query, Duration? timeout}) async {
    final req = http.Request(method, uri(path, query))..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final streamed = await _client.send(req).timeout(timeout ?? const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    final text = utf8.decode(res.bodyBytes);
    dynamic data;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      data = text;
    }
    if (res.statusCode >= 400) {
      final msg = data is Map && data['error'] != null ? data['error'].toString() : 'HTTP ${res.statusCode}';
      throw ApiError(res.statusCode, msg, captcha: data is Map && data['captcha'] == true);
    }
    return data;
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body, Duration? timeout]) => _send('POST', path, body: body ?? const {}, timeout: timeout);
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Streams a file as the raw request body (courseware upload).
  Future<dynamic> upload(String path, Map<String, String> query, Stream<List<int>> data, int length) async {
    final req = http.StreamedRequest('POST', uri(path, query))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/octet-stream'
      ..contentLength = length;
    unawaited(data.pipe(req.sink));
    final res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(minutes: 10)));
    final text = utf8.decode(res.bodyBytes);
    dynamic out;
    try {
      out = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      out = text;
    }
    if (res.statusCode >= 400) throw ApiError(res.statusCode, out is Map && out['error'] != null ? '${out['error']}' : 'HTTP ${res.statusCode}');
    return out;
  }

  /// Streams a response into [dest] through a temporary file, reporting the
  /// bytes written so far (backup export).
  Future<int> download(String path, Map<String, String> query, File dest, {void Function(int bytes)? onProgress}) async {
    final req = http.Request('GET', uri(path, query))..headers['Authorization'] = 'Bearer $token';
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
    if (await dest.exists()) await dest.delete(); // Windows cannot rename over a file
    await tmp.rename(dest.path);
    return n;
  }

  /// Server-Sent Events as decoded JSON objects. Cancel the subscription to
  /// close the connection.
  Stream<Map<String, dynamic>> sse(String path, {String method = 'GET', Object? body}) {
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
              final data = block.split('\n').where((l) => l.startsWith('data: ')).map((l) => l.substring(6)).join('\n');
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
