import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';

String isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// All schedule items, kept in sync with lookd's schedule_changed events.
class ScheduleStore extends ChangeNotifier {
  ScheduleStore(this.app) {
    app.addListener(_onApp);
    _onApp();
  }
  final AppState app;
  List<ScheduleItem> items = [];
  bool loaded = false;
  StreamSubscription? _sub;
  Timer? _debounce;

  void _onApp() {
    if (!app.connected || _sub != null) return;
    _sub = app.events.listen((e) {
      if (e['type'] == 'schedule_changed' || e['type'] == 'hello') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 150), load);
      }
    });
    load();
  }

  Future<void> load() async {
    if (!app.connected) return;
    try {
      final r = jsonList(await app.api.get('/api/schedule'));
      items = r.map((e) => ScheduleItem((e as Map).cast<String, dynamic>())).toList();
      loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  ScheduleItem? byId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  List<ScheduleItem> forLecture(String lectureId) => items.where((i) => i.lectureId == lectureId).toList();

  List<ScheduleItem> onDay(DateTime d) {
    final k = isoDate(d);
    return items.where((i) => i.dueDate == k).toList();
  }

  /// Open items that are overdue or due within the next two days.
  int get dueSoon {
    final limit = isoDate(dayOf(DateTime.now()).add(const Duration(days: 2)));
    return items.where((i) => !i.done && i.dueDate.compareTo(limit) <= 0).length;
  }

  List<ScheduleItem> upcoming({int days = 14}) {
    final today = isoDate(dayOf(DateTime.now()));
    final limit = isoDate(dayOf(DateTime.now()).add(Duration(days: days)));
    return items.where((i) => !i.done && i.dueDate.compareTo(limit) <= 0 && (i.dueDate.compareTo(today) >= 0 || i.overdue)).toList();
  }

  void _replace(ScheduleItem it) {
    final i = items.indexWhere((x) => x.id == it.id);
    if (i >= 0) {
      items[i] = it;
    } else {
      items.add(it);
    }
    items.sort((a, b) => a.dueDate != b.dueDate ? a.dueDate.compareTo(b.dueDate) : a.dueTime.compareTo(b.dueTime));
    notifyListeners();
  }

  Future<ScheduleItem> add(Map<String, dynamic> fields) async {
    final r = (await app.api.post('/api/schedule', fields) as Map).cast<String, dynamic>();
    final it = ScheduleItem((r['item'] as Map).cast<String, dynamic>());
    _replace(it);
    return it;
  }

  Future<void> patch(ScheduleItem it, Map<String, dynamic> fields) async {
    // Optimistic: reflect the change at once, then take the server's copy.
    _replace(ScheduleItem({...it.j, ...fields}));
    try {
      _replace(ScheduleItem((await app.api.patch('/api/schedule/${it.id}', fields) as Map).cast<String, dynamic>()));
    } catch (e) {
      _replace(it);
      rethrow;
    }
  }

  Future<void> remove(ScheduleItem it) async {
    items.removeWhere((x) => x.id == it.id);
    notifyListeners();
    try {
      await app.api.delete('/api/schedule/${it.id}');
    } catch (e) {
      _replace(it);
      rethrow;
    }
  }

  /// Puts back an item removed by mistake (same fields, new id).
  Future<ScheduleItem> restore(ScheduleItem it) => add({...it.j}..remove('id'));

  @override
  void dispose() {
    app.removeListener(_onApp);
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
