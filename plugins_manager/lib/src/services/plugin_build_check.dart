import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/plugin_version_entry.dart';
import '../models/store_plugin.dart';
import 'plugin_manifest_reader.dart';
import 'plugin_version_compare.dart';

/// מנהל באתר יכול לשנות את מספר הגרסה בלי קובץ חדש, ולכן גרסה שונה במניפסט
/// אינה סיבה לדחות; מזהה שונה או sha256 שונה — כן.
enum PluginBuildMatch { matches, versionDiffers, wrongId, notPlugin }

abstract final class PluginBuildCheck {
  static PluginBuildMatch match(
    Map<String, dynamic>? manifest, {
    required String version,
    String? expectedId,
  }) {
    final id = PluginManifestReader.idOf(manifest);
    if (id == null) return PluginBuildMatch.notPlugin;
    if (expectedId != null && id != expectedId) return PluginBuildMatch.wrongId;
    final manifestVersion = manifest?['version'];
    return manifestVersion is String &&
            manifestVersion.trim().isNotEmpty &&
            comparePluginVersions(manifestVersion, version) == 0
        ? PluginBuildMatch.matches
        : PluginBuildMatch.versionDiffers;
  }

  static bool isAcceptable(PluginBuildMatch match) =>
      match == PluginBuildMatch.matches ||
      match == PluginBuildMatch.versionDiffers;

  static Future<String> sha256Of(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  static Future<bool> verifyLocal(
    String path, {
    required PluginLocalFile local,
    required PluginVersionEntry target,
    String? expectedId,
  }) async {
    final file = File(path);
    if (!await file.exists()) return false;
    if (local.size > 0 && await file.length() != local.size) return false;
    final expected = local.sha256 ?? target.sha256;
    if (expected != null && await sha256Of(path) != expected) return false;
    return isAcceptable(
      match(
        PluginManifestReader.read(path),
        version: target.version,
        expectedId: expectedId,
      ),
    );
  }
}
