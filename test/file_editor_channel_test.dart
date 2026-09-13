import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/windows/file_editor_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('privacy waits for the editor to join the bidirectional channel', () async {
    const channel = WindowMethodChannel('synthetic/editor-registration');
    final registration = Completer<void>();
    var registered = false;
    var windowRequested = false;
    var privacyRequests = 0;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'registerMethodHandler') {
        expect((call.arguments as Map)['mode'], 'bidirectional');
        await registration.future;
        registered = true;
      } else if (call.method == 'invokeMethod') {
        if (!registered) throw PlatformException(code: 'CHANNEL_UNREGISTERED');
        final args = call.arguments as Map;
        expect(args['method'], 'privacy');
        expect(args['arguments'], 123);
        privacyRequests++;
        return true;
      }
      return null;
    });
    addTearDown(() async {
      await channel.setMethodCallHandler(null);
      messenger.setMockMethodCallHandler(native, null);
    });

    final connected = connectFileEditor(
      channel: channel,
      getWindowId: () async {
        windowRequested = true;
        return 123;
      },
      onLock: () async {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(windowRequested, isFalse);
    expect(privacyRequests, 0);
    registration.complete();
    expect(await connected, isTrue);
    expect(privacyRequests, 1);
  });

  test('registration failure stops startup without requesting window or privacy', () async {
    const channel = WindowMethodChannel('synthetic/editor-registration-failure');
    var windowRequested = false;
    messenger.setMockMethodCallHandler(native, (call) async {
      expect(call.method, 'registerMethodHandler');
      throw PlatformException(code: 'CHANNEL_LIMIT_REACHED');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(native, null));
    await expectLater(
      connectFileEditor(
        channel: channel,
        getWindowId: () async {
          windowRequested = true;
          return 123;
        },
        onLock: () async {},
      ),
      throwsA(isA<WindowChannelException>()),
    );
    expect(windowRequested, isFalse);
  });

  test('capture refusal is returned and lock handler is active during setup', () async {
    const channel = WindowMethodChannel('synthetic/editor-lock');
    const codec = StandardMethodCodec();
    var locked = false;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'invokeMethod') {
        final completed = Completer<void>();
        messenger.handlePlatformMessage(
          native.name,
          codec.encodeMethodCall(
            MethodCall('methodCall', {
              'channel': channel.name,
              'method': 'lock',
              'arguments': null,
            }),
          ),
          (_) => completed.complete(),
        );
        await completed.future;
        expect(locked, isTrue);
        return false;
      }
      return null;
    });
    addTearDown(() async {
      await channel.setMethodCallHandler(null);
      messenger.setMockMethodCallHandler(native, null);
    });
    expect(
      await connectFileEditor(
        channel: channel,
        getWindowId: () async => 123,
        onLock: () async {
          locked = true;
        },
      ),
      isFalse,
    );
  });
}
