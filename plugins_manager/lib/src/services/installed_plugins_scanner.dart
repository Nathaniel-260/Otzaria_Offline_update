import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaDataRoot;
import 'package:path/path.dart' as p;

import 'installed_plugins_registry.dart';

class InstalledPluginsScanner {
  const InstalledPluginsScanner({
    this.customPluginsDir,
    this.otzariaLaunchPath,
    this.locatePluginsDb,
  });

  final String? customPluginsDir;

  final String? otzariaLaunchPath;

  final Future<String?> Function(String dataRoot)? locatePluginsDb;

  /// שם תיקיית המשנה שאוצריא מתקינה לתוכה כל תוסף.
  static const String installedDirName = 'installed';

  /// שמות תיקיות ההוצאה שבתוך `installed/<manifestId>/` — המבנה הישן
  /// (`current`) והחדש (`.release-<hash>`).
  static const String currentDirName = 'current';
  static const String releaseDirPrefix = '.release-';

  /// סימון ההתקנה הניידת של אוצריא, ליד ה-executable שלה, ותיקיית הנתונים
  /// שהוא מפעיל. **חייבים להישאר תואמים ל-`LibraryDbLocator`** — אותו זיהוי
  /// בדיוק בשתי החבילות; יש בדיקה ב-`launcher_app` שמאמתת זאת.
  static const String portableMarkerFileName =
      OtzariaDataRoot.portableMarkerFileName;
  static const String portableDataFolderName =
      OtzariaDataRoot.portableDataFolderName;

  Future<Map<String, String>> scan() async => (await scanState()).versions;

  static Map<String, String> Function() environment =
      () => Platform.environment;

  static void Function(String path)? debugPathGuard;

  /// מפנה את ברירת המחדל לתיקייה זמנית, ונכשל אם בדיקה מגיעה בכל זאת לנתוני
  /// אוצריא האמיתיים של המחשב.
  static void sandboxForTests(String sandboxRoot) {
    final real = Platform.environment;
    final forbidden = [
      for (final key in const ['APPDATA', 'LOCALAPPDATA', 'ProgramData'])
        if ((real[key] ?? '').isNotEmpty) p.join(real[key]!, 'otzaria'),
      if ((real['HOME'] ?? '').isNotEmpty)
        p.join(real['HOME']!, 'Library', 'Application Support', 'otzaria'),
    ];
    final sandbox = {
      'APPDATA': p.join(sandboxRoot, 'Roaming'),
      'HOME': p.join(sandboxRoot, 'home'),
    };
    environment = () => sandbox;
    debugPathGuard = (path) {
      for (final root in forbidden) {
        if (p.equals(root, path) || p.isWithin(root, path)) {
          throw StateError('A test reached a real Otzaria path: $path');
        }
      }
    };
  }

