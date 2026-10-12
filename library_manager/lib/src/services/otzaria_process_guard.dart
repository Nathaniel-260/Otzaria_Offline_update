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

  Future<bool> isAnyRunning(List<String> processNames) async =>
      (await _locator.probe()).isRunning;

  Future<bool> isRunning(String processName) => isAnyRunning([processName]);
}

/// נזרק על ידי [LibraryManager] כשמנסים לעדכן DB בזמן שאוצריא רצה.
class OtzariaIsRunningException implements Exception {
  const OtzariaIsRunningException();

  @override
  String toString() => AppL10n.strings.libraryDomain.otzariaIsRunning;
}
