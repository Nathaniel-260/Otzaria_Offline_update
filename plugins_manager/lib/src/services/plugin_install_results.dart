import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PluginInstallReport {
  const PluginInstallReport({
    required this.path,
    required this.outcome,
    required this.at,
    this.pluginId,
    this.version,
    this.message,
  });

  final String path;
  final String outcome;
  final DateTime at;
  final String? pluginId;
  final String? version;
  final String? message;

  bool get succeeded => outcome == 'installed' || outcome == 'updated';

  bool get cancelled => outcome == 'cancelled';

  static PluginInstallReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    final outcome = json['outcome'];
    final rawAt = json['at'];
    final at = rawAt is String ? DateTime.tryParse(rawAt) : null;
    if (path is! String || outcome is! String || at == null) return null;
    String? text(Object? value) => value is String ? value : null;
    return PluginInstallReport(
      path: path,
      outcome: outcome,
      at: at,
      pluginId: text(json['pluginId']),
      version: text(json['version']),
      message: text(json['message']),
    );
  }
}

abstract final class PluginInstallResults {
  static const String fileName = 'plugin_install_results.jsonl';

  static const Duration clockSkew = Duration(seconds: 2);

  static Future<List<PluginInstallReport>> read(String dataRoot) async {
    final List<String> lines;
    try {
      lines = await File(p.join(dataRoot, fileName)).readAsLines();
    } on FileSystemException {
      return const [];
    }
    return [
      for (final line in lines)
        if (_parse(line) case final report?) report,
    ];
  }

  static PluginInstallReport? latestFor(
    List<PluginInstallReport> reports,
    String path,
    DateTime since,
  ) {
    final from = since.subtract(clockSkew);
    PluginInstallReport? latest;
    for (final report in reports) {
      if (!p.equals(report.path, path) || report.at.isBefore(from)) continue;
      if (latest == null || !report.at.isBefore(latest.at)) latest = report;
    }
    return latest;
  }

  static PluginInstallReport? _parse(String line) {
    if (line.trim().isEmpty) return null;
    try {
      return PluginInstallReport.fromJson(jsonDecode(line));
    } on FormatException {
      return null;
    }
  }
}
