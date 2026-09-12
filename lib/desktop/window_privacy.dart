import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

abstract final class WindowPrivacy {
  static final _windows = <int>{};
  static bool _captureAllowed = false;

  static Future<bool> initialize({required bool captureAllowed}) async {
    _captureAllowed = captureAllowed;
    try {
      return registerWindow(await windowManager.getId());
    } catch (_) {
      return false;
    }
  }

  static bool registerWindow(int id) {
    if (!_isOwnWindow(id)) return false;
    _windows.add(id);
    return _apply(id, _captureAllowed);
  }

  static bool setCaptureAllowed(bool allowed) {
    _windows.removeWhere((id) => !_isOwnWindow(id));
    if (_windows.isEmpty) return false;
    var applied = true;
    for (final id in _windows) {
      if (!_apply(id, allowed)) applied = false;
    }
    if (applied) {
      _captureAllowed = allowed;
      return true;
    }
    for (final id in _windows) {
      _apply(id, _captureAllowed);
    }
    return false;
  }

  static bool _isOwnWindow(int id) {
    if (id == 0) return false;
    return using((arena) {
      final processId = arena<Uint32>();
      final window = HWND(Pointer.fromAddress(id));
      return GetWindowThreadProcessId(window, processId) != 0 && processId.value == GetCurrentProcessId();
    });
  }

  static bool _apply(int id, bool captureAllowed) {
    try {
      final window = HWND(Pointer.fromAddress(id));
      final affinity = captureAllowed ? WDA_NONE : WDA_EXCLUDEFROMCAPTURE;
      if (!SetWindowDisplayAffinity(window, affinity).value) return false;
      return using((arena) {
        final actual = arena<Uint32>();
        return GetWindowDisplayAffinity(window, actual).value && actual.value == (captureAllowed ? 0 : 0x11);
      });
    } catch (_) {
      return false;
    }
  }
}
