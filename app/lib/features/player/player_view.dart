import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../theme/prefs.dart';
import '../../theme/tokens.dart';
import '../../widgets/loading.dart';
import 'lecture_player.dart';
import 'seek_bar.dart';

const kSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

String speedLabel(double s) => '${s.toStringAsFixed(s == s.roundToDouble() ? 1 : 2).replaceAll(RegExp(r'0$'), '')}×';

/// Video surface with custom MD3 controls, gestures and overlays.
class PlayerView extends StatefulWidget {
  const PlayerView({
    super.key,
    required this.ctl,
    required this.fullscreen,
    required this.onFullscreen,
    required this.onBack,
    this.panelOpen,
    this.onTogglePanel,
  });
  final LecturePlayer ctl;
  final bool fullscreen;
  final VoidCallback onFullscreen, onBack;
  final bool? panelOpen;
  final VoidCallback? onTogglePanel;

  @override
  State<PlayerView> createState() => PlayerViewState();
}

class PlayerViewState extends State<PlayerView> {
  bool _controls = true;
  Timer? _hide;
  String? _toast;
  IconData? _toastIcon;
  Timer? _toastTimer;
  bool _menuOpen = false;

  // "Resumed from" prompt, scoped to the player and self-dismissing.
  int? _resumeFrom;
  Timer? _resumeTimer;
  static const _resumeFor = Duration(seconds: 8);

  // Drag gestures (touch).
  double? _dragSeekMs;
  int _dragStartMs = 0;
  double? _dragVol;
  bool _horizontal = true;

  LecturePlayer get ctl => widget.ctl;

  @override
  void initState() {
    super.initState();
    _bump();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _toastTimer?.cancel();
    _resumeTimer?.cancel();
    super.dispose();
  }

