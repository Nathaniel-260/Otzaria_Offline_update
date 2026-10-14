import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria_manager/otzaria_manager.dart'
    show OtzariaCapabilities, OtzariaDataRoot;
import 'package:path/path.dart' as p;

import 'library_state_store.dart';
import 'otzaria_settings_reader.dart';

/// מוצא את נתיב `seforim.db` של המשתמש.
///
/// **סדר החיפוש**:
/// 1. **ההגדרות של אוצריא עצמה** — `key-library-path` +
///    `key-library-folder-name` מתוך `app_preferences.hive`, בדיוק כמו
///    `DatabaseConstants.getDatabasePath` שם; אחריהן `library_database_path.txt`
///    ו-`libraryDbPath` של `otzaria_capabilities.json` בשורש הנתונים שלה.
/// 2. נתיב מותאם אישית ששמור מ-[LibraryStateStore] (המשתמש כבר הצביע עליו).
/// 3. ספרייה מצורפת ליד ההתקנה (חבילת FULL ב-macOS) — ראו [bundledLibraryDir].
/// 4. ברירות המחדל של אוצריא בפלטפורמה הנוכחית — ראו [defaultDbDirs].
/// 5. **גיבוי** בווינדוס: `C:\אוצריא\seforim.db`.
///
/// מחזיר null אם אף מקור לא נמצא — הקורא (UI) צריך לבקש מהמשתמש להצביע על
/// הקובץ, ואז לקרוא ל-[LibraryStateStore.saveCustomDbPath].
class LibraryDbLocator {
  const LibraryDbLocator({
    required this.stateStore,
    this.settingsReader = const OtzariaSettingsReader(),
    this.otzariaLaunchPath,
    String? operatingSystem,
    Map<String, String>? environment,
  }) : _operatingSystemOverride = operatingSystem,
       _environmentOverride = environment;

  factory LibraryDbLocator.forLaunch({
    required String stateDir,
    required String launchPath,
    String? dataDir,
  }) => LibraryDbLocator(
    stateStore: LibraryStateStore.inDir(stateDir, dataDir: dataDir),
    otzariaLaunchPath: () async => launchPath,
  );

  final LibraryStateStore stateStore;

  /// קורא את קופסת ההגדרות של אוצריא. best-effort — ראו [OtzariaSettingsReader].
  final OtzariaSettingsReader settingsReader;

  /// נתיב ההפעלה של אוצריא (`.exe` בווינדוס, חבילת `.app` ב-macOS), אם ידוע.
  /// דרוש כדי לזהות התקנה **ניידת** (שם שורש הנתונים יושב ליד התוכנה ולא
  /// ב-`%APPDATA%`) וספרייה מצורפת. `null` = פשוט מדלגים על שתי האפשרויות.
  final Future<String?> Function()? otzariaLaunchPath;

  /// דריסות לבדיקות בלבד. בלעדיהן בדיקה כמו "אין DB בשום מקום" הייתה
  /// נכשלת אצל מפתח שאוצריא אמיתית מותקנת אצלו במיקום ברירת המחדל.
  final String? _operatingSystemOverride;
  final Map<String, String>? _environmentOverride;

  LibraryDbLocator withSettingsReader(OtzariaSettingsReader reader) =>
      LibraryDbLocator(
        stateStore: stateStore,
        settingsReader: reader,
        otzariaLaunchPath: otzariaLaunchPath,
        operatingSystem: _operatingSystemOverride,
        environment: _environmentOverride,
      );

  String get _operatingSystem =>
      _operatingSystemOverride ?? Platform.operatingSystem;
  Map<String, String> get _environment =>
      _environmentOverride ?? defaultEnvironment();

  @visibleForTesting
  static Map<String, String> Function() defaultEnvironment =
      _platformEnvironment;

  static Map<String, String> _platformEnvironment() => Platform.environment;

  @visibleForTesting
  static String legacyFallbackRoot = legacyFallbackLibraryPath;

  @visibleForTesting
  static void Function(String path)? debugPathGuard;

  static String _guarded(String path) {
    debugPathGuard?.call(path);
    return path;
  }

  static const String macSystemDataRoot =
      '/Library/Application Support/otzaria';

