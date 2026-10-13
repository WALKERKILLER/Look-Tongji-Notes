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
  if (h > 0) return m > 0 ? '$h 小时 $m 分' : '$h 小时';
  return '$m 分钟';
}

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

String fmtLectureDate(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return '今天 $hm';
  if (diff == 1) return '昨天 $hm';
  if (diff == -1) return '明天 $hm';
  final wd = '周${_weekdays[d.weekday - 1]}';
  if (d.year == now.year) return '${d.month}月${d.day}日 $wd';
  return '${d.year}年${d.month}月${d.day}日';
}

String fmtRelative(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '刚刚';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  if (d.inDays < 30) return '${d.inDays} 天前';
  return '${t.month}月${t.day}日';
}

String fmtUntil(DateTime t) {
  final d = t.difference(DateTime.now());
  if (d.isNegative) return '已过期';
  if (d.inHours >= 24) return '${d.inDays} 天 ${d.inHours % 24} 小时';
  if (d.inMinutes >= 60) return '${d.inHours} 小时 ${d.inMinutes % 60} 分';
  return '${d.inMinutes} 分钟';
}

const kindLabels = {'video': '视频', 'slides': 'PPT', 'courseware': '课件', 'transcript': '转写', 'audio': '音频', 'parse': '课件解析'};

const weekdayNames = _weekdays;