  /// Show controls and restart the auto-hide timer.
  void _bump() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && ctl.playing && !_menuOpen) setState(() => _controls = false);
    });
  }

  void toast(String text, IconData icon) {
    _toastTimer?.cancel();
    setState(() {
      _toast = text;
      _toastIcon = icon;
    });
    _toastTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void showResume(int fromMs) {
    _resumeTimer?.cancel();
    setState(() => _resumeFrom = fromMs);
    _resumeTimer = Timer(_resumeFor, _dismissResume);
  }

  void _dismissResume() {
    _resumeTimer?.cancel();
    if (mounted && _resumeFrom != null) setState(() => _resumeFrom = null);
  }

  void seekBy(int s) {
    ctl.seekBy(s);
    toast('${s > 0 ? '+' : ''}$s 秒', s > 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded);
  }

  void volumeBy(double d) {
    final v = (ctl.volume + d).clamp(0.0, 100.0);
    ctl.setVolume(v);
    toast('音量 ${v.round()}%', v == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded);
  }

  void cycleSpeed(int dir) {
    final i = kSpeeds.indexWhere((s) => s >= ctl.rate - 0.01);
    final n = kSpeeds[((i < 0 ? 2 : i) + dir).clamp(0, kSpeeds.length - 1)];
    ctl.setRate(n);
    toast('倍速 ${speedLabel(n)}', Icons.speed_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UiPrefs>();
    final mobile = Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS;
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final showUi = _controls || !ctl.playing;
        return MouseRegion(
          cursor: showUi ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _bump(),
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Colors.black),
            Video(controller: ctl.video, controls: NoVideoControls, fill: Colors.black, wakelock: true),
            // Gestures
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (mobile) {
                  setState(() => _controls = !_controls);
                  if (_controls) _bump();
                } else {
                  ctl.player.playOrPause();
                  _bump();
                }
              },
              onDoubleTapDown: mobile
                  ? (d) {
                      final w = context.size?.width ?? 1;
                      final x = d.localPosition.dx / w;
                      if (x < 0.35) {
                        seekBy(-prefs.seekStepSec);
                      } else if (x > 0.65) {
                        seekBy(prefs.seekStepSec);
                      } else {
                        ctl.player.playOrPause();
                      }
                    }
                  : null,
              onDoubleTap: mobile ? () {} : widget.onFullscreen,
              onLongPressStart: (_) {
                HapticFeedback.lightImpact();
                ctl.startBoost();
              },
              onLongPressEnd: (_) => ctl.endBoost(),
              onPanStart: mobile
                  ? (d) {
                      _horizontal = true;
                      _dragSeekMs = null;
                      _dragVol = null;
                      _dragStartMs = ctl.positionMs;
                    }
                  : null,
              onPanUpdate: mobile
                  ? (d) {
                      final size = context.size ?? const Size(1, 1);
                      if (_dragSeekMs == null && _dragVol == null) {
                        _horizontal = d.delta.dx.abs() >= d.delta.dy.abs();
                        if (_horizontal) {
                          _dragSeekMs = _dragStartMs.toDouble();
                        } else {
                          _dragVol = ctl.volume;
                        }
                      }
                      setState(() {
                        if (_horizontal) {
                          final span = (ctl.duration.inMilliseconds).clamp(60000, 600000).toDouble();
                          _dragSeekMs = (_dragSeekMs! + d.delta.dx / size.width * span).clamp(0, ctl.duration.inMilliseconds.toDouble());
                        } else {
                          _dragVol = (_dragVol! - d.delta.dy / size.height * 150).clamp(0, 100);
                          ctl.setVolume(_dragVol!);
                        }
                      });
                    }
                  : null,
              onPanEnd: mobile
                  ? (_) {
                      if (_dragSeekMs != null) ctl.seekTo(_dragSeekMs!.round());
                      setState(() {
                        _dragSeekMs = null;
                        _dragVol = null;
                      });
                    }
                  : null,
            ),
            // Picture-in-picture second view
            if (ctl.pipVideo != null) _PipWindow(controller: ctl.pipVideo!, label: ctl.sources[ctl.pipIdx!].label, onClose: () => ctl.setPip(null)),
            // Subtitles from the transcript
            if (prefs.showSubtitles && ctl.segments.isNotEmpty)
              Positioned(
                left: 24,
                right: 24,
                bottom: showUi ? 108 : 28,
                child: IgnorePointer(child: _Subtitle(ctl: ctl, scale: prefs.subtitleScale * (widget.fullscreen ? 1.25 : 1))),
              ),
            // Buffering
            if (ctl.buffering && ctl.error == null)
              const Center(child: IgnorePointer(child: ExpressiveLoader(size: 56))),
            if (ctl.error != null) Center(child: _ErrorBox(text: ctl.error!, onRetry: () => ctl.switchSource(ctl.sourceIdx))),
            // Boost pill
            Positioned(
              top: 72,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: Motion.short4,
                    transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: c)),
                    child: ctl.boosting ? _Pill(icon: Icons.fast_forward_rounded, text: '${speedLabel(prefs.boostSpeed)} 快进中', key: const ValueKey('b')) : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            // Center toasts / drag feedback
            Center(
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: Motion.short3,
                  child: _dragSeekMs != null
                      ? _Pill(key: const ValueKey('ds'), icon: Icons.swap_horiz_rounded, text: '${fmtClock(_dragSeekMs!.round())} / ${fmtClock(ctl.duration.inMilliseconds)}', big: true)
                      : _dragVol != null
                          ? _Pill(key: const ValueKey('dv'), icon: Icons.volume_up_rounded, text: '${_dragVol!.round()}%', big: true)
                          : _toast != null
                              ? _Pill(key: ValueKey(_toast), icon: _toastIcon!, text: _toast!, big: true)
                              : const SizedBox.shrink(),
                ),
              ),
            ),
            // Resume prompt: bottom-left, above the controls while they show.
            AnimatedPositioned(
              duration: Motion.medium2,
              curve: Motion.emphasized,
              left: Space.lg,
              bottom: showUi ? 112 : Space.lg,
              child: AnimatedSwitcher(
                duration: Motion.medium2,
                switchInCurve: Motion.emphasizedDecelerate,
                switchOutCurve: Motion.emphasizedAccelerate,
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(-0.15, 0), end: Offset.zero).animate(a), child: c),
                ),
                child: _resumeFrom == null
                    ? const SizedBox.shrink()
                    : _ResumePrompt(
                        key: ValueKey(_resumeFrom),
                        fromMs: _resumeFrom!,
                        duration: _resumeFor,
                        onRestart: () {
                          ctl.seekTo(0);
                          _dismissResume();
                        },
                        onClose: _dismissResume,
                      ),
              ),
            ),
            // Chrome
            _fade(showUi, Align(alignment: Alignment.topCenter, child: _topBar(context))),
            _fade(showUi, Align(alignment: Alignment.bottomCenter, child: _bottomBar(context, prefs))),
          ]),
        );
      },
    );
  }

  /// Eased scrim: several stops so the fade has no visible band.
  static const _scrim = [Color(0xC2000000), Color(0x8A000000), Color(0x3D000000), Color(0x0F000000), Color(0x00000000)];

  /// The chapter under the playhead; opens the outline.
  Widget _chapterChip(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ValueListenableBuilder(
        valueListenable: ctl.position,
        builder: (context, p, _) {
          final i = ctl.chapterAt(p.inMilliseconds);
          if (i < 0) return const SizedBox.shrink();
          final c = ctl.chapters[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: TextButton(
              onPressed: () {
                // The outline lives in the side panel: bring it into view first.
                if (widget.fullscreen) widget.onFullscreen();
                if (widget.panelOpen == false) widget.onTogglePanel?.call();
                ctl.panelTab.value = 'outline';
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.sm)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedSwitcher(
                  duration: Motion.medium2,
                  switchInCurve: Motion.emphasizedDecelerate,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: child),
                  ),
                  child: Row(key: ValueKey(i), mainAxisSize: MainAxisSize.min, children: [
                    Text('${i + 1}/${ctl.chapters.length}', style: tt.labelMedium?.copyWith(color: Colors.white60, fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(width: Space.sm),
                    Flexible(child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.labelLarge?.copyWith(color: Colors.white))),
                    const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white70),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fade(bool show, Widget child) => IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(opacity: show ? 1 : 0, duration: show ? Motion.short4 : Motion.medium2, curve: Motion.standard, child: child),
      );

  Widget _topBar(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final l = ctl.lecture;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _scrim),
      ),
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, Space.xl),
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded), color: Colors.white, tooltip: '返回'),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(l?.shortTitle ?? '', style: tt.titleMedium?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (ctl.course != null)
                Text(ctl.course!.title, style: tt.bodySmall?.copyWith(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (ctl.sources.length > 1) _sourcePicker(context),
          if (widget.onTogglePanel != null)
            IconButton(
              tooltip: widget.panelOpen == true ? '收起侧栏' : '展开侧栏',
              onPressed: widget.onTogglePanel,
              color: Colors.white,
              icon: Icon(widget.panelOpen == true ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined),
            ),
        ]),
      ),
    );
  }

  Widget _sourcePicker(BuildContext context) {
    return MenuAnchor(
      onOpen: () => _menuOpen = true,
      onClose: () {
        _menuOpen = false;
        _bump();
      },
      menuChildren: [
        for (var i = 0; i < ctl.sources.length; i++)
          MenuItemButton(
            leadingIcon: Icon(i == ctl.sourceIdx ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
            trailingIcon: ctl.sources[i].local ? const Icon(Icons.download_done_rounded, size: 18) : null,
            onPressed: () => ctl.switchSource(i),
            child: Text('${ctl.sources[i].label}${ctl.sources[i].local ? '（本地）' : ''}'),
          ),
        const Divider(),
        SubmenuButton(
          leadingIcon: const Icon(Icons.picture_in_picture_alt_rounded),
          menuChildren: [
            MenuItemButton(onPressed: () => ctl.setPip(null), leadingIcon: Icon(ctl.pipIdx == null ? Icons.check_rounded : null), child: const Text('关闭')),
            for (var i = 0; i < ctl.sources.length; i++)
              if (i != ctl.sourceIdx && !ctl.sources[i].local)
                MenuItemButton(
                  onPressed: () => ctl.setPip(i),
                  leadingIcon: Icon(ctl.pipIdx == i ? Icons.check_rounded : null),
                  child: Text(ctl.sources[i].label),
                ),
          ],
          child: const Text('画中画'),
        ),
      ],
      builder: (context, menu, _) => TextButton.icon(
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        icon: const Icon(Icons.videocam_outlined, size: 18),
        label: Text(ctl.source?.label ?? ''),
      ),
    );
  }

  Widget _bottomBar(BuildContext context, UiPrefs prefs) {
    final tt = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    const white = Colors.white;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: _scrim),
      ),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.xxl, Space.lg, Space.sm),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (ctl.chapters.isNotEmpty) _chapterChip(context),
          SeekBar(ctl: ctl, onInteract: _bump),
          const SizedBox(height: Space.xs),
          Row(children: [
            _PlayButton(playing: ctl.playing, onPressed: () => ctl.player.playOrPause()),
            const SizedBox(width: Space.xs),
            if (!compact) ...[
              IconButton(tooltip: '后退 ${prefs.seekStepSec} 秒 (←)', onPressed: () => seekBy(-prefs.seekStepSec), color: white, icon: const Icon(Icons.replay_10_rounded)),
              IconButton(tooltip: '前进 ${prefs.seekStepSec} 秒 (→)', onPressed: () => seekBy(prefs.seekStepSec), color: white, icon: const Icon(Icons.forward_10_rounded)),
              _VolumeControl(ctl: ctl),
            ],
            const SizedBox(width: Space.sm),
            ValueListenableBuilder(
              valueListenable: ctl.position,
              builder: (_, p, _) => Text.rich(
                TextSpan(children: [
                  TextSpan(text: fmtClock(p.inMilliseconds)),
                  TextSpan(text: '  /  ${fmtClock(ctl.duration.inMilliseconds)}', style: const TextStyle(color: Colors.white60)),
                ]),
                style: tt.labelLarge?.copyWith(color: white, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            const Spacer(),
            MenuAnchor(
              onOpen: () => _menuOpen = true,
              onClose: () {
                _menuOpen = false;
                _bump();
              },
              menuChildren: [
                for (final s in kSpeeds)
                  MenuItemButton(
                    onPressed: () => ctl.setRate(s),
                    leadingIcon: Icon((ctl.rate - s).abs() < 0.01 ? Icons.check_rounded : null),
                    child: Text(speedLabel(s)),
                  ),
              ],
              builder: (context, menu, _) => Tooltip(
                message: '倍速 ([ / ])',
                child: TextButton(
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  style: TextButton.styleFrom(
                    foregroundColor: white,
                    backgroundColor: (ctl.rate - 1).abs() < 0.01 ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.24),
                    minimumSize: const Size(56, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(speedLabel(ctl.rate), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
            ),
            if (ctl.segments.isNotEmpty)
              IconButton(
                tooltip: '字幕 (C)',
                onPressed: () => prefs.update((p) => p.showSubtitles = !p.showSubtitles),
                color: white,
                icon: Icon(prefs.showSubtitles ? Icons.closed_caption_rounded : Icons.closed_caption_off_outlined),
              ),
            IconButton(
              tooltip: '添加书签 (B)',
              onPressed: () async {
                final b = await ctl.addBookmark();
                if (b != null) toast('已添加书签 ${fmtClock(b.tMs)}', Icons.bookmark_added_rounded);
              },
              color: white,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
            IconButton(
              tooltip: widget.fullscreen ? '退出全屏 (F)' : '全屏 (F)',
              onPressed: widget.onFullscreen,
              color: white,
              icon: Icon(widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _VolumeControl extends StatefulWidget {
  const _VolumeControl({required this.ctl});
  final LecturePlayer ctl;
  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _hover = false;
  double _before = 100;
  @override
  Widget build(BuildContext context) {
    final v = widget.ctl.volume;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: '静音 (M)',
          color: Colors.white,
          onPressed: () {
            if (v > 0) {
              _before = v;
              widget.ctl.setVolume(0);
            } else {
              widget.ctl.setVolume(_before);
            }
          },
          icon: Icon(v == 0 ? Icons.volume_off_rounded : v < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
        ),
        AnimatedContainer(
          duration: Motion.medium1,
          curve: Motion.emphasized,
          width: _hover ? 96 : 0,
          child: ClipRect(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 4, overlayShape: SliderComponentShape.noOverlay),
              child: Slider(value: v.clamp(0, 100), max: 100, onChanged: widget.ctl.setVolume),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.ctl, required this.scale});
  final LecturePlayer ctl;
  final double scale;
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ctl.position,
      builder: (context, p, _) {
        final i = ctl.segmentAt(p.inMilliseconds);
        final seg = i >= 0 && ctl.segments[i].endMs + 600 >= p.inMilliseconds ? ctl.segments[i] : null;
        return Center(
          child: AnimatedSwitcher(
            duration: Motion.short3,
            child: seg == null
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey(seg.idx),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(Corners.sm)),
                    child: Text(seg.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 17 * scale, height: 1.35, fontWeight: FontWeight.w500)),
                  ),
          ),
        );
      },
    );
  }
}

/// "Resumed from mm:ss · 从头播放", with a hairline that runs out as the
/// prompt times out.
class _ResumePrompt extends StatelessWidget {
  const _ResumePrompt({super.key, required this.fromMs, required this.duration, required this.onRestart, required this.onClose});
  final int fromMs;
  final Duration duration;
  final VoidCallback onRestart, onClose;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xE6202124),
      borderRadius: BorderRadius.circular(Corners.md),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.xs, Space.xs),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.history_rounded, size: 18, color: Colors.white70),
            const SizedBox(width: Space.sm),
            Text('已从 ${fmtClock(fromMs)} 继续', style: tt.bodyMedium?.copyWith(color: Colors.white)),
            const SizedBox(width: Space.sm),
            TextButton(
              onPressed: onRestart,
              style: TextButton.styleFrom(foregroundColor: cs.inversePrimary, visualDensity: VisualDensity.compact),
              child: const Text('从头播放'),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: Colors.white70,
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: 0),
          duration: duration,
          builder: (_, v, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(widthFactor: v, child: Container(height: 2, color: cs.inversePrimary.withValues(alpha: 0.7))),
          ),
        ),
      ]),
    );
  }
}

