import '../l10n/l10n.dart';
String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

String fmtSpeed(num bps) => '${fmtBytes(bps)}/s';

String fmtClock(int ms) {
  final s = (ms / 1000).floor();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

String fmtDuration(int seconds) {
  if (seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return m > 0 ? l10n.durationHoursMinutes(h, m) : l10n.durationHours(h);
  return l10n.durationMinutes(m);
}

final _weekdays = [l10n.weekdayShort1, l10n.weekdayShort2, l10n.weekdayShort3, l10n.weekdayShort4, l10n.weekdayShort5, l10n.weekdayShort6, l10n.weekdayShort7];

String fmtLectureDate(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return l10n.timeToday(hm);
  if (diff == 1) return l10n.timeYesterday(hm);
  if (diff == -1) return l10n.timeTomorrow(hm);
  final wd = l10n.weekdayName(_weekdays[d.weekday - 1]);
  if (d.year == now.year) return l10n.dateMonthDayWeekday(d.month, d.day, wd);
  return l10n.dateYearMonthDay(d.year, d.month, d.day);
}

String fmtRelative(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return l10n.timeJustNow;
  if (d.inMinutes < 60) return l10n.timeMinutesAgo(d.inMinutes);
  if (d.inHours < 24) return l10n.timeHoursAgo(d.inHours);
  if (d.inDays < 30) return l10n.timeDaysAgo(d.inDays);
  return l10n.dateMonthDay(t.month, t.day);
}

String fmtUntil(DateTime t) {
  final d = t.difference(DateTime.now());
  if (d.isNegative) return l10n.timeExpired;
  if (d.inHours >= 24) return l10n.durationDaysHours(d.inDays, d.inHours % 24);
  if (d.inMinutes >= 60) return l10n.durationHoursMinutesShort(d.inHours, d.inMinutes % 60);
  return l10n.durationMinutesLong(d.inMinutes);
}

/// Time of day, `14:05:30`.
String fmtClockTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

final kindLabels = {'video': l10n.assetVideo, 'slides': 'PPT', 'courseware': l10n.assetCourseware, 'transcript': l10n.assetTranscript, 'audio': l10n.assetAudio, 'parse': l10n.assetParse};

final weekdayNames = _weekdays;

/// Compact count for statistics: 0, 980, 12.3K, 4.5M.
String fmtCompact(num n) {
  if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(n >= 1e7 ? 0 : 1)}M';
  if (n >= 1e4) return '${(n / 1e3).toStringAsFixed(0)}K';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
  return '${n.round()}';
}

/// Estimated USD cost; small amounts keep four decimals so they don't read as zero.
String fmtUsd(num v) {
  if (v == 0) return '\$0';
  if (v < 0.01) return '\$${v.toStringAsFixed(4)}';
  if (v < 100) return '\$${v.toStringAsFixed(2)}';
  return '\$${v.toStringAsFixed(0)}';
}

final kWeekdays = [l10n.weekdayShort1, l10n.weekdayShort2, l10n.weekdayShort3, l10n.weekdayShort4, l10n.weekdayShort5, l10n.weekdayShort6, l10n.weekdayShort7];

/// "10月14日 周二"
String fmtDayLabel(DateTime d) => l10n.dateMonthDayWeek(d.month, d.day, kWeekdays[d.weekday - 1]);

/// Local calendar day as YYYY-MM-DD.
String fmtIsoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
