import 'dart:ffi';
import 'dart:io';

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

  static String quoteArgument(String argument) {
    if (argument.isNotEmpty && !RegExp(r'[\s"]').hasMatch(argument)) {
      return argument;
    }
    final escaped = argument.replaceAllMapped(
      RegExp(r'(\\*)"'),
      (m) => '${m[1]}${m[1]}\\"',
    );
    final trailing = RegExp(r'(\\*)$').firstMatch(escaped)![1]!;
    return '"$escaped$trailing"';
  }

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
