import 'dart:async';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

class CustomAppDetectionSnapshot {
  CustomAppDetectionSnapshot({
    required FutureOr<List<String>> Function() runningImagePaths,
    required FutureOr<List<InstallRegistryEntry>> Function() uninstallEntries,
  })  : _runningImagePaths = runningImagePaths,
        _uninstallEntries = uninstallEntries;

  factory CustomAppDetectionSnapshot.live() => CustomAppDetectionSnapshot(
        runningImagePaths:
            RunningOtzariaLocator.windowsRunningImagePathsOffUiIsolate,
        uninstallEntries: () => const WindowsInstallRegistry()
            .entriesOffUiIsolate(matchesDisplayName: _any),
      );

  static bool _any(String _) => true;

  final FutureOr<List<String>> Function() _runningImagePaths;
  final FutureOr<List<InstallRegistryEntry>> Function() _uninstallEntries;

  Future<List<String>>? _processes;
  Future<List<InstallRegistryEntry>>? _entries;

  Future<String?> runningProcess(String exeName) async {
    final target = exeName.toLowerCase();
    for (final path in await (_processes ??= _quietly(_runningImagePaths))) {
      if (p.basename(path).toLowerCase() == target) return path;
    }
    return null;
  }

  Future<List<String>> uninstallDirs(RegExp displayName) async {
    final dirs = <String>[];
    final seen = <String>{};
    for (final entry in await (_entries ??= _quietly(_uninstallEntries))) {
      final dir = entry.installDir;
      if (dir == null || !displayName.hasMatch(entry.displayName)) continue;
      if (seen.add(dir.toLowerCase())) dirs.add(dir);
    }
    return dirs;
  }

  static Future<List<T>> _quietly<T>(
    FutureOr<List<T>> Function() read,
  ) async {
    try {
      return await read();
    } catch (_) {
      return const [];
    }
  }
}
