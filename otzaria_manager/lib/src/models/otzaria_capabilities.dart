import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'otzaria_release.dart';

class OtzariaCapabilities {
  const OtzariaCapabilities({
    this.formatVersion,
    this.appVersion,
    this.buildNumber,
    this.arch,
    this.portable,
    this.exePath,
    this.readableDbSchemaVersion,
    this.libraryDbPath,
    this.reportsQueueFormat,
    this.pluginInstallResults,
    this.writtenAt,
  });

  static const String fileName = 'otzaria_capabilities.json';
  static const String portableDataFolderName = 'otzaria_data';
  static const String portableMarkerFileName = 'portable.marker';

  final int? formatVersion;
  final String? appVersion;
  final int? buildNumber;
  final String? arch;
  final bool? portable;
  final String? exePath;
  final int? readableDbSchemaVersion;
  final String? libraryDbPath;
  final int? reportsQueueFormat;
  final int? pluginInstallResults;
  final DateTime? writtenAt;

  static OtzariaCapabilities? fromJson(Object? json) {
    if (json is! Map) return null;
    T? field<T>(String key) {
      final value = json[key];
      return value is T ? value : null;
    }

    final writtenAt = field<String>('writtenAt');
    return OtzariaCapabilities(
      formatVersion: field<int>('formatVersion'),
      appVersion: field<String>('appVersion'),
      buildNumber: field<int>('buildNumber'),
      arch: field<String>('arch'),
      portable: field<bool>('portable'),
      exePath: field<String>('exePath'),
      readableDbSchemaVersion: field<int>('readableDbSchemaVersion'),
      libraryDbPath: field<String>('libraryDbPath'),
      reportsQueueFormat: field<int>('reportsQueueFormat'),
      pluginInstallResults: field<int>('pluginInstallResults'),
      writtenAt: writtenAt == null ? null : DateTime.tryParse(writtenAt),
    );
  }

  static String? dataRootFor(
    String launchPath, {
    required OtzariaTargetPlatform platform,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    switch (platform) {
      case OtzariaTargetPlatform.windows:
        final exeDir = p.dirname(launchPath);
        if (File(p.join(exeDir, portableMarkerFileName)).existsSync()) {
          return p.join(exeDir, portableDataFolderName);
        }
        final appData = env['APPDATA'];
        return appData == null || appData.isEmpty
            ? null
            : p.join(appData, 'otzaria');
      case OtzariaTargetPlatform.macos:
        final home = env['HOME'];
        return home == null || home.isEmpty
            ? null
            : p.join(home, 'Library', 'Application Support', 'otzaria');
    }
  }

  static OtzariaCapabilities? readForInstall(
    String launchPath, {
    required OtzariaTargetPlatform platform,
    Map<String, String>? environment,
  }) {
    final root = dataRootFor(
      launchPath,
      platform: platform,
      environment: environment,
    );
    if (root == null) return null;
    try {
      final file = File(p.join(root, fileName));
      if (!file.existsSync()) return null;
      return fromJson(jsonDecode(file.readAsStringSync()));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  bool describesExe(String launchPath) {
    final exe = exePath;
    if (exe == null) return false;
    if (p.equals(exe, launchPath)) return true;
    return p.isWithin(launchPath, exe) &&
        launchPath.toLowerCase().endsWith('.app');
  }
}
