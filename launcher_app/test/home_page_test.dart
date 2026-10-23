// דף הבית מהמודל: כל מצב של ההכוונה מציג את הגיבור, האריחים וההודעות
// הנכונים, וכל כפתור מפעיל את הפעולה שלו. בלי סשן ובלי קונטרולרים — מלבד
// בדיקות המדים בסוף, שקוראות מ-progress של קונטרולרים אמיתיים.

import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/home/home_page.dart';
import 'package:launcher_app/src/screens/home/home_progress.dart';
import 'package:launcher_app/src/screens/home/home_view_model.dart';
import 'package:launcher_app/src/self_update/launcher_release.dart';
import 'package:launcher_app/src/services/byte_size.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_navigator.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart' show PluginsOnlineStatus;

import 'home_fixtures.dart';
import 'test_harness.dart';

void main() {
  final g = stringsOf().guide;
  final he = stringsOf();

  Finder inHero(Finder finder) =>
      find.descendant(of: find.byKey(ShellKeys.hero), matching: finder);

  ActionButton primary(WidgetTester tester) =>
      tester.widget<ActionButton>(find.byKey(ShellKeys.heroPrimary));

  group('מצבי המוקאפ', () {
    final expectations = <String, ({String title, String? button})>{
      'offline': (title: g.updateHereTitle, button: g.updateHereButton),
      'online': (title: g.downloadTitle, button: g.downloadButton),
      'uptodate': (title: g.upToDateTitle, button: g.launchButton),
      'newer': (title: g.newerTitle, button: g.launchButton),
      'open': (title: g.updateHereTitle, button: g.updateHereButton),
      'readonly': (title: g.updateHereTitle, button: g.updateHereButton),
      'drivefull': (title: g.upToDateTitle, button: g.launchButton),
    };

    for (final MapEntry(key: name, value: want) in expectations.entries) {
      testWidgets('$name: גיבור עם כותרת וכפתור אחד ראשי', (tester) async {
        await pumpScreen(tester, HomePage(model: homeScenario(name)));

        expect(inHero(find.text(want.title)), findsOneWidget);
        expect(find.byKey(ShellKeys.heroPrimary), findsOneWidget);
        expect(primary(tester).text, want.button);
        expect(find.byKey(ShellKeys.welcome), findsNothing);
        // שלושת האריחים הקבועים תמיד שם.
        for (final section in [
          ShellSection.otzaria,
          ShellSection.library,
          ShellSection.plugins,
        ]) {
          expect(find.byKey(ShellKeys.tile(section)), findsOneWidget);
        }
      });
    }

    for (final name in ['first', 'firstOffline']) {
      testWidgets('$name: מסך הפתיחה במקום הבית', (tester) async {
        await pumpScreen(tester, HomePage(model: homeScenario(name)));

        expect(find.byKey(ShellKeys.welcome), findsOneWidget);
        expect(find.byKey(ShellKeys.hero), findsNothing);
        expect(find.text(g.welcomeTitle), findsOneWidget);
        final online = name == 'first';
        expect(
          find.text(g.welcomeDownloadButton),
          online ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(g.welcomeHelpButton),
          online ? findsNothing : findsOneWidget,
        );
        expect(
          find.text(online ? g.welcomeLeadOnline : g.welcomeLeadOffline),
          findsOneWidget,
        );
        expect(find.text(g.youAreHere), findsOneWidget);
      });
    }

    testWidgets('offline: מה ייכלל — תוכנה, ספרייה ותוספים, בסדר הזה', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('offline')));

      final app = tester.getCenter(find.text(g.pillApp('0.10.4')));
      final library = tester.getCenter(find.text(g.pillLibraryUpdate));
      final plugins = tester.getCenter(find.text(g.pillPluginUpdates(3)));
      // מימין לשמאל; גלולה שלא נכנסה בשורה יורדת לשורה הבאה.
      expect(app.dx, greaterThan(library.dx));
      expect(
        plugins.dy > library.dy || plugins.dx < library.dx,
        isTrue,
      );
      expect(find.text(g.eyebrowOffline), findsOneWidget);
      expect(find.text(g.eyebrowOtzaria('0.10.3')), findsOneWidget);
    });

    testWidgets('online: הורדה ראשית, "לעדכן גם כאן" משני, והערה על הכונן', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('online')));

      // הגרסה הגולמית מהאתר ('v0.10.5+812') מוצגת בלי v ובלי build, וחנות
      // התוספים מתמזגת לגלולת התוספים, בלי גרסה.
      expect(find.text(g.pillApp('0.10.5')), findsOneWidget);
      expect(find.text(g.pillLibraryUpdate), findsOneWidget);
      expect(find.text(g.pillPluginsWithStore(3)), findsOneWidget);
      expect(find.textContaining('812'), findsNothing);
      expect(find.textContaining('v0.10'), findsNothing);
      expect(
        tester.widget<ActionButton>(find.byKey(ShellKeys.heroSecondary)).text,
        g.updateHereTooButton,
      );
      expect(find.text(g.updateHereTooNote('0.10.4')), findsOneWidget);
      expect(find.text(g.eyebrowOnline), findsOneWidget);
    });

    testWidgets('uptodate: הרמז על כונן בלי אינטרנט, ופס התוספים החדשים', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('uptodate')));

      expect(
        find.text(g.upToDateBody('0.10.4', offline: true)),
        findsOneWidget,
      );
      expect(find.text(g.offlineNote), findsOneWidget);
      expect(find.byKey(ShellKeys.newPluginsBanner), findsOneWidget);
      expect(
        find.byKey(ShellKeys.tile(ShellSection.customApps)),
        findsOneWidget,
      );
      expect(find.byKey(ShellKeys.tile(ShellSection.reports)), findsNothing);
      expect(find.byKey(ShellKeys.launcherLine), findsNothing);
    });

    testWidgets('בלי תוכנות נוספות ובלי דיווחים — אין להם אריחים', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(guidance: homeScenario('uptodate').guidance),
        ),
      );
      expect(
        find.byKey(ShellKeys.tile(ShellSection.customApps)),
        findsNothing,
      );
      expect(find.byKey(ShellKeys.tile(ShellSection.reports)), findsNothing);
    });

    testWidgets('newer: פס התוספים החדשים מוצג גם כשהמותקנת חדשה מהכונן', (
      tester,
    ) async {
      final newer = homeScenario('newer');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: newer.guidance,
            installedVersion: newer.installedVersion,
            driveAppVersion: newer.driveAppVersion,
            newPlugins: const ['דף יומי'],
          ),
        ),
      );
      expect(newer.guidance.primary, GuidancePrimary.newerHereThanDrive);
      expect(find.byKey(ShellKeys.newPluginsBanner), findsOneWidget);
    });

    testWidgets('newer: בלי פעולה מהכונן, ושתי הגרסאות בגוף', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('newer')));

      expect(find.text(g.newerBody('0.10.5', '0.10.4')), findsOneWidget);
      expect(find.text(g.newerNote), findsOneWidget);
      expect(find.text(g.chipNewerHere), findsOneWidget);
      expect(find.byKey(ShellKeys.newPluginsBanner), findsNothing);
    });

    testWidgets('open: פס "אוצריא פתוחה כרגע" כמו במוקאפ, בלי כפתור', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('open')));

      final banner = find.byKey(ShellKeys.otzariaOpenBanner);
      expect(banner, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.text(g.otzariaOpenTitle)),
        findsOneWidget,
      );
      // ההתקנה האוטומטית דילגה — נאמר בפתיח של אותו פס.
      expect(
        find.text('${g.autoInstallSkippedLead}${g.otzariaOpenBody}'),
        findsOneWidget,
      );
      expect(
        find.descendant(of: banner, matching: find.byType(ActionButton)),
        findsNothing,
      );
      expect(find.text(he.common.closeOtzariaButton), findsNothing);
    });

    testWidgets('readonly: הודעת הכונן המוגן, בלי שורת הורדה נעולה', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('readonly')));

      expect(find.byKey(ShellKeys.readOnlyNotice), findsOneWidget);
      expect(find.text(he.readOnlyDrive.bannerTitle), findsOneWidget);
      // בכונן מוגן אין בדיקה ברשת, ולכן גם אין מה "לנעול".
      expect(find.text(g.downloadButton), findsNothing);
      expect(find.text(g.checkNowLink), findsNothing);
      expect(find.byKey(ShellKeys.checkNow), findsNothing);
    });

    testWidgets('readonly: אריח הדיווחים מוצג, נעול ("לא זמין בכונן הזה")', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('readonly')));

      final tile = find.byKey(ShellKeys.tile(ShellSection.reports));
      expect(tile, findsOneWidget);
      final chip = tester.widget<StatusChip>(
        find.descendant(of: tile, matching: find.byType(StatusChip)),
      );
      expect(chip.kind, StatusKind.locked);
      expect(chip.label, g.chipReportsLocked);
    });

    testWidgets('drivefull: הודעת הכונן המלא, ואריח דיווחים נעול', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('drivefull')));

      expect(find.byKey(ShellKeys.driveFullNotice), findsOneWidget);
      expect(find.text(he.readOnlyDrive.bannerTitleDriveFull), findsOneWidget);
      expect(find.byKey(ShellKeys.newPluginsBanner), findsOneWidget);
      expect(
        find.byKey(ShellKeys.tile(ShellSection.customApps)),
        findsOneWidget,
      );
      expect(find.text(g.chipReportsLocked), findsOneWidget);
    });
  });

  group('הפעולות', () {
    testWidgets('הכפתורים הראשיים מפעילים את הזרימה של כל מצב', (
      tester,
    ) async {
      final calls = <String>[];
      final actions = HomeActions(
        onInstallHere: () => calls.add('install'),
        onUpdateHere: () => calls.add('update'),
        onDownload: () => calls.add('download'),
        onLaunch: () => calls.add('launch'),
        onRecheck: () => calls.add('recheck'),
      );
      Future<void> tapIn(String scenario, Key key) async {
        await pumpScreen(
          tester,
          HomePage(model: homeScenario(scenario), actions: actions),
        );
        await tester.tap(find.byKey(key));
        await tester.pump();
      }

      await tapIn('offline', ShellKeys.heroPrimary);
      await tapIn('online', ShellKeys.heroPrimary);
      await tapIn('online', ShellKeys.heroSecondary);
      await tapIn('uptodate', ShellKeys.heroPrimary);
      await tapIn('uptodate', ShellKeys.heroSecondary);
      expect(calls, ['update', 'download', 'update', 'launch', 'recheck']);
    });

    testWidgets('התקנה ראשונה במחשב ריק כשבכונן יש תוכנה', (tester) async {
      var installs = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                otzariaInstalled: false,
                otzariaMirrorVersion: '0.10.4',
                otzariaStatus: AppStatusFact.updateAvailable,
                libraryStatus: LibraryStatusFact.updateAvailable,
                libraryFreshInstall: true,
                online: false,
              ),
            ),
            driveAppVersion: '0.10.4',
          ),
          actions: HomeActions(onInstallHere: () => installs++),
        ),
      );

      expect(find.text(g.installHereTitle), findsOneWidget);
      expect(find.text(g.pillLibraryFull), findsOneWidget);
      expect(find.text(g.eyebrowNotInstalled), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.heroPrimary));
      expect(installs, 1);
    });

    testWidgets('"הורדת העדכונים" מושבתת בזמן בדיקה ברשת', (tester) async {
      final online = homeScenario('online');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: online.guidance,
            online: true,
            installedVersion: online.installedVersion,
            onlineAppVersion: '0.10.5',
            isCheckingOnline: true,
          ),
        ),
      );
      expect(primary(tester).onPressed, isNull);
    });

    testWidgets('אריח פותח את המקטע שלו; פס התוספים החדשים פותח את החנות', (
      tester,
    ) async {
      final opened = <ShellSection>[];
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('offline'),
          actions: HomeActions(onOpenSection: opened.add),
        ),
      );

      for (final section in [
        ShellSection.otzaria,
        ShellSection.library,
        ShellSection.plugins,
        ShellSection.customApps,
        ShellSection.reports,
      ]) {
        await tester.tap(find.byKey(ShellKeys.tile(section)));
      }
      await tester.tap(find.text(g.toPluginsButton));
      await tester.tap(find.text(g.whatsNewButton));
      expect(opened, [
        ShellSection.otzaria,
        ShellSection.library,
        ShellSection.plugins,
        ShellSection.customApps,
        ShellSection.reports,
        ShellSection.plugins,
        ShellSection.otzaria,
      ]);
    });

    testWidgets('הודעות במקום דיאלוגים: כל כפתור מפעיל את שלו', (tester) async {
      final calls = <String>[];
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('offline').guidance,
            installedVersion: '0.10.3',
            offersElevation: true,
            reportsIntro: true,
            legacyReportsNotice: true,
          ),
          actions: HomeActions(
            onRestartElevated: () => calls.add('elevate'),
            onDismissElevation: () => calls.add('notNow'),
            onDismissReportsIntro: () => calls.add('intro'),
            onDismissLegacyReports: () => calls.add('legacy'),
          ),
        ),
      );

      await tester.tap(find.text(he.elevation.bannerConfirm));
      await tester.tap(find.text(he.elevation.bannerDismiss));
      await tester.tap(
        find.descendant(
          of: find.byKey(ShellKeys.reportsIntroNotice),
          matching: find.text(he.errorReports.introDialogConfirm),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(ShellKeys.legacyReportsNotice),
          matching: find.text(he.errorReports.introDialogConfirm),
        ),
      );
      expect(calls, ['elevate', 'notNow', 'intro', 'legacy']);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('הסבר הדיווחים בהודעה — פסקה אחת, בלי שורה ריקה', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('uptodate').guidance,
            reportsIntro: true,
          ),
        ),
      );
      final notice = tester.widget<NoticeBanner>(
        find.byKey(ShellKeys.reportsIntroNotice),
      );
      expect(he.errorReports.introDialogContent, contains('\n\n'));
      expect(notice.body, isNot(contains('\n')));
      // "הבנתי" באמצע גובה ההודעה (בלי השוליים התחתונים), לא בשורה הראשונה.
      final box = tester.getRect(find.byKey(ShellKeys.reportsIntroNotice));
      expect(
        tester.getCenter(find.text(he.errorReports.introDialogConfirm)).dy,
        closeTo(box.top + (box.height - 12) / 2, 1.5),
      );
    });

    testWidgets('אוצריא פתוחה בלי דילוג: אותו פס, בלי הפתיח על הדילוג', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('open').guidance,
            installedVersion: '0.10.3',
          ),
        ),
      );

      expect(find.byKey(ShellKeys.otzariaOpenBanner), findsOneWidget);
      expect(find.text(g.otzariaOpenBody), findsOneWidget);
      expect(find.textContaining(g.autoInstallSkippedLead), findsNothing);
    });

    testWidgets('דילוג אוטומטי כשאוצריא כבר נסגרה — אין פס "פתוחה"', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('offline').guidance,
            autoInstallSkipped: true,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.otzariaOpenBanner), findsNothing);
      expect(find.textContaining(g.autoInstallSkippedLead), findsNothing);
    });

    testWidgets('בזמן הורדה: מד, וכפתור ביטול שמבקש את הביטול פעם אחת', (
      tester,
    ) async {
      var cancels = 0;
      HomeViewModel downloading({bool cancelling = false}) => HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(longTaskRunning: true),
            ),
            task: HomeTask.downloading,
            cancellingDownload: cancelling,
          );
      await pumpScreen(
        tester,
        HomePage(
          model: downloading(),
          actions: HomeActions(onCancelDownload: () => cancels++),
          taskProgress: const Text('progress-slot'),
        ),
      );

      expect(find.text(g.taskDownloadingTitle), findsOneWidget);
      expect(find.text('progress-slot'), findsOneWidget);
      // כפתור רגיל "ביטול", לא אדום: האישור עצמו בדו-שיח של המסגרת.
      final button = tester.widget<ActionButton>(
        find.byKey(ShellKeys.heroCancel),
      );
      expect(button.text, he.common.cancel);
      expect(
        find.descendant(
          of: find.byKey(ShellKeys.heroCancel),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
      expect(button.icon, isNull);
      await tester.tap(find.byKey(ShellKeys.heroCancel));
      expect(cancels, 1);

      await pumpScreen(
        tester,
        HomePage(model: downloading(cancelling: true)),
      );
      final cancel = tester.widget<ActionButton>(
        find.byKey(ShellKeys.heroCancel),
      );
      expect(cancel.text, he.home.cancelDownloadPending);
      expect(cancel.onPressed, isNull);
    });
  });

  group('הורדה לכונן — מה ייכלל ומה לא', () {
    HomeViewModel model({
      bool syncApp = true,
      bool syncPlugins = true,
      int pluginChanges = 0,
      bool catalogOnly = false,
      bool storeApp = false,
      bool libraryFailed = false,
    }) =>
        HomeViewModel(
          guidance: deriveHomeGuidance(
            GuidanceFacts(
              online: true,
              onlineApp: true,
              onlinePlugins: true,
              syncApp: syncApp,
              syncPlugins: syncPlugins,
            ),
          ),
          online: true,
          installedVersion: '0.10.4',
          onlineAppVersion: '0.10.5',
          onlinePluginChanges: pluginChanges,
          onlinePluginCatalogChanged: catalogOnly,
          onlineStoreApp: storeApp,
          syncApp: syncApp,
          syncPlugins: syncPlugins,
          libraryDownloadFailed: libraryFailed,
        );

    testWidgets('תוספים וחנות התוספים — גלולה אחת, בלי מספר גרסה', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(model: model(pluginChanges: 4, storeApp: true)),
      );
      expect(find.text(g.pillPluginsWithStore(4)), findsOneWidget);
      expect(find.text(g.pillPlugins(4)), findsNothing);
      expect(find.text(g.pillStoreApp), findsNothing);
      expect(find.text(g.pillApp('0.10.5')), findsOneWidget);
    });

    testWidgets('רק חנות התוספים התחדשה — "עדכון לחנות התוספים"', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: model(storeApp: true)));
      expect(find.text(g.pillStoreApp), findsOneWidget);
    });

    // תחליף ל'חנות שאין בה מה חדש אינה מוסיפה שורות לכרטיס'.
    testWidgets('בחנות אין מה חדש — אין גלולת תוספים', (tester) async {
      await pumpScreen(tester, HomePage(model: model()));
      expect(find.text(g.pillApp('0.10.5')), findsOneWidget);
      expect(
        inHero(find.byIcon(FluentIcons.puzzle_piece_16_regular)),
        findsNothing,
      );
    });

    test('תוסף שהקובץ שלו חסר בכונן נספר; תוסף שהוסר מהאתר — לא', () {
      expect(onlinePluginChangesOf(null), 0);
      expect(
        onlinePluginChangesOf(
          const PluginsOnlineStatus(
            newPlugins: ['a'],
            updatedPlugins: ['b', 'c'],
            missingPlugins: ['d'],
            removedPlugins: ['e'],
          ),
        ),
        4,
      );
      expect(
        onlinePluginChangesOf(
          const PluginsOnlineStatus(removedPlugins: ['e']),
        ),
        0,
      );
    });

    testWidgets('רק רשימת התוספים השתנתה (תוסף הוסר) — עדיין נאמר', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: model(catalogOnly: true)));
      expect(find.text(g.pillPluginsCatalog), findsOneWidget);
    });

    testWidgets('רכיב כבוי בהגדרות נאמר, עם קישור להגדרות', (tester) async {
      var settings = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: model(syncPlugins: false, pluginChanges: 2),
          actions: HomeActions(onOpenSettings: () => settings++),
        ),
      );
      expect(
        find.text(g.syncOffNote(app: false, library: false, plugins: true)),
        findsOneWidget,
      );
      // התוספים לא יירדו, ולכן גם אינם ב"מה ייכלל".
      expect(find.text(g.pillPlugins(2)), findsNothing);
      await tester.tap(find.text(g.changeInSettingsLink));
      expect(settings, 1);
    });

    testWidgets('הורדת ספרייה שנכשלה נשארת כתובה עד ההורדה הבאה', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: model(libraryFailed: true)));
      expect(find.text(g.libraryRetryNote), findsOneWidget);
    });

    testWidgets('יש חדש באתר אבל שום רכיב לא מסומן — בלי כפתור הורדה', (
      tester,
    ) async {
      var settings = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                online: true,
                onlineApp: true,
                syncApp: false,
                syncLibrary: false,
                syncPlugins: false,
              ),
            ),
            online: true,
            installedVersion: '0.10.4',
          ),
          actions: HomeActions(onOpenSettings: () => settings++),
        ),
      );
      expect(find.text(g.downloadButton), findsNothing);
      expect(find.text(g.noSyncSelectionNote), findsOneWidget);
      await tester.tap(find.text(g.chooseInSettingsLink));
      expect(settings, 1);
    });
  });

  group('שורת התחתית', () {
    HomeViewModel withLauncher(LauncherLine? line, {bool busy = false}) =>
        HomeViewModel(
          guidance: deriveHomeGuidance(
            GuidanceFacts(online: false, longTaskRunning: busy),
          ),
          launcher: line,
          checkedAt: DateTime(2026, 10, 23, 9, 5),
          driveName: 'E:',
        );

    testWidgets('גרסה חדשה באתר: "פרטים ועדכון" פותח את דף הכלי — לא התקנה', (
      tester,
    ) async {
      var opened = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(
            const LauncherLine(LauncherLineKind.online, version: '3.3.0'),
          ),
          actions: HomeActions(onOpenLauncherUpdate: () => opened++),
        ),
      );
      expect(find.text(g.launcherOnline('3.3.0')), findsOneWidget);
      expect(find.text(he.launcherUpdate.installButton), findsNothing);
      await tester.tap(find.text(g.launcherDetailsLink));
      expect(opened, 1);
    });

    testWidgets('גרסה שכבר בכונן: הקישור לדף הכלי, וחסום בזמן משימה', (
      tester,
    ) async {
      var opened = 0;
      const ready = LauncherLine(LauncherLineKind.ready, version: '3.3.0');
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(ready),
          actions: HomeActions(onOpenLauncherUpdate: () => opened++),
        ),
      );
      expect(find.text(g.launcherOnDrive('3.3.0')), findsOneWidget);
      // ההתקנה עצמה בדף הכלי, לא בשורה שבבית.
      expect(find.text(he.launcherUpdate.installButton), findsNothing);
      await tester.tap(find.text(g.launcherDetailsLink));
      expect(opened, 1);

      await pumpScreen(
        tester,
        HomePage(model: withLauncher(ready, busy: true)),
      );
      expect(
        tester
            .widget<TextLink>(
              find.widgetWithText(TextLink, g.launcherDetailsLink),
            )
            .onTap,
        isNull,
      );
    });

    testWidgets('בלי קובץ הרצה להחלפה: הקישור לדף הכלי, בלי כפתור התקנה', (
      tester,
    ) async {
      var opened = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(
            const LauncherLine(LauncherLineKind.readyManual, version: '3.3.0'),
          ),
          actions: HomeActions(onOpenLauncherUpdate: () => opened++),
        ),
      );
      expect(find.text(g.launcherOnDrive('3.3.0')), findsOneWidget);
      expect(find.text(he.launcherUpdate.installButton), findsNothing);
      await tester.tap(find.text(g.launcherDetailsLink));
      expect(opened, 1);
    });

    testWidgets('אין מה לומר על הכלי — אין שורה; "נבדק ב-" עם רמז Ctrl+R', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: withLauncher(null)));
      expect(find.byKey(ShellKeys.launcherLine), findsNothing);
      expect(find.text(g.checkedAt('09:05')), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byKey(ShellKeys.checkedAt)).message,
        g.recheckHint,
      );
      expect(find.text(g.drive('E:')), findsOneWidget);
    });

    testWidgets('"בדוק עכשיו" תמיד ליד "נבדק ב-", ומפעיל את הבדיקה', (
      tester,
    ) async {
      var checks = 0;
      // מצב "עדכון כאן" — בלי "בדוק שוב" בגיבור, ובלי רשת שנבדקה.
      final here = homeScenario('offline');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: here.guidance,
            installedVersion: '0.10.3',
            checkedAt: DateTime(2026, 10, 23, 9, 5),
          ),
          actions: HomeActions(onRecheck: () => checks++),
        ),
      );
      expect(find.text(g.recheckButton), findsNothing);
      final link = find.byKey(ShellKeys.checkNow);
      expect(link, findsOneWidget);
      // באותה שורה עם "נבדק ב-".
      expect(
        tester.getCenter(link).dy,
        closeTo(tester.getCenter(find.byKey(ShellKeys.checkedAt)).dy, 2),
      );
      await tester.tap(link);
      expect(checks, 1);
    });

    testWidgets('בזמן "בדוק עכשיו" — מחוון במקום הקישור', (tester) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('offline').guidance,
            checkingNow: true,
          ),
        ),
      );
      final slot = find.byKey(ShellKeys.checkNow);
      expect(
        find.descendant(
          of: slot,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text(g.checkNowLink), findsNothing);
    });

    testWidgets(
        'משימה שחוסמת את הבדיקה (ייצוא, סנכרון) — אין קישור, ו"בדוק שוב" מושבת',
        (tester) async {
      var checks = 0;
      final uptodate = homeScenario('uptodate');
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: uptodate.guidance,
            installedVersion: uptodate.installedVersion,
            checkedAt: DateTime(2026, 10, 23, 9, 5),
            checkBlocked: true,
          ),
          actions: HomeActions(onRecheck: () => checks++),
        ),
      );
      expect(uptodate.guidance.primary, isNot(GuidancePrimary.taskInProgress));
      expect(find.byKey(ShellKeys.checkNow), findsNothing);
      expect(
        tester
            .widget<ActionButton>(find.byKey(ShellKeys.heroSecondary))
            .onPressed,
        isNull,
      );
      expect(checks, 0);
    });

    testWidgets('בזמן משימה אין "בדוק עכשיו", ו"פרטים ועדכון" מושבת', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(
            const LauncherLine(LauncherLineKind.online, version: '3.3.0'),
            busy: true,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.checkNow), findsNothing);
      expect(
        tester
            .widget<TextLink>(
              find.widgetWithText(TextLink, g.launcherDetailsLink),
            )
            .onTap,
        isNull,
      );
    });

    testWidgets('בלי שורת כלי, המטא נשאר בקצה הסוף (כמו `.selfupd` ריק)', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: withLauncher(null)));
      final hero = tester.getRect(find.byKey(ShellKeys.hero));
      final drive = tester.getRect(find.byKey(ShellKeys.driveLine));
      // RTL: סוף השורה הוא השמאל.
      expect(drive.left, closeTo(hero.left, 1));
    });

    testWidgets('גרסת הכלי מוצגת בלי v', (tester) async {
      await pumpScreen(
        tester,
        HomePage(
          model: withLauncher(
            const LauncherLine(LauncherLineKind.online, version: 'v3.3.0'),
          ),
        ),
      );
      expect(find.text(g.launcherOnline('3.3.0')), findsOneWidget);
    });
  });

  group('מסך הפתיחה', () {
    testWidgets('כפתור השפה מציג את השפה האחרת ומחליף אותה', (tester) async {
      var toggles = 0;
      for (final language in AppLanguage.values) {
        await pumpScreen(
          tester,
          HomePage(
            model: homeScenario('first'),
            actions: HomeActions(onToggleLanguage: () => toggles++),
          ),
          language: language,
        );
        final s = stringsOf(language).settings;
        final other = language == AppLanguage.hebrew
            ? s.languageEnglish
            : s.languageHebrew;
        expect(
          tester
              .widget<ActionButton>(find.byKey(ShellKeys.welcomeLanguage))
              .text,
          other,
        );
        await tester.tap(find.byKey(ShellKeys.welcomeLanguage));
      }
      expect(toggles, 2);
    });

    testWidgets('בכונן מחובר הורדה; בלי אינטרנט — עזרה', (tester) async {
      final calls = <String>[];
      final actions = HomeActions(
        onDownload: () => calls.add('download'),
        onHelp: () => calls.add('help'),
      );
      for (final name in ['first', 'firstOffline']) {
        await pumpScreen(
          tester,
          HomePage(model: homeScenario(name), actions: actions),
        );
        await tester.tap(find.byKey(ShellKeys.welcomePrimary));
      }
      expect(calls, ['download', 'help']);
    });
  });

  group('המדים קוראים רק מ-progress', () {
    late Directory tempDir;
    late OtzariaModuleController otzaria;
    late LibraryModuleController library;
    late PluginsModuleController plugins;
    late LauncherUpdateController launcher;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('home_page_test');
      otzaria = OtzariaModuleController(dataDir: tempDir.path);
      library = LibraryModuleController(dataDir: tempDir.path);
      plugins = PluginsModuleController(mirrorRootDir: tempDir.path);
      launcher = LauncherUpdateController(dataDir: tempDir.path);
    });

    tearDown(() {
      otzaria.dispose();
      library.dispose();
      plugins.dispose();
      launcher.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Widget progress(HomeTask task) => HomeTaskProgress(
          task: task,
          otzaria: otzaria,
          library: library,
          plugins: plugins,
        );

    testWidgets('החלת ספרייה, הורדת תוכנה והורדת הכלי — בלי שינוי מצב', (
      tester,
    ) async {
      library.status = LibraryModuleStatus.updating;
      library.applyProgress = 0.1;
      otzaria.downloadStatus = OtzariaDownloadStatus.downloading;
      launcher.status = LauncherUpdateStatus.downloading;
      var stateNotifications = 0;
      void count() => stateNotifications++;
      library.addListener(count);
      otzaria.addListener(count);
      launcher.addListener(count);

      await pumpScreen(
        tester,
        Column(
          children: [
            progress(HomeTask.updatingLibrary),
            progress(HomeTask.downloading),
            LauncherDownloadPercent(controller: launcher),
          ],
        ),
      );
      expect(find.text('10%'), findsOneWidget);

      library.applyProgress = 0.42;
      library.notifyProgress();
      otzaria.downloadReceived = 30;
      otzaria.downloadTotal = 100;
      otzaria.notifyProgress();
      launcher.downloadReceived = 70;
      launcher.downloadTotal = 100;
      launcher.notifyProgress();
      await tester.pump();

      expect(find.text('42%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(stateNotifications, 0);
    });

    testWidgets('הורדת הספרייה: שלב, שלב נלווה ובתים', (tester) async {
      library.downloadStatus = MirrorDownloadStatus.downloading;
      library.downloadStage = 'stage 1';
      library.downloadReceivedBytes = 10;
      library.downloadTotalBytes = 100;
      var stateNotifications = 0;
      library.addListener(() => stateNotifications++);

      await pumpScreen(tester, progress(HomeTask.downloading));
      expect(find.text('stage 1'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);

      library.downloadStage = 'stage 2';
      library.downloadCompanionStage = 'companion 2';
      library.downloadReceivedBytes = 2048;
      library.downloadTotalBytes = 4096;
      library.notifyProgress();
      await tester.pump();

      expect(find.text('stage 2'), findsOneWidget);
      expect(find.text('companion 2'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text(formatBytesProgress(2048, 4096)!), findsOneWidget);
      expect(stateNotifications, 0);
    });

    testWidgets('סנכרון התוספים בתוך ההורדה', (tester) async {
      plugins.status = PluginsModuleStatus.syncing;
      plugins.syncMessage = 'sync 1';
      plugins.syncProgress = 0.2;
      var stateNotifications = 0;
      plugins.addListener(() => stateNotifications++);

      await pumpScreen(tester, progress(HomeTask.downloading));
      expect(find.text('sync 1'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);

      plugins.syncMessage = 'sync 2';
      plugins.syncProgress = 0.8;
      plugins.notifyProgress();
      await tester.pump();

      expect(find.text('sync 2'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(stateNotifications, 0);
    });

    testWidgets('עדכון ספרייה: מד עם השלב והאזהרה לא לנתק', (tester) async {
      library.status = LibraryModuleStatus.updating;
      library.stageText = 'verify (2/3)';
      library.applyProgress = 0.37;

      await pumpScreen(tester, progress(HomeTask.updatingLibrary));

      expect(find.byType(InfoProgressRow), findsOneWidget);
      expect(find.text('verify (2/3)'), findsOneWidget);
      expect(find.text('37%'), findsOneWidget);
      expect(find.text(he.home.doNotRemoveDriveWarning), findsOneWidget);
    });
  });

  group('launcherLineOf — מה שורת הכלי אומרת', () {
    late Directory tempDir;
    late LauncherUpdateController c;
    const release = LauncherRelease(
      tagName: 'v9.9.9',
      name: 'Otzaria Updates v9.9.9',
      assetName: 'x.exe',
      downloadUrl: 'https://example/x.exe',
      sizeBytes: 42 << 20,
    );

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('launcher_line_test');
      c = LauncherUpdateController(dataDir: tempDir.path);
    });

    tearDown(() {
      c.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('הכלי מעודכן — אין שורה', () {
      expect(launcherLineOf(c), isNull);
    });

    test('נמצאה גרסה ברשת — הצעה לפרטים, לא התקנה', () {
      c
        ..onlineRelease = release
        ..onlineCheckedAt = DateTime(2026, 8, 1);
      final line = launcherLineOf(c)!;
      expect(line.kind, LauncherLineKind.online);
      expect(line.version, '9.9.9');
    });

    // אחרי עדכון עצמי התיקייה מחזיקה את הגרסה שרצה — היא אינה "חדשה".
    test('גרסה ישנה בתיקייה אינה מוצגת כגרסה החדשה', () {
      c
        ..status = LauncherUpdateStatus.upToDate
        ..downloadedVersion = c.currentVersion
        ..onlineRelease = release;
      final line = launcherLineOf(c)!;
      expect(line.kind, LauncherLineKind.online);
      expect(line.version, '9.9.9');
    });

    test('גרסה שכבר בכונן — התקנה, וגם בלי רשת', () {
      c
        ..status = LauncherUpdateStatus.readyToInstall
        ..downloadedVersion = '9.9.9'
        ..canInstall = true;
      final line = launcherLineOf(c)!;
      expect(line.kind, LauncherLineKind.ready);
      expect(line.version, '9.9.9');
    });

    test('בלי נתיב לקובץ ההרצה — הסבר במקום התקנה', () {
      c
        ..status = LauncherUpdateStatus.readyToInstall
        ..downloadedVersion = '9.9.9'
        ..canInstall = false;
      expect(launcherLineOf(c)!.kind, LauncherLineKind.readyManual);
    });
  });

  group('displayVersion — גרסה כפי שהמשתמש רואה', () {
    test('בלי v ובלי build', () {
      expect(displayVersion('v0.9.98+801'), '0.9.98');
      expect(displayVersion('0.9.98'), '0.9.98');
    });

    test('build נשאר רק כשבלעדיו שתי הגרסאות נראות זהות', () {
      expect(displayVersion('0.9.98+801', other: '0.9.98+799'), '0.9.98+801');
      expect(displayVersion('v0.9.98+801', other: '0.9.98+799'), '0.9.98+801');
      expect(displayVersion('0.9.98+801', other: '0.9.97+801'), '0.9.98');
      expect(displayVersion('0.9.98+801', other: 'v0.9.98+801'), '0.9.98');
    });

    test('build בצד אחד בלבד — אותה גרסה (sameBuild), ולכן בלי סיומת', () {
      expect(displayVersion('0.9.98+801', other: '0.9.98'), '0.9.98');
      expect(displayVersion('0.9.98', other: '0.9.98+801'), '0.9.98');
      expect(displayVersion('v0.9.98+801', other: 'v0.9.98'), '0.9.98');
    });

    testWidgets('אותה גרסה בשני build-ים: השבב באריח מבחין ביניהם', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(
              const GuidanceFacts(
                otzariaStatus: AppStatusFact.updateAvailable,
                online: false,
              ),
            ),
            installedVersion: '0.9.98+799',
            driveAppVersion: '0.9.98+801',
            appTile: TileStatus.updateHere,
          ),
        ),
      );
      expect(find.text(g.chipAppUpdate('0.9.98+801')), findsOneWidget);
      expect(find.text(g.eyebrowOtzaria('0.9.98+799')), findsOneWidget);
    });
  });

  group('אריחים מול הגיבור', () {
    StatusChip chipOf(WidgetTester tester, ShellSection section) =>
        tester.widget<StatusChip>(
          find.descendant(
            of: find.byKey(ShellKeys.tile(section)),
            matching: find.byType(StatusChip),
          ),
        );

    testWidgets('מה שההורדה תביא — "חדש באינטרנט" עם סמל הורדה', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: homeScenario('downloadOnly')));
      expect(find.text(g.downloadTitle), findsOneWidget);
      for (final section in [
        ShellSection.otzaria,
        ShellSection.library,
        ShellSection.plugins,
      ]) {
        final chip = chipOf(tester, section);
        expect(chip.label, g.chipNewOnline, reason: section.name);
        expect(chip.kind, StatusKind.updateAvailable);
        expect(chip.icon, FluentIcons.arrow_download_16_regular);
      }
      expect(find.text(g.chipNotOnDrive), findsNothing);
    });

    testWidgets('בלי רשת: האריח מתאר את הכונן כרגיל', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('offline')));
      expect(find.text(g.chipNewOnline), findsNothing);
      expect(chipOf(tester, ShellSection.library).label, g.chipLibraryUpdate);
    });

    testWidgets('שבב "מעודכן" — וי פשוט, לא וי בעיגול', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('uptodate')));
      final chip = chipOf(tester, ShellSection.library);
      expect(chip.kind, StatusKind.ok);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(ShellKeys.tile(ShellSection.library)),
          matching: find.byIcon(FluentIcons.checkmark_16_filled),
        ),
      );
      expect(icon.size, 14);
    });

    testWidgets('החיצים באריחים מלאים, כמו במוקאפ', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('uptodate')));
      expect(find.byIcon(FluentIcons.chevron_left_20_filled), findsWidgets);
      expect(find.byIcon(FluentIcons.chevron_left_20_regular), findsNothing);
    });
  });

  group('הגיבור — ליטוש', () {
    testWidgets('"צריך בדיקה": הכפתור אומר לאיזה דף', (tester) async {
      final opened = <ShellSection>[];
      for (final (status, section, label) in [
        (
          const GuidanceFacts(libraryStatus: LibraryStatusFact.error),
          ShellSection.library,
          g.attentionLibraryButton,
        ),
        (
          const GuidanceFacts(otzariaStatus: AppStatusFact.error),
          ShellSection.otzaria,
          g.attentionAppButton,
        ),
      ]) {
        await pumpScreen(
          tester,
          HomePage(
            model: HomeViewModel(guidance: deriveHomeGuidance(status)),
            actions: HomeActions(onOpenSection: opened.add),
          ),
        );
        expect(primary(tester).text, label);
        await tester.tap(find.byKey(ShellKeys.heroPrimary));
        expect(opened.last, section);
      }
    });

    testWidgets('"בודק..." — מחוון פעילות בגיבור', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('checking')));
      expect(find.text(g.checkingTitle), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ShellKeys.heroChecking),
          matching: find.byType(AppProgressBar),
        ),
        findsOneWidget,
      );
      expect(find.byKey(ShellKeys.heroPrimary), findsNothing);
    });
  });

  group('מסך הפתיחה — מה עוד יש בכונן', () {
    testWidgets('תוכנות נוספות ודיווחים — קישורים, והודעות הכונן והבית', (
      tester,
    ) async {
      final opened = <ShellSection>[];
      await pumpScreen(
        tester,
        HomePage(
          model: homeScenario('firstWithApps'),
          actions: HomeActions(onOpenSection: opened.add),
        ),
      );
      expect(find.byKey(ShellKeys.welcome), findsOneWidget);
      expect(find.byKey(ShellKeys.readOnlyNotice), findsOneWidget);
      final links = find.byKey(ShellKeys.welcomeLinks);
      await tester.tap(
        find.descendant(of: links, matching: find.text(g.tileCustomApps)),
      );
      await tester.tap(
        find.descendant(of: links, matching: find.text(g.tileReports)),
      );
      expect(opened, [ShellSection.customApps, ShellSection.reports]);
    });

    testWidgets('בלי תוכנות ובלי דיווחים — אין שורת קישורים', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('first')));
      expect(find.byKey(ShellKeys.welcomeLinks), findsNothing);
    });

    testWidgets('כפתור השפה נשאר גם כשיש הודעת כונן, ומעליה', (tester) async {
      await pumpScreen(tester, HomePage(model: homeScenario('firstWithApps')));
      final language = find.byKey(ShellKeys.welcomeLanguage);
      expect(language, findsOneWidget);
      expect(
        tester.getRect(language).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(ShellKeys.readOnlyNotice)).top,
        ),
      );
    });

    testWidgets('הפעלה כמנהל והסבר הדיווחים מוצגים גם במסך הפתיחה', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: homeScenario('first').guidance,
            offersElevation: true,
            reportsIntro: true,
          ),
        ),
      );
      expect(find.byKey(ShellKeys.welcome), findsOneWidget);
      expect(find.byKey(ShellKeys.elevationBanner), findsOneWidget);
      expect(find.byKey(ShellKeys.reportsIntroNotice), findsOneWidget);
    });
  });
}