  @visibleForTesting
  static String macSystemRoot = macSystemDataRoot;

  @visibleForTesting
  static void sandboxForTests(String sandboxRoot) {
    final real = Platform.environment;
    final forbidden = <String>[
      for (final key in const ['APPDATA', 'ProgramData', 'LOCALAPPDATA'])
        if ((real[key] ?? '').isNotEmpty) p.join(real[key]!, 'otzaria'),
      if ((real['HOME'] ?? '').isNotEmpty) ...[
        p.join(real['HOME']!, 'Library', 'Application Support', 'otzaria'),
        p.join(real['HOME']!, '.local', 'share', 'otzaria'),
      ],
      if (Platform.isMacOS) macSystemDataRoot,
      legacyFallbackLibraryPath,
    ];
    final sandbox = <String, String>{
      'APPDATA': p.join(sandboxRoot, 'Roaming'),
      'ProgramData': p.join(sandboxRoot, 'ProgramData'),
      'LOCALAPPDATA': p.join(sandboxRoot, 'Local'),
      'HOME': p.join(sandboxRoot, 'home'),
      for (final key in const ['ProgramFiles', 'ProgramFiles(x86)'])
        if (real[key] != null) key: real[key]!,
    };
    defaultEnvironment = () => sandbox;
    legacyFallbackRoot = p.join(sandboxRoot, 'legacy-otzaria');
    macSystemRoot = p.join(sandboxRoot, 'SystemLibrary', 'otzaria');
    debugPathGuard = (path) {
      for (final root in forbidden) {
        if (p.equals(root, path) || p.isWithin(root, path)) {
          throw StateError('A test reached a real Otzaria path: $path');
        }
      }
    };
  }

  /// ה-context לבניית נתיבים — לפי [_operatingSystem], לא לפי המכונה המריצה,
  /// כדי שדריסת ה-OS בבדיקות תייצר נתיבים באמת בסגנון אותה פלטפורמה.
  p.Context get _path => _operatingSystem == 'windows' ? p.windows : p.posix;

  static const String databaseFileName = 'seforim.db';

  /// סימון ההתקנה הניידת של אוצריא, ליד ה-executable שלה
  /// (`AppPaths.portableMarkerFileName`), ותיקיית הנתונים שהוא מפעיל.
  static const String portableMarkerFileName = 'portable.marker';
  static const String portableDataFolderName = 'otzaria_data';

  /// ספרייה מצורפת בחבילת FULL: תיקיית `אוצריא` ליד ההתקנה, עם קובץ סימון
  /// שה-CI של אוצריא יוצר (`AppPaths._bundledLibraryMarkerFileName`).
  static const String bundledLibraryFolderName = 'אוצריא';
  static const String bundledLibraryMarkerFileName = '.otzaria_bundled_library';

  /// גיבוי משני בווינדוס — לא ברירת המחדל האמיתית. ייתכן שזה עדיין נכון
  /// בהתקנות ישנות/מסוימות (למשל חבילת "FULL" שמתקינה במיקום קבוע).
  static const String legacyFallbackLibraryPath = r'C:\אוצריא';

  /// הסימון שהמתקין של אוצריא כותב ליד ה-exe בהתקנת מנהל
  /// (`AppPaths.isWindowsSystemInstall`).
  static const String systemInstallMarkerFileName = 'system_install.marker';

  /// תיקיות ה-`books` שאוצריא משתמשת בהן כברירת מחדל, לפי סדר עדיפות.
  ///
  /// **נגזר מקוד המקור של אוצריא** (`lib/core/app_paths.dart`,
  /// `getDataRootPath` + `getDefaultLibraryPath`), לא מניחוש:
  ///
  /// * Windows — `%APPDATA%\otzaria\books` (אומת גם מול דיווח משתמש בגרסה
  ///   0.9.9x), ובהתקנה מערכתית `%ProgramData%\otzaria\books`.
  /// * macOS — `~/Library/Application Support/otzaria/books`, ובהתקנה
  ///   מערכתית `/Library/Application Support/otzaria/books`.
  ///
  /// [environment] מוזרק כדי שהבדיקות יוכלו לדמות את שתי הפלטפורמות בלי
  /// לגעת בסביבה האמיתית. [systemInstall] הופך את הסדר — ראו
  /// [isSystemInstall].
  static List<String> defaultDbDirs({
    required String operatingSystem,
    required Map<String, String> environment,
    bool systemInstall = false,
  }) {
    final path = _pathFor(operatingSystem);
    return [
      for (final root in _platformDataRoots(
        operatingSystem: operatingSystem,
        environment: environment,
        // פלטפורמה לא מוכרת מחזירה ריק במקום לנחש — יש על כך בדיקה.
        guessUnknownPlatform: false,
        systemWideFirst: systemInstall,
      ))
        path.join(root, 'books'),
    ];
  }

