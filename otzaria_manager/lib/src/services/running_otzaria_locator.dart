import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'mac_app_version_reader.dart';

/// מה שנצפה על תהליך אוצריא בבדיקה **אחת**. שני השדות אינם חופפים:
/// תהליך שרץ מוגבה (כמנהל) מזוהה כרץ, אבל הנתיב שלו אינו קריא.
typedef RunningOtzariaProbe = ({bool isRunning, String? launchPath});

/// מאתר את ההתקנה של אוצריא לפי **התהליך שרץ כרגע**, ולא לפי ניחוש
/// תיקיות: הנתיב של תהליך חי הוא בדיוק העותק שהמשתמש מפעיל בפועל, גם אם
/// הותקן במקום שאינו ברשימת ברירות המחדל של
/// [OtzariaManager] (`_autoDetectDirs`).
///
/// **מה זה לא פותר:** מיקום ה-`seforim.db`. הוא יושב תחת `%APPDATA%`
/// ללא קשר לתיקיית ההתקנה, ולגזור אותו מהתהליך היה מחייב סריקת
/// ה-handles הפתוחים שלו — ראו `LibraryDbLocator`.
class RunningOtzariaLocator {
  const RunningOtzariaLocator({
    this.mutexName = singleInstanceMutexName,
    this.isMutexHeldByThisProcess,
  });

  static const String singleInstanceMutexName = 'OtzariaAppSingleInstance';

  final String mutexName;

  final bool Function()? isMutexHeldByThisProcess;

  static const int _maxPathChars = 32768;

  static Object? lastProbeFailure;