/// Play/pause that morphs: a circle while paused, a rounded square while
/// playing (M3 Expressive shape morph).
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});
  final bool playing;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(playing ? 14 : 24);
    return Tooltip(
      message: playing ? '暂停 (空格)' : '播放 (空格)',
      child: AnimatedContainer(
        duration: Motion.medium2,
        curve: Motion.emphasized,
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: Colors.white, borderRadius: r),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onPressed,
            child: AnimatedSwitcher(
              duration: Motion.short4,
              transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
              child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing), size: 28, color: Colors.black87),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.icon, required this.text, this.big = false});
  final IconData icon;
  final String text;
  final bool big;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: big ? 18 : 14, vertical: big ? 10 : 6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.66), borderRadius: BorderRadius.circular(Corners.full)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: big ? 22 : 18),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: Colors.white, fontSize: big ? 16 : 14, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(Space.xl),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(Corners.xl)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 36),
          const SizedBox(height: Space.md),
          Text('播放出错', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: Space.xs),
          Text(text, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: Space.lg),
          FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('重新加载')),
        ]),
      );
}

/// Draggable floating second camera that snaps to the nearest corner.
class _PipWindow extends StatefulWidget {
  const _PipWindow({required this.controller, required this.label, required this.onClose});
  final VideoController controller;
  final String label;
  final VoidCallback onClose;
  @override
  State<_PipWindow> createState() => _PipWindowState();
}