  /// ה-context לבניית נתיבים נבחר לפי ה-OS ולא לפי המכונה המריצה: `p.join`
  /// הגלובלי היה מרכיב נתיבי macOS עם `\` כשהבדיקות רצות ב-Windows.
  static p.Context _pathFor(String operatingSystem) =>
      operatingSystem == 'windows' ? p.windows : p.posix;

  /// שורשי הנתונים של אוצריא לפלטפורמה, בסדר עדיפות — **הטבלה היחידה**
  /// שממנה נגזרים גם [defaultDbDirs] (שמוסיפה `books`) וגם [otzariaDataRoots]
  /// (שקוראת משם את קופסת ההגדרות). שני העתקים נפרדים שלה כבר סחפו זה מזה.
  ///
  /// [guessUnknownPlatform] הוא ההבדל **המכוון** בין שני הקוראים: איתור המסד
  /// מסרב לנחש נתיב בפלטפורמה שאינה מוכרת, ואיתור ההגדרות דווקא מנסה את
  /// מיקום ה-XDG — כדי שבדיקות שרצות בלינוקס ב-CI לא יקבלו רשימה ריקה.
  ///
  /// [systemWideFirst] הופך את סדר שני המיקומים בווינדוס: בהתקנת מנהל
  /// ברירת המחדל של אוצריא היא `%ProgramData%` ולא `%APPDATA%`. רלוונטי
  /// למיקום **הספרייה** בלבד.
  ///
  /// [userOnly] משמיט לגמרי את המיקום המערכתי — לכתיבת ההגדרות, שיושבות
  /// תמיד בשורש של המשתמש. בלעדיו סביבה בלי `%APPDATA%` הייתה מחזירה את
  /// `%ProgramData%` כ"ראשון", כלומר כותבת הגדרות למקום שאוצריא לא קוראת ממנו.
  static List<String> _platformDataRoots({
    required String operatingSystem,
    required Map<String, String> environment,
    required bool guessUnknownPlatform,
    bool systemWideFirst = false,
    bool userOnly = false,
  }) {
    final path = _pathFor(operatingSystem);
    final user = <String>[];
    final system = <String>[];

    void addUnder(List<String> into, String? base, List<String> parts) {
      if (base == null || base.isEmpty) return;
      into.add(path.joinAll([base, ...parts]));
    }

    switch (operatingSystem) {
      case 'windows':
        addUnder(user, environment['APPDATA'], const ['otzaria']);
        addUnder(system, environment['ProgramData'], const ['otzaria']);
      case 'macos':
        addUnder(user, environment['HOME'], const [
          'Library',
          'Application Support',
          'otzaria',
        ]);
        system.add(macSystemRoot);
      default:
        // הלאנצ'ר לא נבנה ללינוקס, אבל הבדיקות רצות שם ב-CI.
        if (operatingSystem == 'linux' || guessUnknownPlatform) {
          addUnder(user, environment['HOME'], const [
            '.local',
            'share',
            'otzaria',
          ]);
        }
    }

    if (userOnly) return user;
    return systemWideFirst ? [...system, ...user] : [...user, ...system];
  }

  /// התיקייה שבה יושב ה-executable של אוצריא, לפי נתיב ההפעלה: ב-macOS זהו
  /// `Contents/MacOS` שבתוך חבילת ה-`.app`, ושם גם יושב סימון ההתקנה הניידת.
  String? exeDirFor(String? launchPath) =>
      OtzariaDataRoot.exeDirOf(launchPath, operatingSystem: _operatingSystem);

