import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:skysecret/core/desktop/system_shortcut.dart';
import 'package:skysecret/core/settings/shortcut_settings.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.leanflutter.plugins/hotkey_manager');
  const events = MethodChannel('dev.leanflutter.plugins/hotkey_manager_event');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(events, (_) async => null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'register') {
        final args = call.arguments as Map;
        expect(
          args['modifiers'],
          isA<List>(),
          reason: 'Windows uses std::get<EncodableList>; null terminates the process',
        );
      }
      return true;
    });
  });

  tearDown(() async {
    await hotKeyManager.unregisterAll();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('bare F reaches the Windows channel as an empty modifier list and unregisters by the same id', () async {
    final key = HotKey(key: PhysicalKeyboardKey.keyF);
    expect(key.toJson()['modifiers'], isNull);
    var presses = 0;
    await registerSystemShortcut(key, keyDownHandler: (_) => presses++);
    final args = calls.single.arguments as Map;
    expect(args['modifiers'], isEmpty);
    expect(args['keyCode'], 0x46);
    expect(args['identifier'], key.identifier);
    binding.defaultBinaryMessenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'type': 'onKeyDown',
        'data': {'identifier': key.identifier},
      }),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(presses, 1);
    await hotKeyManager.unregister(key);
    expect(calls.last.method, 'unregister');
    expect((calls.last.arguments as Map)['identifier'], key.identifier);
    expect(hotKeyManager.registeredHotKeyList, isEmpty);
  });

  test('legacy null modifiers from disk and replacement shortcuts keep valid native arguments', () async {
    final directory = await Directory.systemTemp.createTemp('skysecret-hotkey-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/search_shortcut.json');
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'shortcut': HotKey(key: PhysicalKeyboardKey.keyF).toJson(),
      }),
    );
    final loaded = (await ShortcutStore(file: file).load())!;
    for (final key in [loaded, defaultSearchShortcut(), defaultShortcut(), HotKey(key: PhysicalKeyboardKey.keyK)]) {
      await registerSystemShortcut(key, keyDownHandler: (_) {});
      expect((calls.last.arguments as Map)['modifiers'], key.toJson()['modifiers'] ?? []);
      await hotKeyManager.unregister(key);
    }
  });
}