  Future<InstalledPluginsState> scanState() async {
    final root = resolveInstalledDir();
    if (root == null) return InstalledPluginsState.empty;
    debugPathGuard?.call(root);

    final registered = await _readRegistry(root);
    if (registered != null) return registered;

    final dir = Directory(root);
    if (!await dir.exists()) return InstalledPluginsState.empty;

    final result = <String, String>{};
    try {
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! Directory) continue;
        final version = _readInstalledVersion(entry.path);
        if (version != null) result[p.basename(entry.path)] = version;
      }
    } on FileSystemException {
      return InstalledPluginsState(versions: result);
    }
    return InstalledPluginsState(versions: result);
  }

  Future<InstalledPluginsState?> _readRegistry(String installedDir) async {
    final locate = locatePluginsDb;
    if (locate == null) return null;
    try {
      final dbPath = await locate(p.dirname(p.dirname(installedDir)));
      if (dbPath == null) return null;
      debugPathGuard?.call(dbPath);
      return await Isolate.run(() => readInstalledPluginsRegistry(dbPath));
    } catch (_) {
      return null;
    }
  }

  /// תיקיית ה-`installed` שתיסרק בפועל, או null אם אי אפשר לגזור אותה
  /// בפלטפורמה הזו.
  String? resolveInstalledDir() {
    final plugins = resolvePluginsDir();
    if (plugins == null) return null;
    // מי שמוסר נתיב יכול להצביע על `plugins` או ישירות על `plugins/installed`.
    return p.basename(plugins) == installedDirName
        ? plugins
        : p.join(plugins, installedDirName);
  }

  /// תיקיית ה-`plugins` של אוצריא, לפי סדר העדיפות שבתיאור המחלקה.
  String? resolvePluginsDir() {
    final custom = customPluginsDir;
    if (custom != null && custom.isNotEmpty) return custom;

    final portable = portablePluginsDir(otzariaLaunchPath);
    if (portable != null) return portable;

    return defaultPluginsDir();
  }

  /// תיקיית התוספים של התקנה **ניידת** — `<exeDir>/otzaria_data/plugins` —
  /// או null כשההתקנה שזוהתה אינה ניידת.
  ///
  /// כמו באוצריא, רק קובץ הסימון קובע — תיקיית נתונים בלעדיו אינה ניידת.
  static String? portablePluginsDir(String? launchPath) {
    final root = OtzariaDataRoot.portableRoot(
      launchPath,
      operatingSystem: Platform.operatingSystem,
    );
    return root == null ? null : p.join(root, 'plugins');
  }

  /// `<dataRoot>/plugins` של אוצריא (`AppPaths.getPluginsRootPath`).
  static String? defaultPluginsDir() {
    final root = OtzariaDataRoot.userRoot(
      operatingSystem: Platform.operatingSystem,
      environment: environment(),
    );
    return root == null ? null : p.join(root, 'plugins');
  }

  /// הגרסה המותקנת של תוסף אחד — מתוך תיקיית ההוצאה הפעילה שלו.
  static String? _readInstalledVersion(String pluginDir) {
    for (final dir in _releaseDirs(pluginDir)) {
      final version = _versionIn(dir);
      if (version != null) return version;
    }
    return null;
  }

  /// תיקיות ההוצאה של תוסף, בסדר עדיפות. `current` קודמת כי היא המצביע
  /// המפורש של המבנה הישן; אחריה `.release-<hash>` מהחדשה לישנה, כי זו
  /// שאוצריא כתבה אחרונה היא הפעילה.
  static List<String> _releaseDirs(String pluginDir) {
    final current = p.join(pluginDir, currentDirName);
    final result = <String>[if (Directory(current).existsSync()) current];

    final releases = <Directory>[];
    try {
      for (final entry in Directory(pluginDir).listSync(followLinks: false)) {
        if (entry is Directory &&
            p.basename(entry.path).startsWith(releaseDirPrefix)) {
          releases.add(entry);
        }
      }
    } catch (_) {
      return result; // תיקייה שאי אפשר לקרוא — מה שנמצא עד כה
    }
    // מיון משני לפי השם, כדי ששתי הוצאות באותה חותמת זמן ייבחרו בקביעות.
    releases.sort((a, b) {
      final byTime = _modified(b).compareTo(_modified(a));
      return byTime != 0
          ? byTime
          : p.basename(b.path).compareTo(p.basename(a.path));
    });
    result.addAll(releases.map((dir) => dir.path));
    return result;
  }

  static DateTime _modified(Directory dir) {
    try {
      return dir.statSync().modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  static String? _versionIn(String releaseDir) {
    try {
      final file = File(p.join(releaseDir, 'manifest.json'));
      if (!file.existsSync()) return null;
      final decoded =
          jsonDecode(file.readAsStringSync().replaceFirst('\uFEFF', ''));
      if (decoded is! Map) return null;
      final version = decoded['version'];
      return version is String && version.isNotEmpty ? version : null;
    } catch (_) {
      return null; // מניפסט פגום — מתעלמים בשקט מההוצאה הזו
    }
  }
}