  /// שורשי הנתונים של אוצריא לפי סדר עדיפות: התקנה ניידת קודמת לכול, בדיוק
  /// כמו `AppPaths.getDataRootPath`.
  Future<List<String>> otzariaDataRoots(String? launchPath) async {
    final roots = <String>[];
    final portable = await portableDataRoot(launchPath);
    if (portable != null) roots.add(portable);

    roots.addAll(
      _platformDataRoots(
        operatingSystem: _operatingSystem,
        environment: _environment,
        guessUnknownPlatform: true,
      ),
    );
    return roots;
  }

  /// תיקיית הנתונים של התקנה **ניידת** (`portable.marker` ליד ה-exe), או
  /// `null` כשההתקנה אינה כזו.
  Future<String?> portableDataRoot(String? launchPath) async =>
      OtzariaDataRoot.portableRoot(
        launchPath,
        operatingSystem: _operatingSystem,
      );

  /// השורש היחיד שאוצריא **כותבת** אליו את ההגדרות — תרגום של
  /// `AppPaths.getDataRootPath`: תיקיית ההתקנה הניידת אם יש, ואחרת השורש של
  /// המשתמש. `%ProgramData%` לעולם אינו כזה: שם יושבת לכל היותר הספרייה
  /// בהתקנת מנהל, וקופסת ההגדרות נשארת אצל המשתמש. `null` = אין מיקום ידוע,
  /// ואז אין לאן לכתוב.
  Future<String?> otzariaSettingsRoot(String? launchPath) async {
    final root = OtzariaDataRoot.resolve(
      launchPath,
      operatingSystem: _operatingSystem,
      environment: _environment,
    );
    return root == null ? null : _guarded(root);
  }