  static List<String> processNamesFor(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => const ['otzaria.exe'],
      'macos' => const ['אוצריא', 'otzaria'],
      _ => const ['otzaria'],
    };
  }

  Future<String?> findLaunchPath() async => (await probe()).launchPath;

  Future<RunningOtzariaProbe> probe() async {
    try {
      final RunningOtzariaProbe result;
      if (Platform.isWindows) {
        result = await _probeWindows();
      } else if (Platform.isMacOS) {
        result = await _probeMac();
      } else {
        return (isRunning: false, launchPath: null);
      }
      lastProbeFailure = null;
      return result;
    } on _ProbeFailure catch (failure) {
      lastProbeFailure = failure.cause;
      return (isRunning: false, launchPath: null);
    } on ProcessException catch (e) {
      lastProbeFailure = e;
      return (isRunning: false, launchPath: null);
    }
  }

  Future<RunningOtzariaProbe> _probeWindows() async {
    final mutex = mutexName;
    final self = Platform.resolvedExecutable;
    final ownMutex = (isMutexHeldByThisProcess ?? OtzariaSelfLock.isHeld)();
    final result = await _offUiIsolate(
      () => windowsProbeSync(mutex, self, mutexHeldByThisProcess: ownMutex),
    );
    final failure = result.failure;
    if (failure != null) throw _ProbeFailure(failure);
    return (isRunning: result.isRunning, launchPath: result.launchPath);
  }

  static ({bool isRunning, String? launchPath, String? failure})
      windowsProbeSync(
    String mutexName,
    String selfPath, {
    bool mutexHeldByThisProcess = false,
  }) {
    final mutex = mutexHeldByThisProcess
        ? WindowsMutexState.unknown
        : windowsMutexState(mutexName);
    final running = _otzariaProcesses(selfPath);
    if (running == null) {
      return mutex == WindowsMutexState.present
          ? (isRunning: true, launchPath: null, failure: null)
          : (
              isRunning: false,
              launchPath: null,
              failure: 'CreateToolhelp32Snapshot failed',
            );
    }
    final path = running.map((process) => process.path).nonNulls.firstOrNull;
    return (
      isRunning: mutex == WindowsMutexState.present || running.isNotEmpty,
      launchPath: path,
      failure: null,
    );
  }

  Future<bool?> waitForExit(Duration timeout) async {
    if (!Platform.isWindows) return null;
    final self = Platform.resolvedExecutable;
    final millis = timeout.inMilliseconds;
    return _offUiIsolate(() => _waitForExitSync(self, millis));
  }

  static bool? _waitForExitSync(String selfPath, int timeoutMillis) {
    final processes = _otzariaProcesses(selfPath);
    if (processes == null || processes.isEmpty) return null;
    return _waitForPidSync(processes.first.pid, timeoutMillis);
  }

  static Future<bool?> waitForImageToExit(
    String imagePath,
    Duration timeout, {
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    if (!Platform.isWindows) return null;
    final deadline = DateTime.now().add(timeout);
    var seen = false;
    while (true) {
      final pids = await _offUiIsolate(() => _pidsOfImage(imagePath));
      if (pids.isEmpty) return seen ? true : null;
      seen = true;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return false;
      final slice = remaining < const Duration(seconds: 30)
          ? remaining
          : const Duration(seconds: 30);
      final pid = pids.first;
      final millis = slice.inMilliseconds;
      final waited = await _offUiIsolate(() => _waitForPidSync(pid, millis));
      if (waited == null) await Future<void>.delayed(pollInterval);
    }
  }

  static List<int> _pidsOfImage(String imagePath) => [
        for (final process in _processesNamed(p.basename(imagePath)) ??
            const <({int pid, String? path})>[])
          if (process.path == null || p.equals(process.path!, imagePath))
            process.pid,
      ];

  static bool? _waitForPidSync(int processId, int timeoutMillis) {
    final handle = OpenProcess(SYNCHRONIZE, FALSE, processId);
    if (handle == 0) return null;
    try {
      return WaitForSingleObject(handle, timeoutMillis) == WAIT_OBJECT_0;
    } finally {
      CloseHandle(handle);
    }
  }

  static Future<T> _offUiIsolate<T>(T Function() compute) async {
    try {
      return await Isolate.run(compute);
    } on IsolateSpawnException {
      return compute();
    }
  }

  Future<RunningOtzariaProbe> _probeMac() async {
    final result = await Process.run('/bin/ps', ['-A', '-o', 'comm=']);
    if (result.exitCode != 0) {
      throw _ProbeFailure('ps exited with ${result.exitCode}');
    }

    final executablePath = selectMacExecutablePath(
      const LineSplitter().convert(result.stdout.toString()),
      processNamesFor('macos'),
      selfExecutable: Platform.resolvedExecutable,
    );
    if (executablePath == null) return (isRunning: false, launchPath: null);

    return (
      isRunning: true,
      launchPath: MacAppVersionReader.bundleRootOf(executablePath),
    );
  }

  static Future<List<int>> windowsPidsOf(String imageName) async {
    if (!Platform.isWindows) return const [];
    return _offUiIsolate(
      () => [
        for (final process in _processesNamed(imageName) ??
            const <({int pid, String? path})>[])
          process.pid,
      ],
    );
  }

  static Future<List<int>> windowsOtzariaPids() async {
    if (!Platform.isWindows) return const [];
    final self = Platform.resolvedExecutable;
    return _offUiIsolate(
      () => [
        for (final process
            in _otzariaProcesses(self) ?? const <({int pid, String? path})>[])
          process.pid,
      ],
    );
  }

  static List<({int pid, String? path})>? _otzariaProcesses(String selfPath) {
    final self = pid;
    return _processesNamed(processNamesFor('windows').single)
        ?.where(
          (process) =>
              process.pid != self &&
              (process.path == null || !p.equals(process.path!, selfPath)),
        )
        .toList();
  }

  static List<({int pid, String? path})>? _processesNamed(String imageName) {
    final target = imageName.toLowerCase();
    final snapshot = _createSnapshot(_th32csSnapProcess, 0);
    if (snapshot == INVALID_HANDLE_VALUE || snapshot == 0) return null;
    final entry = calloc<_ProcessEntry32W>();
    final buffer = malloc<Uint16>(_maxPathChars).cast<Utf16>();
    final sizePtr = calloc<Uint32>();
    try {
      entry.ref.dwSize = sizeOf<_ProcessEntry32W>();
      final found = <({int pid, String? path})>[];
      for (var more = _process32First(snapshot, entry) != 0;
          more;
          more = _process32Next(snapshot, entry) != 0) {
        if (_exeFileOf(entry.ref).toLowerCase() != target) continue;
        final processId = entry.ref.th32ProcessID;
        found.add((
          pid: processId,
          path: _imagePathOf(processId, buffer, sizePtr),
        ));
      }
      return found;
    } finally {
      CloseHandle(snapshot);
      calloc.free(entry);
      malloc.free(buffer);
      calloc.free(sizePtr);
    }
  }

  static String _exeFileOf(_ProcessEntry32W entry) {
    final units = <int>[];
    for (var i = 0; i < _maxPath; i++) {
      final unit = entry.szExeFile[i];
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }

  static const int _maxPath = 260;
  static const int _th32csSnapProcess = 0x2;

  static final _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _createSnapshot = _kernel32.lookupFunction<
      IntPtr Function(Uint32, Uint32),
      int Function(int, int)>('CreateToolhelp32Snapshot');

  static final _process32First = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Pointer<_ProcessEntry32W>),
      int Function(int, Pointer<_ProcessEntry32W>)>('Process32FirstW');

  static final _process32Next = _kernel32.lookupFunction<
      Int32 Function(IntPtr, Pointer<_ProcessEntry32W>),
      int Function(int, Pointer<_ProcessEntry32W>)>('Process32NextW');

  static WindowsMutexState windowsMutexState(String name) {
    if (!Platform.isWindows) return WindowsMutexState.unknown;
    final namePtr = name.toNativeUtf16();
    final openMutex = _openMutex;
    final lastError = _lastError;
    try {
      final handle = openMutex(SYNCHRONIZE, FALSE, namePtr);
      final error = lastError();
      if (handle != 0) {
        CloseHandle(handle);
        return WindowsMutexState.present;
      }
      return switch (error) {
        ERROR_FILE_NOT_FOUND => WindowsMutexState.absent,
        ERROR_ACCESS_DENIED => WindowsMutexState.present,
        _ => WindowsMutexState.unknown,
      };
    } finally {
      calloc.free(namePtr);
    }
  }

  static final _openMutex = DynamicLibrary.open('kernel32.dll').lookupFunction<
      IntPtr Function(Uint32, Int32, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>)>('OpenMutexW', isLeaf: true);

  static final _lastError = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
    isLeaf: true,
  );

  static String? windowsImagePathOfPid(int processId) {
    if (!Platform.isWindows) return null;

    final buffer = malloc<Uint16>(_maxPathChars).cast<Utf16>();
    final sizePtr = calloc<Uint32>();
    try {
      return _imagePathOf(processId, buffer, sizePtr);
    } finally {
      malloc.free(buffer);
      calloc.free(sizePtr);
    }
  }

  static Future<List<String>> windowsRunningImagePathsOffUiIsolate() =>
      _offUiIsolate(windowsRunningImagePaths);

  static List<String> windowsRunningImagePaths() {
    if (!Platform.isWindows) return const [];

    final paths = <String>[];
    final buffer = malloc<Uint16>(_maxPathChars).cast<Utf16>();
    final sizePtr = calloc<Uint32>();
    try {
      for (final processId in _windowsAllPids() ?? const <int>[]) {
        final path = _imagePathOf(processId, buffer, sizePtr);
        if (path != null) paths.add(path);
      }
    } finally {
      malloc.free(buffer);
      calloc.free(sizePtr);
    }
    return paths;
  }

  static List<int>? _windowsAllPids() {
    for (var capacity = 1024;; capacity *= 2) {
      final pids = malloc<Uint32>(capacity);
      final neededPtr = calloc<Uint32>();
      try {
        final bytes = capacity * sizeOf<Uint32>();
        if (EnumProcesses(pids, bytes, neededPtr) == 0) return null;
        if (neededPtr.value < bytes) {
          final count = neededPtr.value ~/ sizeOf<Uint32>();
          return [for (var i = 0; i < count; i++) pids[i]];
        }
      } finally {
        malloc.free(pids);
        calloc.free(neededPtr);
      }
    }
  }

  static String? _imagePathOf(
    int processId,
    Pointer<Utf16> buffer,
    Pointer<Uint32> sizePtr,
  ) {
    final handle = OpenProcess(
      PROCESS_QUERY_LIMITED_INFORMATION,
      FALSE,
      processId,
    );
    if (handle == 0) return null;

    try {
      sizePtr.value = _maxPathChars;
      if (QueryFullProcessImageName(handle, 0, buffer, sizePtr) == 0) {
        return null;
      }
      return buffer.toDartString(length: sizePtr.value);
    } finally {
      CloseHandle(handle);
    }
  }

  /// בוחר מתוך פלט `ps -A -o comm=` (שב-macOS מדפיס **נתיב מלא**) את
  /// התהליך של אוצריא.
  ///
  /// ההתאמה היא על שם הקובץ **במלואו**, כמו `pgrep -x` — ולא כתת-מחרוזת,
  /// שהייתה תופסת גם את הלאנצ'ר עצמו: הנתיב שלו מכיל את המילה otzaria.
  ///
  /// [selfExecutable] הוא קובץ ההרצה של הלאנצ'ר, ותהליך שרץ ממנו נפסל —
  /// המקבילה ל-[_isSelf] שבמסלול ווינדוס. שם הלאנצ'ר ב-macOS אמנם שונה
  /// (`Otzaria Launcher`, ראו `AppInfo.xcconfig`), אבל ההסתמכות על כך לבדה
  /// היא בדיוק סוג ההנחה שכבר נשברה כאן פעם אחת.
  static String? selectMacExecutablePath(
    Iterable<String> psLines,
    List<String> processNames, {
    String? selfExecutable,
  }) {
    for (final line in psLines) {
      final path = line.trim();
      if (path.isEmpty) continue;
      if (!processNames.contains(p.basename(path))) continue;
      if (selfExecutable != null && p.equals(path, selfExecutable)) continue;
      return path;
    }
    return null;
  }
}

enum WindowsMutexState { present, absent, unknown }

class _ProbeFailure implements Exception {
  const _ProbeFailure(this.cause);

  final Object cause;

  @override
  String toString() => '$cause';
}

final class _ProcessEntry32W extends Struct {
  @Uint32()
  external int dwSize;
  @Uint32()
  external int cntUsage;
  @Uint32()
  external int th32ProcessID;
  @UintPtr()
  external int th32DefaultHeapID;
  @Uint32()
  external int th32ModuleID;
  @Uint32()
  external int cntThreads;
  @Uint32()
  external int th32ParentProcessID;
  @Int32()
  external int pcPriClassBase;
  @Uint32()
  external int dwFlags;
  @Array(260)
  external Array<Uint16> szExeFile;
}

class OtzariaSelfLock {
  const OtzariaSelfLock._();

  static bool Function() isHeldByThisProcess = _never;

  static bool isHeld() => isHeldByThisProcess();

  static bool _never() => false;
}
