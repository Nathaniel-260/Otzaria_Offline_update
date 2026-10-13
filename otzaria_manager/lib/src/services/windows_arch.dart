import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

enum OtzariaArch {
  x64,
  arm64;

  static OtzariaArch? fromPeMachine(int machine) => switch (machine) {
        IMAGE_FILE_MACHINE_AMD64 => OtzariaArch.x64,
        IMAGE_FILE_MACHINE_ARM64 => OtzariaArch.arm64,
        _ => null,
      };
}

class WindowsArch {
  const WindowsArch._();

  static OtzariaArch? _machine;

  static OtzariaArch machine({Map<String, String>? environment}) =>
      _machine ??= _detectMachine(environment ?? Platform.environment);

  static OtzariaArch _detectMachine(Map<String, String> environment) {
    if (Platform.isWindows) {
      final native = _nativeMachineOrNull();
      if (native != null) return native;
    }
    return machineFromEnvironment(environment);
  }

  static OtzariaArch machineFromEnvironment(Map<String, String> environment) {
    final reported = (environment['PROCESSOR_ARCHITEW6432'] ??
            environment['PROCESSOR_ARCHITECTURE'] ??
            '')
        .toUpperCase();
    return reported == 'ARM64' ? OtzariaArch.arm64 : OtzariaArch.x64;
  }

  static OtzariaArch? _nativeMachineOrNull() {
    final processMachine = calloc<Uint16>();
    final nativeMachine = calloc<Uint16>();
    try {
      if (IsWow64Process2(GetCurrentProcess(), processMachine, nativeMachine) ==
          0) {
        return null;
      }
      return OtzariaArch.fromPeMachine(nativeMachine.value) ?? OtzariaArch.x64;
    } on ArgumentError {
      return null;
    } finally {
      calloc.free(processMachine);
      calloc.free(nativeMachine);
    }
  }

  static OtzariaArch? ofExecutable(String path) {
    RandomAccessFile? file;
    try {
      file = File(path).openSync();
      final dos = file.readSync(64);
      if (dos.length < 64 || dos[0] != 0x4d || dos[1] != 0x5a) return null;
      final peOffset = ByteData.sublistView(dos).getUint32(0x3c, Endian.little);
      file.setPositionSync(peOffset);
      final header = file.readSync(6);
      if (header.length < 6 ||
          header[0] != 0x50 ||
          header[1] != 0x45 ||
          header[2] != 0 ||
          header[3] != 0) {
        return null;
      }
      return OtzariaArch.fromPeMachine(
        ByteData.sublistView(header).getUint16(4, Endian.little),
      );
    } on FileSystemException {
      return null;
    } finally {
      file?.closeSync();
    }
  }
}
