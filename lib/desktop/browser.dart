import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

bool openBrowser(String url) {
  final uri = Uri.tryParse(url);
  if (!Platform.isWindows || uri == null || uri.scheme != 'https' || uri.host.isEmpty || url.contains('\u0000')) {
    return false;
  }
  final com = CoInitializeEx(COINIT_APARTMENTTHREADED);
  if (com.isError && com != RPC_E_CHANGED_MODE) return false;
  try {
    return using((arena) {
      final result = ShellExecute(
        null,
        PCWSTR('open'.toNativeUtf16(allocator: arena)),
        PCWSTR(url.toNativeUtf16(allocator: arena)),
        null,
        null,
        SW_SHOWNORMAL,
      );
      return result.address > 32;
    });
  } finally {
    if (!com.isError) CoUninitialize();
  }
}
