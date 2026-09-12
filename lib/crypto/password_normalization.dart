import 'dart:ffi';

import 'package:ffi/ffi.dart';

final _normalizeString = DynamicLibrary.open('normaliz.dll')
    .lookupFunction<
      Int32 Function(Int32, Pointer<Utf16>, Int32, Pointer<Utf16>, Int32),
      int Function(int, Pointer<Utf16>, int, Pointer<Utf16>, int)
    >('NormalizeString');

String normalizeMasterPassword(String password) {
  if (password.isEmpty || password.length > 1024 * 1024) throw const FormatException();
  final input = password.toNativeUtf16();
  try {
    var capacity = _normalizeString(1, input, password.length, nullptr, 0);
    for (var attempt = 0; attempt < 3; attempt++) {
      if (capacity <= 0 || capacity > 4 * 1024 * 1024) throw const FormatException();
      final allocatedCapacity = capacity;
      final output = calloc<Uint16>(allocatedCapacity);
      try {
        final count = _normalizeString(1, input, password.length, output.cast(), capacity);
        if (count > 0 && count <= capacity) return output.cast<Utf16>().toDartString(length: count);
        if (count == 0) throw const FormatException();
        capacity = -count;
      } finally {
        output.asTypedList(allocatedCapacity).fillRange(0, allocatedCapacity, 0);
        calloc.free(output);
      }
    }
    throw const FormatException();
  } finally {
    input.cast<Uint16>().asTypedList(password.length + 1).fillRange(0, password.length + 1, 0);
    calloc.free(input);
  }
}
