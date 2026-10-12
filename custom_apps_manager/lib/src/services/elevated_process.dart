import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

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
    return resolveElevated(() async => _tokenIsElevated());
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

  /// Runs [executable] through `ShellExecuteExW` and waits for it. A failure
  /// to start (UAC declined = [cancelledCode]) is reported as the exit code.
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    bool elevate = true,
    bool rawLastArgument = false,
  }) {
    final parameters =
        buildCommandLine(arguments, rawLastArgument: rawLastArgument);
    return Isolate.run(() => shellExecute(
          executable,
          parameters,
          verb: elevate ? 'runas' : null,
          wait: true,
        ));
  }

  /// Like [run], elevated, without waiting for the program to exit.
  static Future<ProcessResult> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    final parameters = buildCommandLine(arguments);
    return Isolate.run(() => shellExecute(
          executable,
          parameters,
          verb: 'runas',
          wait: false,
          workingDirectory: workingDirectory,
        ));
  }

  static String buildCommandLine(
    List<String> arguments, {
    bool rawLastArgument = false,
  }) =>
      [
        for (var i = 0; i < arguments.length; i++)
          rawLastArgument && i == arguments.length - 1
              ? arguments[i]
              : quoteWindowsArg(arguments[i]),
      ].join(' ');

  static bool needsQuoting(String arg) =>
      arg.isEmpty || arg.contains(RegExp(r'[ \t"]'));

  static String quoteWindowsArg(String arg) {
    if (!needsQuoting(arg)) return arg;
    final out = StringBuffer('"');
    var backslashes = 0;
    for (final ch in arg.split('')) {
      if (ch == r'\') {
        backslashes++;
        continue;
      }
      if (ch == '"') {
        out.write(r'\' * (backslashes * 2 + 1));
      } else {
        out.write(r'\' * backslashes);
      }
      backslashes = 0;
      out.write(ch);
    }
    out
      ..write(r'\' * (backslashes * 2))
      ..write('"');
    return out.toString();
  }
}

const _seeMaskNoCloseProcess = 0x00000040;
const _seeMaskNoAsync = 0x00000100;
const _seeMaskFlagNoUi = 0x00000400;

const _seErrAccessDenied = 5;

/// Dart FFI clobbers `GetLastError` after a non-leaf call, so the cause comes
/// from `hInstApp`; a declined UAC prompt is reported there as access denied.
int shellExecuteFailureCode(int hInstApp, {String? verb}) {
  if (verb == 'runas' && hInstApp == _seErrAccessDenied) {
    return ElevatedProcess.cancelledCode;
  }
  return hInstApp > 0 && hInstApp <= 32 ? hInstApp : 1;
}

/// Blocks until the program exits when [wait] — call it inside an isolate.
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

bool _tokenIsElevated() {
  final token = calloc<IntPtr>();
  final elevation = calloc<Uint32>();
  final length = calloc<Uint32>();
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
                length,
              ) !=
              0 &&
          elevation.value != 0;
    } finally {
      CloseHandle(token.value);
    }
  } finally {
    free(token);
    free(elevation);
    free(length);
  }
}
