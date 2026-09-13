import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/ui/shared/input/sensitive_text_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('copy and cut intents route to the same sensitive transfer with distinct operations', () {
    final transfers = <bool>[];
    final action = SensitiveTextActions.copyAction(({required cut}) async => transfers.add(cut));
    const ActionDispatcher().invokeAction(action, CopySelectionTextIntent.copy);
    const ActionDispatcher().invokeAction(action, const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard));
    expect(transfers, [false, true]);
  });

  test('menu copy and cut never invoke the original unprotected callbacks', () {
    final transfers = <bool>[];
    var standardCopies = 0;
    var toolbarCloses = 0;
    final items = SensitiveTextActions.menuItems(
      original: [
        ContextMenuButtonItem(type: ContextMenuButtonType.copy, onPressed: () => standardCopies++),
        ContextMenuButtonItem(type: ContextMenuButtonType.cut, onPressed: () => standardCopies++),
      ],
      transfer: ({required cut}) async => transfers.add(cut),
      hideToolbar: () => toolbarCloses++,
    );
    for (final item in items) {
      item.onPressed!();
    }
    expect(transfers, [false, true]);
    expect(standardCopies, 0);
    expect(toolbarCloses, 2);
  });

  test('paste and select-all keep their original behavior and menu order', () {
    var pastes = 0;
    var selections = 0;
    final paste = ContextMenuButtonItem(type: ContextMenuButtonType.paste, onPressed: () => pastes++);
    final select = ContextMenuButtonItem(type: ContextMenuButtonType.selectAll, onPressed: () => selections++);
    final items = SensitiveTextActions.menuItems(
      original: [paste, select],
      transfer: ({required cut}) async => fail('Paste must not copy text'),
      hideToolbar: () => fail('The original menu action owns its toolbar'),
    );
    expect(items, [paste, select]);
    for (final item in items) {
      item.onPressed!();
    }
    expect(pastes, 1);
    expect(selections, 1);
  });
}
