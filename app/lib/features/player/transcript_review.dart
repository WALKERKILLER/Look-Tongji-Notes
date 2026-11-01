import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';

class TranscriptReviewBar extends StatefulWidget {
  const TranscriptReviewBar({
    super.key,
    required this.lectureId,
    required this.call,
    required this.onChanged,
  });
  final String lectureId;
  final ApiCall call;
  final void Function(Map<String, dynamic> review, bool visible) onChanged;
  @override
  State<TranscriptReviewBar> createState() => _TranscriptReviewBarState();
}

class _TranscriptReviewBarState extends State<TranscriptReviewBar> {
  Map<String, dynamic> _review = {};
  bool _busy = false, _visible = true;
  String? _error;
  Timer? _poll;
  int _requestVersion = 0;
  String get _path =>
      '/agent/transcript-review/${Uri.encodeComponent(widget.lectureId)}';
  bool get _running =>
      _review['state'] == 'running' && _review['stale'] != true;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _publish(Map value) {
    if (!mounted) return;
    setState(() {
      _review = value.cast<String, dynamic>();
      _error = null;
    });
    widget.onChanged(_review, _visible);
    _poll?.cancel();
    if (_running) _poll = Timer(const Duration(seconds: 3), _refresh);
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final version = ++_requestVersion;
    try {
      final r = await widget.call('GET', _path);
      if (mounted && version == _requestVersion) _publish(r as Map);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _start() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.reviewStart),
        content: Text(l10n.reviewConsent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.reviewStart),
          ),
        ],
      ),
    );
    if (!mounted || yes != true) return;
    await _action('POST');
  }

  Future<void> _action(String method) async {
    _poll?.cancel();
    final version = ++_requestVersion;
    setState(() => _busy = true);
    try {
      final r = await widget.call(method, _path, {});
      if (mounted && version == _requestVersion) _publish(r as Map);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _status() {
    if (_review['stale'] == true) return l10n.reviewStale;
    final n = (_review['suggestions'] as List? ?? [])
        .where((s) => s['dismissed'] != true)
        .length;
    return switch (_review['state']) {
      'running' => l10n.reviewProgress(
        _review['completed'] ?? 0,
        _review['total'] ?? 0,
      ),
      'completed' => l10n.reviewCompleted(n),
      'cancelled' => l10n.reviewCancelled,
      'error' => l10n.reviewFailed,
      'interrupted' => l10n.reviewInterrupted,
      _ => l10n.reviewHint,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : _running
                    ? () => _action('DELETE')
                    : _start,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _running
                            ? Icons.stop_circle_outlined
                            : Icons.spellcheck_rounded,
                      ),
                label: Text(_running ? l10n.reviewCancel : l10n.reviewStart),
              ),
              FilterChip(
                label: Text(l10n.reviewShow),
                selected: _visible,
                onSelected: (v) {
                  setState(() => _visible = v);
                  widget.onChanged(_review, v);
                },
              ),
              IconButton(
                tooltip: l10n.commonRetry,
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Text(
            _status(),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (((_review['rejected'] as num?) ?? 0) > 0)
            Text(
              l10n.reviewFiltered((_review['rejected'] as num).toInt()),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          if (_review['model'] != null)
            Text(
              l10n.reviewModel('${_review['model']}'),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          if (_running)
            LinearProgressIndicator(
              value: ((_review['total'] as num?) ?? 0) > 0
                  ? ((_review['completed'] as num?) ?? 0) /
                        (_review['total'] as num)
                  : null,
            ),
          if (_error != null)
            Text(
              l10n.reviewLoadFailed(_error!),
              style: TextStyle(color: cs.error),
            ),
        ],
      ),
    );
  }
}

/// Original words remain present; only typed, exact-match sidecar guesses are
/// inserted. Search highlighting applies to original text independently.
class ReviewedTranscriptText extends StatelessWidget {
  const ReviewedTranscriptText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    required this.suggestions,
    required this.onDismiss,
  });
  final String text, query;
  final TextStyle style;
  final List<Map<String, dynamic>> suggestions;
  final Future<void> Function(String id) onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final valid =
        suggestions
            .where(
              (a) =>
                  a['dismissed'] != true &&
                  '${a['original'] ?? ''}'.isNotEmpty &&
                  text.split('${a['original']}').length == 2,
            )
            .toList()
          ..sort(
            (a, b) => text
                .indexOf('${a['original']}')
                .compareTo(text.indexOf('${b['original']}')),
          );
    final spans = <InlineSpan>[];
    void original(String part) {
      if (query.isEmpty) {
        spans.add(TextSpan(text: part));
        return;
      }
      var at = 0;
      while (true) {
        final pos = part.indexOf(query, at);
        if (pos < 0) break;
        spans.add(TextSpan(text: part.substring(at, pos)));
        spans.add(
          TextSpan(
            text: query,
            style: TextStyle(
              backgroundColor: cs.tertiaryContainer,
              color: cs.onTertiaryContainer,
            ),
          ),
        );
        at = pos + query.length;
      }
      spans.add(TextSpan(text: part.substring(at)));
    }

    var at = 0;
    for (final a in valid) {
      final end = text.indexOf('${a['original']}') + '${a['original']}'.length;
      if (end < at) continue;
      original(text.substring(at, end));
      spans.add(
        TextSpan(
          text: l10n.reviewGuess('${a['guess']}'),
          style: TextStyle(
            color: cs.tertiary,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            backgroundColor: cs.tertiaryContainer.withValues(alpha: 0.35),
          ),
        ),
      );
      at = end;
    }
    original(text.substring(at));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(children: spans), style: style),
        if (valid.isNotEmpty)
          Wrap(
            spacing: Space.xs,
            children: [
              for (final a in valid)
                ActionChip(
                  avatar: const Icon(Icons.info_outline_rounded, size: 14),
                  label: Text(
                    '${a['original']} → ${a['guess']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => _details(context, a),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _details(BuildContext context, Map<String, dynamic> a) async {
    final dismiss = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.reviewGuess('${a['guess']}')),
        content: SingleChildScrollView(
          child: SelectionArea(
            child: Text(
              l10n.reviewDetails(
                '${a['original']}',
                '${a['reason']}',
                '${a['evidence']}',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(l10n.commonClose),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.reviewDismiss),
          ),
        ],
      ),
    );
    if (dismiss != true || !context.mounted) return;
    try {
      await onDismiss('${a['id']}');
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.reviewLoadFailed(e.toString()))),
        );
    }
  }
}
