import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WindowsElevation {
  const WindowsElevation._();

  static bool? _elevated;
  static bool? _otherUser;

  static bool get isElevated =>
      _elevated ??= Platform.isWindows && _currentTokenIsElevated();

  static bool get isElevatedAsOtherUser =>
      _otherUser ??= isElevated && _shellUserDiffers();

  static bool needsQuoting(String argument) =>
      argument.isEmpty || argument.contains(RegExp(r'[\s"]'));

  static String quoteArgument(String argument) {
    if (!needsQuoting(argument)) return argument;
    final out = StringBuffer('"');
    var backslashes = 0;
    for (final ch in argument.split('')) {
      if (ch == r'\') {
        backslashes++;
        continue;
      }
      out.write(r'\' * (ch == '"' ? backslashes * 2 + 1 : backslashes));
      backslashes = 0;
      out.write(ch);
    }
    out
      ..write(r'\' * (backslashes * 2))
      ..write('"');
    return out.toString();
  }

  static String buildCommandLine(
    List<String> arguments, {
    bool rawLastArgument = false,
  }) =>
      [
        for (var i = 0; i < arguments.length; i++)
          rawLastArgument && i == arguments.length - 1
              ? arguments[i]
              : quoteArgument(arguments[i]),
      ].join(' ');

  /// CreateProcessWithTokenW needs SeImpersonatePrivilege (elevated admins have
  /// it) and the Secondary Logon service; on failure the caller starts directly.
  static bool launchUnelevated(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) {
    if (!Platform.isWindows) return false;
    final shellToken = _shellToken(TOKEN_DUPLICATE);
    if (shellToken == null) return false;
    final primary = calloc<IntPtr>();
    final startup = calloc<STARTUPINFO>();
    final info = calloc<PROCESS_INFORMATION>();
    final app = executable.toNativeUtf16();
    final commandLine =
        [executable, ...arguments].map(quoteArgument).join(' ').toNativeUtf16();
    final directory = workingDirectory.toNativeUtf16();
    try {
      if (_duplicateTokenEx(
            shellToken,
            TOKEN_QUERY |
                TOKEN_ASSIGN_PRIMARY |
                TOKEN_DUPLICATE |
                TOKEN_ADJUST_DEFAULT |
                TOKEN_ADJUST_SESSIONID,
            nullptr,
            _securityImpersonation,
            _tokenPrimary,
            primary,
          ) ==
          0) {
        return false;
      }
      startup.ref.cb = sizeOf<STARTUPINFO>();
      final created = _createProcessWithToken(
        primary.value,
        0,
        app,
        commandLine,
        0,
        nullptr,
        directory,
        startup,
        info,
      );
      if (created == 0) return false;
      CloseHandle(info.ref.hThread);
      CloseHandle(info.ref.hProcess);
      return true;
    } finally {
      if (primary.value != 0) CloseHandle(primary.value);
      CloseHandle(shellToken);
      calloc.free(primary);
      calloc.free(startup);
      calloc.free(info);
      calloc.free(app);
      calloc.free(commandLine);
      calloc.free(directory);
    }
  }

  static bool _currentTokenIsElevated() {
    final token = calloc<IntPtr>();
    final elevation = calloc<Uint32>();
    final returned = calloc<Uint32>();
    try {
      if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, token) == 0) {
        return false;
      }
      try {
        return GetTokenInformation(
                  token.value,
                  TokenElevation,
                  elevation,
                  sizeOf<Uint32>(),
                  returned,
                ) !=
                0 &&
            elevation.value != 0;
      } finally {
        CloseHandle(token.value);
      }
    } finally {
      calloc.free(token);
      calloc.free(elevation);
      calloc.free(returned);
    }
  }

  static bool _shellUserDiffers() {
    final shell = _shellToken(TOKEN_QUERY);
    if (shell == null) return false;
    final own = calloc<IntPtr>();
    try {
      if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, own) == 0) {
        return false;
      }
      try {
        return _withUserSid(
          shell,
          (shellSid) => _withUserSid(
            own.value,
            (ownSid) => _equalSid(shellSid, ownSid) == 0,
          ),
        );
      } finally {
        CloseHandle(own.value);
      }
    } finally {
      CloseHandle(shell);
      calloc.free(own);
    }
  }

  static bool _withUserSid(int token, bool Function(Pointer<Void> sid) use) {
    const size = 256;
    final buffer = calloc<Uint8>(size);
    final returned = calloc<Uint32>();
    try {
      if (GetTokenInformation(token, TokenUser, buffer, size, returned) == 0) {
        return false;
      }
      return use(buffer.cast<Pointer<Void>>().value);
    } finally {
      calloc.free(buffer);
      calloc.free(returned);
    }
  }

  static int? _shellToken(int access) {
    final window = GetShellWindow();
    if (window == 0) return null;
    final processId = calloc<Uint32>();
    final token = calloc<IntPtr>();
    try {
      GetWindowThreadProcessId(window, processId);
      if (processId.value == 0) return null;
      final process = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION,
        FALSE,
        processId.value,
      );
      if (process == 0) return null;
      try {
        if (OpenProcessToken(process, access, token) == 0) return null;
        return token.value;
      } finally {
        CloseHandle(process);
      }
    } finally {
      calloc.free(processId);
      calloc.free(token);
    }
  }

  static const int _securityImpersonation = 2;
  static const int _tokenPrimary = 1;

  static final _advapi32 = DynamicLibrary.open('advapi32.dll');

  static final _duplicateTokenEx = _advapi32.lookupFunction<
      Int32 Function(
          IntPtr, Uint32, Pointer<Void>, Int32, Int32, Pointer<IntPtr>),
      int Function(int, int, Pointer<Void>, int, int,
          Pointer<IntPtr>)>('DuplicateTokenEx');

  static final _createProcessWithToken = _advapi32.lookupFunction<
      Int32 Function(
        IntPtr,
        Uint32,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<STARTUPINFO>,
        Pointer<PROCESS_INFORMATION>,
      ),
      int Function(
        int,
        int,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<STARTUPINFO>,
        Pointer<PROCESS_INFORMATION>,
      )>('CreateProcessWithTokenW');

  static final _equalSid = _advapi32.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('EqualSid');
}

