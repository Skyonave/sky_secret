import 'dart:ffi' hide Size;
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

import '../../desktop/totp_window_layout.dart';

final _gdi = DynamicLibrary.open('gdi32.dll');
final _roundRegion = _gdi
    .lookupFunction<
      Pointer<Void> Function(Int32, Int32, Int32, Int32, Int32, Int32),
      Pointer<Void> Function(int, int, int, int, int, int)
    >('CreateRoundRectRgn');
final _combineRegion = _gdi
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Int32),
      int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, int)
    >('CombineRgn');

void configureTotpWindowFrame(int id) => using((arena) {
  final window = win32.HWND(Pointer.fromAddress(id));
  final border = arena<Uint32>()..value = 0xFFFFFFFE;
  final corners = arena<Int32>()..value = 1;
  win32.DwmSetWindowAttribute(window, win32.DWMWA_BORDER_COLOR, border.cast(), sizeOf<Uint32>());
  win32.DwmSetWindowAttribute(window, win32.DWMWA_WINDOW_CORNER_PREFERENCE, corners.cast(), sizeOf<Int32>());
});

void setTotpWindowRegion(int id, Size size) {
  final window = win32.HWND(Pointer.fromAddress(id));
  final dpi = win32.GetDpiForWindow(window);
  if (dpi == 0) throw StateError('Window scale unavailable');
  final scale = dpi / 96;
  final combined = win32.CreateRectRgn(0, 0, 0, 0);
  if (combined.address == 0) throw StateError('Window region unavailable');
  var transferred = false;
  try {
    for (final rect in totpTileRects(size)) {
      final tile = _roundRegion(
        (rect.left * scale).round(),
        (rect.top * scale).round(),
        (rect.right * scale).round(),
        (rect.bottom * scale).round(),
        (totpTileRadius * 2 * scale).round(),
        (totpTileRadius * 2 * scale).round(),
      );
      if (tile.address == 0) throw StateError('Tile region unavailable');
      try {
        if (_combineRegion(combined.cast(), combined.cast(), tile, 2) == 0) {
          throw StateError('Tile region unavailable');
        }
      } finally {
        win32.DeleteObject(win32.HGDIOBJ(tile));
      }
    }
    transferred = win32.SetWindowRgn(window, combined, true) != 0;
    if (transferred == false) throw StateError('Window shape unavailable');
  } finally {
    if (transferred == false) win32.DeleteObject(win32.HGDIOBJ(combined));
  }
}

void setRoundedWindowRegion(int id, Size size, double radius) {
  final window = win32.HWND(Pointer.fromAddress(id));
  final dpi = win32.GetDpiForWindow(window);
  if (dpi == 0) throw StateError('Window scale unavailable');
  final scale = dpi / 96;
  final region = _roundRegion(
    0,
    0,
    (size.width * scale).round(),
    (size.height * scale).round(),
    (radius * 2 * scale).round(),
    (radius * 2 * scale).round(),
  );
  if (region.address == 0) throw StateError('Window region unavailable');
  if (win32.SetWindowRgn(window, win32.HRGN(region), true) == 0) {
    win32.DeleteObject(win32.HGDIOBJ(region));
    throw StateError('Window shape unavailable');
  }
}
