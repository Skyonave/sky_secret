import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class DeviceProtectionException implements Exception {
  const DeviceProtectionException();
}

final class _DataBlob extends Struct {
  @Uint32()
  external int length;
  external Pointer<Uint8> data;
}

typedef _TransformNative = Int32 Function(
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_DataBlob>,
);
typedef _Transform = int Function(
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_DataBlob>,
);

Uint8List protectDeviceData(List<int> bytes, {bool decrypt = false}) {
  if (!Platform.isWindows || bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
    throw const DeviceProtectionException();
  }
  final crypt = DynamicLibrary.open('crypt32.dll');
  final transform = crypt.lookupFunction<_TransformNative, _Transform>(
    decrypt ? 'CryptUnprotectData' : 'CryptProtectData',
  );
  final release = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('LocalFree');
  return using((arena) {
    final input = arena<_DataBlob>();
    final output = arena<_DataBlob>();
    input.ref.length = bytes.length;
    input.ref.data = arena<Uint8>(bytes.length)..asTypedList(bytes.length).setAll(0, bytes);
    try {
      if (transform(input, nullptr, nullptr, nullptr, nullptr, 1, output) == 0) {
        throw const DeviceProtectionException();
      }
      if (output.ref.length > 4 * 1024 * 1024) {
        throw const DeviceProtectionException();
      }
      return Uint8List.fromList(output.ref.data.asTypedList(output.ref.length));
    } finally {
      input.ref.data.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      if (output.ref.data != nullptr) {
        output.ref.data.asTypedList(output.ref.length).fillRange(0, output.ref.length, 0);
        release(output.ref.data.cast());
      }
    }
  });
}