  /// האם אוצריא הותקנה כמנהל (התקנה מערכתית) — תרגום של
  /// `AppPaths.isWindowsSystemInstall`: סימון ליד ה-exe, או exe תחת
  /// `Program Files`. בהתקנה כזו ברירת המחדל של הספרייה היא `%ProgramData%`,
  /// ולכן ספרייה שהותקנה ב-`%APPDATA%` פשוט לא נמצאת. התקנה ניידת לעולם
  /// אינה מערכתית. מחוץ לווינדוס תמיד `false` — שם הסימון הוא קיום תיקייה
  /// מערכתית, שממילא נבדק בהמשך הרשימה.
  Future<bool> isSystemInstall(String? launchPath) async {
    if (_operatingSystem != 'windows') return false;
    final exeDir = exeDirFor(launchPath);
    if (exeDir == null) return false;
    if (await File(_path.join(exeDir, portableMarkerFileName)).exists()) {
      return false;
    }
    if (await File(_path.join(exeDir, systemInstallMarkerFileName)).exists()) {
      return true;
    }
    final lower = exeDir.toLowerCase();
    for (final key in const ['ProgramFiles', 'ProgramFiles(x86)']) {
      final base = _environment[key];
      if (base != null &&
          base.isNotEmpty &&
          lower.startsWith(base.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// תיקיית הספרייה המצורפת (חבילת FULL) ליד ההתקנה, או `null`. הסימון הוא
  /// תנאי — בלעדיו תיקייה בשם `אוצריא` שבמקרה נמצאת שם הייתה נחשבת ספרייה.
  Future<String?> bundledLibraryDir(String? launchPath) async {
    // באוצריא הזיהוי מדולג בווינדוס (שם ה-installer כותב את ההגדרה בעצמו).
    if (_operatingSystem != 'macos') return null;
    final exeDir = exeDirFor(launchPath);
    if (exeDir == null) return null;

    final dir = _path.normalize(
      _path.join(exeDir, '..', '..', '..', bundledLibraryFolderName),
    );
    final marker = File(_path.join(dir, bundledLibraryMarkerFileName));
    final db = File(_path.join(dir, databaseFileName));
    if (await marker.exists() && await db.exists()) return dir;
    return null;
  }

  /// הנתיבים שבהם **אוצריא עצמה** מחפשת את המסד, לפי סדר עדיפות — הבסיס
  /// המשותף ל-[resolveDbPath] (הראשון שקיים בפועל), ל-[resolveInstallDbPath]
  /// (הראשון, גם כשעדיין אין שם קובץ) ול-[isKnownToOtzaria].
  ///
  /// [includeReadOnly] מוסיף מקומות שמזהים בהם מסד קיים אבל **לא מתקינים**
  /// אליהם חדש: ספרייה מצורפת (חבילת FULL) והגיבוי הישן בווינדוס.
  Future<({List<String> current, List<String> fallbacks})>
  _otzariaDbCandidates({
    required String? launchPath,
    required bool includeReadOnly,
  }) async {
    final current = <String>[];
    for (final root in (await otzariaDataRoots(launchPath)).map(_guarded)) {
      final settings = await settingsReader.read(root);
      final fromSettings = settings?.resolveDbPath(
        path: _path,
        fileName: databaseFileName,
      );
      if (fromSettings != null) current.add(fromSettings);
    }

    final settingsRoot = await otzariaSettingsRoot(launchPath);
    if (settingsRoot != null) {
      final recordedDir = await OtzariaCapabilities.readLibraryDatabaseDir(
        settingsRoot,
      );
      if (recordedDir != null) {
        current.add(_path.join(recordedDir, databaseFileName));
      }
      final declared = (await OtzariaCapabilities.read(
        settingsRoot,
      ))?.libraryDbPath;
      if (declared != null) current.add(declared);
    }

    final fallbacks = <String>[];
    if (includeReadOnly) {
      final bundled = await bundledLibraryDir(launchPath);
      if (bundled != null) fallbacks.add(_path.join(bundled, databaseFileName));
    }

    final exeDir = exeDirFor(launchPath);
    if (exeDir != null &&
        await File(_path.join(exeDir, portableMarkerFileName)).exists()) {
      fallbacks.add(
        _path.joinAll([
          exeDir,
          portableDataFolderName,
          'books',
          databaseFileName,
        ]),
      );
    }

    for (final dir in defaultDbDirs(
      operatingSystem: _operatingSystem,
      environment: _environment,
      systemInstall: await isSystemInstall(launchPath),
    )) {
      fallbacks.add(_path.join(dir, databaseFileName));
    }

    if (includeReadOnly && _operatingSystem == 'windows') {
      fallbacks.add(_path.join(legacyFallbackRoot, databaseFileName));
    }

    return (current: current, fallbacks: fallbacks);
  }

  Future<String?> resolveDbPath() async {
    for (final candidate in await dbCandidates()) {
      if (await File(_guarded(candidate)).exists()) return candidate;
    }
    return null;
  }

  Future<List<String>> dbCandidates() =>
      _orderedCandidates(includeReadOnly: true);

  Future<List<String>> _orderedCandidates({
    required bool includeReadOnly,
  }) async {
    final custom = await stateStore.loadCustomDbChoice();
    final otzaria = await _otzariaDbCandidates(
      launchPath: await otzariaLaunchPath?.call(),
      includeReadOnly: includeReadOnly,
    );
    final explicit = custom != null && custom.explicit;
    return [
      if (explicit) custom.path,
      ...otzaria.current,
      if (custom != null && !explicit) custom.path,
      ...otzaria.fallbacks,
    ];
  }

  Future<String?> resolveInstallDbPath() async {
    final candidates = await _orderedCandidates(includeReadOnly: false);
    return candidates.isEmpty ? null : _guarded(candidates.first);
  }

  /// האם אוצריא תמצא את המסד הזה בעצמה — כלומר ההגדרה שלה או אחת מברירות
  /// המחדל מצביעות עליו. `false` = אחרי ההתקנה המשתמש יצטרך להצביע על
  /// המיקום מתוך אוצריא, ובלי זה היא לא תראה שם ספרים.
  Future<bool> isKnownToOtzaria(String dbPath) async {
    final candidates = await _otzariaDbCandidates(
      launchPath: await otzariaLaunchPath?.call(),
      includeReadOnly: true,
    );
    return [
      ...candidates.current,
      ...candidates.fallbacks,
    ].any((candidate) => _path.equals(candidate, dbPath));
  }
}
