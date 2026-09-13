import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/clipboard/sensitive_clipboard_boundary.dart';

class _PlatformMessenger extends BinaryMessenger {
  final messages = <({String channel, ByteData? message})>[];
  final handlers = <String, MessageHandler?>{};
  ByteData? response;

  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    messages.add((channel: channel, message: message));
    return response;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) => handlers[channel] = handler;

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) async {
    callback?.call(await handlers[channel]?.call(data));
  }
}

void main() {
  const codec = JSONMethodCodec();
  late _PlatformMessenger platform;
  late SensitiveClipboardBoundary boundary;
  late SensitiveClipboardMessenger messenger;

  setUp(() {
    platform = _PlatformMessenger();
    boundary = SensitiveClipboardBoundary();
    messenger = SensitiveClipboardMessenger(delegate: platform, clipboard: boundary);
  });

  Future<Object?> sendCopy(Object? arguments) async {
    final message = codec.encodeMethodCall(MethodCall('Clipboard.setData', arguments));
    final response = await messenger.send('flutter/platform', message);
    return codec.decodeEnvelope(response!);
  }

  test('direct framework and accessibility copies cannot reach the ordinary clipboard', () async {
    final copied = <String>[];
    boundary.attach((text) async {
      copied.add(text);
      return true;
    });
    expect(await sendCopy({'text': 'synthetic sensitive text'}), isNull);
    expect(copied, ['synthetic sensitive text']);
    expect(platform.messages, isEmpty);
  });

  test('missing, failing and detached writers fail closed without a native fallback', () async {
    Future<bool> writer(String text) async => false;
    for (final configure in <void Function()>[
      () {},
      () => boundary.attach(writer),
      () => boundary.attach((_) async => throw StateError('synthetic writer failure')),
      () {
        boundary.attach(writer);
        boundary.detach(writer);
      },
    ]) {
      configure();
      await expectLater(
        sendCopy({'text': 'synthetic private value'}),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'sensitive_clipboard_unavailable',
          ),
        ),
      );
    }
    expect(platform.messages, isEmpty);
  });

  test('an old owner cannot detach the replacement clipboard writer', () async {
    Future<bool> oldWriter(String text) async => false;
    Future<bool> currentWriter(String text) async => true;
    boundary.attach(oldWriter);
    boundary.attach(currentWriter);
    boundary.detach(oldWriter);
    expect(await sendCopy({'text': 'synthetic text'}), isNull);
    boundary.detach(currentWriter);
    await expectLater(sendCopy({'text': 'synthetic text'}), throwsA(isA<PlatformException>()));
  });

  test('malformed clipboard payload never reaches a writer or native clipboard', () async {
    boundary.attach((_) async => fail('Invalid payload must not reach the writer'));
    await expectLater(sendCopy({'text': 42}), throwsA(isA<PlatformException>()));
    await expectLater(sendCopy(null), throwsA(isA<PlatformException>()));
    expect(platform.messages, isEmpty);
  });

  test('clipboard reads and other platform channels keep their original messages', () async {
    final read = codec.encodeMethodCall(const MethodCall('Clipboard.getData', 'text/plain'));
    platform.response = codec.encodeSuccessEnvelope({'text': 'synthetic paste'});
    final response = await messenger.send('flutter/platform', read);
    expect(codec.decodeEnvelope(response!), {'text': 'synthetic paste'});
    expect(platform.messages.single.message, same(read));
    final binary = ByteData(3);
    await messenger.send('synthetic/channel', binary);
    expect(platform.messages.last.channel, 'synthetic/channel');
    expect(platform.messages.last.message, same(binary));
  });
}
