part of 'study_canvas.dart';

class _PDFBody extends StatefulWidget {
  const _PDFBody({required this.owner, required this.card});
  final StudyCanvasState owner;
  final StudyCard card;
  @override
  State<_PDFBody> createState() => _PDFBodyState();
}

class _PDFBodyState extends State<_PDFBody> {
  bool busy = false;
  String? error;
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
          child: Stack(
            children: [
              Positioned.fill(
                child: Image(
                  image: ResizeImage(
                    NetworkImage(widget.owner.widget.api.fileUrl(card.path)),
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
              if (busy) const Center(child: CircularProgressIndicator()),
            ],
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
            ],
          ),
        ),
      ],
    );
  }
}
