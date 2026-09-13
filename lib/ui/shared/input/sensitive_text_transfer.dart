import 'package:flutter/widgets.dart';

abstract final class SensitiveTextTransfer {
  static Future<void> copySelection({
    required TextEditingController controller,
    required Future<bool> Function(String) copy,
    required bool Function() isActive,
    required bool cut,
    bool readOnly = false,
    bool obscureText = false,
  }) async {
    if (isActive() == false || obscureText || (cut && readOnly)) return;

    final value = controller.value;
    final selection = value.selection;
    if (selection.isValid == false || selection.isCollapsed || selection.end > value.text.length) return;

    final copied = await copy(selection.textInside(value.text));
    if (copied && cut && isActive() && controller.value == value) {
      controller.value = TextEditingValue(
        text: value.text.replaceRange(selection.start, selection.end, ''),
        selection: TextSelection.collapsed(offset: selection.start),
      );
    }
  }
}
