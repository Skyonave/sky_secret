import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../../core/desktop/search_session.dart';
import '../../core/os/windows/window_privacy.dart';
import '../../i18n/translations.g.dart';

class VaultSearchPresenter {
  static const _placement = MethodChannel('skysecret/companion');
  final bool Function(int) registerWindow;
  WindowController? _controller;
  WindowMethodChannel? _channel;
  VaultSearchSession? _session;
  Completer<String?>? _selection;
  Future<void>? _warming;
  Future<void> _transition = Future.value();
  Completer<void>? _ready;
  int? _windowId;
  int _epoch = 0;
  bool _disposed = false;
  VoidCallback? _onBlur;
  Future<bool> Function(String)? _copy;
  Future<void> Function()? _clearClipboard;

  VaultSearchPresenter({this.registerWindow = WindowPrivacy.registerWindow});

  Future<void> prepare() {
    if (_disposed) return Future.value();
    return _warming ??= _create();
  }

  Future<void> _create() async {
    final token = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final channel = WindowMethodChannel('skysecret/search/$token');
    final ready = Completer<void>();
    _channel = channel;
    _ready = ready;
    try {
      await channel.setMethodCallHandler((call) async {
        if (_disposed) return null;
        if (call.method == 'privacy') {
          final id = call.arguments;
          _windowId = id is int && registerWindow(id) ? id : null;
          return _windowId != null;
        }
        if (_windowId == null) return null;
        if (call.method == 'ready') {
          if (ready.isCompleted == false) ready.complete();
          return true;
        }
        final args = call.arguments;
        final session = _session;
        final epoch = _epoch;
        bool valid() => _disposed == false && _epoch == epoch && session?.valid == true;
        if (args is! Map || args['epoch'] != epoch || valid() == false) return null;
        switch (call.method) {
          case 'copyQuery':
            final text = args['text'];
            final copy = _copy;
            final clearClipboard = _clearClipboard;
            if (text is! String || text.length > 256 || copy == null || clearClipboard == null) return false;
            final copied = await copy(text);
            if (valid() == false) await clearClipboard();
            return valid() && copied;
          case 'search':
            final query = args['query'];
            return query is String ? session!.search(query) : null;
          case 'select':
            final id = args['id'];
            if (id is String && session!.accepts(id)) {
              _selection?.complete(id);
              _selection = null;
              close();
              return true;
            }
            return false;
          case 'position':
            return await _placement.invokeMethod<bool>('placeSearch', {'window': _windowId, 'gap': 12.0}) == true &&
                valid();
          case 'activity':
            session!.activity();
            return true;
          case 'blur':
            _onBlur?.call();
            return true;
          case 'closed':
            close();
            return true;
        }
        return null;
      });
      _controller = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            'type': 'search',
            'channel': channel.name,
            'locale': LocaleSettings.currentLocale.languageCode,
          }),
        ),
      );
      await ready.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      await _destroy();
      _warming = null;
      rethrow;
    }
  }

  Future<String?> open({
    required bool Function() isValid,
    required List<Map<String, Object>> Function(String) find,
    required VoidCallback activity,
    required VoidCallback onBlur,
    required Future<bool> Function(String) copy,
    required Future<void> Function() clearClipboard,
  }) async {
    if (_disposed || _session != null) return null;
    final session = VaultSearchSession(isValid: isValid, find: find, activity: activity);
    final selected = Completer<String?>();
    final epoch = ++_epoch;
    _session = session;
    _selection = selected;
    _onBlur = onBlur;
    _copy = copy;
    _clearClipboard = clearClipboard;
    try {
      await prepare();
      final previous = _transition;
      final activation = () async {
        await previous;
        if (_epoch != epoch || session.valid == false) return;
        final shown = await _channel!
            .invokeMethod<bool>('activate', {
              'epoch': epoch,
              'locale': LocaleSettings.currentLocale.languageCode,
            })
            .timeout(const Duration(seconds: 5));
        if (_epoch == epoch && shown != true) throw StateError('Search unavailable');
      }();
      _transition = activation.catchError((_) {});
      await activation;
      if (_epoch == epoch && session.valid == false) close();
      return await selected.future;
    } catch (_) {
      if (_epoch == epoch) close();
      rethrow;
    }
  }

  void close() {
    final epoch = _epoch++;
    _session?.close();
    _session = null;
    _selection?.complete(null);
    _selection = null;
    _onBlur = null;
    _copy = null;
    _clearClipboard = null;
    unawaited(_placement.invokeMethod<void>('detachSearch').catchError((_) {}));
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
    if (ready != null && ready.isCompleted == false) ready.complete();
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
    _channel = null;
    _controller = null;
    _windowId = null;
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
