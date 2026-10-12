import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

enum InstanceLockResult { acquired, heldElsewhere, unavailable }

abstract final class InstanceLock {
  static const String fileName = 'instance.lock';

  static const String windowClassName = 'FLUTTER_RUNNER_WIN32_WINDOW';

  static const String windowTitle =
      '\u05E2\u05D3\u05DB\u05D5\u05E0\u05D9 \u05D0\u05D5\u05E6\u05E8\u05D9\u05D0';

  static RandomAccessFile? _held;

  static Future<InstanceLockResult> acquire(
    String directory, {
    Duration wait = const Duration(seconds: 2),
    Duration retryInterval = const Duration(milliseconds: 250),
  }) async {
    if (_held != null) return InstanceLockResult.acquired;
    final deadline = DateTime.now().add(wait);
    while (true) {
      final result = await _tryAcquire(directory);
      if (result != InstanceLockResult.heldElsewhere ||
          !DateTime.now().isBefore(deadline)) {
        return result;
      }
      await Future<void>.delayed(retryInterval);
    }
  }

  static Future<void> release() async {
    final held = _held;
    _held = null;
    if (held == null) return;
    try {
      await held.close();
    } on FileSystemException {
      return;
    }
  }

  static Future<InstanceLockResult> _tryAcquire(String directory) async {
    final RandomAccessFile file;
    try {
      await Directory(directory).create(recursive: true);
      file =
          await File(p.join(directory, fileName)).open(mode: FileMode.append);
    } on FileSystemException {
      return InstanceLockResult.unavailable;
    }
    try {
      await file.lock(FileLock.exclusive);
      _held = file;
      return InstanceLockResult.acquired;
    } on FileSystemException catch (e) {
      try {
        await file.close();
      } on FileSystemException catch (_) {}
      return isContention(e.osError?.errorCode)
          ? InstanceLockResult.heldElsewhere
          : InstanceLockResult.unavailable;
    }
  }

  static bool isContention(
    int? errorCode, {
    bool? isWindows,
    bool? isMacOS,
  }) {
    if (errorCode == null) return false;
    if (isWindows ?? Platform.isWindows) return errorCode == 33;
    if (isMacOS ?? Platform.isMacOS) return errorCode == 35 || errorCode == 13;
    return errorCode == 11 || errorCode == 13;
  }

  /// One launcher per PC session, whatever drive it runs from: two drives
  /// applying to the same `seforim.db` at once is what the file lock, being
  /// per drive, cannot see.
  static const String machineMutexName = r'Local\OtzariaOfflineUpdate';

  static int _machineMutex = 0;

  /// [InstanceLockResult.unavailable] when the mutex cannot be opened at all
  /// (another account's elevated launcher): the drive lock still applies.
  static Future<InstanceLockResult> acquireMachineWide({
    Duration wait = const Duration(seconds: 2),
    Duration retryInterval = const Duration(milliseconds: 250),
    String name = machineMutexName,
  }) async {
    if (!Platform.isWindows) return InstanceLockResult.acquired;
    if (_machineMutex != 0) return InstanceLockResult.acquired;
    final deadline = DateTime.now().add(wait);
    while (true) {
      final result = tryOwnMutex(name);
      if (result.handle != 0) _machineMutex = result.handle;
      if (result.result != InstanceLockResult.heldElsewhere ||
          !DateTime.now().isBefore(deadline)) {
        return result.result;
      }
      await Future<void>.delayed(retryInterval);
    }
  }

  /// Ownership is per thread; the Windows UI isolate stays on the platform
  /// thread, and the OS releases an abandoned mutex when the process dies.
  static ({InstanceLockResult result, int handle}) tryOwnMutex(String name) {
    final native = name.toNativeUtf16();
    try {
      final handle = _createMutex(nullptr, 0, native);
      if (handle == 0) {
        return (result: InstanceLockResult.unavailable, handle: 0);
      }
      final waited = WaitForSingleObject(handle, 0);
      if (waited == WAIT_OBJECT_0 || waited == WAIT_ABANDONED) {
        return (result: InstanceLockResult.acquired, handle: handle);
      }
      CloseHandle(handle);
      return (
        result: waited == WAIT_TIMEOUT
            ? InstanceLockResult.heldElsewhere
            : InstanceLockResult.unavailable,
        handle: 0,
      );
    } finally {
      free(native);
    }
  }

  static final int Function(Pointer, int, Pointer<Utf16>) _createMutex =
      DynamicLibrary.open('kernel32.dll').lookupFunction<
          IntPtr Function(Pointer, Int32, Pointer<Utf16>),
          int Function(Pointer, int, Pointer<Utf16>)>('CreateMutexW');

  static void focusOtherInstance() {
    if (!Platform.isWindows) return;
    final className = windowClassName.toNativeUtf16();
    final title = windowTitle.toNativeUtf16();
    final owner = calloc<Uint32>();
    try {
      var window = 0;
      while (true) {
        window = FindWindowEx(0, window, className, title);
        if (window == 0) return;
        GetWindowThreadProcessId(window, owner);
        if (owner.value == pid) continue;
        if (IsIconic(window) != 0) ShowWindow(window, SW_RESTORE);
        SetForegroundWindow(window);
        return;
      }
    } finally {
      free(owner);
      free(title);
      free(className);
    }
  }
}
