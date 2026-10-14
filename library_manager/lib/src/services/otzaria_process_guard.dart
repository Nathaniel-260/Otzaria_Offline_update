import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart'
    show RunningOtzariaLocator;

class OtzariaProcessGuard {
  const OtzariaProcessGuard({
    RunningOtzariaLocator locator = const RunningOtzariaLocator(),
  }) : _locator = locator;

  final RunningOtzariaLocator _locator;

  static List<String> processNamesFor(String operatingSystem) =>
      RunningOtzariaLocator.processNamesFor(operatingSystem);

  Future<bool> isAnyRunning(List<String> processNames) async {
    if (!Platform.isWindows) {
      for (final name in processNames) {
        if (await isRunning(name)) return true;
      }
      return false;
    }
    final probe = await _locator.probe();
    return probe.isRunning || RunningOtzariaLocator.lastProbeFailure != null;
  }

  Future<bool> isRunning(String processName) async {
    if (Platform.isWindows) return isAnyRunning([processName]);
    if (!Platform.isMacOS && !Platform.isLinux) return false;
    final ProcessResult result;
    try {
      result = await Process.run('/usr/bin/pgrep', ['-x', processName]);
    } on ProcessException {
      return true;
    }
    return result.exitCode != 1;
  }
}

/// נזרק על ידי [LibraryManager] כשמנסים לעדכן DB בזמן שאוצריא רצה.
class OtzariaIsRunningException implements Exception {
  const OtzariaIsRunningException();

  @override
  String toString() => AppL10n.strings.libraryDomain.otzariaIsRunning;
}
