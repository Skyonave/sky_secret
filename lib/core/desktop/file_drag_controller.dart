import 'dart:async';

import 'package:flutter/services.dart';

import '../crypto/crypto.dart';

class FileDragController {
  static const _channel = MethodChannel('skysecret/file_drag');
  static int _sequence = 0;
  final Future<Object?> Function(String method, Object? arguments) _invoke;
  final void Function(bool active)? onActiveChanged;
  int? _active;
  bool _disposed = false;

  FileDragController({
    Future<Object?> Function(String method, Object? arguments)? invoke,
    this.onActiveChanged,
  }) : _invoke = invoke ?? ((method, arguments) => _channel.invokeMethod<Object?>(method, arguments));

  bool get active => _active != null;

  Future<bool> start({
    required VaultAttachment attachment,
    required bool Function() allowed,
  }) async {
    if (_disposed || active || !allowed()) return false;
    final id = ++_sequence;
    _active = id;
    onActiveChanged?.call(true);
    try {
      final epoch = await _invoke('prepare', null);
      if (_disposed || _active != id || !allowed() || epoch is! int || epoch < 0) return false;
      final protected = attachment.copyProtectedMemory();
      try {
        final copied = await _invoke('start', {
          'id': id,
          'epoch': epoch,
          'name': attachment.name,
          'size': attachment.size,
          'data': protected,
        });
        return copied == true && !_disposed && _active == id && allowed();
      } finally {
        protected.fillRange(0, protected.length, 0);
      }
    } finally {
      if (_active == id) {
        _active = null;
        onActiveChanged?.call(false);
      }
    }
  }

  void cancel() {
    final id = _active;
    if (id == null) return;
    _active = null;
    onActiveChanged?.call(false);
    unawaited(_invoke('cancel', id).catchError((_) => null));
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
