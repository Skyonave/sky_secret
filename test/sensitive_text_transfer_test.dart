import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/ui/shared/input/sensitive_text_transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TextEditingController controller;
  late List<String> writes;
  late bool active;
  late int standardClipboardWrites;

  setUp(() {
    controller = TextEditingController(text: 'prefix synthetic secret suffix');
    controller.selection = const TextSelection(baseOffset: 7, extentOffset: 23);
    writes = [];
    active = true;
    standardClipboardWrites = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') standardClipboardWrites++;
        return null;
      },
    );
  });

  tearDown(() {
    expect(standardClipboardWrites, 0);
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  Future<void> transfer({
    bool cut = false,
    bool readOnly = false,
    bool obscureText = false,
    Future<bool> Function(String)? copy,
  }) => SensitiveTextTransfer.copySelection(
    controller: controller,
    copy:
        copy ??
        (text) async {
          writes.add(text);
          return true;
        },
    isActive: () => active,
    cut: cut,
    readOnly: readOnly,
    obscureText: obscureText,
  );

  test('copy sends only selected text through the sensitive writer', () async {
    final before = controller.value;
    await transfer();
    expect(writes, ['synthetic secret']);
    expect(controller.value, before);
  });

  test('cut deletes selected text only after the sensitive writer succeeds', () async {
    final result = Completer<bool>();
    final pending = transfer(
      cut: true,
      copy: (text) async {
        writes.add(text);
        return await result.future;
      },
    );
    expect(controller.text, 'prefix synthetic secret suffix');
    result.complete(true);
    await pending;
    expect(writes, ['synthetic secret']);
    expect(controller.text, 'prefix  suffix');
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
  });

  test('failed copy preserves the cut selection', () async {
    final before = controller.value;
    await transfer(cut: true, copy: (_) async => false);
    expect(controller.value, before);
  });

  test('late cut cannot edit a changed document or an inactive session', () async {
    for (final deactivate in [false, true]) {
      active = true;
      controller.text = 'synthetic secret';
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 16);
      final result = Completer<bool>();
      final pending = transfer(cut: true, copy: (_) => result.future);
      if (deactivate) {
        active = false;
      } else {
        controller.text = 'replacement draft';
      }
      final before = controller.value;
      result.complete(true);
      await pending;
      expect(controller.value, before);
    }
  });

  test('obscured, inactive and read-only cut paths never write secrets', () async {
    await transfer(obscureText: true);
    await transfer(cut: true, readOnly: true);
    active = false;
    await transfer();
    expect(writes, isEmpty);
  });

  test('read-only copy and reversed selection remain supported', () async {
    controller.selection = const TextSelection(baseOffset: 23, extentOffset: 7);
    await transfer(readOnly: true);
    expect(writes, ['synthetic secret']);
  });

  test('empty and invalid selections never reach the clipboard', () async {
    controller.selection = const TextSelection.collapsed(offset: 7);
    await transfer();
    controller.selection = const TextSelection.collapsed(offset: -1);
    await transfer();
    expect(writes, isEmpty);
  });
}
