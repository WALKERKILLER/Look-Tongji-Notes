import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';

/// Finished task runs not yet seen on the 定时 tab, for the rail badge
/// (docs/specs/0003-scheduled-agent-tasks.md). Only the newest seen finish
/// time is kept on this device.
class TaskInbox extends ChangeNotifier {
  TaskInbox(this.app) {
    app.addListener(_onApp);
    _onApp();
  }
  final AppState app;
  static const _key = 'tasks.seenAt';

  int unread = 0;

  /// Runs that finished after this were new when the tab was last opened.
  int lastVisit = 0;
  int _seenAt = -1;
  int _newest = 0;
  bool _viewing = false;
  StreamSubscription? _sub;
  SharedPreferences? _sp;

  void _onApp() {
    if (_sub != null || !app.agentReady) return;
    _sub = app.events.listen((e) {
      if (e['type'] == 'agent_task' && (e['data'] as Map?)?['phase'] == 'finished') load();
    });
    load();
  }

  Future<void> load() async {
    try {
      _sp ??= await SharedPreferences.getInstance();
      final runs = jsonList(await app.api.get('/agent/tasks/runs', {'limit': '200'}));
      // Aborted runs were stopped by the user, so they are not news.
      final finished = [
        for (final r in runs)
          if (r is Map && r['status'] != 'aborted' && r['finished'] is num) (r['finished'] as num).toInt(),
      ];
      _newest = finished.fold(0, math.max);
      if (_seenAt < 0) {
        // The first time, history from before this version counts as seen.
        _seenAt = _sp!.getInt(_key) ?? _newest;
        lastVisit = _seenAt;
      }
      if (_viewing) {
        _markSeen();
      } else {
        unread = finished.where((f) => f > _seenAt).length;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Set by the shell while the 定时 tab is on screen.
  set viewing(bool v) {
    if (v == _viewing) return;
    _viewing = v;
    if (!v) return;
    if (_seenAt >= 0) lastVisit = _seenAt;
    _markSeen();
    notifyListeners();
  }

  void _markSeen() {
    unread = 0;
    if (_newest <= _seenAt) return;
    _seenAt = _newest;
    _sp?.setInt(_key, _seenAt);
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _sub?.cancel();
    super.dispose();
  }
}
