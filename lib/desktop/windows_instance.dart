import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class WindowsInstance {
  late final bool isPrimary;
  int _mutex = 0;
  int _event = 0;
  Timer? _listener;
  static final _kernel = DynamicLibrary.open('kernel32.dll');
  static final _createMutex = _kernel
      .lookupFunction<
        IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
        int Function(Pointer<Void>, int, Pointer<Utf16>)
      >('CreateMutexW');
  static final _createEvent = _kernel
      .lookupFunction<
        IntPtr Function(Pointer<Void>, Int32, Int32, Pointer<Utf16>),
        int Function(Pointer<Void>, int, int, Pointer<Utf16>)
      >('CreateEventW');
  static final _getLastError = _kernel.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  static final _setEvent = _kernel.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetEvent');
  static final _wait = _kernel.lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
    'WaitForSingleObject',
  );
  static final _close = _kernel.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  WindowsInstance({String name = 'SecretManager.Desktop.v1'}) {
    final eventName = 'Local\\$name.Activate'.toNativeUtf16();
    final mutexName = 'Local\\$name.Instance'.toNativeUtf16();
    try {
      _event = _createEvent(nullptr, 0, 0, eventName);
      if (_event == 0) {
        throw const FileSystemException('Cannot create activation event');
      }
      final getLastError = _getLastError;
      _mutex = _createMutex(nullptr, 0, mutexName);
      final error = getLastError();
      if (_mutex == 0) {
        throw const FileSystemException('Cannot claim application instance');
      }
      isPrimary = error != 183;
      if (!isPrimary && _setEvent(_event) == 0) {
        throw const FileSystemException('Cannot activate application instance');
      }
    } catch (_) {
      dispose();
      rethrow;
    } finally {
      calloc.free(eventName);
      calloc.free(mutexName);
    }
  }

  void listen(void Function() onActivate) {
    if (!isPrimary || _event == 0 || _listener != null) return;
    _listener = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_wait(_event, 0) == 0) onActivate();
    });
  }

  void dispose() {
    _listener?.cancel();
    if (_event != 0) _close(_event);
    if (_mutex != 0) _close(_mutex);
    _event = 0;
    _mutex = 0;
  }
}
