import 'dart:async';

import 'sensitive_clipboard.dart';

class SensitiveClipboardController {
  final SensitiveClipboard clipboard;
  final void Function() onCleared;
  Timer? _timer;
  int? _revision;
  int _generation = 0;
  bool _disposed = false;
  bool _writing = false;

  SensitiveClipboardController({required this.clipboard, required this.onCleared});

  void cancelPendingWrites() => _generation++;

  Future<bool> write(String text) async {
    if (_disposed || _writing) return false;
    _writing = true;
    final generation = _generation;
    try {
      _revision = await clipboard.write(text);
      _timer?.cancel();
      if (_disposed || generation != _generation) {
        await _clearCurrent();
        return false;
      }
      _timer = Timer(const Duration(seconds: 10), _clearCurrent);
      return true;
    } finally {
      _writing = false;
    }
  }

  Future<void> _clearCurrent() async {
    final owned = _revision;
    if (owned == null) return;
    try {
      await clipboard.clearIfCurrent(owned);
    } on ClipboardUnavailable {
      if (_disposed == false && _revision == owned) {
        _timer = Timer(const Duration(seconds: 1), _clearCurrent);
      }
      return;
    }
    if (_revision != owned) return;
    _revision = null;
    if (_disposed == false) onCleared();
  }

  Future<void> clear() async {
    cancelPendingWrites();
    _timer?.cancel();
    await _clearCurrent();
  }

  void dispose() {
    _disposed = true;
    unawaited(clear());
  }
}
