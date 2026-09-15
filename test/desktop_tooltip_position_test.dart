import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/ui/shared/desktop_tooltip.dart';

void main() {
  const overlay = Size(460, 700);
  const tooltip = Size(180, 40);

  test('tooltip starts beside and below the cursor', () {
    expect(
      desktopTooltipPosition(pointer: const Offset(40, 80), tooltip: tooltip, overlay: overlay),
      const Offset(52, 100),
    );
  });

  test('tooltip at the right edge stays inside the window', () {
    expect(
      desktopTooltipPosition(pointer: const Offset(458, 80), tooltip: tooltip, overlay: overlay),
      const Offset(272, 100),
    );
  });

  test('tooltip near the bottom appears above the cursor', () {
    expect(
      desktopTooltipPosition(pointer: const Offset(40, 690), tooltip: tooltip, overlay: overlay),
      const Offset(52, 638),
    );
  });

  test('a constrained child window does not produce invalid clamp bounds', () {
    expect(
      desktopTooltipPosition(pointer: Offset.zero, tooltip: tooltip, overlay: const Size(100, 30)),
      const Offset(8, 8),
    );
  });
}
