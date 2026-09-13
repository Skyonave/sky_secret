import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class SensitiveClipboardBoundary {
  Future<bool> Function(String)? _copy;

  void attach(Future<bool> Function(String) copy) => _copy = copy;

  void detach(Future<bool> Function(String) copy) {
    if (_copy == copy) _copy = null;
  }

  Future<bool> write(String text) async => await _copy?.call(text) ?? false;
}

class SensitiveWidgetsBinding extends WidgetsFlutterBinding {
  final SensitiveClipboardBoundary clipboard;

  SensitiveWidgetsBinding(this.clipboard);

  @override
  BinaryMessenger createBinaryMessenger() => SensitiveClipboardMessenger(
    delegate: super.createBinaryMessenger(),
    clipboard: clipboard,
  );
}

class SensitiveClipboardMessenger extends BinaryMessenger {
  final BinaryMessenger delegate;
  final SensitiveClipboardBoundary clipboard;
  static const _codec = JSONMethodCodec();

  const SensitiveClipboardMessenger({required this.delegate, required this.clipboard});

  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    if (channel == 'flutter/platform' && message != null) {
      final call = _codec.decodeMethodCall(message);
      if (call.method == 'Clipboard.setData') {
        try {
          if (call.arguments case {'text': final String text}) {
            if (await clipboard.write(text)) return _codec.encodeSuccessEnvelope(null);
          }
        } catch (_) {
          return _clipboardError();
        }
        return _clipboardError();
      }
    }
    return await delegate.send(channel, message);
  }

  ByteData _clipboardError() => _codec.encodeErrorEnvelope(
    code: 'sensitive_clipboard_unavailable',
    message: 'Protected clipboard write was not completed',
  );

  @override
  void setMessageHandler(String channel, MessageHandler? handler) => delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) async {
    ServicesBinding.instance.channelBuffers.push(channel, data, callback ?? (_) {});
  }
}
