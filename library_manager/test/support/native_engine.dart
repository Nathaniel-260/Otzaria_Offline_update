import 'dart:io';

import 'package:path/path.dart' as p;

/// The engine's build hook puts its library under `build/native_assets`;
/// `flutter test` runs the hook, so this is the pinned version.
String? hookEngineLibrary() {
  final name = Platform.isWindows
      ? 'search_engine.dll'
      : Platform.isMacOS
      ? 'libsearch_engine.dylib'
      : 'libsearch_engine.so';
  for (final os in ['windows', 'macos', 'linux']) {
    final file = File(p.join('build', 'native_assets', os, name));
    if (file.existsSync()) return file.absolute.path;
  }
  return null;
}
