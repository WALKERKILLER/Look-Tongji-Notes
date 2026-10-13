// Plain data classes mirroring lookd JSON.

int _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _s(dynamic v) => v?.toString() ?? '';
bool _b(dynamic v) => v == true || v == 1 || v == '1';

class AuthState {
  AuthState(this.j);
  final Map<String, dynamic> j;
  String get status => _s(j['status']);
  String get username => _s(j['username']);
  String get realname => _s(j['realname']);
  String get method => _s(j['method']);
  bool get remember => _b(j['remember']);
  String get error => _s(j['error']);
  DateTime? get expiresAt => DateTime.tryParse(_s(j['expires_at']))?.toLocal();
  DateTime? get renewedAt => DateTime.tryParse(_s(j['renewed_at']))?.toLocal();
  bool get signedIn => status == 'active' || status == 'renewing';
  static final empty = AuthState({'status': 'signed_out'});
}

class Course {
  Course(this.j);
  final Map<String, dynamic> j;
  String get id => _s(j['id']);
  String get rawTitle => _s(j['title']);
  String get alias => _s(j['alias']);
  String get title => alias.isNotEmpty ? alias : rawTitle;
  String get teacher => _s(j['teacher']);
  String get college => _s(j['college']);
  String get term => _s(j['term']);
  int get lectureTotal => _i(j['lecture_total']);
  double get progress => _d(j['progress']);
  bool get pinned => _b(j['pinned']);
  bool get hidden => _b(j['hidden']);
  String get color => _s(j['color']);
  String get lastSubId => _s(j['last_sub_id']);
  String get lastLearnAt => _s(j['last_learn_at']);
  int get localLectures => _i(j['local_lectures']);
  List<String> get teachers =>
      ((j['teachers'] as List?) ?? []).map((t) => _s((t as Map)['realname'])).where((s) => s.isNotEmpty).toList();

  /// "20261" → "2026 秋", "20252" → "2026 春"
  String get termLabel {
    if (term.length != 5) return term;
    final y = int.tryParse(term.substring(0, 4)) ?? 0;
    return term.endsWith('1') ? '$y 秋' : '${y + 1} 春';
  }
}

class Lecture {
  Lecture(this.j);
  final Map<String, dynamic> j;
  String get id => _s(j['id']);
  String get courseId => _s(j['course_id']);
  String get title => _s(j['title']);
  String get date => _s(j['date']);
  int get beginAt => _i(j['begin_at']);
  int get endAt => _i(j['end_at']);
  String get lecturer => _s(j['lecturer']);
  String get room => _s(j['room']);
  bool get hasPlayback => _b(j['has_playback']);
  int get durationS => _i(j['duration_s']);
  String get thumb => _s(j['thumb']);
  String get dir => _s(j['dir']);
  List<String> get assets => ((j['assets'] as List?) ?? []).map(_s).toList();
  int get positionMs => _i(j['position_ms']);
  int get segments => _i(j['segments']);
  bool has(String kind) => assets.contains(kind);
  DateTime? get begin => beginAt > 0 ? DateTime.fromMillisecondsSinceEpoch(beginAt * 1000) : null;
  bool get upcoming => beginAt > 0 && DateTime.now().millisecondsSinceEpoch < beginAt * 1000;

  /// Title without a leading date that the platform repeats in titles.
  String get shortTitle {
    final t = title.startsWith(date) ? title.substring(date.length).trim() : title;
    return t.isEmpty ? title : t;
  }
}

class Job {
  Job(this.j);
  final Map<String, dynamic> j;
  String get id => _s(j['id']);
  String get courseId => _s(j['course_id']);
  String get lectureId => _s(j['lecture_id']);
  String get kind => _s(j['kind']);
  String get title => _s(j['title']);
  String get state => _s(j['state']);
  int get doneBytes => _i(j['done_bytes']);
  int get totalBytes => _i(j['total_bytes']);
  double get progress => _d(j['progress']).clamp(0, 1);
  String get error => _s(j['error']);
  int get speed => _i(j['speed']);
  int get conns => _i(j['conns']);
  String get stage => _s(j['stage']);
  int get updatedAt => _i(j['updated_at']);
  bool get active => state == 'running' || state == 'queued';
}

