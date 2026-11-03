import 'dart:ui';

/// UTF-16 ranges match Dart/JavaScript selection offsets; regions are object-normalized.
class StudyAnchor {
  StudyAnchor({
    required this.id,
    required this.objectId,
    required this.kind,
    this.workspaceId = '',
    this.documentId = '',
    this.sourceLectureId = '',
    this.originalPath = '',
    this.page = 0,
    this.start = 0,
    this.end = 0,
    this.timeStartMs = 0,
    this.timeEndMs = 0,
    this.fingerprint = '',
    this.quote = '',
    this.region,
    this.strokeIds = const [],
  });
  final String id,
      objectId,
      kind,
      documentId,
      fingerprint,
      quote,
      workspaceId,
      sourceLectureId,
      originalPath;
  final int page, start, end, timeStartMs, timeEndMs;
  final Rect? region;
  final List<String> strokeIds;
  Map<String, dynamic> json() => {
    'id': id,
    'object_id': objectId,
    'kind': kind,
    'workspace_id': workspaceId,
    'document_id': documentId,
    'source_lecture_id': sourceLectureId,
    'original_path': originalPath,
    'page': page,
    'start': start,
    'end': end,
    'time_start_ms': timeStartMs,
    'time_end_ms': timeEndMs,
    'fingerprint': fingerprint,
    'quote': quote,
    if (region != null)
      'region': [region!.left, region!.top, region!.width, region!.height],
    'stroke_ids': strokeIds,
  };
  factory StudyAnchor.fromJson(Map m) {
    final r = m['region'] as List?;
    return StudyAnchor(
      id: '${m['id']}',
      objectId: '${m['object_id']}',
      kind: '${m['kind']}',
      workspaceId: '${m['workspace_id'] ?? ''}',
      documentId: '${m['document_id'] ?? ''}',
      sourceLectureId: '${m['source_lecture_id'] ?? ''}',
      originalPath: '${m['original_path'] ?? ''}',
      page: (m['page'] as num? ?? 0).toInt(),
      start: (m['start'] as num? ?? 0).toInt(),
      end: (m['end'] as num? ?? 0).toInt(),
      timeStartMs: (m['time_start_ms'] as num? ?? 0).toInt(),
      timeEndMs: (m['time_end_ms'] as num? ?? 0).toInt(),
      fingerprint: '${m['fingerprint'] ?? ''}',
      quote: '${m['quote'] ?? ''}',
      region: r == null
          ? null
          : Rect.fromLTWH(
              (r[0] as num).toDouble(),
              (r[1] as num).toDouble(),
              (r[2] as num).toDouble(),
              (r[3] as num).toDouble(),
            ),
      strokeIds: (m['stroke_ids'] as List? ?? []).cast<String>(),
    );
  }
}

class StudyBlock {
  StudyBlock({
    required this.type,
    this.text = '',
    this.items = const [],
    this.columns = const [],
    this.rows = const [],
    this.language = '',
    this.hint = '',
    this.answer = '',
  });
  final String type;
  String text, language, hint, answer;
  List<String> items, columns;
  List<List<String>> rows;
  Map<String, dynamic> json() => {
    'type': type,
    'text': text,
    'items': items,
    'columns': columns,
    'rows': rows,
    'language': language,
    'hint': hint,
    'answer': answer,
  };
  factory StudyBlock.fromJson(Map m) => StudyBlock(
    type: '${m['type']}',
    text: '${m['text'] ?? ''}',
    items: (m['items'] as List? ?? []).cast<String>(),
    columns: (m['columns'] as List? ?? []).cast<String>(),
    rows: [
      for (final r in m['rows'] as List? ?? []) (r as List).cast<String>(),
    ],
    language: '${m['language'] ?? ''}',
    hint: '${m['hint'] ?? ''}',
    answer: '${m['answer'] ?? ''}',
  );
  String get plainText => [
    text,
    ...items,
    columns.join(' | '),
    ...rows.map((r) => r.join(' | ')),
    hint,
    answer,
  ].where((s) => s.isNotEmpty).join('\n');
}

class StudyConnection {
  StudyConnection(this.id, this.from, this.to, this.label);
  final String id, from, to;
  String label;
  Map<String, dynamic> json() => {
    'id': id,
    'from': from,
    'to': to,
    'label': label,
  };
  factory StudyConnection.fromJson(Map m) => StudyConnection(
    '${m['id']}',
    '${m['from']}',
    '${m['to']}',
    '${m['label']}',
  );
}

class StudySelection {
  String? objectId;
  int start = 0, end = 0;
  Rect? region;
  final strokeIds = <String>{};
  void clear() {
    objectId = null;
    start = end = 0;
    region = null;
    strokeIds.clear();
  }

  Map<String, dynamic> json() => {
    'object_id': objectId ?? '',
    'start': start,
    'end': end,
    if (region != null)
      'region': [region!.left, region!.top, region!.width, region!.height],
    'stroke_ids': strokeIds.toList(),
  };
}
