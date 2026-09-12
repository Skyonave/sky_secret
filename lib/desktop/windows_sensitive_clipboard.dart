import 'dart:ffi';
import 'dart:typed_data';

import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import 'sensitive_clipboard.dart';

class WindowsSensitiveClipboard implements SensitiveClipboard {
  static const privacyFormats = [
    'ExcludeClipboardContentFromMonitorProcessing',
    'CanIncludeInClipboardHistory',
    'CanUploadToCloudClipboard',
  ];

  Future<HWND> _owner() async {
    final id = await windowManager.getId();
    if (id == 0) throw const ClipboardUnavailable();
    return HWND(Pointer.fromAddress(id));
  }

  static int _format(String name) {
    final nativeName = name.toPcwstr();
    try {
      final format = RegisterClipboardFormat(nativeName).value;
      if (format == 0) throw const ClipboardUnavailable();
      return format;
    } finally {
      free(nativeName);
    }
  }

  static HGLOBAL _allocate(Uint8List bytes) {
    final memory = GlobalAlloc(
      GMEM_MOVEABLE | GMEM_ZEROINIT,
      bytes.length,
    ).value;
    if (!memory.isValid) throw const ClipboardUnavailable();
    final pointer = GlobalLock(memory).value;
    if (pointer == nullptr) {
      GlobalFree(memory);
      throw const ClipboardUnavailable();
    }
    try {
      pointer.cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
    } finally {
      GlobalUnlock(memory);
    }
    return memory;
  }

  Future<void> _open(HWND owner) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      if (OpenClipboard(owner).value) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw const ClipboardUnavailable();
  }

  @override
  Future<int> write(String text) async {
    final owner = await _owner();
    final pending = <(int, HGLOBAL)>[];
    var opened = false;
    try {
      for (final name in privacyFormats) {
        pending.add((_format(name), _allocate(Uint8List(4))));
      }
      final utf16 = Uint16List.fromList([...text.codeUnits, 0]);
      try {
        pending.add((CF_UNICODETEXT, _allocate(utf16.buffer.asUint8List())));
      } finally {
        utf16.fillRange(0, utf16.length, 0);
      }
      await _open(owner);
      opened = true;
      if (!EmptyClipboard().value) throw const ClipboardUnavailable();
      while (pending.isNotEmpty) {
        final (format, memory) = pending.first;
        if (SetClipboardData(format, HANDLE(memory)).value == nullptr) {
          EmptyClipboard();
          throw const ClipboardUnavailable();
        }
        pending.removeAt(0);
      }
      CloseClipboard();
      opened = false;
      return GetClipboardSequenceNumber();
    } finally {
      if (opened) CloseClipboard();
      for (final (_, memory) in pending) {
        final pointer = GlobalLock(memory).value;
        if (pointer != nullptr) {
          pointer.cast<Uint8>().asTypedList(GlobalSize(memory).value).fillRange(0, GlobalSize(memory).value, 0);
          GlobalUnlock(memory);
        }
        GlobalFree(memory);
      }
    }
  }

  @override
  Future<bool> clearIfCurrent(int revision) async {
    final owner = await _owner();
    await _open(owner);
    try {
      if (GetClipboardSequenceNumber() != revision || GetClipboardOwner().value != owner) {
        return false;
      }
      if (!EmptyClipboard().value) throw const ClipboardUnavailable();
      return true;
    } finally {
      CloseClipboard();
    }
  }
}
