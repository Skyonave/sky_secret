import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:skysecret/core/settings/shortcut_settings.dart';

void main() {
  test('search defaults to F and is saved independently of the manager shortcut', () async {
    final directory = await Directory.systemTemp.createTemp('search-shortcut-test-');
    addTearDown(() => directory.delete(recursive: true));
    final manager = ShortcutStore(file: File('${directory.path}/settings.json'));
    final search = ShortcutStore(file: File('${directory.path}/search_shortcut.json'));
    expect(shortcutLabel(defaultSearchShortcut()), 'F');
    expect(defaultSearchShortcut().scope, HotKeyScope.system);
    await manager.save(defaultShortcut());
    await search.save(defaultSearchShortcut());
    final replacement = HotKey(key: PhysicalKeyboardKey.keyK, modifiers: [HotKeyModifier.control]);
    await search.save(replacement);
    expect(sameShortcut((await search.load())!, replacement), isTrue);
    expect(sameShortcut((await manager.load())!, defaultShortcut()), isTrue);
  });
  test(
    'shortcut survives restart and replacement, corrupt settings rejected',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'skysecret-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/settings.json');
      final store = ShortcutStore(file: file);
      expect(await store.load(), isNull);
      await store.save(defaultShortcut());
      final key = HotKey(
        key: PhysicalKeyboardKey.keyK,
        modifiers: [HotKeyModifier.alt, HotKeyModifier.control],
      );
      await store.save(key);
      final restored = await ShortcutStore(file: file).load();
      expect(sameShortcut(key, restored!), isTrue);
      expect(shortcutLabel(restored), 'Ctrl + Alt + K');
      await file.writeAsString('{"version":99}');
      await expectLater(store.load(), throwsFormatException);
    },
  );
}
