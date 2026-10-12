import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'otzaria_process_guard.dart';

abstract interface class OtzariaInstanceLease {
  void release();
}

class OtzariaInstanceLock {
  const OtzariaInstanceLock();

  static const String mutexName = 'OtzariaAppSingleInstance';

  static int _heldByThisProcess = 0;

  static bool get isHeldByThisProcess => _heldByThisProcess > 0;

  Future<OtzariaInstanceLease> acquire() async {
    if (!Platform.isWindows) return const _NoLease();
    final lease = _WindowsMutexLease.tryCreate();
    if (lease == null) throw const OtzariaIsRunningException();
    return lease;
  }
}

class _NoLease implements OtzariaInstanceLease {
  const _NoLease();

  @override
  void release() {}
}

class _WindowsMutexLease implements OtzariaInstanceLease {
  _WindowsMutexLease._(this._handle) {
    OtzariaInstanceLock._heldByThisProcess++;
  }

  static const int _errorAlreadyExists = 183;
  static const int _synchronize = 0x00100000;

  int _handle;

  static OtzariaInstanceLease? tryCreate() {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final openMutex = kernel32
        .lookupFunction<
          IntPtr Function(Uint32, Int32, Pointer<Utf16>),
          int Function(int, int, Pointer<Utf16>)
        >('OpenMutexW', isLeaf: true);
    final createMutex = kernel32
        .lookupFunction<
          IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
          int Function(Pointer<Void>, int, Pointer<Utf16>)
        >('CreateMutexW', isLeaf: true);
    final getLastError = kernel32
        .lookupFunction<Uint32 Function(), int Function()>(
          'GetLastError',
          isLeaf: true,
        );
    final name = OtzariaInstanceLock.mutexName.toNativeUtf16();
    try {
      final existing = openMutex(_synchronize, 0, name);
      if (existing != 0) {
        _closeHandle(existing);
        return null;
      }
      final handle = createMutex(nullptr, 0, name);
      final error = getLastError();
      if (handle == 0) return const _NoLease();
      if (error == _errorAlreadyExists) {
        _closeHandle(handle);
        return null;
      }
      return _WindowsMutexLease._(handle);
    } finally {
      malloc.free(name);
    }
  }

  static void _closeHandle(int handle) {
    DynamicLibrary.open(
      'kernel32.dll',
    ).lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'CloseHandle',
      isLeaf: true,
    )(handle);
  }

  @override
  void release() {
    if (_handle == 0) return;
    _closeHandle(_handle);
    _handle = 0;
    OtzariaInstanceLock._heldByThisProcess--;
  }
}
