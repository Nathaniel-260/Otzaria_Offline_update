import 'dart:io';

import 'package:path/path.dart' as p;

/// שורש הנתונים של אוצריא — תרגום של `AppPaths.getDataRootPath`: קובץ
/// `portable.marker` ליד ה-exe מפנה ל-`otzaria_data` שלידו, ואחרת שורש המשתמש.
class OtzariaDataRoot {
  const OtzariaDataRoot._();

  static const String portableMarkerFileName = 'portable.marker';
  static const String portableDataFolderName = 'otzaria_data';

  static p.Context _pathFor(String operatingSystem) =>
      operatingSystem == 'windows' ? p.windows : p.posix;

  static String? exeDirOf(String? launchPath,
      {required String operatingSystem}) {
    if (launchPath == null || launchPath.isEmpty) return null;
    final path = _pathFor(operatingSystem);
    if (launchPath.toLowerCase().endsWith('.app')) {
      return path.join(launchPath, 'Contents', 'MacOS');
    }
    return path.dirname(launchPath);
  }

  static String? portableRoot(
    String? launchPath, {
    required String operatingSystem,
  }) {
    final exeDir = exeDirOf(launchPath, operatingSystem: operatingSystem);
    if (exeDir == null) return null;
    final path = _pathFor(operatingSystem);
    if (!File(path.join(exeDir, portableMarkerFileName)).existsSync()) {
      return null;
    }
    return path.join(exeDir, portableDataFolderName);
  }

  static String? userRoot({
    required String operatingSystem,
    required Map<String, String> environment,
  }) {
    final path = _pathFor(operatingSystem);
    String? under(String key, List<String> parts) {
      final base = environment[key];
      return base == null || base.isEmpty
          ? null
          : path.joinAll([base, ...parts]);
    }

    return switch (operatingSystem) {
      'windows' => under('APPDATA', const ['otzaria']),
      'macos' =>
        under('HOME', const ['Library', 'Application Support', 'otzaria']),
      _ => under('HOME', const ['.local', 'share', 'otzaria']),
    };
  }

  static String? resolve(
    String? launchPath, {
    required String operatingSystem,
    required Map<String, String> environment,
  }) =>
      portableRoot(launchPath, operatingSystem: operatingSystem) ??
      userRoot(operatingSystem: operatingSystem, environment: environment);
}