class _PipWindowState extends State<_PipWindow> {
  Alignment _corner = Alignment.topRight;
  Offset? _drag;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth * 0.26).clamp(160.0, 360.0);
      final h = w * 9 / 16;
      const m = 16.0;
      final base = Offset(
        _corner.x < 0 ? m : c.maxWidth - w - m,
        _corner.y < 0 ? 72 : c.maxHeight - h - 112,
      );
      final pos = _drag ?? base;
      return Stack(children: [
        AnimatedPositioned(
          duration: _drag == null ? Motion.medium4 : Duration.zero,
          curve: Motion.emphasized,
          left: pos.dx,
          top: pos.dy,
          width: w,
          height: h,
          child: GestureDetector(
            onPanStart: (_) => setState(() => _drag = base),
            onPanUpdate: (d) => setState(() => _drag = _drag! + d.delta),
            onPanEnd: (_) => setState(() {
              final cx = _drag!.dx + w / 2, cy = _drag!.dy + h / 2;
              _corner = Alignment(cx < c.maxWidth / 2 ? -1 : 1, cy < c.maxHeight / 2 ? -1 : 1);
              _drag = null;
            }),
            child: Material(
              elevation: 6,
              color: Colors.black,
              borderRadius: BorderRadius.circular(Corners.lg),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                Video(controller: widget.controller, controls: NoVideoControls, wakelock: false),
                Positioned(
                  left: 8,
                  top: 6,
                  child: Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 4)])),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(onPressed: widget.onClose, iconSize: 18, color: Colors.white, icon: const Icon(Icons.close_rounded)),
                ),
              ]),
            ),
          ),
        ),
      ]);
    });
  }
}
