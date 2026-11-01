import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/study_canvas/study_document.dart';
import '../lib/features/study_canvas/study_pdf_column.dart';
import 'study_canvas_ui_test.dart' as fixture;

StudyCard pdf() => StudyCard(
  id: 'pdf',
  type: 'pdfdoc',
  layer: 'main',
  rect: const Rect.fromLTWH(40, 180, 600, 472),
  title: '操作系统课件.pdf',
  page: 2,
  pageCount: 3,
  pageAspect: 1.5,
  source: 'study-assets/book/source.pdf',
  path: 'study-assets/book/page-2.png',
);
Map page(int n) => {
  'file': 'study-assets/book/page-$n.png',
  'width': 1200,
  'height': 800,
  'text': 'Page $n',
  'boxes': [],
};
StudyStroke ink(String anchor, int page, Offset point) => StudyStroke(
  id: studyId(),
  layer: 'main',
  anchor: anchor,
  page: page,
  points: [InkPoint(point, .7)],
  color: 0xff000000,
  width: 3,
);

class PDFApi extends fixture.FixtureApi {
  PDFApi(super.doc);
  int? fail;
  @override
  Future<dynamic> studyPDFPage(String id, String source, int number) async {
    if (number == fail) throw StateError('temporary renderer failure');
    return page(number);
  }
}

void main() {
  test('page ink survives column expansion, new writing, movement, collapse and reopening', () {
    final d = StudyDocument();
    final root = pdf();
    d.cards.add(root);
    final original = ink(root.id, 2, const Offset(140, 316));
    d.strokes.add(original);
    d.beginPDFColumn(root);
    for (var n = 1; n <= 3; n++) {
      d.appendPDFPage(root, n, page(n));
    }
    final pages = d.pdfPages(root.id);
    expect(pages.map((c) => c.page), [1, 2, 3]);
    expect(pages.every((c) => c.rect.left == root.rect.left), true);
    expect(pages[1].rect.top, greaterThan(pages[0].rect.bottom));
    expect(d.strokes.single.anchor, pages[1].id);
    expect(d.strokes.single.id, original.id);
    final added = ink(
      pages[2].id,
      0,
      pages[2].rect.topLeft + const Offset(100, 120),
    );
    d.addStroke(added);
    d.transformCards(
      {pages[2].id},
      pages[2].rect,
      pages[2].rect.shift(const Offset(100, 50)),
    );
    final reopened = StudyDocument.fromJson(d.json());
    reopened.collapsePDFColumn(root.id);
    expect(reopened.cards.length, 1);
    expect(reopened.strokes.map((s) => s.page), [2, 3]);
    expect(reopened.strokes.every((s) => s.anchor == root.id), true);
    expect(
      (reopened.strokes.first.points.first.p - original.points.first.p)
          .distance,
      lessThan(.001),
    );
    final saved = StudyDocument.fromJson(reopened.json());
    final again = saved.cards.single;
    saved.beginPDFColumn(again);
    for (var n = 1; n <= 3; n++) {
      saved.appendPDFPage(again, n, page(n));
    }
    expect(saved.strokes.map((s) => s.id), [original.id, added.id]);
    expect(saved.strokes.every(saved.strokeVisible), true);
  });

  test(
    'partial expansion resumes without duplicate pages and respects locked ink',
    () {
      final d = StudyDocument();
      final root = pdf();
      d.cards.add(root);
      d.beginPDFColumn(root);
      d.appendPDFPage(root, 1, page(1));
      final reopened = StudyDocument.fromJson(d.json());
      final r = reopened.cards.first;
      reopened.beginPDFColumn(r);
      reopened.appendPDFPage(r, 1, page(1));
      reopened.appendPDFPage(r, 2, page(2));
      reopened.appendPDFPage(r, 3, page(3));
      expect(reopened.pdfPages(r.id).length, 3);
      reopened.layers.add(StudyLayer('locked', '锁定批注', locked: true));
      final s = ink(
        reopened.pdfPages(r.id).first.id,
        1,
        const Offset(100, 350),
      );
      reopened.strokes.add(
        StudyStroke(
          id: s.id,
          layer: 'locked',
          anchor: s.anchor,
          page: 1,
          points: s.points,
          color: s.color,
          width: s.width,
        ),
      );
      final before = reopened.json();
      expect(() => reopened.collapsePDFColumn(r.id), throwsFormatException);
      expect(reopened.json(), before);
    },
  );

  testWidgets(
    'expand directly on canvas, write on a later page and save its binding',
    (t) async {
      final d = StudyDocument()..cards.add(pdf());
      final api = PDFApi(d.json());
      final key = await fixture.open(t, api);
      await t.tap(find.byTooltip('在画布展开为一列'));
      await t.pumpAndSettle();
      final state = key.currentState!;
      final doc = state.document!;
      expect(find.byType(Dialog), findsNothing);
      expect(doc.pdfPages('pdf').length, 3);
      await t.tap(find.byKey(const ValueKey('study-tool-pen')));
      await t.pumpAndSettle();
      final target = doc.pdfPages('pdf')[1];
      final point =
          t.getTopLeft(find.byKey(const ValueKey('study-input'))) +
          doc.camera +
          (target.rect.topLeft + const Offset(120, 130)) * doc.zoom;
      await t.dragFrom(
        point,
        const Offset(50, 25),
        kind: ui.PointerDeviceKind.stylus,
      );
      await t.pumpAndSettle();
      await state.flush();
      final saved = StudyDocument.fromJson(api.doc);
      expect(saved.strokes.where((s) => s.anchor == target.id), isNotEmpty);
      expect(saved.pdfPages('pdf').length, 3);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'failed conversion retains saved pages and retries missing pages',
    (t) async {
      final api = PDFApi((StudyDocument()..cards.add(pdf())).json())..fail = 2;
      final key = await fixture.open(t, api);
      await t.tap(find.byTooltip('在画布展开为一列'));
      await t.pumpAndSettle();
      expect(StudyDocument.fromJson(api.doc).pdfPages('pdf').length, 1);
      api.fail = null;
      await t.tap(find.byTooltip('继续展开整列'));
      await t.pumpAndSettle();
      expect(key.currentState!.document!.pdfPages('pdf').length, 3);
      expect(StudyDocument.fromJson(api.doc).pdfPages('pdf').length, 3);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
