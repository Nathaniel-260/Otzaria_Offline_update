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

  /// לאנצ'ר אחד בכל סשן של המחשב, מכל כונן שהוא — נעילת הקובץ היא לכל כונן,
  /// ושני כוננים החילו עדכון על אותו `seforim.db` במקביל. `Local\` = לכל סשן.
  static const String machineMutexName = r'Local\OtzariaOfflineUpdate';

  static int _machineMutex = 0;

  /// [InstanceLockResult.unavailable] כשאי אפשר לפתוח את ה-mutex בכלל; נעילת
  /// הכונן עדיין חלה.
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

  /// הבעלות היא לכל thread (ה-UI isolate בווינדוס נשאר על thread הפלטפורמה),
  /// ומערכת ההפעלה משחררת mutex נטוש כשהתהליך מת.
  static ({InstanceLockResult result, int handle}) tryOwnMutex(String name) {
    final native = name.toNativeUtf16();
    try {
      var handle = _createMutex(nullptr, 0, native);
      // mutex של מופע מורם מסרב ל-CreateMutexW ממופע רגיל; פתיחה ל-SYNCHRONIZE
      // בלבד מצליחה. GetLastError אינו אמין אחרי קריאת FFI, ולכן אין בו שימוש.
      if (handle == 0) handle = _openMutex(SYNCHRONIZE, 0, native);
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

  /// משחרר בעלות שהתקבלה מ-[tryOwnMutex] וסוגר את ה-handle.
  static void releaseMutex(int handle) {
    if (handle == 0) return;
    _releaseMutex(handle);
    CloseHandle(handle);
  }

  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final int Function(Pointer, int, Pointer<Utf16>) _createMutex =
      _kernel32.lookupFunction<IntPtr Function(Pointer, Int32, Pointer<Utf16>),
          int Function(Pointer, int, Pointer<Utf16>)>('CreateMutexW');

  static final int Function(int, int, Pointer<Utf16>) _openMutex =
      _kernel32.lookupFunction<IntPtr Function(Uint32, Int32, Pointer<Utf16>),
          int Function(int, int, Pointer<Utf16>)>('OpenMutexW');

  static final int Function(int) _releaseMutex =
      _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'ReleaseMutex');

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
