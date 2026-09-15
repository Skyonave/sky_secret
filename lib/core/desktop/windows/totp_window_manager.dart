import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../os/windows/window_privacy.dart';
import '../../os/windows/window_work_area.dart';
import '../totp_session.dart';
import '../totp_window_layout.dart';

class TotpWindowManager {
  static const _placement = MethodChannel('skysecret/companion');
  int? _windowId;
  final bool Function(int) _registerWindow;
  final Rect Function(int) _workArea;
  WindowController? _controller;
  WindowMethodChannel? _channel;
  TotpSession? _session;
  VoidCallback? _onBlur;
  Future<void>? _warming;
  Future<void> _transition = Future.value();
  Completer<void>? _ready;
  int _epoch = 0;
  bool _private = false;
  bool _disposed = false;

  TotpWindowManager({this._registerWindow = WindowPrivacy.registerWindow, this._workArea = windowWorkArea});

  bool get isOpen => _session?.valid == true;

  Future<void> prepare(String locale) {
    if (_disposed) return Future.value();
    return _warming ??= _create(locale);
  }

  Future<void> _create(String locale) async {
    final token = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final channel = WindowMethodChannel('skysecret/totp/$token');
    final ready = Completer<void>();
    _channel = channel;
    _ready = ready;
    try {
      await channel.setMethodCallHandler((call) async {
        if (_disposed) return null;
        if (call.method == 'privacy') {
          _private = call.arguments is int && _registerWindow(call.arguments as int);
          _windowId = _private ? call.arguments as int : null;
          return _private;
        }
        if (_private == false) return null;
        if (call.method == 'ready') {
          if (!ready.isCompleted) ready.complete();
          return true;
        }
        final args = call.arguments;
        final session = _session;
        final epoch = _epoch;
        bool valid() => _disposed == false && _epoch == epoch && session?.valid == true;
        if (args is! Map || args['epoch'] != epoch || valid() == false) return null;
        switch (call.method) {
          case 'closed':
            close();
            return true;
          case 'read':
            final rows = await session!.snapshot(DateTime.now());
            final area = await _placement.invokeMapMethod<String, num>('bounds');
            if (area == null || valid() == false) return null;
            final bounds = Rect.fromLTWH(
              area['x']!.toDouble(),
              area['y']!.toDouble(),
              area['width']!.toDouble(),
              area['height']!.toDouble(),
            );
            final size = totpWindowSize(bounds, _workArea(await windowManager.getId()), count: rows.length);
            if (valid() == false) return null;
            return {'rows': rows, 'width': size.width, 'height': size.height};
          case 'position':
            return await _placement.invokeMethod<bool>('place', {'window': _windowId, 'gap': totpWindowGap}) == true &&
                valid();
          case 'copy':
            final id = args['id'];
            if (id is String && id.length <= 65536) return session!.copyCode(id, DateTime.now());
            return false;
          case 'activity':
            session!.activity();
            return true;
          case 'blur':
            _onBlur?.call();
            return true;
        }
        return null;
      });
      _controller = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({'type': 'totp', 'channel': channel.name, 'locale': locale}),
        ),
      );
      await ready.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      await _destroy();
      _warming = null;
      rethrow;
    }
  }

  Future<void> open({
    required TotpSession session,
    required String locale,
    required VoidCallback onBlur,
  }) async {
    if (_disposed || isOpen) {
      session.close();
      return;
    }
    final epoch = ++_epoch;
    _session = session;
    _onBlur = onBlur;
    bool valid() => _disposed == false && _epoch == epoch && session.valid;
    try {
      await prepare(locale);
      final previous = _transition;
      final activation = () async {
        await previous;
        if (valid() == false) return;
        final shown = await _channel!
            .invokeMethod<bool>('activate', {'epoch': epoch, 'locale': locale})
            .timeout(const Duration(seconds: 5));
        if (valid() && shown != true) throw StateError('Companion window unavailable');
      }();
      _transition = activation.catchError((_) {});
      await activation;
    } catch (_) {
      if (_epoch == epoch) close();
      rethrow;
    }
  }

  void close() {
    final epoch = _epoch++;
    _session?.close();
    _session = null;
    _onBlur = null;
    unawaited(_placement.invokeMethod<void>('detach').catchError((_) {}));
    final locking = _channel?.invokeMethod('lock', epoch).timeout(const Duration(seconds: 3)).catchError((_) => null);
    final previous = _transition;
    _transition = () async {
      await previous;
      try {
        await _controller?.hide();
        await locking;
      } catch (_) {}
    }();
  }

  void dispose() {
    close();
    _disposed = true;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.complete();
    unawaited(() async {
      try {
        await _warming;
      } catch (_) {}
      await _transition;
      await _destroy();
    }());
  }

  Future<void> _destroy() async {
    final channel = _channel;
    final controller = _controller;
    _controller = null;
    _channel = null;
    _private = false;
    _windowId = null;
    try {
      await _placement.invokeMethod<void>('detach');
    } catch (_) {}
    try {
      await controller?.hide();
    } catch (_) {}
    try {
      await channel?.invokeMethod('shutdown').timeout(const Duration(seconds: 1));
    } catch (_) {}
    try {
      await channel?.setMethodCallHandler(null);
    } catch (_) {}
  }
}
