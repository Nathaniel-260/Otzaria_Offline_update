import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class OtzariaCapabilities {
  const OtzariaCapabilities({
    this.reportsQueueFormat,
    this.pluginInstallResults,
  });

  static const String fileName = 'otzaria_capabilities.json';

  final int? reportsQueueFormat;
  final int? pluginInstallResults;

  static Future<OtzariaCapabilities?> read(String dataRoot) async {
    try {
      final text = await File(p.join(dataRoot, fileName)).readAsString();
      final decoded = jsonDecode(text.replaceFirst('\uFEFF', ''));
      if (decoded is! Map) return null;
      int? field(String key) =>
          decoded[key] is int ? decoded[key] as int : null;
      return OtzariaCapabilities(
        reportsQueueFormat: field('reportsQueueFormat'),
        pluginInstallResults: field('pluginInstallResults'),
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
