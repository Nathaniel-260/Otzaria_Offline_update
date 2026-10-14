import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:win32/win32.dart' show CloseHandle;

import 'app_logger.dart';

/// Holds one process-owned request while any foreground update is active.
class SleepInhibitor {
  SleepInhibitor({
    void Function() Function()? acquire,
    void Function(Object)? onError,
  })  : _acquire = acquire ?? _acquireNative,
        _onError = onError ?? _logError;

  final void Function() Function() _acquire;
  final void Function(Object) _onError;
  void Function()? _release;
  bool _disposed = false;

  bool get isActive => _release != null;

  void setActive(bool active) {
    if (_disposed || active == isActive) return;
    try {
      if (active) {
        _release = _acquire();
      } else {
        _release!();
        _release = null;
      }
    } catch (error) {
      _onError(error);
    }
  }

  void dispose() {
    if (_disposed) return;
    setActive(false);
    _disposed = true;
  }

  static void _logError(Object error) =>
      AppLogger.instance.info('sleep inhibition failed: $error');

  static void Function() _acquireNative() {
    final reason = AppL10n.strings.shell.appTitle;
    if (Platform.isWindows) return _acquireWindows(reason);
    if (Platform.isMacOS) return _acquireMac(reason);
    return () {};
  }
}

final class _ReasonDetails extends Struct {
  external Pointer<Void> module;
  @Uint32()
  external int id;
  @Uint32()
  external int count;
  external Pointer<Pointer<Utf16>> strings;
}

final class _ReasonUnion extends Union {
  external Pointer<Utf16> simple;
  external _ReasonDetails detailed;
}

final class _ReasonContext extends Struct {
  @Uint32()
  external int version;
  @Uint32()
  external int flags;
  external _ReasonUnion reason;
}

void Function() _acquireWindows(String reason) {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final create = kernel.lookupFunction<IntPtr Function(Pointer<_ReasonContext>),
      int Function(Pointer<_ReasonContext>)>('PowerCreateRequest');
  final set = kernel.lookupFunction<Int32 Function(IntPtr, Int32),
      int Function(int, int)>('PowerSetRequest');
  final clear = kernel.lookupFunction<Int32 Function(IntPtr, Int32),
      int Function(int, int)>('PowerClearRequest');
  return using((arena) {
    final context = arena<_ReasonContext>();
    context.ref
      ..version = 0
      ..flags = 1;
    context.ref.reason.simple = reason.toNativeUtf16(allocator: arena);
    final handle = create(context);
    if (handle == -1 || handle == 0) {
      throw StateError('PowerCreateRequest failed');
    }
    // PowerRequestSystemRequired permits display sleep and survives thread hops.
    if (set(handle, 1) == 0) {
      CloseHandle(handle);
      throw StateError('PowerSetRequest failed');
    }
    return () {
      clear(handle, 1);
      final closed = CloseHandle(handle);
      if (closed == 0) {
        throw StateError('CloseHandle failed');
      }
    };
  });
}

void Function() _acquireMac(String reason) {
  final core = DynamicLibrary.open(
    '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
  );
  final io = DynamicLibrary.open(
    '/System/Library/Frameworks/IOKit.framework/IOKit',
  );
  final string = core.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32),
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int)>(
    'CFStringCreateWithCString',
  );
  final release = core.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('CFRelease');
  final create = io.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, int, Pointer<Void>, Pointer<Uint32>)>(
    'IOPMAssertionCreateWithName',
  );
  final clear = io.lookupFunction<Int32 Function(Uint32), int Function(int)>(
    'IOPMAssertionRelease',
  );
  return using((arena) {
    final type = string(
        nullptr,
        'PreventUserIdleSystemSleep'.toNativeUtf8(allocator: arena),
        0x08000100);
    final name =
        string(nullptr, reason.toNativeUtf8(allocator: arena), 0x08000100);
    try {
      if (type == nullptr || name == nullptr) {
        throw StateError('CFStringCreateWithCString failed');
      }
      final id = arena<Uint32>();
      final result = create(type, 255, name, id);
      if (result != 0) {
        throw StateError('IOPMAssertionCreateWithName failed: $result');
      }
      final assertion = id.value;
      return () {
        final result = clear(assertion);
        if (result != 0) {
          throw StateError('IOPMAssertionRelease failed: $result');
        }
      };
    } finally {
      if (type != nullptr) release(type);
      if (name != nullptr) release(name);
    }
  });
}