typedef ElevationQuery = Future<bool> Function();

class ElevatedProcess {
  const ElevatedProcess._();

  static const elevationRequiredCode = 740;

  static const cancelledCode = ERROR_CANCELLED;

  static const elevationQueryTimeout = Duration(seconds: 10);

  static bool isElevationRequired(Object error) =>
      error is ProcessException && error.errorCode == elevationRequiredCode;

  static bool? _currentElevated;
  static Future<bool>? _pendingElevated;

  static Future<bool> isCurrentProcessElevated() {
    if (!Platform.isWindows) return Future.value(false);
    return resolveElevated(() async => WindowsElevation.isElevated);
  }

  static Future<bool> resolveElevated(
    ElevationQuery query, {
    Duration timeout = elevationQueryTimeout,
  }) {
    final cached = _currentElevated;
    if (cached != null) return Future.value(cached);
    return _pendingElevated ??= _queryElevated(query, timeout)
        .whenComplete(() => _pendingElevated = null);
  }

  static void resetElevatedCache() {
    _currentElevated = null;
    _pendingElevated = null;
  }

  static Future<bool> _queryElevated(
    ElevationQuery query,
    Duration timeout,
  ) async {
    try {
      return _currentElevated = await query().timeout(timeout);
    } on TimeoutException {
      return false;
    } catch (_) {
      return _currentElevated = false;
    }
  }

  /// מריץ דרך `ShellExecuteExW` (ב-isolate) וממתין לסיום. כשל בהפעלה
  /// מוחזר כקוד היציאה; סירוב או חסימה ב-UAC = [cancelledCode].
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    bool elevate = true,
    bool rawLastArgument = false,
  }) {
    final parameters = WindowsElevation.buildCommandLine(arguments,
        rawLastArgument: rawLastArgument);
    return Isolate.run(() => shellExecute(
          executable,
          parameters,
          verb: elevate ? 'runas' : null,
          wait: true,
        ));
  }

  /// כמו [run], מורם, בלי להמתין לסיום התוכנה.
  static Future<ProcessResult> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    final parameters = WindowsElevation.buildCommandLine(arguments);
    return Isolate.run(() => shellExecute(
          executable,
          parameters,
          verb: 'runas',
          wait: false,
          workingDirectory: workingDirectory,
        ));
  }
}

const _seeMaskNoCloseProcess = 0x00000040;
const _seeMaskNoAsync = 0x00000100;
const _seeMaskFlagNoUi = 0x00000400;

const _seErrAccessDenied = 5;

/// Dart FFI דורס את `GetLastError` אחרי קריאה רגילה, ולכן הסיבה נלקחת מ-
/// `hInstApp`; שם סירוב UAC וחסימת גישה נראים אותו דבר (access denied).
int shellExecuteFailureCode(int hInstApp, {String? verb}) {
  if (verb == 'runas' && hInstApp == _seErrAccessDenied) {
    return ElevatedProcess.cancelledCode;
  }
  return hInstApp > 0 && hInstApp <= 32 ? hInstApp : 1;
}

/// עם [wait] חוסם עד סיום התוכנה — לקרוא רק מתוך isolate.
ProcessResult shellExecute(
  String executable,
  String parameters, {
  String? verb,
  required bool wait,
  String? workingDirectory,
}) {
  final info = calloc<SHELLEXECUTEINFO>();
  final file = executable.toNativeUtf16();
  final params = parameters.toNativeUtf16();
  final verbPtr = verb == null ? nullptr : verb.toNativeUtf16();
  final dir =
      workingDirectory == null ? nullptr : workingDirectory.toNativeUtf16();
  final exitCode = calloc<Uint32>();
  try {
    info.ref
      ..cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..fMask = _seeMaskNoCloseProcess | _seeMaskNoAsync | _seeMaskFlagNoUi
      ..lpVerb = verbPtr
      ..lpFile = file
      ..lpParameters = params
      ..lpDirectory = dir
      ..nShow = SW_SHOWNORMAL;
    if (ShellExecuteEx(info) == 0) {
      final error = shellExecuteFailureCode(info.ref.hInstApp, verb: verb);
      return ProcessResult(0, error, '', 'ShellExecuteEx failed: $error');
    }
    final process = info.ref.hProcess;
    if (process == 0) return ProcessResult(0, 0, '', '');
    try {
      final pid = GetProcessId(process);
      if (!wait) return ProcessResult(pid, 0, '', '');
      WaitForSingleObject(process, INFINITE);
      if (GetExitCodeProcess(process, exitCode) == 0) {
        final error = GetLastError();
        return ProcessResult(pid, error, '', 'GetExitCodeProcess: $error');
      }
      return ProcessResult(pid, exitCode.value, '', '');
    } finally {
      CloseHandle(process);
    }
  } finally {
    free(info);
    free(file);
    free(params);
    if (verbPtr != nullptr) free(verbPtr);
    if (dir != nullptr) free(dir);
    free(exitCode);
  }
}
