part of 'study_canvas.dart';

class _PDFBody extends StatefulWidget {
  const _PDFBody({required this.owner, required this.card});
  final StudyCanvasState owner;
  final StudyCard card;
  @override
  State<_PDFBody> createState() => _PDFBodyState();
}

class _PDFBodyState extends State<_PDFBody> {
  bool busy = false, selectText = false;
  String? error;
  int? start, end;
  Future<void> page(int number) async {
    if (busy || number < 1 || number > widget.card.pageCount) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final out = await widget.owner.widget.api.studyPDFPage(
        widget.owner.widget.ctl.lectureId,
        widget.card.source,
        number,
      );
      if (!mounted) return;
      final d = widget.owner.document!;
      d.checkpoint();
      widget.card
        ..pageAspect = (out['width'] as num) / (out['height'] as num)
        ..page = number
        ..path = '${out['file']}'
        ..text = '${out['text']}'
        ..textBoxes = (out['boxes'] as List? ?? []).cast<Map>();
      start = null;
      end = null;
      d.changed();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (_, size) {
              final ratio =
                  card.rect.width / math.max(1, card.rect.height - 86);
              var width = size.maxWidth, height = width / ratio;
              if (height > size.maxHeight) {
                height = size.maxHeight;
                width = height * ratio;
              }
              final left = (size.maxWidth - width) / 2,
                  top = (size.maxHeight - height) / 2;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Image(
                      image: ResizeImage(
                        NetworkImage(
                          widget.owner.widget.api.fileUrl(card.path),
                        ),
                        width: 1500,
                        height: 1500,
                        policy: ResizeImagePolicy.fit,
                      ),
                      fit: BoxFit.contain,
                      errorBuilder: (_, e, s) => Center(
                        child: TextButton(
                          onPressed: () => page(card.page),
                          child: const Text('重载此页'),
                        ),
                      ),
                    ),
                  ),
                  if (selectText)
                    Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (e) =>
                            pick(e.localPosition, width, height, true),
                        onPanUpdate: (e) =>
                            pick(e.localPosition, width, height, false),
                        child: CustomPaint(
                          painter: _PDFTextHighlight(
                            card.textBoxes,
                            start,
                            end,
                          ),
                        ),
                      ),
                    ),
                  if (busy) const Center(child: CircularProgressIndicator()),
                ],
              );
            },
          ),
        ),
        if (error != null)
          Text(
            error!,
            maxLines: 2,
            style: const TextStyle(fontSize: 11, color: Colors.red),
          ),
        SizedBox(
          height: 36,
          child: Row(
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: busy || card.page <= 1
                    ? null
                    : () => page(card.page - 1),
                icon: const Icon(Icons.chevron_left, size: 18),
              ),
              Text(
                '${card.page} / ${card.pageCount}',
                style: const TextStyle(fontSize: 12),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: busy || card.page >= card.pageCount
                    ? null
                    : () => page(card.page + 1),
                icon: const Icon(Icons.chevron_right, size: 18),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  widget.owner._chooseTool(StudyTool.select);
                  setState(() => selectText = !selectText);
                },
                child: Text(selectText ? '结束选字' : '选择文字'),
              ),
              if (start != null && end != null)
                TextButton(
                  onPressed: () {
                    widget.owner._selection
                      ..clear()
                      ..add(card.id);
                    widget.owner._detail
                      ..clear()
                      ..objectId = card.id
                      ..start = math.min(start!, end!)
                      ..end = math.max(start!, end!);
                    widget.owner._regionSelection = null;
                    widget.owner._openConversation();
                  },
                  child: const Text('问 AI'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void pick(Offset p, double w, double h, bool first) {
    final boxes = widget.card.textBoxes;
    if (boxes.isEmpty) {
      setState(() => error = '此页没有文字层，请圈选视觉区域后问 AI');
      return;
    }
    final hit = boxes
        .where(
          (b) => Rect.fromLTWH(
            (b['x'] as num).toDouble() * w,
            (b['y'] as num).toDouble() * h,
            (b['w'] as num).toDouble() * w,
            (b['h'] as num).toDouble() * h,
          ).inflate(4).contains(p),
        )
        .firstOrNull;
    if (hit != null)
      setState(() {
        if (first) start = (hit['start'] as num).toInt();
        end = (hit['end'] as num).toInt();
      });
  }
}

class _PDFTextHighlight extends CustomPainter {
  const _PDFTextHighlight(this.boxes, this.start, this.end);
  final List<Map> boxes;
  final int? start, end;
  @override
  void paint(Canvas canvas, Size size) {
    if (start == null || end == null) return;
    for (final b in boxes) {
      if ((b['start'] as num) >= math.min(start!, end!) &&
          (b['end'] as num) <= math.max(start!, end!))
        canvas.drawRect(
          Rect.fromLTWH(
            (b['x'] as num).toDouble() * size.width,
            (b['y'] as num).toDouble() * size.height,
            (b['w'] as num).toDouble() * size.width,
            (b['h'] as num).toDouble() * size.height,
          ),
          Paint()..color = const Color(0x555b7fff),
        );
    }
  }

  @override
  bool shouldRepaint(covariant _PDFTextHighlight old) =>
      old.start != start || old.end != end || old.boxes != boxes;
}
