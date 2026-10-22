import 'dart:async';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/app_report/launcher_crash_session.dart';
import 'package:launcher_app/src/controllers/app_reports_controller.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/launcher_update_flow.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/self_update/launcher_release.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/services/sleep_inhibitor.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/app_session.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/home_guidance_session.dart';
import 'package:launcher_app/src/shell/session_prompts.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:plugins_manager/plugins_manager.dart';

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

  AppSession session({bool readOnly = false, SleepInhibitor? sleep}) {
    final s = AppSession(
      dataDir: tempDir.path,
      stateDir: tempDir.path,
      settings: settings,
      prompts: prompts,
      readOnly: readOnly,
      runningLocator: const _NeverRunningLocator(),
      noticesStore:
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
      // בלי רשת אין גרסה חדשה של הכלי, ולכן גם אין הצעה להוריד אותה.
      expect(prompts.calls, isNot(contains('offerLauncherUpdate')));
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
      expect(prompts.calls, isNot(contains('offerLauncherUpdate')));
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
  Future<bool?> offerLauncherUpdate(
    LauncherRelease release,
    String? whatsNew,
  ) async {
    calls.add('offerLauncherUpdate');
    return false;
  }

  @override
  Future<void> showErrorReportsIntro() async => calls.add('intro');

  @override
  Future<bool?> showCrashPrompt(
    AppReportsController reports,
    CrashCandidate candidate,
  ) async =>
      false;

  @override
  Future<void> announcePlugins({
    required List<StorePlugin> fresh,
    required bool hasUpdates,
  }) async =>
      calls.add('announcePlugins');

  @override
  Future<bool?> offerElevation() async => false;

  @override
  Future<bool> confirmLauncherInstall(String version,
          {String? whatsNew}) async =>
      false;

  @override
  void notifyLauncherUpdate(LauncherUpdateNotice notice, String detail) {}

  @override
  Future<void> showAutoInstallSkipped() async =>
      calls.add('showAutoInstallSkipped');

  @override
  Future<bool> confirmCancelDownload() async => false;

  @override
  Future<bool> confirmSemanticSearch() async => false;

  @override
  Future<bool> confirmSemanticConsent() async => false;

  @override
  Future<bool> confirmLibraryReindex() async => false;

  @override
  void reportDownload({
    required List<MirrorComponent> failed,
    required List<MirrorComponent> skipped,
  }) {}

  @override
  Future<void> performReportOffer() async {}

  @override
  Future<void> uploadReports({
    required bool Function() isCancelled,
    required void Function(bool active) onActiveChanged,
    required void Function(bool uploading) onUploadingChanged,
  }) async {}
}
