import 'android_bridge.dart';
import 'app_state.dart';

/// On Android, keeps the app (and lookd in its workspace) running in the
/// background while there is work: downloads or transcriptions queued or
/// running, or a sync. A low-priority notification says what is going on;
/// it goes away when the work is done.
class BackgroundWork {
  BackgroundWork(this.app, {Future<void> Function(bool on, String? text)? apply}) : _apply = apply ?? ((on, text) => AndroidBridge.keepAlive(on, text: text)) {
    app.addListener(_update);
    app.events.listen((e) {
      switch (e['type']) {
        case 'sync_progress':
          _syncing = true;
        case 'sync_done':
          _syncing = false;
        default:
          return;
      }
      _update();
    });
  }

  final AppState app;
  final Future<void> Function(bool on, String? text) _apply;
  bool _syncing = false;
  String? _shown;

  void _update() {
    final active = app.jobs.values.where((j) => j.state == 'running' || j.state == 'queued').length;
    final text = active > 0
        ? '正在处理 $active 个下载或转写任务'
        : _syncing
            ? '正在同步数据'
            : null;
    if (text == _shown) return;
    _shown = text;
    _apply(text != null, text).catchError((_) {});
  }
}
