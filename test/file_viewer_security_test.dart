import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/windows/file_viewer_manager.dart';
import 'package:skysecret/core/files/text_document.dart';

class EditorHarness {
  static const native = MethodChannel('mixin.one/desktop_multi_window');
  static const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  static const codec = StandardMethodCodec();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late final FileViewerManager manager;
  String channel = '';
  bool valid = true;
  bool privacy = false;
  int saves = 0;
  int copies = 0;
  int clears = 0;
  Completer<bool>? copying;

  EditorHarness() {
    manager = FileViewerManager(registerWindow: (_) => privacy);
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'createWindow') {
        final config = call.arguments as Map;
        expect(config['hiddenAtLaunch'], isTrue);
        final args = jsonDecode(config['arguments'] as String) as Map;
        expect(args.keys.toSet(), {'type', 'channel', 'locale'});
        channel = args['channel'] as String;
        return 'synthetic-editor';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (_) async => true);
  }

  Future<void> open() => manager.open(
    id: 'synthetic-file',
    name: 'fixture.txt',
    text: 'synthetic content',
    encoding: 'UTF-8',
    locale: 'en',
    isValid: () => valid,
    activity: () {},
    save: (_) async {
      saves++;
      return true;
    },
    copy: (_) async {
      copies++;
      return await copying?.future ?? true;
    },
    clearClipboard: () async {
      clears++;
    },
  );

  Future<dynamic> call(String method, [Object? arguments]) {
    final response = Completer<dynamic>();
    messenger.handlePlatformMessage(
      channels.name,
      codec.encodeMethodCall(MethodCall('methodCall', {'channel': channel, 'method': method, 'arguments': arguments})),
      (data) => response.complete(codec.decodeEnvelope(data!)),
    );
    return response.future;
  }

  Future<void> dispose() async {
    manager.closeAll();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(channels, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('editor refuses secrets and actions until capture policy succeeds', () async {
    final host = EditorHarness();
    addTearDown(host.dispose);
    await host.open();
    expect(await host.call('read'), isNull);
    expect(await host.call('privacy', 123), isFalse);
    expect(await host.call('read'), isNull);
    expect(await host.call('save', 'synthetic edit'), isNull);
    expect(await host.call('copy', 'synthetic copy'), isNull);
    expect(host.saves, 0);
    expect(host.copies, 0);
    host.privacy = true;
    expect(await host.call('privacy', 123), isTrue);
    expect((await host.call('read') as Map)['text'], 'synthetic content');
    host.privacy = false;
    expect(await host.call('privacy', 123), isFalse);
    expect(await host.call('read'), isNull);
  });

  test('editor rejects oversized messages before invoking save or clipboard', () async {
    final host = EditorHarness();
    addTearDown(host.dispose);
    await host.open();
    host.privacy = true;
    await host.call('privacy', 123);
    final oversized = 'x' * (TextDocument.maxBytes + 1);
    expect(await host.call('save', oversized), isFalse);
    expect(await host.call('copy', oversized), isFalse);
    expect(host.saves, 0);
    expect(host.copies, 0);
  });

  test('editor reports clipboard failure and revokes a copy completed after lock', () async {
    final host = EditorHarness();
    addTearDown(host.dispose);
    await host.open();
    host.privacy = true;
    await host.call('privacy', 123);
    host.copying = Completer<bool>()..complete(false);
    expect(await host.call('copy', 'synthetic copy'), isFalse);
    host.copying = Completer<bool>();
    final pending = host.call('copy', 'synthetic copy');
    await Future<void>.delayed(Duration.zero);
    host.valid = false;
    host.copying!.complete(true);
    expect(await pending, isFalse);
    expect(host.clears, 1);
    expect(await host.call('read'), isNull);
  });
}
