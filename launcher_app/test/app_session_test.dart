import 'dart:async';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/app_report/launcher_crash_session.dart';
import 'package:launcher_app/src/controllers/app_reports_controller.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/launcher_update_flow.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/home/home_view_model.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/services/sleep_inhibitor.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/app_session.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/home_guidance_session.dart';
import 'package:launcher_app/src/shell/session_prompts.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SettingsController settings;
  late _FakePrompts prompts;
  final sessions = <AppSession>[];

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('app_session_test');
    await AppLogger.init(tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
    await settings.update(const AppSettings(autoCheckUpdates: false));
    prompts = _FakePrompts();
  });

  tearDown(() async {
    for (final s in sessions) {
      s.dispose();
    }
    sessions.clear();
    LauncherCrashSession.resetForTest();
    settings.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  AppSession session({
    bool readOnly = false,
    SleepInhibitor? sleep,
    NoticesSeenStore? notices,
  }) {
    final s = AppSession(
      dataDir: tempDir.path,
      stateDir: tempDir.path,
      settings: settings,
      prompts: prompts,
      readOnly: readOnly,
      runningLocator: const _NeverRunningLocator(),
      noticesStore: notices ??
          MemoryNoticesStore(seen: {NoticesSeenStore.errorReportsIntro}),
      sleepInhibitor: sleep,
    );
    sessions.add(s);
    return s;
  }

  Future<void> waitFor(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  group('הודעות הבית במקום דיאלוגים בעלייה', () {
    test('ההסבר על הדיווחים: הודעה עד "הבנתי", ורק אז נרשם', () async {
      final notices = MemoryNoticesStore();
      final s = session(notices: notices)..start();
      await waitFor(() => s.showsReportsIntro);
      expect(s.showsReportsIntro, isTrue);
      expect(notices.marked, isEmpty);

      await s.dismissReportsIntro();
      expect(s.showsReportsIntro, isFalse);
      expect(notices.marked, [NoticesSeenStore.errorReportsIntro]);
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
    });

    test('ההסבר שכבר הוצג במחשב הזה אינו חוזר', () async {
      final s = session()..start();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      expect(s.showsReportsIntro, isFalse);
    });

    test('כונן לקריאה בלבד אינו סופר דיווחים לאיסוף', () async {
      final s = session(readOnly: true);
      await s.recountReportsToCollect();
      expect(s.reportsToCollect, 0);
    });

    test('בלי בעיית הרשאות אין פס "הפעלה מחדש כמנהל"', () {
      expect(session().offersElevation, isFalse);
    });

    // נגזר מהמצב הנוכחי — לא מדגל שנלכד בכשל.
    test('canRestartElevated עוקב אחרי הקונטרולרים, ו"לא עכשיו" רק בבית', () {
      final s = session();
      expect(s.canRestartElevated, isFalse);
      s.library.needsElevation = true;
      expect(s.canRestartElevated, Platform.isWindows);
      s.dismissElevation();
      expect(s.offersElevation, isFalse);
      expect(s.canRestartElevated, Platform.isWindows);
      s.library.status = LibraryModuleStatus.updating;
      expect(s.canRestartElevated, isFalse);
      s.library.status = LibraryModuleStatus.upToDate;
      s.library.needsElevation = false;
      expect(s.canRestartElevated, isFalse);
    });

    test('בלי קטלוג אין תוספים חדשים לפס, והביקור אינו נכשל', () async {
      final s = session();
      expect(s.newPluginsForHome, isEmpty);
      await s.markPluginsVisited();
    });
  });

  group('checkOnline', () {
    setUp(() => HttpOverrides.global = NoNetworkHttpOverrides());
    tearDown(() => HttpOverrides.global = null);

    test('בודק את ארבעת המודולים, ומדליק את הדגל רק בזמן הבדיקה', () async {
      final s = session();
      final flags = <bool>[];
      s.addListener(() => flags.add(s.isCheckingOnline));

      await s.checkOnline();

      expect(s.otzaria.onlineCheckedAt, isNotNull);
      expect(s.library.onlineCheckedAt, isNotNull);
      expect(s.plugins.onlineCheckedAt, isNotNull);
      expect(s.launcherUpdate.onlineCheckedAt, isNotNull);
      expect(flags.first, isTrue);
      expect(s.isCheckingOnline, isFalse);
      expect(s.lastCheckedAt, isNotNull);
      // בלי רשת אין גרסה חדשה של הכלי, ולכן גם אין שאלה על התקנה.
      expect(prompts.calls, isNot(contains('confirmLauncherInstall')));
    });

    test('כונן לקריאה בלבד: אינו בודק כלום ואינו מודיע', () async {
      final s = session(readOnly: true);
      var notified = 0;
      s.addListener(() => notified++);

      await s.checkOnline();

      expect(s.otzaria.onlineCheckedAt, isNull);
      expect(s.library.onlineCheckedAt, isNull);
      expect(s.plugins.onlineCheckedAt, isNull);
      expect(s.launcherUpdate.onlineCheckedAt, isNull);
      expect(notified, 0);
    });
  });

  group('checkNow', () {
    setUp(() => HttpOverrides.global = NoNetworkHttpOverrides());
    tearDown(() => HttpOverrides.global = null);

    // checkAll מחכה לפריים (ההצעות שאחרי הבדיקה), ולכן רץ עם פריימים. כל
    // התרחישים בבדיקה אחת: בדיקת הספרייה זוכרת מצב סטטי בין אזורי זמן מדומה.
    testWidgets('מקומית ואז ברשת; כונן מוגן — מקומית; בלי כפילות; העלייה נחשבת',
        (tester) async {
      Future<void> drive(bool Function() done) async {
        for (var i = 0; i < 300 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> finish(Future<void> run) async {
        var done = false;
        unawaited(run.whenComplete(() => done = true));
        await drive(() => done);
        expect(done, isTrue);
      }

      // מקומית ואז ברשת, מחוון רק בזמן הבדיקה, ולחיצה שנייה אינה מוסיפה.
      final s = session();
      var starts = 0;
      DateTime? localFirst;
      var was = false;
      s.addListener(() {
        if (s.isCheckingOnline && !was) {
          starts++;
          localFirst ??= s.lastCheckedAt;
        }
        was = s.isCheckingOnline;
      });
      final run = s.checkNow();
      expect(s.isCheckingNow, isTrue);
      await finish(s.checkNow());
      await finish(run);
      expect(starts, 1);
      expect(localFirst, isNotNull);
      expect(s.otzaria.onlineCheckedAt, isNotNull);
      expect(s.isCheckingNow, isFalse);

      // כונן מוגן: "בדוק שוב" בודק מקומית בלבד — לא כלום, ולא ברשת.
      final locked = session(readOnly: true);
      var lockedOnline = false;
      locked.addListener(() => lockedOnline |= locked.isCheckingOnline);
      final lockedRun = locked.checkNow();
      expect(locked.isCheckingNow, isTrue);
      await finish(lockedRun);
      expect(locked.lastCheckedAt, isNotNull);
      expect(lockedOnline, isFalse);
      expect(locked.otzaria.onlineCheckedAt, isNull);

      // הבדיקה המקומית שבעלייה נחשבת בדיקה רצה.
      await tester.runAsync(
        () => settings.update(const AppSettings(autoCheckUpdates: true)),
      );
      final started = session()..start();
      expect(started.isCheckingNow, isTrue);
      await drive(() => !started.isCheckingNow);
      expect(started.isCheckingNow, isFalse);
      expect(started.lastCheckedAt, isNotNull);
      await drive(() => started.plugins.status != PluginsModuleStatus.loading);
    });

    test('משימה ארוכה (ייצוא) חוסמת: אין בדיקה, והבית רואה את אותו תנאי',
        () async {
      final s = session();
      s.plugins.isExporting = true;
      expect(s.checkNowBlocked, isTrue);
      expect(homeViewModelOf(s).checkBlocked, isTrue);

      await s.checkNow();

      expect(s.lastCheckedAt, isNull);
      expect(s.isCheckingNow, isFalse);
      s.plugins.isExporting = false;
      expect(homeViewModelOf(s).checkBlocked, isFalse);
    });

    test('הבית מקבל את הערוץ כשממתינים לגרסה חדשה יותר בערוץ שנבחר', () {
      final s = session();
      s.otzaria
        ..status = OtzariaModuleStatus.installedIsNewer
        ..awaitsNewerInSelectedChannel = true;
      expect(
        homeViewModelOf(s).appAwaitsNewerStable,
        !s.otzaria.preferPrerelease,
      );

      s.otzaria.awaitsNewerInSelectedChannel = false;
      expect(homeViewModelOf(s).appAwaitsNewerStable, isNull);
    });
  });

  group('בדיקת המראה בעלייה', () {
    test('רצה גם כשבדיקת העדכונים האוטומטית כבויה', () async {
      final s = session()..start();
      await waitFor(() => s.launcherUpdate.status != LauncherUpdateStatus.idle);
      expect(s.launcherUpdate.status, isNot(LauncherUpdateStatus.idle));
      expect(LauncherCrashSession.closeGuard, s.confirmClose);
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
    });

    test('כונן לקריאה בלבד: אינה רצה', () async {
      final s = session(readOnly: true)..start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(s.launcherUpdate.status, LauncherUpdateStatus.idle);
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
    });

    test('הפירוק מסיר את שומר הסגירה', () async {
      final s = session()..start();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      sessions.remove(s);
      s.dispose();
      expect(LauncherCrashSession.closeGuard, isNull);
    });
  });

  group('דגלי משימה ארוכה', () {
    test('עדכון ספרייה והתקנת אוצריא חוסמים יציאה וסנכרון', () {
      final s = session();
      expect(s.longTaskRunning, isFalse);
      expect(s.exitWouldInterrupt, isFalse);
      expect(s.pluginSyncBlockedElsewhere, isFalse);
      expect(s.exitPending, isFalse);

      s.library.status = LibraryModuleStatus.updating;
      expect(s.longTaskRunning, isTrue);
      expect(s.exitWouldInterrupt, isTrue);
      expect(s.pluginSyncBlockedElsewhere, isTrue);

      s.library.status = LibraryModuleStatus.upToDate;
      s.otzaria.status = OtzariaModuleStatus.installing;
      expect(s.longTaskRunning, isTrue);
      expect(s.pluginSyncBlockedElsewhere, isTrue);

      s.otzaria.status = OtzariaModuleStatus.upToDate;
      expect(s.longTaskRunning, isFalse);
    });

    test('החלפת קובץ ההרצה היא exitPending וחלק ממשימה ארוכה', () {
      final s = session();
      s.launcherUpdate.status = LauncherUpdateStatus.installing;
      expect(s.exitPending, isTrue);
      expect(s.longTaskRunning, isTrue);
      expect(s.pluginSyncBlockedElsewhere, isFalse);
    });

    test('Ctrl+R/F5 לא רצים כשמסך משימה רץ, גם בלי משימה ארוכה', () async {
      final s = session();
      s.tasks.prepareDownload();
      expect(s.longTaskRunning, isFalse);
      // חוזר מיד, בלי לבדוק דבר — אחרת `_markChecked` היה רושם בדיקה.
      await s.refreshFromKeyboard();
      expect(s.lastCheckedAt, isNull);
      expect(s.otzaria.status, isNot(OtzariaModuleStatus.checking));
    });

    test('"הורדה" בלי בחירה בהגדרות — הודעה ומעבר להגדרות, בלי "מתכונן"',
        () async {
      final s = session();
      await settings.update(settings.settings.copyWith(
        syncApp: false,
        syncPlugins: false,
        syncLibrary: false,
        personalUpdateMode: false,
      ));
      expect(s.settings.settings.hasSyncSelection, isFalse);
      await s.downloadAll();
      expect(prompts.calls, ['noSyncSelection']);
      expect(s.tasks.hasTask, isFalse);

      // גם מ"נסה שוב" במסך שהסתיים: המסך נשאר, וההודעה מסבירה למה.
      prompts.calls.clear();
      s.tasks
        ..prepareDownload()
        ..downloadFailed(const DownloadFailure(DownloadFailureKind.other));
      await s.downloadAll();
      expect(prompts.calls, ['noSyncSelection']);
      expect(
          (s.tasks.current! as DownloadTask).phase, DownloadTaskPhase.failed);
    });

    test('"הורדה" בזמן שמשימה אחרת רצה — לא נפתח "מתכונן" שנסגר בשקט', () {
      final s = session();
      s.otzaria.status = OtzariaModuleStatus.installing;
      unawaited(s.downloadAll());
      expect(s.tasks.hasTask, isFalse);
    });

    test(
        '"ביטול", "הורדה" ו"ביטול" שוב — הבקשה שבוטלה לא סוגרת את המסך '
        'החדש, והביטול השני נשמר', () async {
      final s = session();
      final abandoned = s.downloadAll();
      s.abandonPreparingDownload();
      expect(s.tasks.hasTask, isFalse);

      final again = s.downloadAll();
      expect(s.tasks.hasTask, isTrue);
      s.abandonPreparingDownload();
      expect(s.tasks.hasTask, isFalse);

      await abandoned;
      await again;
      expect(s.tasks.hasTask, isFalse);
      expect(s.longTaskRunning, isFalse);
    });

    test('שומר הסגירה שואל רק בזמן משימה, ומכבד את התשובה', () async {
      final s = session();
      expect(await s.confirmClose(), isTrue);
      expect(prompts.calls, isEmpty);

      s.otzaria.status = OtzariaModuleStatus.installing;
      prompts.closeAnswer = false;
      expect(await s.confirmClose(), isFalse);
      prompts.closeAnswer = true;
      expect(await s.confirmClose(), isTrue);
      expect(prompts.calls, ['confirmClose', 'confirmClose']);
      expect(prompts.closeDownloading, [false, false]);
    });
  });

  group('ההכוונה רואה כל משימה ארוכה', () {
    setUp(() => HttpOverrides.global = NoNetworkHttpOverrides());
    tearDown(() => HttpOverrides.global = null);

    GuidancePrimary primary(AppSession s) =>
        deriveHomeGuidance(guidanceFactsFromSession(s)).primary;

    test('ייצוא, תוכנה מותאמת והחלפת קובץ ההרצה', () {
      final s = session();
      expect(primary(s), isNot(GuidancePrimary.taskInProgress));

      s.plugins.isExporting = true;
      expect(primary(s), GuidancePrimary.taskInProgress);
      s.plugins.isExporting = false;

      s.customApps.isLearning = true;
      expect(primary(s), GuidancePrimary.taskInProgress);
      s.customApps.isLearning = false;

      s.customApps.downloadAllTotal = 2;
      expect(primary(s), GuidancePrimary.taskInProgress);
      s.customApps.downloadAllTotal = null;

      s.launcherUpdate.status = LauncherUpdateStatus.installing;
      expect(primary(s), GuidancePrimary.taskInProgress);
    });

    test('סנכרון החנות', () async {
      final s = session();
      final run = s.plugins.sync();
      expect(s.plugins.isSyncing, isTrue);
      expect(primary(s), GuidancePrimary.taskInProgress);
      try {
        await run;
      } catch (_) {}
      expect(s.plugins.isSyncing, isFalse);
    });
  });

  group('אחרי פירוק הסשן אינו מודיע', () {
    setUp(() => HttpOverrides.global = NoNetworkHttpOverrides());
    tearDown(() => HttpOverrides.global = null);

    // notifyListeners אחרי dispose זורק ב-debug. הקונטרולרים עצמם עוד מודיעים
    // אחרי פירוק (כמו לפני החילוץ), ולכן נבדקות רק השגיאות של הסשן.
    Future<List<String>> sessionErrors(
      Future<void> Function(AppSession s) body,
    ) async {
      final errors = <String>[];
      final done = Completer<void>();
      unawaited(runZonedGuarded(
        () async {
          final s = session();
          sessions.remove(s);
          try {
            await body(s);
          } catch (error) {
            errors.add('$error');
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
          done.complete();
        },
        (error, _) => errors.add('$error'),
      ));
      await done.future;
      return errors.where((e) => e.contains('AppSession')).toList();
    }

    test('פירוק באמצע checkOnline', () async {
      final errors = await sessionErrors((s) async {
        final check = s.checkOnline();
        s.dispose();
        await check;
      });
      expect(errors, isEmpty);
      expect(prompts.calls, isNot(contains('confirmLauncherInstall')));
    });

    test('פירוק מיד אחרי start', () async {
      final errors = await sessionErrors((s) async {
        s
          ..start()
          ..dispose();
      });
      expect(errors, isEmpty);
      expect(LauncherCrashSession.closeGuard, isNull);
    });
  });

  test('מניעת שינה רק בזמן עבודה', () {
    var acquired = 0;
    var released = 0;
    final inhibitor = SleepInhibitor(acquire: () {
      acquired++;
      return () => released++;
    });
    final s = session(sleep: inhibitor);

    s.otzaria.status = OtzariaModuleStatus.upToDate;
    s.otzaria.notifyListeners();
    expect(acquired, 0);

    s.library.downloadStatus = MirrorDownloadStatus.downloading;
    s.library.notifyListeners();
    expect(inhibitor.isActive, isTrue);
    s.library.downloadStatus = MirrorDownloadStatus.done;
    s.library.notifyListeners();
    expect(inhibitor.isActive, isFalse);

    s.otzaria.status = OtzariaModuleStatus.installing;
    s.otzaria.notifyListeners();
    expect(inhibitor.isActive, isTrue);
    s.otzaria.status = OtzariaModuleStatus.upToDate;
    s.otzaria.notifyListeners();
    expect(inhibitor.isActive, isFalse);
    expect((acquired, released), (2, 2));

    s.launcherUpdate.status = LauncherUpdateStatus.downloading;
    s.launcherUpdate.notifyListeners();
    expect(inhibitor.isActive, isTrue);
    sessions.remove(s);
    s.dispose();
    expect(inhibitor.isActive, isFalse);
    expect((acquired, released), (3, 3));
  });
}

class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}

class _FakePrompts implements SessionPrompts {
  final calls = <String>[];
  bool closeAnswer = true;
  final closeDownloading = <bool>[];

  @override
  Future<T?> runDialog<T>(Future<T> Function() body, {bool forever = false}) =>
      body();

  @override
  Future<bool> confirmClose({required bool downloading}) async {
    calls.add('confirmClose');
    closeDownloading.add(downloading);
    return closeAnswer;
  }

  @override
  Future<bool?> showCrashPrompt(
    AppReportsController reports,
    CrashCandidate candidate,
  ) async =>
      false;

  @override
  Future<bool> confirmLauncherInstall(String version,
      {String? whatsNew}) async {
    calls.add('confirmLauncherInstall');
    return false;
  }

  @override
  void notifyLauncherUpdate(LauncherUpdateNotice notice, String detail) {}

  @override
  Future<bool> confirmCancelDownload() async => false;

  @override
  void notifyNoSyncSelection() => calls.add('noSyncSelection');

  @override
  Future<bool> confirmSemanticConsent() async => false;

  @override
  Future<bool> confirmLibraryReindex() async => false;

  @override
  Future<void> uploadReports({
    required bool Function() isCancelled,
    required void Function(bool active) onActiveChanged,
    required void Function(bool uploading) onUploadingChanged,
  }) async {}
}
