import 'dart:ffi';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

Rect windowWorkArea(int id) => using((arena) {
  final window = win32.HWND(Pointer.fromAddress(id));
  final monitor = win32.MonitorFromWindow(window, win32.MONITOR_DEFAULTTONEAREST);
  final info = arena<win32.MONITORINFO>()..ref.cbSize = sizeOf<win32.MONITORINFO>();
  if (!win32.GetMonitorInfo(monitor, info)) throw StateError('Monitor unavailable');
  final dpi = win32.GetDpiForWindow(window);
  if (dpi == 0) throw StateError('Window scale unavailable');
  final scale = dpi / 96;
  final work = info.ref.rcWork;
  return Rect.fromLTRB(work.left / scale, work.top / scale, work.right / scale, work.bottom / scale);
});
