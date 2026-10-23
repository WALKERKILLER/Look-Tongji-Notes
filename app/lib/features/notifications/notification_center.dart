import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/look_markdown.dart' show openPlainLink;
import '../../widgets/states.dart';
import '../courses/course_page.dart';
import '../player/player_page.dart';

/// Icon per notification kind (lookd/internal/notify).
IconData notificationIcon(String kind) => switch (kind) {
  'lecture_ready' => Icons.smart_display_outlined,
  'lecture_added' => Icons.event_available_outlined,
  'assignment_new' => Icons.assignment_outlined,
  'assignment_due' => Icons.alarm_rounded,
  'announcement' => Icons.campaign_outlined,
  _ => Icons.notifications_none_rounded,
};

/// Opens what a notification points at: the replay, the course or a web page.
void openNotification(BuildContext context, Map<String, dynamic> n) {
  final nav = Navigator.of(context, rootNavigator: true);
  final lecture = '${n['lecture_id'] ?? ''}';
  final course = '${n['course_id'] ?? ''}';
  final url = '${n['url'] ?? ''}';
  if (n['kind'] == 'lecture_ready' && lecture.isNotEmpty) {
    nav.push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: lecture)));
  } else if (url.isNotEmpty) {
    openPlainLink(context, url);
  } else if (course.isNotEmpty) {
    nav.push(MaterialPageRoute(builder: (_) => CoursePage(courseId: course)));
  }
}

/// Bell with the unread count; opens the notification center.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context) {
    final unread = context.select<AppState, int>((a) => a.unreadNotifications);
    return IconButton(
      tooltip: unread > 0 ? '通知（$unread 条未读）' : '通知',
      onPressed: () => showNotificationCenter(context),
      icon: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        child: Icon(unread > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded),
      ),
    );
  }
}

/// MD3 modal side sheet on wide windows, bottom sheet on compact ones.
Future<void> showNotificationCenter(BuildContext context) {
  final api = context.read<AppState>().api.call;
  final events = context.read<AppState>().events;
  if (context.isCompact) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: NotificationList(api: api, events: events, onOpen: (n) => openNotification(context, n)),
      ),
    );
  }
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭通知',
    transitionDuration: Motion.medium4,
    pageBuilder: (c, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Material(
          color: Theme.of(c).colorScheme.surfaceContainerLow,
          elevation: 1,
          borderRadius: Corners.all(Corners.xl),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 400,
            child: NotificationList(api: api, events: events, onOpen: (n) => openNotification(context, n), onClose: () => Navigator.pop(c)),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, a, _, child) {
      final t = CurvedAnimation(parent: a, curve: Motion.emphasizedDecelerate, reverseCurve: Motion.emphasizedAccelerate);
      return SlideTransition(
        position: Tween(begin: const Offset(0.25, 0), end: Offset.zero).animate(t),
        child: FadeTransition(opacity: t, child: child),
      );
    },
  );
}

class NotificationList extends StatefulWidget {
  const NotificationList({super.key, required this.api, required this.events, required this.onOpen, this.onClose});
  final ApiCall api;
  final Stream<Map<String, dynamic>> events;
  final void Function(Map<String, dynamic>) onOpen;
  final VoidCallback? onClose;
  @override
  State<NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<NotificationList> {
  List<Map<String, dynamic>>? _items;
  Object? _error;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = widget.events.listen((e) {
      if (e['type'] == 'notification') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api('GET', '/api/notifications') as Map;
      if (mounted) setState(() => _items = jsonList(r['items']).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _read({String? id}) async {
    setState(() {
      for (final n in _items ?? <Map<String, dynamic>>[]) {
        if (id == null || n['id'] == id) n['read'] = true;
      }
    });
    try {
      await widget.api(
        'POST',
        '/api/notifications/read',
        id == null
            ? {'all': true}
            : {
                'ids': [id],
              },
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    final unread = items?.where((n) => n['read'] != true).length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.sm, Space.sm),
          child: Row(
            children: [
              Expanded(child: Text('通知', style: tt.titleLarge)),
              if (unread > 0) TextButton(onPressed: () => _read(), child: const Text('全部已读')),
              if (widget.onClose != null) IconButton(tooltip: '关闭', onPressed: widget.onClose, icon: const Icon(Icons.close_rounded)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: Text('新回放、新课次、Canvas 作业和公告会出现在这里。Look Studio 打开时在后台自动检查。', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        const SizedBox(height: Space.sm),
        Expanded(
          child: items == null
              ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const CenteredLoader())
              : items.isEmpty
              ? const EmptyState(icon: Icons.notifications_none_rounded, title: '暂时没有通知', body: '有新回放或新作业时会第一时间提醒你')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.lg),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final n = items[i];
                    final read = n['read'] == true;
                    return ListTile(
                      shape: RoundedRectangleBorder(borderRadius: Corners.all(Corners.lg)),
                      leading: CircleAvatar(
                        backgroundColor: read ? cs.surfaceContainerHighest : cs.secondaryContainer,
                        foregroundColor: read ? cs.onSurfaceVariant : cs.onSecondaryContainer,
                        child: Icon(notificationIcon('${n['kind']}'), size: 20),
                      ),
                      title: Text('${n['title']}', style: read ? null : const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          '${n['body'] ?? ''}',
                          fmtRelative(DateTime.fromMillisecondsSinceEpoch(((n['at'] as num?) ?? 0).toInt() * 1000)),
                        ].where((s) => s.isNotEmpty).join('\n'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: read
                          ? null
                          : Semantics(
                              label: '未读',
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                              ),
                            ),
                      onTap: () {
                        _read(id: '${n['id']}');
                        widget.onClose?.call();
                        widget.onOpen(n);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
