import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class MemoryProtectionException implements Exception {
  const MemoryProtectionException();
}

class SecretLifetime {
  bool _revoked = false;

  void check() {
    if (_revoked) throw StateError('Secret session was locked');
  }

  void revoke() => _revoked = true;
}

class ProtectedBytes {
  final int length;
  final Uint8List _ciphertext;
  SecretLifetime? _lifetime;
  bool _destroyed = false;

  ProtectedBytes(List<int> bytes) : length = bytes.length, _ciphertext = _transform(bytes, decrypt: false);

  ProtectedBytes._copy(ProtectedBytes source, this._lifetime)
    : length = source.length,
      _ciphertext = Uint8List.fromList(source._ciphertext);

  ProtectedBytes ownFor(SecretLifetime lifetime) {
    _check();
    _lifetime ??= lifetime;
    if (identical(_lifetime, lifetime)) return this;
    return ProtectedBytes._copy(this, lifetime);
  }

  void _check() {
    _lifetime?.check();
    if (_destroyed) throw StateError('Protected value was destroyed');
  }

  Uint8List read() {
    _check();
    final padded = _transform(_ciphertext, decrypt: true);
    try {
      return Uint8List.fromList(Uint8List.sublistView(padded, 0, length));
    } finally {
      padded.fillRange(0, padded.length, 0);
    }
  }

  Uint8List copyProtectedMemory() {
    _check();
    return Uint8List.fromList(_ciphertext);
  }

  void destroy() {
    _ciphertext.fillRange(0, _ciphertext.length, 0);
    _destroyed = true;
  }
}

class ProtectedText {
  late final ProtectedBytes _value;

  ProtectedText._(this._value);

  ProtectedText(String text) {
    final bytes = utf8.encode(text);
    try {
      _value = ProtectedBytes(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  ProtectedText ownFor(SecretLifetime lifetime) => ProtectedText._(_value.ownFor(lifetime));

  void destroy() => _value.destroy();

  bool get isEmpty {
    _value._check();
    return _value.length == 0;
  }

  String read() {
    final bytes = _value.read();
    try {
      return utf8.decode(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

const _chunkSize = 16 * 1024;
const _sameProcess = 0;
final _kernel = DynamicLibrary.open('kernel32.dll');
final _crypt = DynamicLibrary.open('crypt32.dll');
final _allocate = _kernel
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, IntPtr, Uint32, Uint32),
      Pointer<Void> Function(Pointer<Void>, int, int, int)
    >('VirtualAlloc');
final _release = _kernel
    .lookupFunction<Int32 Function(Pointer<Void>, IntPtr, Uint32), int Function(Pointer<Void>, int, int)>(
      'VirtualFree',
    );
final _lock = _kernel.lookupFunction<Int32 Function(Pointer<Void>, IntPtr), int Function(Pointer<Void>, int)>(
  'VirtualLock',
);
final _unlock = _kernel.lookupFunction<Int32 Function(Pointer<Void>, IntPtr), int Function(Pointer<Void>, int)>(
  'VirtualUnlock',
);
final _protect = _crypt
    .lookupFunction<Int32 Function(Pointer<Void>, Uint32, Uint32), int Function(Pointer<Void>, int, int)>(
      'CryptProtectMemory',
    );
final _unprotect = _crypt
    .lookupFunction<Int32 Function(Pointer<Void>, Uint32, Uint32), int Function(Pointer<Void>, int, int)>(
      'CryptUnprotectMemory',
    );

Uint8List _transform(List<int> source, {required bool decrypt}) {
  if (!Platform.isWindows) throw const MemoryProtectionException();
  if (source.isEmpty) return Uint8List(0);
  final paddedLength = ((source.length + 15) ~/ 16) * 16;
  final capacity = min(_chunkSize, paddedLength);
  final pointer = _allocate(nullptr, capacity, 0x3000, 0x04);
  if (pointer == nullptr) throw const MemoryProtectionException();
  final scratch = pointer.cast<Uint8>().asTypedList(capacity);
  var locked = false;
  final result = Uint8List(paddedLength);
  try {
    locked = _lock(pointer, capacity) != 0;
    if (!locked) throw const MemoryProtectionException();
    for (var offset = 0; offset < paddedLength; offset += capacity) {
      final count = min(capacity, paddedLength - offset);
      final available = min(count, source.length - offset);
      scratch.fillRange(0, capacity, 0);
      scratch.setRange(0, available, source, offset);
      final success = (decrypt ? _unprotect : _protect)(
        pointer,
        count,
        _sameProcess,
      );
      if (success == 0) throw const MemoryProtectionException();
      result.setRange(offset, offset + count, scratch);
    }
    return result;
  } catch (_) {
    result.fillRange(0, result.length, 0);
    rethrow;
  } finally {
    scratch.fillRange(0, capacity, 0);
    if (locked) _unlock(pointer, capacity);
    _release(pointer, 0, 0x8000);
  }
}
