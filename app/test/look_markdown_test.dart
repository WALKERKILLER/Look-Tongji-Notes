import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_studio/widgets/look_markdown.dart';
import 'package:val_latex_flutter/val_latex_flutter.dart';

// Typical model-written note: inline and display math in paragraphs, lists
// and tables, bare environments, padded dollars, timestamps, code.
const note = r'''
### 静压强特性

- 斜面 $ABC$ 面积 $S$，三个坐标面面积 $S_x,\ S_y,\ S_z$ [01:35]：
  $$S_x = S\cos\alpha,\quad S_y = S\cos\beta$$
- 代入 $V=\tfrac13 S_x\,dx$，取极限 $dx\to 0$ 得 $p_x = p_n$。

速度 $ v = \frac{dx}{dt} $ 与区间 $[0:10]$ 无关，见 [12:03]–[13:40]。

$$\rho f_x - \frac{\partial p}{\partial x} = 0,\qquad
\rho f_y - \frac{\partial p}{\partial y} = 0$$

\begin{aligned}
dp &= \rho\left(f_x dx + f_y dy + f_z dz\right) \\
dW &= f_x dx + f_y dy + f_z dz
\end{aligned}

梯度 \( \nabla p \) 与 \[ \vec f = \dfrac{1}{\rho}\nabla p \]

| 量 | 公式 |
|---|---|
| 压强 | $p=F/S$ |

**结论：$p=p(x,y,z)$**，价格 $5 和 $10 不是公式。

```python
cost = "$5"  # [00:10] stays code
```
''';

void main() {
  test('prepareMarkdown repairs math and links timestamps outside math and code', () {
    final out = prepareMarkdown(note);
    expect(out, contains('\$v = \\frac{dx}{dt}\$'));
    expect(out, contains('\$\$\n\\begin{aligned}'));
    expect(out, contains('[01:35](look://seek?t=95)'));
    expect(out, contains('[12:03–13:40](look://seek?t=723&end=820)'));
    expect(out, contains(r'$[0:10]$'));
    expect(out, contains('# [00:10] stays code'));
    expect(prepareMarkdown(r'价格 $ 5 + $ 10'), r'价格 $ 5 + $ 10');
  });

  testWidgets('every formula renders as parsed math', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: LookMarkdown(note, onRef: (_) {}))),
    ));
    await t.pumpAndSettle();
    final maths = t.widgetList<Math>(find.byType(Math)).toList();
    final errors = [for (final m in maths) ...parseLatex(m.tex).diagnostics.map((d) => '${m.tex}: $d')];
    final text = t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('\n');
    expect(errors, isEmpty);
    // List: ABC, S, S_x…, display, tfrac, dx→0, p_x (7); v, [0:10], display
    // block, aligned, \( \), \[ \], table, bold (8).
    expect(maths.length, 15);
    final prose = text.replaceAll('价格 \$5 和 \$10', '').replaceAll('"\$5"', '');
    expect(prose.contains(r'$'), isFalse, reason: text);
    expect(text.contains(r'\begin'), isFalse);
  });
}
