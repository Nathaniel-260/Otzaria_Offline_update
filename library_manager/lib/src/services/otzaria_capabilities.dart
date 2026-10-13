import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class OtzariaCapabilities {
  const OtzariaCapabilities({
    this.appVersion,
    this.readableDbSchemaVersion,
    this.libraryDbPath,
  });

  static const String fileName = 'otzaria_capabilities.json';
  static const String libraryDatabasePathFileName = 'library_database_path.txt';

  static const int legacyReadableDbSchemaVersion = 5;

  static const List<(int, String)> _readableSchemaSinceAppVersion = [
    (6, '0.9.98'),
  ];

  final String? appVersion;
  final int? readableDbSchemaVersion;
  final String? libraryDbPath;

  static Future<OtzariaCapabilities?> read(String dataRoot) async {
    try {
      final file = File(p.join(dataRoot, fileName));
      if (!await file.exists()) return null;
      var text = utf8.decode(await file.readAsBytes());
      if (text.startsWith('﻿')) text = text.substring(1);
      final json = jsonDecode(text);
      if (json is! Map) return null;
      final schema = json['readableDbSchemaVersion'];
      final version = json['appVersion'];
      final dbPath = json['libraryDbPath'];
      return OtzariaCapabilities(
        appVersion: version is String && version.isNotEmpty ? version : null,
        readableDbSchemaVersion: schema is int && schema > 0 ? schema : null,
        libraryDbPath: dbPath is String && dbPath.isNotEmpty ? dbPath : null,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> readLibraryDatabaseDir(String dataRoot) async {
    try {
      final file = File(p.join(dataRoot, libraryDatabasePathFileName));
      if (!await file.exists()) return null;
      var text = utf8.decode(await file.readAsBytes());
      if (text.startsWith('﻿')) text = text.substring(1);
      text = text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static int? readableDbSchemaForAppVersion(String version) {
    if (_numericParts(version).isEmpty) return null;
    for (final (schema, since) in _readableSchemaSinceAppVersion.reversed) {
      if (compareAppVersions(version, since) >= 0) return schema;
    }
    return legacyReadableDbSchemaVersion;
  }

  static int? resolveReadableDbSchema({
    OtzariaCapabilities? capabilities,
    String? installedVersion,
  }) {
    final declared = capabilities?.readableDbSchemaVersion;
    final fromInstalled = installedVersion == null
        ? null
        : readableDbSchemaForAppVersion(installedVersion);
    if (declared == null) return fromInstalled;
    final declaredFor = capabilities?.appVersion;
    if (fromInstalled == null || installedVersion == null) return declared;
    if (declaredFor == null) return declared;
    final order = compareAppVersions(installedVersion, declaredFor);
    if (order == 0) return declared;
    if (order > 0) return declared > fromInstalled ? declared : fromInstalled;
    return fromInstalled;
  }

  static int compareAppVersions(String a, String b) {
    final left = _numericParts(a);
    final right = _numericParts(b);
    final count = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < count; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l < r ? -1 : 1;
    }
    return 0;
  }

  static List<int> _numericParts(String version) {
    var base = version.trim();
    if (base.startsWith('v') || base.startsWith('V')) base = base.substring(1);
    final cut = base.indexOf(RegExp(r'[+\-\s]'));
    if (cut >= 0) base = base.substring(0, cut);
    final parts = <int>[];
    for (final part in base.split('.')) {
      final value = int.tryParse(part);
      if (value == null) return parts;
      parts.add(value);
    }
    return parts;
  }
}
