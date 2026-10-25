// בדיקות רינדור למסכי הדשבורד. המסכים נבדקים ישירות (ולא דרך AppShell),
// כדי שהבדיקה לא תיגע ברשת: הבנייה של הקונטרולרים אינה פונה לרשת, רק
// checkForUpdate/update — שלא נקראים כאן.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/otzaria_screen.dart';
import 'package:launcher_app/src/screens/payload_mismatch_screen.dart';
import 'package:launcher_app/src/screens/plugins/plugin_store_card.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/screens/setup_error_screen.dart';
import 'package:launcher_app/src/screens/store_kit/store_kit.dart';
import 'package:launcher_app/src/self_update/launcher_version.dart';
import 'package:launcher_app/src/self_update/payload_check.dart';
import 'package:launcher_app/src/services/app_paths.dart';
import 'package:launcher_app/src/services/timestamps.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/safer_mode.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as path;
import 'package:plugins_manager/plugins_manager.dart';

import 'test_harness.dart';

void main() {
  late Directory tempDir;
  late OtzariaModuleController otzaria;
  late LibraryModuleController library;
  late PluginsModuleController plugins;
  late SettingsController settings;
  late LauncherUpdateController launcherUpdate;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('launcher_test');
    otzaria = OtzariaModuleController(dataDir: tempDir.path);
    library = LibraryModuleController(dataDir: tempDir.path);
    // תיקייה זמנית ריקה: אין מראה, ולכן הבדיקה המקומית עונה "אין מה להתקין"
    // בלי לגעת ברשת. הבנייה עצמה לא פונה לשום מקום.
    launcherUpdate = LauncherUpdateController(dataDir: tempDir.path);
    // מראה בתיקייה זמנית ריקה: הקטלוג לא קיים ולכן [load] מחזיר קטלוג ריק
    // בלי לגעת ברשת — בדיוק המצב שלפני הסנכרון הראשון.
    plugins = PluginsModuleController(mirrorRootDir: tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
  });

  /// עדכון ספרייה זמין — מוצב ידנית, בלי דיסק.
  void fakeLibraryUpdateAvailable() {
    library.status = LibraryModuleStatus.updateAvailable;
    library.localVersion = 1;
    library.targetVersion = 2;
  }

  OtzariaScreen otzariaPage({
    VoidCallback? onUpdateHere,
    VoidCallback? onReinstall,
    SaferModeGate? saferMode,
  }) =>
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        onUpdateHere: onUpdateHere,
        onReinstall: onReinstall,
        saferMode: saferMode,
      );

  LibraryScreen libraryPage({
    VoidCallback? onUpdateHere,
    Future<void> Function()? onRequestReindex,
    bool readOnly = false,
  }) =>
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: onRequestReindex ?? () async {},
        onGoToSettings: () {},
        onUpdateHere: onUpdateHere,
        readOnly: readOnly,
      );

  /// "מתקדם" מקופל כברירת מחדל. בלי pumpAndSettle: מצב "בודק" מסתובב.
  Future<void> openAdvanced(WidgetTester tester) async {
    final arrow = tester.widget<AnimatedRotation>(
      find.descendant(
        of: find.byKey(ShellKeys.pageAdvanced),
        matching: find.byType(AnimatedRotation),
      ),
    );
    if (arrow.turns != 0) return;
    await tester.ensureVisible(find.byKey(ShellKeys.pageAdvanced));
    await tester.tap(find.text(stringsOf().pages.advancedTitle));
    await tester.pump();
  }

  tearDown(() {
    otzaria.dispose();
    library.dispose();
    plugins.dispose();
    launcherUpdate.dispose();
    settings.dispose();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('דף התוכנה: כרטיס מצב, שתי הגרסאות, ו"מה חדש" בדף', (
    tester,
  ) async {
    final p = stringsOf().pages;
    otzaria.status = OtzariaModuleStatus.updateAvailable;
    otzaria.currentVersion = '0.9.95';
    otzaria.latestVersion = '0.9.96';
    await pumpScreen(tester, otzariaPage());

    expect(find.text(stringsOf().guide.tileApp), findsOneWidget);
    expect(find.text(p.chipUpdateOnDrive), findsOneWidget);
    expect(find.text(p.onThisComputer), findsOneWidget);
    expect(find.text('0.9.95'), findsOneWidget);
    expect(find.text('0.9.96'), findsOneWidget);
    // בלי הערות לגרסה — אין כותרת "מה חדש" ריקה.
    expect(find.text(p.appWhatsNew('0.9.96')), findsNothing);
    // פעולה ראשית אחת — העדכון; "פתח את אוצריא" משנית.
    expect(
      tester.widget<ActionButton>(find.byKey(ShellKeys.statusPrimary)).text,
      p.appUpdateButton('0.9.96'),
    );
    // בלי שתי גרסאות בכונן אין מה לבחור, ולכן אין פקד ערוץ.
    await openAdvanced(tester);
    expect(find.text(p.appChannelTitle), findsNothing);
  });

  testWidgets('מעודכנת — "פתח את אוצריא" ראשי, והתקנה מחדש במתקדם', (
    tester,
  ) async {
    final p = stringsOf().pages;
    otzaria.status = OtzariaModuleStatus.upToDate;
    otzaria.currentVersion = '0.9.96';
    otzaria.latestVersion = '0.9.96';
    var reinstalls = 0;
    await pumpScreen(tester, otzariaPage(onReinstall: () => reinstalls++));

    expect(find.text(p.chipUpToDate), findsOneWidget);
    expect(
      tester.widget<ActionButton>(find.byKey(ShellKeys.statusPrimary)).text,
      stringsOf().guide.launchButton,
    );
    await openAdvanced(tester);
    // אותה גרסה — נאמר שזו התקנה חוזרת, לא "עדכון מ-0.9.96 ל-0.9.96".
    expect(find.text(p.appReinstallBody('0.9.96')), findsOneWidget);
    final button = find.descendant(
      of: find.byKey(ShellKeys.appReinstall),
      matching: find.byType(ActionButton),
    );
    expect(tester.widget<ActionButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    expect(reinstalls, 1);
  });

  testWidgets('המחשב מעודכן יותר מהכונן — מצב רגוע, בלי שום התקנה', (
    tester,
  ) async {
    final p = stringsOf().pages;
    otzaria.status = OtzariaModuleStatus.installedIsNewer;
    otzaria.currentVersion = '0.9.97';
    otzaria.latestVersion = '0.9.96';
    var installs = 0;
    await pumpScreen(
      tester,
      otzariaPage(
          onUpdateHere: () => installs++, onReinstall: () => installs++),
    );

    expect(find.text(stringsOf().guide.chipNewerHere), findsOneWidget);
    expect(find.text('0.9.97'), findsOneWidget);
    // הפעולה היחידה בכרטיס — פתיחת אוצריא.
    expect(
      tester.widget<ActionButton>(find.byKey(ShellKeys.statusPrimary)).text,
      stringsOf().guide.launchButton,
    );
    expect(find.textContaining('0.9.96 ', findRichText: true), findsNothing);
    expect(find.text(p.appWhatsNew('0.9.96')), findsNothing);

    await openAdvanced(tester);
    expect(find.text(p.appReinstallUnavailable), findsOneWidget);
    for (final button in tester.widgetList<ActionButton>(
      find.byType(ActionButton),
    )) {
      if (button.text == stringsOf().appScreen.reinstallButton) {
        expect(button.onPressed, isNull);
      }
    }
    expect(installs, 0);
  });

  testWidgets('לא מותקנת ואין בכונן — אין כפתור התקנה, ויש הסבר', (
    tester,
  ) async {
    final p = stringsOf().pages;
    otzaria.status = OtzariaModuleStatus.needsDownload;
    await pumpScreen(tester, otzariaPage(onUpdateHere: () {}));

    expect(find.text(p.libNotInstalled), findsOneWidget);
    expect(find.text(stringsOf().guide.chipNotOnDrive), findsOneWidget);
    expect(find.byKey(ShellKeys.statusPrimary), findsNothing);
    expect(find.text(p.appInstallButton), findsNothing);
    expect(find.text(p.appNeedsDownloadNote), findsOneWidget);
  });

  testWidgets('מעודכנת, וברשת יש חדש — "יש עדכון להוריד לכונן" כמו האריח בבית',
      (
    tester,
  ) async {
    otzaria
      ..currentVersion = '0.9.95'
      ..status = OtzariaModuleStatus.upToDate
      ..onlineChannels = const OtzariaChannelReleases(
        stable: OtzariaRelease(
          tagName: '0.9.96+736',
          name: 'אוצריא 0.9.96',
          isPrerelease: false,
          isDraft: false,
          publishedAt: null,
          installerKind: OtzariaInstallerKind.windowsSetupExe,
          installerAssetName: 'setup.exe',
          installerDownloadUrl: 'https://example.invalid/setup.exe',
          installerSizeBytes: 1,
        ),
      );
    expect(otzaria.hasOnlineUpdate, isTrue);
    await pumpScreen(tester, otzariaPage(onUpdateHere: () {}));
    expect(find.text(stringsOf().guide.chipNewOnline), findsOneWidget);
    expect(find.text(stringsOf().pages.chipUpToDate), findsNothing);
    // הדף אומר גם מה זמין להורדה, לא רק מה במחשב ובכונן.
    expect(find.text(stringsOf().pages.onlineAvailable), findsOneWidget);
    expect(find.text('0.9.96'), findsOneWidget);
  });

  testWidgets('בלי בדיקה ברשת אין שורת "זמין להורדה"', (tester) async {
    otzaria
      ..currentVersion = '0.9.95'
      ..status = OtzariaModuleStatus.upToDate;
    await pumpScreen(tester, otzariaPage());
    expect(find.text(stringsOf().pages.onlineAvailable), findsNothing);
  });

  testWidgets('הספרייה: מה זמין להורדה אחרי בדיקה ברשת', (tester) async {
    final p = stringsOf().pages;
    library
      ..status = LibraryModuleStatus.upToDate
      ..localVersion = 30
      ..targetVersion = 30
      ..onlineLatestVersion = 31
      ..onlineCheckedAt = DateTime(2026, 10, 25);
    await pumpScreen(tester, libraryPage());
    expect(find.text(p.onlineAvailable), findsOneWidget);
    expect(find.text(p.libVersion(31)), findsOneWidget);

    library.onlineLatestVersion = 30;
    await pumpScreen(tester, libraryPage());
    expect(find.text(p.nothingNewOnline), findsOneWidget);
  });

  testWidgets('לא מותקנת ויש בכונן — "התקנת אוצריא" מוסר למשימה', (
    tester,
  ) async {
    otzaria.status = OtzariaModuleStatus.updateAvailable;
    otzaria.latestVersion = '0.9.96';
    var installs = 0;
    await pumpScreen(tester, otzariaPage(onUpdateHere: () => installs++));

    expect(find.text(stringsOf().pages.appInstallButton), findsOneWidget);
    expect(find.text(stringsOf().guide.launchButton), findsNothing);
    await tester.tap(find.byKey(ShellKeys.statusPrimary));
    expect(installs, 1);
  });

  testWidgets('בחירת ערוץ מוצגת רק כשיש שתי גרסאות, ונשמרת בהגדרות', (
    tester,
  ) async {
    // מדמה מראה עם שתי גרסאות — בלי לגעת בדיסק או ברשת.
    otzaria.hasChannelChoice = true;
    otzaria.stableVersion = '0.9.90';
    otzaria.prereleaseVersion = '0.9.97';
    otzaria.latestVersion = '0.9.90';
    // מצב קבוע — "בודק" מסתובב ולא נותן ל-pumpAndSettle להסתיים.
    otzaria.status = OtzariaModuleStatus.upToDate;

    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
      ),
    );
    await openAdvanced(tester);

    expect(find.text(stringsOf().pages.appChannelTitle), findsOneWidget);
    // הגרסה מבודדת LTR, כדי ש-beta לא תתהפך בעברית.
    expect(find.textContaining('0.9.90\u2069 (יציבה)'), findsOneWidget);

    await tester.tap(find.text(stringsOf().appScreen.channelPrerelease));
    await tester.pumpAndSettle();

    expect(settings.settings.preferAppPrerelease, isTrue);
  });

  testWidgets('בורר הערוץ נעול במצב סייפר — הוא ההגדרה היחידה שמחוץ למסך', (
    tester,
  ) async {
    otzaria.hasChannelChoice = true;
    otzaria.stableVersion = '0.9.90';
    otzaria.prereleaseVersion = '0.9.97';
    otzaria.latestVersion = '0.9.90';
    otzaria.status = OtzariaModuleStatus.upToDate;
    await tester.runAsync(
      () => settings.update(
        AppSettings(
          saferModeEnabled: true,
          saferModePassword: SaferModePassword.encode('1234'),
        ),
      ),
    );

    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        saferMode: SaferModeGate(settings),
      ),
    );
    await openAdvanced(tester);

    // השבב אומר שזה נעול, והבחירה עצמה מבקשת סיסמה.
    expect(find.text(stringsOf().pages.lockedChip), findsOneWidget);
    await tester.tap(find.text(stringsOf().appScreen.channelPrerelease));
    await tester.pumpAndSettle();

    expect(find.text(stringsOf().saferMode.verifyTitle), findsOneWidget);
    expect(settings.settings.preferAppPrerelease, isFalse);
  });

  testWidgets('בורר הערוץ נעול בזמן התקנה', (tester) async {
    final t = stringsOf().appScreen;
    otzaria.hasChannelChoice = true;
    otzaria.stableVersion = '0.9.90';
    otzaria.prereleaseVersion = '0.9.97';
    otzaria.latestVersion = '0.9.90';
    otzaria.status = OtzariaModuleStatus.installing;

    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
      ),
    );
    await openAdvanced(tester);

    final selector = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(selector.onSelectionChanged, isNull);

    await tester.tap(find.text(t.channelPrerelease), warnIfMissed: false);
    await tester.pump();

    expect(settings.settings.preferAppPrerelease, isFalse);
  });

  testWidgets('בחירת מיקום ידנית לאוצריא לא מושבתת בגלל הורדה של רכיב אחר', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
      ),
    );
    await openAdvanced(tester);

    final button = tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, 'בחירת מיקום ידנית'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('בחירת רכיבי ההורדה היא שורת שבבים אחת, והיא נשמרת', (
    tester,
  ) async {
    final t = stringsOf().settings;
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );

    // שלושה שבבים, אחד לכל רכיב — בלי "הכול".
    final chips = tester
        .widgetList<StoreFilterChip>(find.byType(StoreFilterChip))
        .map((c) => c.label)
        .toList();
    expect(chips, [t.syncTargetApp, t.syncTargetLibrary, t.syncTargetPlugins]);

    expect(settings.settings.syncLibrary, isTrue);
    await tester.tap(find.text(t.syncTargetLibrary));
    await tester.pumpAndSettle();
    expect(settings.settings.syncLibrary, isFalse);
    // השאר לא זזו.
    expect(settings.settings.syncApp, isTrue);
    expect(settings.settings.syncPlugins, isTrue);

    // בחירה ריקה מותרת — היא רק מכבה את כפתור ההורדה.
    await tester.tap(find.text(t.syncTargetApp));
    await tester.tap(find.text(t.syncTargetPlugins));
    await tester.pumpAndSettle();
    expect(settings.settings.hasSyncSelection, isFalse);

    await tester.tap(find.text(t.syncTargetLibrary));
    await tester.pumpAndSettle();
    expect(settings.settings.syncLibrary, isTrue);
    expect(settings.settings.hasSyncSelection, isTrue);
  });

  testWidgets('עדכון אישי נועל את "ספרייה" במצב דלוק', (tester) async {
    final t = stringsOf().settings;
    await tester.runAsync(
      () => settings.update(
        const AppSettings(syncLibrary: false, personalUpdateMode: true),
      ),
    );
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );

    expect(find.textContaining(t.syncLibraryLockedSubtitle), findsOneWidget);
    final chips = tester
        .widgetList<StoreFilterChip>(find.byType(StoreFilterChip))
        .toList();
    final library = chips.singleWhere((c) => c.locked);
    expect(library.label, t.syncTargetLibrary);
    expect(library.selected, isTrue);
    expect(chips, hasLength(3));
    expect(chips.where((c) => c.selected), hasLength(3));

    // הסבר צף על השבב הנעול, כמו `title` במוקאפ.
    expect(
      find.ancestor(
        of: find.text(t.syncTargetLibrary),
        matching: find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == t.syncLibraryLockedSubtitle,
        ),
      ),
      findsOneWidget,
    );

    // לחיצה על השבב הנעול אינה משנה דבר.
    await tester.tap(find.text(t.syncTargetLibrary), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(settings.settings.syncLibrary, isFalse);

    // השניים האחרים עדיין נלחצים, בלי לגעת בבחירה השמורה של הספרייה.
    await tester.tap(find.text(t.syncTargetApp));
    await tester.pumpAndSettle();
    expect(settings.settings.syncApp, isFalse);
    expect(settings.settings.syncLibrary, isFalse);
    expect(settings.settings.hasSyncSelection, isTrue);
  });

  testWidgets('דף הספרייה: כרטיס מצב, ובמתקדם התיקייה שממנה מעדכנים', (
    tester,
  ) async {
    final p = stringsOf().pages;
    fakeLibraryUpdateAvailable();
    var tasks = 0;
    await pumpScreen(tester, libraryPage(onUpdateHere: () => tasks++));

    expect(find.text(stringsOf().guide.tileLibrary), findsOneWidget);
    expect(find.text(p.chipUpdateOnDrive), findsOneWidget);
    expect(find.text(p.libVersion(1)), findsOneWidget);
    expect(find.text(p.libVersion(2)), findsOneWidget);
    await tester.tap(find.byKey(ShellKeys.statusPrimary));
    expect(tasks, 1);

    expect(find.text(p.libSourceTitle), findsNothing);
    await openAdvanced(tester);
    expect(find.text(p.libSourceTitle), findsOneWidget);
    // אין בחירת מקור — התיקייה קבועה ליד התוכנה.
    expect(find.text('עדכון מתיקייה מקומית'), findsNothing);
  });

  testWidgets('"מה חדש בספרייה" לפני ההתקנה ואחריה, והדיאלוג מציג את הרשימה', (
    tester,
  ) async {
    final t = stringsOf().libraryScreen;
    final file = File('${tempDir.path}/v33-1.md')
      ..writeAsStringSync('# גרסה 33\n\n* ספר חדש מאוד');
    library
      ..status = LibraryModuleStatus.updateAvailable
      ..changesNotes = [
        LibraryChangesNote(releaseTag: 'v33-1', path: file.path),
      ]
      ..changesNotesVersion = 33;
    Widget screen() => LibraryScreen(
          library: library,
          otzariaIsRunning: false,
          onCloseOtzaria: () async => true,
          isDownloading: false,
          onProcessStateChanged: () async => false,
          onRequestReindex: () async {},
          onGoToSettings: () {},
        );

    await pumpScreen(tester, screen());
    expect(find.text(t.changesTitle), findsOneWidget);
    expect(find.text(t.changesPendingSubtitle('33')), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ActionButton, t.changesButton));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('ספר חדש מאוד', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text(stringsOf().common.close));
    await tester.pumpAndSettle();

    library.changesNotesApplied = true;
    await pumpScreen(tester, screen());
    expect(find.text(t.changesAppliedSubtitle('33')), findsOneWidget);

    library.changesNotesRange = 5;
    await pumpScreen(tester, screen());
    expect(find.textContaining(t.changesPartial(1, 5)), findsOneWidget);

    library.changesNotes = const [];
    await pumpScreen(tester, screen());
    expect(find.text(t.changesTitle), findsNothing);
  });

  // המחשב המקוון בעדכון אישי: הסבר במקום ההודעה האדומה, ושתי הדרכים החוצה.
  testWidgets('מראה שנבנתה למחשב אחר מוסברת, בלי שורת שגיאה', (tester) async {
    final t = stringsOf().libraryScreen;
    var wentToSettings = 0;
    library.status = LibraryModuleStatus.personalTargetElsewhere;
    library.personalFromVersion = 741;

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () => wentToSettings++,
      ),
    );

    expect(find.text(t.personalOtherMachineTitle), findsOneWidget);
    expect(find.text(t.personalOtherMachineSubtitle('741')), findsOneWidget);
    expect(find.byType(InfoErrorRow), findsNothing);

    await tester.tap(
      find.widgetWithText(ActionButton, t.personalOtherMachineSettingsButton),
    );
    await tester.pumpAndSettle();
    expect(wentToSettings, 1);
  });

  // לפני התיקון ההתקנה הטרייה נחתה בתיקיית הלאנצ'ר בלי שאיש ראה זאת מראש.
  testWidgets('בלי מסד — מוצג המיקום שבו תותקן, ואפשר לשנות אותו', (
    tester,
  ) async {
    library.installTargetPath = r'C:\otzaria\books\seforim.db';

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
      ),
    );
    await openAdvanced(tester);

    // אותה כותרת תמיד; הנתיב הוא היעד שאליו תותקן הספרייה.
    expect(find.text(stringsOf().pages.libLocationTitle), findsOneWidget);
    expect(find.text(stringsOf().pages.libLocationNone), findsNothing);
    expect(
      find.widgetWithText(ActionButton, 'בחירת תיקייה'),
      findsOneWidget,
    );
  });

  testWidgets('כשיש מסד — אין יותר בחירת מיקום להתקנה', (tester) async {
    library.dbPath = r'C:\otzaria\books\seforim.db';

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
      ),
    );
    await openAdvanced(tester);

    expect(find.text(stringsOf().pages.libLocationTitle), findsOneWidget);
    expect(
      find.widgetWithText(ActionButton, 'בחירת תיקייה'),
      findsNothing,
    );
  });

  // עדכון מסד שנעשה מכאן משאיר את אינדקס החיפוש של אוצריא על התוכן הישן,
  // והבקשה לתקן זאת חייבת להיות נגישה גם אחרי שהמשתמש דחה אותה פעם אחת.
  testWidgets('אריח בקשת עדכון האינדקס מופיע רק כשיש בקשה ממתינה', (
    tester,
  ) async {
    final t = stringsOf().libraryScreen;
    var requests = 0;

    Future<void> pumpLibrary() => pumpScreen(
          tester,
          LibraryScreen(
            library: library,
            otzariaIsRunning: false,
            onCloseOtzaria: () async => true,
            isDownloading: false,
            onProcessStateChanged: () async => false,
            onRequestReindex: () async => requests++,
            onGoToSettings: () {},
          ),
        );

    await pumpLibrary();
    await openAdvanced(tester);
    expect(find.text(t.reindexTitle), findsNothing);

    // כמו אחרי עדכון מסד מוצלח: הסימון נקרא בבדיקה ויושב בקונטרולר.
    library.pendingReindex = const ExternalUpdateNoticeData(
      route: ExternalUpdateNotice.routeDelta,
      booksTouched: {3, 9},
      dbVersion: 42,
    );
    await pumpLibrary();
    await openAdvanced(tester);

    expect(find.text(t.reindexTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionButton, t.reindexButton));
    await tester.pump();

    // הדיאלוג והמסירה עצמה יושבים ב-`AppShell` — כאן נבדק שהאריח קורא לו.
    expect(requests, 1);
  });

  testWidgets('"בדוק שוב" במסך הספרייה מרענן גם את מצב התהליך', (tester) async {
    // האזהרה "אוצריא פתוחה" יושבת באותו כרטיס, ולכן הכפתור שמתחתיה חייב
    // לרענן גם אותה ולא רק את גרסת המסד.
    var checks = 0;
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: true,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async {
          checks++;
          return false;
        },
        onRequestReindex: () async {},
        onGoToSettings: () {},
      ),
    );

    // בלי pumpAndSettle: בדיקת הספרייה שאחריה קוראת מהדיסק ואינה מסתיימת
    // בתוך ה-fake-async. ה-pump הארוך רק מנקז את סיבוב-המינימום של הכפתור.
    await tester.tap(find.widgetWithText(ActionButton, 'בדוק שוב'));
    await tester.pump();

    expect(checks, 1);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('מסך החנות מציג מצב ריק אמיתי כשהמראה עוד ריקה', (tester) async {
    // הטעינה נעשית ב-runAsync: קריאות דיסק אמיתיות לא מסתיימות בתוך
    // ה-fake-async של testWidgets. באפליקציה עצמה AppShell קורא ל-load().
    await tester.runAsync(plugins.load);
    plugins.installed = const {};
    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    final t = stringsOf().plugins;
    expect(find.text(t.emptyTitle), findsOneWidget);
    expect(find.text(t.emptyBodyOnline), findsOneWidget);
    // "רענון" אחד — הפעולה של המצב הריק, לא גם בראש הדף.
    expect(find.text(t.refreshButton), findsOneWidget);
    expect(find.byKey(ShellKeys.storeEmptyReload), findsNothing);
    // מראה ריקה — לא מציגים חיפוש וסינון על כלום.
    expect(find.text(t.searchHint), findsNothing);
    expect(find.text(t.filterInstalled), findsNothing);
  });

  testWidgets('בלי אינטרנט אין "רענון", והמצב הריק אומר מאיפה מביאים', (
    tester,
  ) async {
    await tester.runAsync(plugins.load);
    plugins.installed = const {};
    await pumpScreen(tester, PluginsScreen(controller: plugins, online: false));
    await tester.pumpAndSettle();

    final t = stringsOf().plugins;
    expect(find.text(t.refreshButton), findsNothing);
    expect(find.text(t.emptyBodyOffline), findsOneWidget);
    // בלי אינטרנט עדיין אפשר לטעון מחדש את מה שבכונן.
    expect(find.byKey(ShellKeys.storeEmptyReload), findsOneWidget);
  });

  testWidgets('מסך החנות מציג כרטיס תוסף מהקטלוג המקומי', (tester) async {
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(
      () => store.save(
        PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            StorePlugin.fromApi(const {
              'id': 'abc',
              'name': 'תוסף לבדיקה',
              'shortDescription': 'תקציר קצר',
              'description': 'תיאור מלא',
              'version': '1.2.3',
              'status': 'stable',
              'author': 'מחבר',
              'originalDate': '2026-04-02',
              'tags': ['לימוד'],
              'supportsDirectInstall': true,
              'downloadUrl': '/api/plugins/abc/download',
            }, 'https://otzaria.org'),
          ],
        ),
      ),
    );

    await tester.runAsync(plugins.load);
    // הסריקה שב-load קוראת מההתקנה האמיתית של אוצריא במחשב הזה; הבדיקה
    // אינה נשענת עליה, ולכן המפה מאופסת מיד.
    plugins.installed = const {};
    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    final t = stringsOf().plugins;
    expect(find.text(t.storeTitle), findsOneWidget);
    expect(find.textContaining(t.storeSubtitle), findsOneWidget);
    expect(find.text('תוסף לבדיקה'), findsOneWidget);
    expect(find.text('תקציר קצר'), findsOneWidget);
    expect(find.text(t.pluginVersionBadge('1.2.3')), findsOneWidget);
    // "יציב" אינו מוצג בכרטיס — רק בטא וניסיוני, כמו באתר.
    expect(find.text(t.statusStable), findsNothing);
    expect(find.text(t.searchHint), findsOneWidget);
    expect(find.text(t.installInOtzariaButton), findsOneWidget);
  });

  testWidgets('כרטיס עמוס בכרטיס הצר ביותר אינו גולש — בכל הגדלה ובשתי השפות', (
    tester,
  ) async {
    // המקרה הגרוע: שם ארוך, תקציר ארוך, מונה הורדות בן שש ספרות, דירוג,
    // שבבי "ניסיוני" ו"חדש", ו"עדכון ל-<גרסה ארוכה>" עם הערת קובץ חסר.
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(
      () => store.save(
        PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            for (var i = 0; i < 5; i++)
              StorePlugin.fromApi({
                'id': 'p$i',
                'name': 'שם ארוך במיוחד לתוסף שנועד לתפוס שתי שורות שלמות',
                'shortDescription':
                    'תקציר ארוך שנמשך על פני כמה שורות כדי לבדוק שהכרטיס '
                        'אינו גולש גם כשהטקסט מגיע למקסימום השורות המותר בו',
                'version': '10.20.30',
                'status': 'experimental',
                'downloadCount': 123456,
                'ratingAvg': 4.5,
                'ratingCount': 128,
                'requiresNetwork': true,
                'tags': const [
                  'תגית ארוכה למדי',
                  'עוד תגית',
                  'שלישית',
                  'רביעית',
                ],
                'supportsDirectInstall': true,
              }, 'https://otzaria.org')
                  // התוסף האחרון נשאר בלי manifestId: קובץ שטרם הורד מדווח
                  // PluginInstallStatus.unknown, וזה מצב תקין ולא שגיאה.
                  .copyWith(manifestId: i == 4 ? null : 'id-$i'),
          ],
        ),
      ),
    );

    await tester.runAsync(plugins.load);
    // גרסאות מותקנות ישנות — כדי שהכפתור הארוך ביותר ("עדכון ל-...") ייבנה.
    plugins.installed = {for (var i = 0; i < 4; i++) 'id-$i': '1.0.0'};

    // 584 = שורות צרות, 760 = שורות רחבות, 840 = שני כרטיסים צרים,
    // 1160 = שניים ברוחב המרבי. כל ההגדלות שהמשתמש יכול לבחור
    // (0.9/1.0/1.15), ומעליהן 1.3 ו-1.5 מהגדלת המערכת.
    final cases = <({double width, AppLanguage language, double scale})>[
      for (final width in [584.0, 760.0, 840.0, 1160.0])
        for (final language in AppLanguage.values)
          for (final scale in [0.9, 1.0, 1.15, 1.3, 1.5])
            (width: width, language: language, scale: scale),
    ];

    for (final c in cases) {
      final t = stringsOf(c.language).plugins;
      useViewSize(tester, Size(c.width, 2400));
      AppL10n.use(c.language);
      addTearDown(() => AppL10n.use(AppLanguage.hebrew));

      // עץ נקי בין שילוב לשילוב: `RenderFlex` מדווח על גלישה **פעם אחת**
      // לכל render object, ובלי איפוס שילוב גולש היה נבלע בשקט.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        wrap(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(c.scale)),
            child: PluginsScreen(controller: plugins),
          ),
          language: c.language,
        ),
      );
      await tester.pumpAndSettle();

      // הכפתור הארוך אכן מוצג — אחרת הבדיקה לא בודקת את המקרה הגרוע.
      expect(
        find.text(t.updateToButton('10.20.30')),
        findsWidgets,
        reason: 'כפתור העדכון חסר ב-$c',
      );
      // גלישת RenderFlex נזרקת כחריג; אין צורך ב-expect נוסף.
      expect(tester.takeException(), isNull, reason: 'הכרטיס גלש ב-$c');
    }
  });

  testWidgets('בורר "הכול / מותקנים / לא מותקנים" מצמצם את הרשת', (
    tester,
  ) async {
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(
      () => store.save(
        PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            StorePlugin.fromApi(const {
              'id': 'a',
              'name': 'תוסף שכבר מותקן',
              'version': '1.0.0',
              'status': 'stable',
            }, 'https://otzaria.org')
                .copyWith(manifestId: 'id-a'),
            StorePlugin.fromApi(const {
              'id': 'b',
              'name': 'תוסף שאינו מותקן',
              'version': '1.0.0',
              'status': 'stable',
            }, 'https://otzaria.org'),
          ],
        ),
      ),
    );

    await tester.runAsync(plugins.load);
    plugins.installed = {'id-a': '1.0.0'};

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    final t = stringsOf().plugins;
    // ברירת המחדל "הכול" — גם המותקן מוצג, עם "מותקן ✓".
    expect(find.text('תוסף שכבר מותקן'), findsOneWidget);
    expect(find.text('תוסף שאינו מותקן'), findsOneWidget);
    expect(find.text(t.installedLabel), findsOneWidget);

    await tester.tap(find.text(t.filterNotInstalled));
    await tester.pumpAndSettle();
    expect(find.text('תוסף שכבר מותקן'), findsNothing);
    expect(find.text('תוסף שאינו מותקן'), findsOneWidget);

    await tester.tap(find.text(t.filterInstalled));
    await tester.pumpAndSettle();
    expect(find.text('תוסף שכבר מותקן'), findsOneWidget);
    expect(find.text('תוסף שאינו מותקן'), findsNothing);
  });

  testWidgets('הרשת בשתי עמודות בחלון רחב, ובעמודה אחת בחלון צר', (
    tester,
  ) async {
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(
      () => store.save(
        PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            for (var i = 0; i < 6; i++)
              StorePlugin.fromApi({
                'id': 'p$i',
                'name': 'תוסף מספר $i',
                'shortDescription': 'תקציר',
                'status': 'stable',
                'supportsDirectInstall': true,
              }, 'https://otzaria.org'),
          ],
        ),
      ),
    );
    await tester.runAsync(plugins.load);
    plugins.installed = const {};

    int perRow() {
      final cards = find.byType(PluginStoreCard);
      final top = tester.getTopLeft(cards.first).dy;
      return [
        for (var i = 0; i < tester.widgetList(cards).length; i++)
          if (tester.getTopLeft(cards.at(i)).dy == top) i,
      ].length;
    }

    // רוחב התוכן 952 — מעל נקודת השבירה (772) של המוקאפ.
    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      size: const Size(1000, 1200),
    );
    await tester.pumpAndSettle();
    expect(perRow(), 2);

    await pumpScreen(
      tester,
      PluginsScreen(controller: plugins),
      size: const Size(760, 1200),
    );
    await tester.pumpAndSettle();
    expect(perRow(), 1);
  });

  testWidgets('שבב קטגוריה מסנן את הרשת, ו"הכול" מחזיר', (tester) async {
    StorePlugin plugin(String id, String name) => StorePlugin.fromApi({
          'id': id,
          'name': name,
          'status': 'stable',
        }, 'https://otzaria.org');

    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(
      () => store.save(
        PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [plugin('a', 'תוסף בקטגוריה'), plugin('b', 'תוסף אחר')],
          categories: const [
            PluginStoreCategory(
              slug: 'study',
              name: 'כלי לימוד',
              description: 'תוספים שמסייעים בלימוד',
              pluginIds: ['a'],
            ),
            // קטגוריה ריקה אינה מקבלת שבב.
            PluginStoreCategory(slug: 'empty', name: 'קטגוריה ריקה'),
          ],
        ),
      ),
    );

    await tester.runAsync(plugins.load);
    plugins.installed = const {};
    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    final t = stringsOf().plugins;
    expect(
        find.widgetWithText(StoreCategoryChip, 'קטגוריה ריקה'), findsNothing);

    await tester.tap(find.widgetWithText(StoreCategoryChip, 'כלי לימוד'));
    await tester.pumpAndSettle();
    expect(find.text('תוסף בקטגוריה'), findsOneWidget);
    expect(find.text('תוסף אחר'), findsNothing);

    await tester.tap(find.widgetWithText(StoreCategoryChip, t.filterAll));
    await tester.pumpAndSettle();
    expect(find.text('תוסף אחר'), findsOneWidget);
  });

  testWidgets('מסך ההגדרות מציג את קבוצות ההגדרה, ומתקדם מקופל', (
    tester,
  ) async {
    final t = stringsOf().settings;
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );

    expect(find.text(t.groupGeneral), findsOneWidget);
    expect(find.text(stringsOf().pages.advancedTitle), findsOneWidget);
    expect(find.text(t.advancedSummary), findsOneWidget);
    expect(find.text(t.groupAbout), findsOneWidget);
    // בלי קונטרולרים — בלי הקבוצות שתלויות בהם.
    expect(find.text(t.groupPrivacy), findsNothing);
    // הסדר: כללי, מתקדם, אודות.
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top(t.groupGeneral), lessThan(top(t.languageTitle)));
    expect(top(t.languageTitle), lessThan(top(t.autoCheckTitle)));
    expect(top(t.syncTargetsTitle),
        lessThan(top(stringsOf().pages.advancedTitle)));
    expect(top(stringsOf().pages.advancedTitle), lessThan(top(t.groupAbout)));
    expect(find.text(t.aboutTitle(launcherVersion)), findsOneWidget);
    // מתקדם מקופל: הנעילה, העדכון למחשב מסוים, היומן והאיפוס אינם שם.
    expect(find.text(stringsOf().saferMode.lockTitle), findsNothing);
    expect(find.text(t.personalModeTitle), findsNothing);
    expect(find.text(t.resetTitle), findsNothing);

    await openAdvanced(tester);
    await tester.pumpAndSettle();
    expect(find.text(stringsOf().saferMode.lockTitle), findsOneWidget);
    expect(find.text(t.personalModeTitle), findsOneWidget);
    expect(find.text(t.logTitle), findsOneWidget);
    expect(find.text(t.resetTitle), findsOneWidget);

    // ההגדרה "timeout להורדה" הוסרה — הזמן הקצוב נקבע בלקוחות עצמם.
    expect(find.text('רשת'), findsNothing);
    expect(find.text('timeout להורדה'), findsNothing);
    // אין יותר הגדרות נתיבים — התיקייה צמודה לתוכנה ואינה ניתנת לשינוי.
    expect(find.text('נתיבים ואחסון'), findsNothing);
    expect(find.text('בחירת תיקייה'), findsNothing);
    // גיבוי המסד בוטל לגמרי — אין כרטיס אחסון ואין מה לכבות/להדליק.
    expect(find.text('אחסון'), findsNothing);
    expect(find.text('גיבוי בטיחות של המסד'), findsNothing);
    // הערוץ רק בדף התוכנה, ואין מראה (ערכת נושא, צבע) ואין "הצג שאלות".
    expect(find.text(stringsOf().appScreen.channelStable), findsNothing);
    expect(find.text(stringsOf().appScreen.channelPrerelease), findsNothing);
    expect(find.text('ערוצי גרסאות'), findsNothing);
    expect(find.text('התקנת תוספים אוטומטית'), findsNothing);
    expect(find.byType(SegmentedButton<Object?>), findsNothing);
  });

  testWidgets('אודות היא שורה אחת — בלי שורת "יומן שינויים" נוספת', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: '3.3.0-beta',
      ),
    );

    final t = stringsOf().settings;
    expect(find.text(stringsOf().launcherUpdate.changelogButton), findsNothing);
    // הגרסה עטופה בבידוד כיוון, כדי ש-"3.3.0-beta" לא תתהפך בכותרת עברית.
    expect(t.aboutTitle('3.3.0-beta'), contains('\u20663.3.0-beta\u2069'));
    expect(find.text(t.aboutTitle('3.3.0-beta')), findsOneWidget);
  });

  testWidgets('אודות פותח את דף הכלי, ומתקדם פותח את עריכת השאלות', (
    tester,
  ) async {
    var launcherPage = 0;
    var faqEdit = 0;
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
        onOpenLauncherUpdate: () => launcherPage++,
        onEditFaq: () => faqEdit++,
      ),
    );

    final t = stringsOf().settings;
    expect(find.text(t.aboutTitle(launcherVersion)), findsOneWidget);
    // בלי מצב עדכון ידוע — הפירוט הכללי, ולא "יש גרסה חדשה".
    expect(find.text(t.aboutSubtitle), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('settings.about')));
    await tester.tap(find.byKey(const ValueKey('settings.about')));
    expect(launcherPage, 1);

    await openAdvanced(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('settings.faqEdit')));
    await tester.tap(find.byKey(const ValueKey('settings.faqEdit')));
    expect(faqEdit, 1);
  });

  testWidgets('עדכון למחשב מסוים פעיל — קישור לרישום המחשב בדף הספרייה', (
    tester,
  ) async {
    var library = 0;
    await tester.runAsync(
      () => settings.update(const AppSettings(personalUpdateMode: true)),
    );
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
        onOpenLibrary: () => library++,
      ),
    );
    await openAdvanced(tester);
    await tester.pumpAndSettle();

    final link = find.text(stringsOf().settings.personalModeRegisterLink);
    await tester.ensureVisible(link);
    await tester.tap(link);
    expect(library, 1);
    // הלחיצה על הקישור אינה מכבה את המצב.
    expect(settings.settings.personalUpdateMode, isTrue);
  });

  testWidgets('מסך ההגדרות באנגלית — הכול מתורגם והכיוון מתהפך', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
      language: AppLanguage.english,
    );

    // מול מלל ה-l10n עצמו ולא מול מחרוזות קבועות: ליטוש נוסח באנגלית הוא
    // שינוי לגיטימי, וכשהוא הפיל את הבדיקה הזאת הוא הפיל איתה את כל ה-CI.
    // מה שנבדק כאן הוא שהמסך אכן מתורגם ומתהפך, לא איך בדיוק הוא מנוסח.
    const en = EnglishStrings();
    expect(find.text(en.settings.groupGeneral), findsOneWidget);
    expect(find.text(en.settings.groupAbout), findsOneWidget);
    expect(find.text(en.settings.languageTitle), findsOneWidget);
    expect(find.text(en.settings.autoCheckTitle), findsOneWidget);
    expect(find.text(en.settings.syncTargetsTitle), findsOneWidget);
    expect(
      find.text(const HebrewStrings().settings.groupGeneral),
      findsNothing,
    );

    final direction = Directionality.of(
      tester.element(find.text(en.settings.groupGeneral)),
    );
    expect(direction, TextDirection.ltr);
  });

  testWidgets('בחירת שפה נשמרת בהגדרות ומחליפה את המלל', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );

    final t = stringsOf().settings;
    // ברירת המחדל היא "כמו במחשב" — לפי שפת המחשב.
    expect(settings.settings.languagePreference, AppLanguagePreference.system);
    // הבורר פותח דו-שיח של כרטיסי אפשרות; בחירה סוגרת אותו.
    await tester.tap(find.text(t.languageSystem));
    await tester.pumpAndSettle();
    expect(find.byType(OptionCard), findsNWidgets(3));
    // בדו-שיח "כמו במחשב" אומר לאיזו שפה הוא מתורגם בפועל.
    final systemOption = t.languageSystemAs(
      AppLanguagePreference.system.resolve().isRtl
          ? t.languageHebrew
          : t.languageEnglish,
    );
    expect(find.text(systemOption), findsOneWidget);
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.byType(OptionCard), findsNothing);

    expect(settings.settings.languagePreference, AppLanguagePreference.english);
    expect(settings.settings.language, AppLanguage.english);
    // ה-scope כאן קבוע לעברית (הוא נבנה פעם אחת ב-`wrap`), ולכן הבדיקה
    // היא על ההגדרה עצמה ועל המצב הגלובלי שהיא מזליגה לחבילות התשתית.
    expect(AppL10n.language, AppLanguage.english);
    addTearDown(() => AppL10n.use(AppLanguage.hebrew));

    // וחזרה לאוטומטי — הבחירה המפורשת ניתנת לביטול.
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(systemOption));
    await tester.pumpAndSettle();

    expect(settings.settings.languagePreference, AppLanguagePreference.system);
  });

  testWidgets('הפעלת התקנה אוטומטית דורשת אישור באזהרה', (tester) async {
    final t = stringsOf().settings;
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );

    await tester.tap(find.text(t.autoInstallTitle));
    await tester.pumpAndSettle();

    expect(find.text(t.autoInstallDialogTitle), findsOneWidget);
    expect(find.text(t.autoInstallDialogContent), findsOneWidget);
    // אזהרה: הביטול הוא הכפתור המומלץ והממוקד, וההפעלה בצבע אזהרה. בלי
    // שורה אדומה נוספת — הגוף אחד, כמו במוקאפ.
    final cancel = find.widgetWithText(FilledButton, stringsOf().common.cancel);
    expect(cancel, findsOneWidget);
    expect(
        Focus.of(tester.element(find.text(stringsOf().common.cancel))).hasFocus,
        isTrue);
    expect(
      find.widgetWithText(TextButton, t.autoInstallDialogConfirm),
      findsOneWidget,
    );
    expect(find.textContaining('ההתקנה מחליפה קבצים'), findsNothing);

    // Enter אינו מפעיל: הוא לוחץ על הביטול הממוקד.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(t.autoInstallDialogTitle), findsNothing);
    expect(settings.settings.autoInstall, isFalse);

    await tester.tap(find.text(t.autoInstallTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.autoInstallDialogConfirm));
    await tester.pumpAndSettle();

    expect(settings.settings.autoInstall, isTrue);
  });

  // ── מסך השגיאה שמחליף את האפליקציה ────────────────────────────────────────

  testWidgets('מסך "התוכנה במקום הלא נכון" מוצג ואינו מציע דרך להמשיך', (
    tester,
  ) async {
    final t = stringsOf().setupError;
    const error = AppPathsException(
      message: 'Access is denied',
      attemptedDir: r'C:\Program Files\Otzaria\OtzariaData',
    );

    // בלי ההזרקה WindowCaption פונה לערוץ פלטפורמה שאינו קיים בבדיקות.
    await pumpScreen(
      tester,
      const SetupErrorScreen(error: error, showWindowButtons: false),
    );

    expect(find.text(t.title), findsOneWidget);
    expect(find.text(t.explanation), findsOneWidget);
    expect(find.text(t.whatToDo), findsOneWidget);
    expect(find.text(error.message), findsOneWidget);
    // `SettingsActionTile.path` משתיל LRM אחרי כל מפריד, ולכן ההשוואה על חלק.
    expect(find.textContaining('OtzariaData'), findsOneWidget);

    // הפעולה היחידה היא העתקת הנתיב — אין "המשך בכל זאת" ואין ניווט פנימה.
    final buttons = tester.widgetList<ActionButton>(find.byType(ActionButton));
    expect(buttons.length, 1);
    expect(
      find.widgetWithText(ActionButton, stringsOf().common.copyPathButton),
      findsOneWidget,
    );
  });

  testWidgets('מסך "הקבצים אינם תואמים" מציג את שתי הגרסאות ורק סגירה', (
    tester,
  ) async {
    final t = stringsOf().payloadMismatch;
    var closed = false;

    await pumpScreen(
      tester,
      PayloadMismatchScreen(
        mismatch: const PayloadMismatch(
          runningVersion: '0.1.8',
          stubVersion: '0.1.9',
        ),
        showWindowButtons: false,
        onClose: () => closed = true,
      ),
    );

    expect(find.text(t.title), findsOneWidget);
    expect(find.text(t.whatToDo), findsOneWidget);
    // שתי הגרסאות מוצגות — בלעדיהן אי אפשר לדעת מה נתקע במה.
    expect(find.textContaining('0.1.8'), findsOneWidget);
    expect(find.textContaining('0.1.9'), findsOneWidget);

    // אין "המשך בכל זאת": הרצה במצב הזה היא בדיוק מה שקורס.
    final buttons = tester.widgetList<ActionButton>(find.byType(ActionButton));
    expect(buttons.length, 1);
    await tester.tap(find.widgetWithText(ActionButton, t.closeButton));
    expect(closed, isTrue);
  });

  for (final (kind, title, message) in [
    (
      AppPathsFailure.driveFull,
      stringsOf().setupError.driveFullTitle,
      stringsOf().setupError.driveFull,
    ),
    (
      AppPathsFailure.appTranslocated,
      stringsOf().setupError.appTranslocatedTitle,
      stringsOf().setupError.appTranslocated,
    ),
    (
      AppPathsFailure.runningFromTemp,
      stringsOf().setupError.runningFromTempTitle,
      stringsOf().setupError.runningFromTemp,
    ),
  ]) {
    testWidgets('מסך השגיאה עבור ${kind.name}: כותרת והנחיה ייעודיות בלבד', (
      tester,
    ) async {
      final t = stringsOf().setupError;

      await pumpScreen(
        tester,
        SetupErrorScreen(
          error: AppPathsException(
            message: message,
            attemptedDir: '/Volumes/USB/OtzariaData',
            kind: kind,
          ),
          showWindowButtons: false,
        ),
      );

      expect(find.text(title), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.text(t.title), findsNothing);
      expect(find.text(t.explanation), findsNothing);
      expect(find.text(t.whatToDo), findsNothing);
      expect(find.byType(InfoErrorRow), findsNothing);
      expect(find.textContaining('OtzariaData'), findsOneWidget);
    });
  }

  testWidgets('מסך השגיאה מתורגם לאנגלית', (tester) async {
    final t = stringsOf(AppLanguage.english).setupError;

    await pumpScreen(
      tester,
      const SetupErrorScreen(
        error: AppPathsException(message: 'denied', attemptedDir: '/ro/data'),
        showWindowButtons: false,
      ),
      language: AppLanguage.english,
    );

    expect(find.text(t.title), findsOneWidget);
    expect(find.text(stringsOf().setupError.title), findsNothing);
  });

  // ── מסך התוכנה: ערוצים ────────────────────────────────────────────────────

  testWidgets('pre-release כגרסה היחידה מוצג בלי פקד בחירת ערוץ', (
    tester,
  ) async {
    // אין יציבה בעמוד הראשון של ה-API — רק ה-pre-release ירד למראה.
    final t = stringsOf().appScreen;
    otzaria.hasChannelChoice = false;
    otzaria.stableVersion = null;
    otzaria.prereleaseVersion = '0.9.99';
    otzaria.latestVersion = '0.9.99';

    await pumpScreen(tester, otzariaPage());

    expect(find.text(stringsOf().pages.onTheDrive), findsOneWidget);
    expect(find.text('0.9.99'), findsOneWidget);
    await openAdvanced(tester);
    // בלי שתי גרסאות אין מה לבחור, ולכן אין פקד ערוץ ואין זוג גרסאות.
    expect(find.text(stringsOf().pages.appChannelTitle), findsNothing);
    expect(find.text(t.channelStable), findsNothing);
    expect(find.text(t.channelPrerelease), findsNothing);
  });

  testWidgets('דף התוכנה באנגלית', (tester) async {
    final en = stringsOf(AppLanguage.english);

    await pumpScreen(tester, otzariaPage(), language: AppLanguage.english);

    expect(find.text(en.guide.tileApp), findsOneWidget);
    expect(find.text(en.pages.onThisComputer), findsOneWidget);
    expect(find.text(en.pages.advancedTitle), findsOneWidget);
    expect(find.text(stringsOf().guide.tileApp), findsNothing);
  });

  // שני המסכים עיצבו את "הורד לאחרונה" בעצמם דרך `DateTime.toString`, וכך
  // הוצג בעברית תאריך ISO בזמן ש"סונכרן ב־" שבחנות הוצג ב-dd.mm.yyyy.
  // תאריך בלבד, כמו בכרטיס — בלי "00:00:00".
  testWidgets('"הורד לאחרונה" בשני המסכים באותו פורמט של formatDate', (
    tester,
  ) async {
    final at = DateTime(2026, 8, 12, 9, 5, 7);
    final expected = '${stringsOf().common.lastDownloaded}: ${formatDate(at)}';
    expect(formatDate(at), isNot(contains('09:05')));

    otzaria.lastDownloadedAt = at;
    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
      ),
    );
    await openAdvanced(tester);
    expect(find.textContaining(expected), findsOneWidget);

    library.lastDownloadedAt = at;
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
      ),
    );
    await openAdvanced(tester);
    expect(find.textContaining(expected), findsOneWidget);
  });

  // ── מסך הספרייה: שגיאה והתקדמות ───────────────────────────────────────────

  testWidgets('מסך הספרייה מציג שגיאה עם ניסיון חוזר', (tester) async {
    library.status = LibraryModuleStatus.error;
    library.errorMessage = 'המראה המקומית פגומה';

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
      ),
    );
    await openAdvanced(tester);

    expect(find.byType(InfoErrorRow), findsOneWidget);
    expect(find.text('המראה המקומית פגומה'), findsOneWidget);
    expect(
      find.textContaining(stringsOf().libraryScreen.mirrorUnreadable),
      findsOneWidget,
    );
  });

  // A local DB that could not be read stopped the check before the mirror,
  // so the mirror row must not say the mirror is unreadable.
  testWidgets('a local-DB read error does not blame the mirror', (
    tester,
  ) async {
    final t = stringsOf().libraryScreen;
    library.status = LibraryModuleStatus.error;
    library.localDbUnreadable = true;
    library.errorMessage = stringsOf().libraryDomain.localDbLocked;

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
      ),
    );
    await openAdvanced(tester);

    expect(find.text(stringsOf().libraryDomain.localDbLocked), findsOneWidget);
    Finder inSource(String text) => find.descendant(
          of: find.byKey(ShellKeys.librarySource),
          matching: find.textContaining(text),
        );
    expect(inSource(t.mirrorNotChecked), findsOneWidget);
    expect(inSource(t.mirrorUnreadable), findsNothing);
  });

  // מצב "עדכון אישי": האריח שמאפשר לרשום את הגרסה מופיע רק במצב הזה, כי הוא
  // הדרך **היחידה** שגרסה נרשמת — התוכנה אינה קוראת אותה מעצמה.
  testWidgets('אריח גרסת המסד האישית מופיע רק במצב עדכון אישי', (tester) async {
    final t = stringsOf().libraryScreen;

    Widget screen() => LibraryScreen(
          library: library,
          otzariaIsRunning: false,
          onCloseOtzaria: () async => true,
          isDownloading: false,
          onProcessStateChanged: () async => false,
          onRequestReindex: () async {},
          onGoToSettings: () {},
        );

    await pumpScreen(tester, screen());
    await openAdvanced(tester);
    expect(find.text(t.personalVersionTitle), findsNothing);

    library.personalUpdateMode = true;
    await pumpScreen(tester, screen());
    await openAdvanced(tester);

    expect(find.text(t.personalVersionTitle), findsOneWidget);
    // טרם נרשמה גרסה — המסך אומר במפורש איפה יש ללחוץ.
    expect(find.textContaining(t.personalVersionMissing), findsOneWidget);
    expect(find.text(t.personalVersionButton), findsOneWidget);

    library.personalFromVersion = 20;
    await pumpScreen(tester, screen());
    await openAdvanced(tester);
    expect(
      find.textContaining(t.personalVersionRecorded('20')),
      findsOneWidget,
    );
  });

  testWidgets('מצב אישי בלי גרסה רשומה מדווח שירד המסד המלא', (tester) async {
    library.personalUpdateMode = true;
    library.personalDownloadNote = LibraryPersonalDownloadNote.versionUnknown;
    library.lastDownloadedAt = DateTime(2026, 8, 12);

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
      ),
    );
    await openAdvanced(tester);

    expect(
      find.text(stringsOf().libraryScreen.downloadNotePersonalUnknownVersion),
      findsOneWidget,
    );
  });

  testWidgets('הפעלת עדכון אישי דורשת אישור באזהרה', (tester) async {
    final t = stringsOf().settings;

    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );

    await openAdvanced(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.personalModeTitle));
    await tester.pumpAndSettle();

    expect(find.text(t.personalModeDialogTitle), findsOneWidget);
    // נוסח פשוט, והעובדה החשובה נאמרת: הספרייה המלאה תימחק.
    expect(find.text(t.personalModeDialogContent), findsOneWidget);
    expect(
      t.personalModeDialogContent,
      contains('הספרייה המלאה שבכונן תימחק בהורדה הבאה'),
    );
    expect(find.textContaining('גרסת המסד'), findsNothing);
    expect(find.textContaining('מגה'), findsNothing);
    // עדיין אזהרה — הביטול מומלץ.
    expect(
      find.widgetWithText(FilledButton, stringsOf().common.cancel),
      findsOneWidget,
    );

    await tester.tap(find.text(stringsOf().common.cancel));
    await tester.pumpAndSettle();
    expect(settings.settings.personalUpdateMode, isFalse);

    await tester.tap(find.text(t.personalModeTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.personalModeDialogConfirm));
    await tester.pumpAndSettle();

    expect(settings.settings.personalUpdateMode, isTrue);
  });

  testWidgets('מסך הספרייה מציג התקדמות בזמן עדכון וחוסם פעולות', (
    tester,
  ) async {
    library.status = LibraryModuleStatus.updating;
    library.stageText = 'מחיל תיקון 3 מתוך 7';
    library.applyProgress = 0.42;

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: true,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
      ),
    );

    expect(find.byType(InfoProgressRow), findsOneWidget);
    expect(find.text('מחיל תיקון 3 מתוך 7'), findsOneWidget);
    // אוצריא פתוחה — האזהרה מוצגת כאן ולא רק בדף הבית.
    expect(
      find.text(stringsOf().guide.otzariaOpenTitle),
      findsOneWidget,
    );
    final recheck = tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, stringsOf().guide.recheckButton),
    );
    expect(recheck.onPressed, isNull);
  });

  // ── שלב 3: תיקוני QA ועיצוב ───────────────────────────────────────────────

  // החלטת המשתמש: בחירת "יציבה" כשמותקנת ניסיונית חדשה ממנה אינה מורידה גרסה.
  testWidgets('ניסיונית חדשה מותקנת והערוץ יציב — מצב רגוע, ממתינים ליציבה', (
    tester,
  ) async {
    otzaria.status = OtzariaModuleStatus.installedIsNewer;
    otzaria.currentVersion = '0.9.98';
    otzaria.latestVersion = '0.9.97';
    otzaria.hasChannelChoice = true;
    otzaria.stableVersion = '0.9.97';
    otzaria.prereleaseVersion = '0.9.98';
    otzaria.awaitsNewerInSelectedChannel = true;
    var installs = 0;
    await pumpScreen(tester, otzariaPage(onUpdateHere: () => installs++));

    expect(
      find.text(stringsOf().pages.appAwaitsNewer(stable: true)),
      findsOneWidget,
    );
    expect(
      tester.widget<ActionButton>(find.byKey(ShellKeys.statusPrimary)).text,
      stringsOf().guide.launchButton,
    );
    expect(find.textContaining('0.9.97 ', findRichText: true), findsNothing);
    expect(installs, 0);
  });

  testWidgets('אוצריא פתוחה — ההודעה בדף התוכנה גם בלי עדכון', (tester) async {
    otzaria.status = OtzariaModuleStatus.upToDate;
    otzaria.currentVersion = '0.9.96';
    otzaria.latestVersion = '0.9.96';
    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: true,
        onCloseOtzaria: () async => true,
      ),
    );

    expect(find.text(stringsOf().guide.otzariaOpenTitle), findsOneWidget);
  });

  testWidgets('לפני בדיקה — "טרם נבדק" ולא "בודק"', (tester) async {
    final common = stringsOf().common;
    await pumpScreen(tester, otzariaPage());
    expect(find.text(common.notCheckedYet), findsOneWidget);
    expect(find.text(stringsOf().guide.chipChecking), findsNothing);

    await pumpScreen(tester, libraryPage());
    expect(find.text(common.notCheckedYet), findsOneWidget);
    expect(find.text(stringsOf().guide.chipChecking), findsNothing);
  });

  testWidgets('משימה רצה — הכפתורים מושבתים, ונאמר למה', (tester) async {
    otzaria.status = OtzariaModuleStatus.updateAvailable;
    otzaria.currentVersion = '0.9.95';
    otzaria.latestVersion = '0.9.96';
    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        onUpdateHere: () {},
        busy: true,
      ),
    );
    expect(
      tester
          .widget<ActionButton>(find.byKey(ShellKeys.statusPrimary))
          .onPressed,
      isNull,
    );
    expect(find.text(stringsOf().pages.pageBusyNote), findsOneWidget);

    fakeLibraryUpdateAvailable();
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
        onUpdateHere: () {},
        busy: true,
      ),
    );
    expect(
      tester
          .widget<ActionButton>(find.byKey(ShellKeys.statusPrimary))
          .onPressed,
      isNull,
    );
    expect(find.text(stringsOf().pages.pageBusyNote), findsOneWidget);
  });

  testWidgets('בלי אוצריא ועם התוכנה בכונן — "התקנת אוצריא והספרייה" עם הסבר', (
    tester,
  ) async {
    final p = stringsOf().pages;
    library.status = LibraryModuleStatus.updateAvailable;
    library.isFreshInstall = true;
    library.targetVersion = 31;
    var tasks = 0;
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
        onUpdateHere: () => tasks++,
        appInstalled: false,
        appInstallable: true,
      ),
    );

    final primary =
        tester.widget<ActionButton>(find.byKey(ShellKeys.statusPrimary));
    expect(primary.text, p.libInstallWithAppButton);
    expect(find.text(p.libInstallWithAppNote), findsOneWidget);
    await tester.tap(find.byKey(ShellKeys.statusPrimary));
    expect(tasks, 1);
  });

  testWidgets('בלי אוצריא ובלי התוכנה בכונן — ההתקנה מושבתת, עם הסבר', (
    tester,
  ) async {
    final p = stringsOf().pages;
    library.status = LibraryModuleStatus.updateAvailable;
    library.isFreshInstall = true;
    library.targetVersion = 31;
    var tasks = 0;
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
        onUpdateHere: () => tasks++,
        appInstalled: false,
      ),
    );

    final primary =
        tester.widget<ActionButton>(find.byKey(ShellKeys.statusPrimary));
    expect(primary.text, p.libInstallButton);
    expect(primary.onPressed, isNull);
    expect(find.text(p.libInstallNeedsApp), findsOneWidget);

    // בזמן שמודול התוכנה בבדיקה לא ידוע אם היא בכונן — אין הסבר שגוי.
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
        onUpdateHere: () => tasks++,
        appInstalled: false,
        appInstallable: null,
      ),
    );
    expect(find.byKey(ShellKeys.libraryInstallNote), findsNothing);
  });

  testWidgets('אחרי כשל — הספרייה המלאה היא הפעולה הראשית, עם גודל', (
    tester,
  ) async {
    final s = stringsOf().libraryScreen;
    library.status = LibraryModuleStatus.error;
    library.errorMessage = 'העדכון נכשל';
    library.canRetryWithFullDownload = true;
    var full = 0;
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
        onInstallFull: () => full++,
      ),
    );

    final primary =
        tester.widget<ActionButton>(find.byKey(ShellKeys.statusPrimary));
    expect(primary.text, s.fullDownloadInsteadButton);
    // בלי גודל ובלי אומדן ידועים אין שורת "הספרייה המלאה שבכונן" ריקה.
    expect(find.text(stringsOf().pages.libFullMeta()), findsNothing);
    // "בדוק שוב" בכרטיס הוא הניסיון החוזר — בלי "נסה שוב" בשורת השגיאה.
    expect(find.text(stringsOf().common.retry), findsNothing);
    await tester.tap(find.byKey(ShellKeys.statusPrimary));
    expect(full, 1);

    await openAdvanced(tester);
    expect(find.text(stringsOf().pages.libFullBodyNoSize), findsOneWidget);
  });

  // מיקום המסד נשמר ב-stateDir, שבכונן מוגן עובר למחשב עצמו.
  testWidgets('כונן מוגן — אפשר לבחור את מיקום הספרייה', (tester) async {
    library.installTargetPath = r'C:\otzaria\books\seforim.db';
    await pumpScreen(tester, libraryPage(readOnly: true));
    await openAdvanced(tester);

    for (final text in [
      stringsOf().libraryScreen.pickInstallDirButton,
      stringsOf().libraryScreen.pickDbButton,
    ]) {
      expect(
        tester
            .widget<ActionButton>(find.widgetWithText(ActionButton, text))
            .onPressed,
        isNotNull,
      );
    }

    library.status = LibraryModuleStatus.needsManualPath;
    await pumpScreen(tester, libraryPage(readOnly: true));
    expect(
      tester
          .widget<ActionButton>(find.byKey(ShellKeys.statusPrimary))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('הסכמה לחיפוש החכם — "מה נשלח?" מציג את הגילוי המלא', (
    tester,
  ) async {
    fakeLibraryUpdateAvailable();
    library.semanticPending = true;
    await pumpScreen(tester, libraryPage());

    await tester.ensureVisible(find.byKey(ShellKeys.libraryConsentWhatIsSent));
    await tester.tap(find.byKey(ShellKeys.libraryConsentWhatIsSent));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.textContaining(stringsOf().guide.reportsDisclosureSearch),
      findsOneWidget,
    );
    expect(
      find.textContaining(stringsOf().guide.reportsDisclosureReports),
      findsNothing,
    );
  });

  test('הגודל והאומדן של הספרייה המלאה נאמרים יחד', () {
    final p = stringsOf().pages;
    final meta = p.libFullMeta(size: '1.3 GB', lowMinutes: 3, highMinutes: 12);
    expect(meta, contains('1.3 GB'));
    expect(meta, contains('3'));
    expect(meta, contains('12'));
    expect(p.libFullMeta(lowMinutes: 3, highMinutes: 12), isNot(contains(':')));
  });

  testWidgets('תקציר "מתקדם" מונה רק שורות שמוצגות', (tester) async {
    final p = stringsOf().pages;
    otzaria.status = OtzariaModuleStatus.upToDate;
    await pumpScreen(tester, otzariaPage());
    expect(find.text(p.appAdvancedSummary(channel: false)), findsOneWidget);

    otzaria.hasChannelChoice = true;
    await pumpScreen(tester, otzariaPage());
    expect(find.text(p.appAdvancedSummary(channel: true)), findsOneWidget);

    await pumpScreen(tester, libraryPage());
    expect(find.text(p.libAdvancedSummary(reindex: false)), findsOneWidget);
  });

  test('החנות נפתחת מציגה את הכול, לא רק יציב', () {
    final controller = PluginsModuleController(mirrorRootDir: tempDir.path);
    expect(controller.statusFilter, PluginStatusFilter.all);
    controller.dispose();
  });

  test('ברירות המחדל של ההגדרות נשמרות ונטענות מקובץ', () async {
    await settings.update(
      const AppSettings(syncLibrary: false, preferAppPrerelease: true),
    );

    final reloaded = SettingsController(dataDir: tempDir.path);
    await reloaded.load();

    expect(reloaded.settings.syncLibrary, isFalse);
    expect(reloaded.settings.autoInstall, isFalse);
    // ברירת המחדל היא הגרסה היציבה, והבחירה שורדת הפעלה מחדש.
    expect(const AppSettings().preferAppPrerelease, isFalse);
    expect(reloaded.settings.preferAppPrerelease, isTrue);
    reloaded.dispose();
  });

  // ── מתקדם: כל שורה נגישה ────────────────────────────────────────────────

  testWidgets('דף התוכנה: כל שורות המתקדם נגישות', (tester) async {
    final p = stringsOf().pages;
    otzaria.status = OtzariaModuleStatus.upToDate;
    otzaria.currentVersion = '0.9.96';
    otzaria.latestVersion = '0.9.96';
    otzaria.hasChannelChoice = true;
    otzaria.stableVersion = '0.9.96';
    otzaria.prereleaseVersion = '0.9.97';
    otzaria.launchPath = r'C:\Program Files\Otzaria\otzaria.exe';
    await pumpScreen(tester, otzariaPage());

    expect(find.byKey(ShellKeys.appChannel), findsNothing);
    await openAdvanced(tester);
    expect(find.byKey(ShellKeys.appChannel), findsOneWidget);
    expect(find.byKey(ShellKeys.appReinstall), findsOneWidget);
    expect(find.text(p.appLocationTitle), findsOneWidget);
    expect(find.text(path.dirname(otzaria.launchPath!)), findsOneWidget);
    expect(find.text(p.appSourceTitle), findsOneWidget);
    expect(find.text(otzaria.mirrorDir), findsOneWidget);
  });

  testWidgets('דף הספרייה: כל שורות המתקדם נגישות', (tester) async {
    final p = stringsOf().pages;
    library
      ..status = LibraryModuleStatus.upToDate
      ..dbPath = r'C:\otzaria\books\seforim.db'
      ..personalUpdateMode = true
      ..pendingReindex = const ExternalUpdateNoticeData(
        route: ExternalUpdateNotice.routeDelta,
        booksTouched: {3},
        dbVersion: 42,
      );
    var settingsOpened = 0;
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () => settingsOpened++,
      ),
    );
    await openAdvanced(tester);
    for (final key in [
      ShellKeys.libraryLocation,
      ShellKeys.libraryReindex,
      ShellKeys.libraryFull,
      ShellKeys.libraryPersonal,
      ShellKeys.librarySource,
    ]) {
      expect(find.byKey(key), findsOneWidget, reason: '$key');
    }
    expect(find.text(r'C:\otzaria\books\seforim.db'), findsOneWidget);
    // נתיב ארוך מקוצר לשורה — הנתיב המלא בריחוף, ואפשר להעתיק אותו.
    expect(
      find.byTooltip(
        '\u2066C:\\otzaria\\books\\seforim.db\u2069',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ShellKeys.libraryLocation),
        matching: find.byTooltip(stringsOf().common.copyPathButton),
      ),
      findsOneWidget,
    );
    expect(find.text(stringsOf().libraryScreen.personalVersionTitle),
        findsOneWidget);
    // "עדכון למחשב מסוים" מופעל בהגדרות — השורה מובילה לשם.
    await tester.tap(
      find.descendant(
        of: find.byKey(ShellKeys.libraryPersonal),
        matching: find.byType(ActionButton),
      ),
    );
    expect(settingsOpened, 1);
    expect(find.textContaining(p.libPersonalOn), findsWidgets);
  });

  testWidgets('הספרייה לא נמצאה — בחירת מיקום או קובץ, בלי שום עדכון', (
    tester,
  ) async {
    final p = stringsOf().pages;
    library.status = LibraryModuleStatus.needsManualPath;
    await pumpScreen(tester, libraryPage(onUpdateHere: () {}));

    expect(find.text(p.libNotFoundTitle), findsOneWidget);
    expect(find.text(p.libNotFoundBody), findsOneWidget);
    expect(
      tester.widget<ActionButton>(find.byKey(ShellKeys.statusPrimary)).text,
      p.libPickFolderButton,
    );
    expect(find.text(stringsOf().libraryScreen.pickDbButton), findsOneWidget);
    expect(find.text(p.libUpdateButton), findsNothing);
  });

  testWidgets('כונן מוגן: רישום המחשב לעדכון אישי מושבת, עם הסבר', (
    tester,
  ) async {
    library.personalUpdateMode = true;
    await pumpScreen(tester, libraryPage(readOnly: true));
    await openAdvanced(tester);

    expect(
      find.textContaining(stringsOf().pages.libPersonalReadOnly),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ActionButton>(
            find.widgetWithText(
              ActionButton,
              stringsOf().libraryScreen.personalVersionButton,
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('קבצים חסרים בכונן — הודעה מעל הכרטיס', (tester) async {
    library
      ..status = LibraryModuleStatus.upToDate
      ..mirroredCompanions = {CompanionAsset.talmud}
      ..unavailableCompanions = {CompanionAsset.talmud};
    await pumpScreen(tester, libraryPage());
    expect(find.text(stringsOf().pages.libMissingFilesTitle), findsOneWidget);
  });
}
