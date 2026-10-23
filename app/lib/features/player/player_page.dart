import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../theme/prefs.dart';
import '../../theme/tokens.dart';
import '../../widgets/report_screen.dart';
import '../../widgets/states.dart';
import '../assistant/assistant_controller.dart';
import '../assistant/assistant_panel.dart';
import 'lecture_player.dart';
import 'player_view.dart';
import 'side_panel.dart';
import '../../l10n/l10n.dart';

/// The page route of each open player, so a seek can bring it back on top.
final _playerRoutes = Expando<ModalRoute<dynamic>>('playerRoute');

/// Closes the pages that cover [p]'s player (a note or practice opened from it).
void revealPlayer(PlayerHandle p) {
  final r = _playerRoutes[p];
  if (r != null && r.isActive && !r.isCurrent) r.navigator?.popUntil((x) => x == r);
}

/// Seeks the open player when it shows [lectureId] (any lecture when empty)
/// and brings it on top; otherwise opens that lecture at [seconds].
void seekOrOpen(BuildContext context, String lectureId, int seconds) {
  final p = context.read<PlayerHub>().value;
  if (p != null && (lectureId.isEmpty || p.lectureId == lectureId)) {
    p.seekTo(seconds * 1000);
    revealPlayer(p);
    return;
  }
  if (lectureId.isEmpty) {
    showSnack(context, l10n.playerNoLectureAtTime);
    return;
  }
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PlayerPage(lectureId: lectureId, startMs: seconds * 1000)));
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.lectureId, this.startMs});
  final String lectureId;
  final int? startMs;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final LecturePlayer ctl;
  final _view = GlobalKey<PlayerViewState>();
  final _focus = FocusNode(debugLabel: 'player');
  bool _fullscreen = false;
  bool _panel = true;
  StreamSubscription? _sub;
  late final PlayerHub _hub;
  bool _resumeShown = false;

  // Arrow-key hold → speed boost (Kazumi style).
  Timer? _holdTimer;
  bool _held = false;

  bool get _desktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _hub = context.read<PlayerHub>();
    ctl = LecturePlayer(api: app.api, lectureId: widget.lectureId, prefs: context.read<UiPrefs>());
    ctl.addListener(_onCtl);
    ctl.load().then((_) {
      if (!mounted) return;
      if (widget.startMs != null) ctl.seekTo(widget.startMs!);
      _hub.value = ctl;
    });
    _sub = app.events.listen((e) {
      final d = e['data'];
      if (d is Map && d['lecture_id'] == widget.lectureId) {
        if (e['type'] == 'lecture_changed') {
          switch (d['what']) {
            case 'timeline':
              ctl.reloadTimeline();
            case 'courseware':
              ctl.reloadCourseware();
            default:
              ctl.reloadTranscript();
              ctl.reloadCourseware();
          }
        } else if (e['type'] == 'notes_changed') {
          ctl.reloadNotes();
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playerRoutes[ctl] = ModalRoute.of(context);
  }

  void _onCtl() {
    if (_resumeShown || ctl.loading || ctl.resumedFrom <= 0 || widget.startMs != null) return;
    _resumeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _view.currentState?.showResume(ctl.resumedFrom);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _holdTimer?.cancel();
    _focus.dispose();
    ctl.removeListener(_onCtl);
    if (_hub.value == ctl) _hub.value = null;
    if (_fullscreen) _setFullscreen(false);
    ctl.close();
    super.dispose();
  }

  Future<void> _setFullscreen(bool v) async {
    if (_desktop) {
      await windowManager.setFullScreen(v);
    } else {
      await SystemChrome.setEnabledSystemUIMode(v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(v ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : []);
    }
    if (mounted) setState(() => _fullscreen = v);
  }

  bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && (ctx.widget is EditableText || ctx.findAncestorStateOfType<EditableTextState>() != null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_typing()) return KeyEventResult.ignored;
    final prefs = context.read<UiPrefs>();
    final k = e.logicalKey;
    final v = _view.currentState;
    if (k == LogicalKeyboardKey.arrowRight) {
      if (e is KeyDownEvent) {
        _held = false;
        _holdTimer = Timer(const Duration(milliseconds: 350), () {
          _held = true;
          ctl.startBoost();
        });
      } else if (e is KeyUpEvent) {
        _holdTimer?.cancel();
        if (_held) {
          ctl.endBoost();
        } else {
          v?.seekBy(prefs.seekStepSec);
        }
        _held = false;
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
      if (e is KeyDownEvent) ctl.player.playOrPause();
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyJ) {
      v?.seekBy(-prefs.seekStepSec);
    } else if (k == LogicalKeyboardKey.keyL) {
      v?.seekBy(prefs.seekStepSec);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      v?.volumeBy(5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      v?.volumeBy(-5);
    } else if (k == LogicalKeyboardKey.bracketRight) {
      v?.cycleSpeed(1);
    } else if (k == LogicalKeyboardKey.bracketLeft) {
      v?.cycleSpeed(-1);
    } else if (k == LogicalKeyboardKey.keyF && e is KeyDownEvent) {
      _setFullscreen(!_fullscreen);
    } else if (k == LogicalKeyboardKey.escape && e is KeyDownEvent) {
      if (_fullscreen) {
        _setFullscreen(false);
      } else {
        return KeyEventResult.ignored;
      }
    } else if (k == LogicalKeyboardKey.keyM && e is KeyDownEvent) {
      ctl.setVolume(ctl.volume > 0 ? 0 : 100);
    } else if (k == LogicalKeyboardKey.keyC && e is KeyDownEvent) {
      prefs.update((p) => p.showSubtitles = !p.showSubtitles);
    } else if (k == LogicalKeyboardKey.keyB && e is KeyDownEvent) {
      ctl.addBookmark().then((b) {
        if (b != null) v?.toast(l10n.playerBookmarkAdded(fmtClock(b.tMs)), Icons.bookmark_added_rounded);
      });
    } else if (k == LogicalKeyboardKey.keyP && e is KeyDownEvent) {
      setState(() => _panel = !_panel);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _ask(String text) {
    final a = context.read<AssistantController>();
    a.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final l = ctl.lecture;
        Widget body;
        if (ctl.loading) {
          body = ColoredBox(color: Colors.black, child: CenteredLoader(label: l10n.playerPreparing));
        } else if (ctl.loadError != null) {
          body = Scaffold(
            appBar: AppBar(),
            body: ErrorState(error: ctl.loadError!, onRetry: ctl.load),
          );
        } else {
          final view = PlayerView(
            key: _view,
            ctl: ctl,
            fullscreen: _fullscreen,
            onFullscreen: () => _setFullscreen(!_fullscreen),
            onBack: () => _fullscreen ? _setFullscreen(false) : Navigator.of(context).maybePop(),
            panelOpen: wide ? _panel : null,
            onTogglePanel: wide && !_fullscreen ? () => setState(() => _panel = !_panel) : null,
          );
          final panel = PlayerSidePanel(
            ctl: ctl,
            onAsk: _ask,
            assistant: const AssistantPanel(docked: true, embedded: true),
          );
          if (_fullscreen) {
            body = view;
          } else if (wide) {
            body = Row(children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(Space.md, Space.md, _panel ? 0 : Space.md, Space.md),
                  child: ClipRRect(borderRadius: BorderRadius.circular(Corners.xl), child: view),
                ),
              ),
              AnimatedSize(
                duration: Motion.medium4,
                curve: Motion.emphasized,
                child: SizedBox(
                  width: _panel ? (width >= 1400 ? 440 : 380) : 0,
                  child: _panel
                      ? Padding(
                          padding: const EdgeInsets.all(Space.md),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Corners.xl),
                            child: ColoredBox(color: cs.surfaceContainerLow, child: panel),
                          ),
                        )
                      : null,
                ),
              ),
            ]);
          } else {
            body = SafeArea(
              child: Column(children: [
                AspectRatio(aspectRatio: 16 / 9, child: view),
                Expanded(child: ColoredBox(color: cs.surface, child: panel)),
              ]),
            );
          }
        }
        return ReportScreen(
          value: {
            'screen': l10n.screenPlayer,
            'lecture_id': widget.lectureId,
            if (l != null) 'lecture': '${l.date} ${l.shortTitle}',
            if (ctl.course != null) 'course': ctl.course!.title,
            if (ctl.course != null) 'course_id': ctl.course!.id,
            'has_transcript': ctl.segments.isNotEmpty ? 'yes' : 'no',
          },
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: _onKey,
            child: Scaffold(
              backgroundColor: _fullscreen ? Colors.black : cs.surfaceContainer,
              body: body,
            ),
          ),
        );
      },
    );
  }
}
