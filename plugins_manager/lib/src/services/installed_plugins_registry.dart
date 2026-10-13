import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const String pluginsRegistryFileName = 'plugins_host.db';

class InstalledPluginsState {
  const InstalledPluginsState({
    this.versions = const {},
    this.disabled = const {},
    this.development = const {},
  });

  static const empty = InstalledPluginsState();

  final Map<String, String> versions;
  final Set<String> disabled;
  final Set<String> development;
}

const Set<String> _developmentSources = {'development', 'localhost_dev'};

InstalledPluginsState? readInstalledPluginsRegistry(String dbPath) {
  if (!File(dbPath).existsSync()) return null;
  Database? db;
  try {
    db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    db.execute('PRAGMA busy_timeout=2000');
    final columns = {
      for (final row in db.select('PRAGMA table_info(plugin_installation)'))
        row['name'],
    };
    if (columns.isEmpty) return null;
    final hasEnabled = columns.contains('enabled');
    final hasSource = columns.contains('source_type');
    final versions = <String, String>{};
    final disabled = <String>{};
    final development = <String>{};
    for (final row in db.select(
      'SELECT plugin_id, version'
      '${hasEnabled ? ', enabled' : ''}'
      '${hasSource ? ', source_type' : ''} FROM plugin_installation',
    )) {
      final id = row['plugin_id'];
      final version = row['version'];
      if (id is! String ||
          id.isEmpty ||
          version is! String ||
          version.isEmpty) {
        continue;
      }
      versions[id] = version;
      if (hasEnabled && row['enabled'] == 0) disabled.add(id);
      if (hasSource && _developmentSources.contains(row['source_type'])) {
        development.add(id);
      }
    }
    return InstalledPluginsState(
      versions: versions,
      disabled: disabled,
      development: development,
    );
  } catch (_) {
    return null;
  } finally {
    db?.close();
  }
}
