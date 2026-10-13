import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaSelfLock;

import 'otzaria_process_guard.dart';

abstract interface class OtzariaInstanceLease {
  void release();
}

class OtzariaInstanceLock {
  const OtzariaInstanceLock();

  static const String mutexName = 'OtzariaAppSingleInstance';

  static int _heldByThisProcess = 0;

  static bool get isHeldByThisProcess => _heldByThisProcess > 0;

  static List<String> mutexNamesFor({String? portableDataRoot}) => [
    mutexName,
    if (portableDataRoot != null) portableMutexName(portableDataRoot),
  ];

  static String portableMutexName(String dataRoot) =>
      '$mutexName-${fnv1a64Hex(_lowerUtf16(dataRoot.replaceAll('/', r'\')))}';

  static String fnv1a64Hex(String text) {
    var hash = 0xcbf29ce484222325;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    return BigInt.from(hash).toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  static String _lowerUtf16(String text) {
    final units = <int>[];
    for (final unit in text.codeUnits) {
      final lower = String.fromCharCode(unit).toLowerCase();
      units.add(lower.length == 1 ? lower.codeUnitAt(0) : unit);
    }
    return String.fromCharCodes(units);
  }

  static bool isMutexPresent(String name) =>
      Platform.isWindows && _WindowsMutexLease.exists(name);

  Future<OtzariaInstanceLease> acquire({String? portableDataRoot}) async {
    if (!Platform.isWindows) return const _NoLease();
    OtzariaSelfLock.isHeldByThisProcess = () => isHeldByThisProcess;
    final lease = _WindowsMutexLease.tryCreate(
      mutexNamesFor(portableDataRoot: portableDataRoot),
    );
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
  _WindowsMutexLease._(this._handles) {
    OtzariaInstanceLock._heldByThisProcess++;
  }

  static const int _errorAccessDenied = 5;
  static const int _errorAlreadyExists = 183;
  static const int _synchronize = 0x00100000;

  final List<int> _handles;
  bool _released = false;

  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final int Function(int, int, Pointer<Utf16>) _openMutex = _kernel32
      .lookupFunction<
        IntPtr Function(Uint32, Int32, Pointer<Utf16>),
        int Function(int, int, Pointer<Utf16>)
      >('OpenMutexW', isLeaf: true);

  static final int Function(Pointer<Void>, int, Pointer<Utf16>) _createMutex =
      _kernel32.lookupFunction<
        IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
        int Function(Pointer<Void>, int, Pointer<Utf16>)
      >('CreateMutexW', isLeaf: true);

  static final int Function() _getLastError = _kernel32
      .lookupFunction<Uint32 Function(), int Function()>(
        'GetLastError',
        isLeaf: true,
      );

  static final int Function(int) _closeHandle = _kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'CloseHandle',
        isLeaf: true,
      );

  static OtzariaInstanceLease? tryCreate(List<String> names) {
    final handles = <int>[];
    for (final name in names) {
      final handle = _createOne(name);
      if (handle == null) {
        handles.forEach(_closeHandle);
        return null;
      }
      if (handle != 0) handles.add(handle);
    }
    return handles.isEmpty ? const _NoLease() : _WindowsMutexLease._(handles);
  }

  static bool exists(String mutexName) {
    final name = mutexName.toNativeUtf16();
    try {
      final handle = _openMutex(_synchronize, 0, name);
      if (handle == 0) return false;
      _closeHandle(handle);
      return true;
    } finally {
      malloc.free(name);
    }
  }

  static int? _createOne(String mutexName) {
    final name = mutexName.toNativeUtf16();
    try {
      final existing = _openMutex(_synchronize, 0, name);
      if (existing != 0) {
        _closeHandle(existing);
        return null;
      }
      final handle = _createMutex(nullptr, 0, name);
      final error = _getLastError();
      if (handle == 0) return error == _errorAccessDenied ? null : 0;
      if (error == _errorAlreadyExists) {
        _closeHandle(handle);
        return null;
      }
      return handle;
    } finally {
      malloc.free(name);
    }
  }

  @override
  void release() {
    if (_released) return;
    _released = true;
    _handles.forEach(_closeHandle);
    OtzariaInstanceLock._heldByThisProcess--;
  }
}
