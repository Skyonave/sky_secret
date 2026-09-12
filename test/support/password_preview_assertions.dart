import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void expectPasswordFullyVisible(WidgetTester tester) {
  final text = find.byKey(const Key('generated-password'));
  final value = tester.widget<Text>(text).data!;
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  final panel = tester.getRect(find.byKey(const Key('password-panel')));
  final origin = paragraph.localToGlobal(Offset.zero);
  for (var i = 0; i < value.length; i++) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    expect(boxes, isNotEmpty, reason: 'Character $i must be rendered');
    for (final box in boxes) {
      final rect = box.toRect().shift(origin);
      expect(rect.left, greaterThanOrEqualTo(panel.left + 8));
      expect(rect.right, lessThanOrEqualTo(panel.right - 8));
      expect(rect.top, greaterThanOrEqualTo(panel.top + 7));
      expect(rect.bottom, lessThanOrEqualTo(panel.bottom - 7));
    }
  }
}