class Slide {
  Slide(this.j);
  final Map<String, dynamic> j;
  int get idx => _i(j['idx']);
  int get tSec => _i(j['t_sec']);
  bool get isKey => _b(j['is_key']);
  String get remoteUrl => _s(j['remote_url']);
  String get abs => _s(j['abs']);
  String get path => _s(j['path']);
}

class Segment {
  Segment(this.j);
  final Map<String, dynamic> j;
  int get idx => _i(j['idx']);
  int get startMs => _i(j['start_ms']);
  int get endMs => _i(j['end_ms']);
  String get text => _s(j['text']);
}

class Note {
  Note(this.j);
  final Map<String, dynamic> j;
  String get id => _s(j['id']);
  String get title => _s(j['title']);
  String get body => _s(j['body']);
  String get courseId => _s(j['course_id']);
  String get lectureId => _s(j['lecture_id']);
  String get source => _s(j['source']);
  String get path => _s(j['path']);
  int get updatedAt => _i(j['updated_at']);
}

class Bookmark {
  Bookmark(this.j);
  final Map<String, dynamic> j;
  int get id => _i(j['id']);
  int get tMs => _i(j['t_ms']);
  String get label => _s(j['label']);
}

class Hit {
  Hit(this.j);
  final Map<String, dynamic> j;
  String get kind => _s(j['kind']);
  String get courseId => _s(j['course_id']);
  String get courseTitle => _s(j['course_title']);
  String get lectureId => _s(j['lecture_id']);
  String get lecture => _s(j['lecture']);
  String get noteId => _s(j['note_id']);
  int get startMs => _i(j['start_ms']);
  String get snippet => _s(j['snippet']);
}

class Stream_ {
  Stream_(this.j);
  final Map<String, dynamic> j;
  String get label => _s(j['label']);
  String get url => _s(j['url']);
  String get thumb => _s(j['thumb']);
}

class LectureMedia {
  LectureMedia(this.j);
  final Map<String, dynamic> j;
  List<Stream_> get streams => ((j['streams'] as List?) ?? []).map((e) => Stream_(e as Map<String, dynamic>)).toList();
  int get duration => _i(j['duration']);
  Map<String, String> get headers =>
      ((j['headers'] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), v.toString()));
  String get localPath => _s(j['local_path']);
  List<Map<String, dynamic>> get courseware => ((j['courseware'] as List?) ?? []).cast<Map<String, dynamic>>();
}

/// A dated item on the schedule (homework, exam, activity, deadline, task).
class ScheduleItem {
  ScheduleItem(this.j);
  final Map<String, dynamic> j;
  String get id => _s(j['id']);
  String get kind => _s(j['kind']);
  String get title => _s(j['title']);
  String get detail => _s(j['detail']);
  String get dueDate => _s(j['due_date']);
  String get dueTime => _s(j['due_time']);
  String get courseId => _s(j['course_id']);
  String get courseTitle => _s(j['course_title']);
  String get lectureId => _s(j['lecture_id']);
  String get lecture => _s(j['lecture']);
  int get tMs => j['t_ms'] == null ? -1 : _i(j['t_ms']);
  String get quote => _s(j['quote']);
  String get source => _s(j['source']);
  bool get done => _b(j['done']);
  DateTime get day => DateTime.tryParse(dueDate) ?? DateTime(1970);
  bool get overdue {
    final n = DateTime.now();
    return !done && day.isBefore(DateTime(n.year, n.month, n.day));
  }
}

/// One chapter of a lecture outline.
class Chapter {
  Chapter(this.j);
  final Map<String, dynamic> j;
  int get idx => _i(j['idx']);
  int get startMs => _i(j['start_ms']);
  int get endMs => _i(j['end_ms']);
  String get title => _s(j['title']);
}

/// An uploaded courseware file and its MinerU parse state.
class CoursewareFile {
  CoursewareFile(this.j);
  final Map<String, dynamic> j;
  String get path => _s(j['path']);
  String get name => _s(j['name']);
  int get bytes => _i(j['bytes']);
  Map<String, dynamic>? get _p => (j['parse'] as Map?)?.cast<String, dynamic>();
  String get parseState => _s(_p?['state']);
  int get pages => _i(_p?['pages']);
  String get mdPath => _s(_p?['md']);
  String get parseError => _s(_p?['error']);
  bool get parsed => parseState == 'done';
  String get ext => name.contains('.') ? name.split('.').last.toLowerCase() : '';
}
