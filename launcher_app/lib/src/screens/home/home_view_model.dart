import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart'
    show OtzariaUpdateCheckResult;
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart' show PluginsOnlineStatus;

import '../../controllers/launcher_update_controller.dart';
import '../../controllers/library_module_controller.dart';
import '../../controllers/otzaria_module_controller.dart';
import '../../shell/app_session.dart';
import '../../shell/home_guidance.dart';
import '../../shell/home_guidance_session.dart';

/// מה רץ כשהגיבור במצב `taskInProgress`.
enum HomeTask { downloading, installingApp, updatingLibrary, other }

enum LauncherLineKind { online, ready, readyManual, downloading, error }

/// שורת העדכון של הכלי עצמו בתחתית הבית.
class LauncherLine {
  const LauncherLine(this.kind, {this.version, this.error});

  final LauncherLineKind kind;
  final String? version;
  final String? error;
}

/// כל מה שדף הבית מציג, בלי קונטרולרים — כך כל מצב נבנה בבדיקה ובצילום.
class HomeViewModel {
  const HomeViewModel({
    required this.guidance,
    this.online,
    this.installedVersion,
    this.driveAppVersion,
    this.appAwaitsNewerStable,
    this.onlineAppVersion,
    this.driveLibraryVersion,
    this.driveCompanionNames,
    this.onlineLibraryVersion,
    this.onlineCompanionNames,
    this.pluginUpdatesOnDrive = 0,
    this.onlinePluginChanges = 0,
    this.onlinePluginCatalogChanged = false,
    this.onlineStoreApp = false,
    this.syncApp = true,
    this.syncLibrary = true,
    this.syncPlugins = true,
    this.libraryDownloadFailed = false,
    this.appTile = TileStatus.upToDate,
    this.libraryTile = TileStatus.upToDate,
    this.pluginsTile = TileStatus.upToDate,
    this.pluginsOnDrive = 0,
    this.pluginsInstalled = 0,
    this.customApps = 0,
    this.customAppsPending = 0,
    this.customAppsUnannounced = false,
    this.reportsToSend = 0,
    this.reportsToCollect = 0,
    this.toolReportsPending = 0,
    this.reportsSending = false,
    this.reportsIntro = false,
    this.autoInstallSkipped = false,
    this.offersElevation = false,
    this.legacyReportsNotice = false,
    this.newPlugins = const [],
    this.canLaunch = false,
    this.task = HomeTask.other,
    this.isCheckingOnline = false,
    this.checkingNow = false,
    this.checkBlocked = false,
    this.launcher,
    this.checkedAt,
    this.driveName,
  });

  final HomeGuidance guidance;

  /// `null` = עוד לא נבדק אם יש אינטרנט.
  final bool? online;
  final String? installedVersion;
  final String? driveAppVersion;

  /// מותקנת גרסה חדשה מהערוץ שנבחר, וממתינים לגרסה חדשה יותר בו: `true`
  /// לערוץ היציב. `null` כשזה לא המצב.
  final bool? appAwaitsNewerStable;
  final String? onlineAppVersion;
  final String? driveLibraryVersion;

  /// בכונן יש רק קבצים נלווים לספרייה, בלי גרסת מסד חדשה.
  final String? driveCompanionNames;
  final String? onlineLibraryVersion;
  final String? onlineCompanionNames;
  final int pluginUpdatesOnDrive;

  /// תוספים חדשים, מעודכנים או חסרים בכונן לפי האתר.
  final int onlinePluginChanges;

  /// באתר השתנתה רק רשימת התוספים (למשל תוסף שהוסר).
  final bool onlinePluginCatalogChanged;

  /// באתר יש גרסה חדשה של חנות התוספים שבאוצריא.
  final bool onlineStoreApp;
  final bool syncApp;
  final bool syncLibrary;
  final bool syncPlugins;
  final bool libraryDownloadFailed;
  final TileStatus appTile;
  final TileStatus libraryTile;
  final TileStatus pluginsTile;
  final int pluginsOnDrive;
  final int pluginsInstalled;

  /// כמה תוכנות נוספות בכונן; 0 — אין אריח.
  final int customApps;
  final int customAppsPending;

  /// יש ממתינה שהמחשב הזה עוד לא ראה בדף שלה.
  final bool customAppsUnannounced;
  final int reportsToSend;
  final int reportsToCollect;

  /// דיווחים של הכלי עצמו שממתינים בתור — נשלחים מדף הדיווחים.
  final int toolReportsPending;
  final bool reportsSending;
  final bool reportsIntro;
  final bool autoInstallSkipped;
  final bool offersElevation;

  /// בכונן תורי דיווחים ישנים (Hive) שלא הועברו — הסבר עד "הבנתי".
  final bool legacyReportsNotice;
  final List<String> newPlugins;
  final bool canLaunch;
  final HomeTask task;
  final bool isCheckingOnline;

  /// "בדוק עכשיו" רץ (מקומית ואז ברשת) — מחוון במקום הקישור.
  final bool checkingNow;

  /// משימה ארוכה חוסמת את "בדוק עכשיו" — `AppSession.checkNowBlocked`.
  final bool checkBlocked;

  /// `null` — אין מה לומר על הכלי עצמו.
  final LauncherLine? launcher;
  final DateTime? checkedAt;

  /// "E:" — שם הכונן שהכלי רץ ממנו, כשיש כזה.
  final String? driveName;

  bool get readOnly => guidance.readOnly;
  bool get driveFull => guidance.driveFull;

  /// גם בכונן מוגן: הדיווחים שבו נאמרים, אף שאי אפשר לשלוח אותם מכאן.
  bool get showsReportsTile =>
      reportsToSend > 0 ||
      reportsToCollect > 0 ||
      toolReportsPending > 0 ||
      reportsSending;

  bool get showsNewPlugins =>
      newPlugins.isNotEmpty &&
      installedVersion != null &&
      guidance.primary != GuidancePrimary.welcome;
}

/// בונה את המודל מהסשן. נקרא בכל בנייה של הבית — הכול כאן קריאת שדות.
HomeViewModel homeViewModelOf(AppSession s) {
  final facts = guidanceFactsFromSession(s);
  final otzaria = s.otzaria;
  final library = s.library;
  final plugins = s.plugins;
  final settings = s.settings.settings;
  final pluginChanges = onlinePluginChangesOf(plugins.onlineStatus);
  final customApps = s.customApps;

  final guidance = deriveHomeGuidance(facts);
  TileStatus tile(GuidanceItem item) =>
      deriveTileStatus(item, facts, download: guidance.downloadItems);

  return HomeViewModel(
    guidance: guidance,
    online: facts.online,
    installedVersion: otzaria.currentVersion,
    driveAppVersion: otzaria.latestVersion,
    appAwaitsNewerStable:
        otzaria.awaitsNewerInSelectedChannel ? !otzaria.preferPrerelease : null,
    onlineAppVersion:
        otzaria.hasOnlineUpdate ? otzaria.onlineUpdateVersion : null,
    driveLibraryVersion: library.companionsOnly || library.targetVersion == null
        ? null
        : '${library.targetVersion}',
    driveCompanionNames:
        library.companionsOnly ? library.pendingCompanionNames : null,
    onlineLibraryVersion:
        library.hasOnlineLibraryUpdate && library.onlineUpdateVersion != null
            ? '${library.onlineUpdateVersion}'
            : null,
    onlineCompanionNames: library.onlinePendingCompanions.isNotEmpty ||
            library.onlineSemanticPending
        ? library.onlinePendingCompanionNames
        : null,
    pluginUpdatesOnDrive: facts.pluginUpdatesOnDrive,
    onlinePluginChanges: plugins.hasCatalogOnlineUpdate ? pluginChanges : 0,
    onlinePluginCatalogChanged:
        plugins.hasCatalogOnlineUpdate && pluginChanges == 0,
    onlineStoreApp: plugins.storeAppOnline != null,
    syncApp: settings.syncApp,
    syncLibrary: settings.downloadsLibrary,
    syncPlugins: settings.syncPlugins,
    libraryDownloadFailed: library.downloadNeedsRetry && !s.isDownloading,
    appTile: tile(GuidanceItem.app),
    libraryTile: tile(GuidanceItem.library),
    pluginsTile: tile(GuidanceItem.plugins),
    pluginsOnDrive: plugins.plugins.length,
    pluginsInstalled: plugins.installedCount,
    customApps: customApps.apps.length,
    customAppsPending: customApps.pendingApps.length,
    customAppsUnannounced: customApps.unannouncedApps.isNotEmpty,
    reportsToSend: s.errorReports.outboxCount + s.searchFeedback.outboxCount,
    reportsToCollect: s.reportsToCollect,
    toolReportsPending: s.appReports?.pendingCount ?? 0,
    reportsSending: s.uploadingReports ||
        s.errorReports.isUploading ||
        s.searchFeedback.isUploading,
    reportsIntro: s.showsReportsIntro,
    autoInstallSkipped: s.autoInstallSkipped,
    offersElevation: s.offersElevation,
    legacyReportsNotice: s.showsLegacyReportsNotice,
    newPlugins: [for (final plugin in s.newPluginsForHome) plugin.name],
    canLaunch: otzaria.canLaunch,
    task: switch (s) {
      _ when s.isDownloading => HomeTask.downloading,
      _ when otzaria.status == OtzariaModuleStatus.installing =>
        HomeTask.installingApp,
      _
          when library.isApplying ||
              library.status == LibraryModuleStatus.updating =>
        HomeTask.updatingLibrary,
      _ => HomeTask.other,
    },
    isCheckingOnline: s.isCheckingOnline,
    checkingNow: s.isCheckingNow,
    checkBlocked: s.checkNowBlocked,
    launcher: s.readOnly ? null : launcherLineOf(s.launcherUpdate),
    checkedAt: s.lastCheckedAt,
    driveName: driveNameOf(s.dataDir),
  );
}

/// תוספים שההורדה תביא: חדשים, מעודכנים, וכאלה שהקובץ שלהם חסר בכונן. תוסף
/// שהוסר מהאתר אינו נספר — הוא רק משנה את הרשימה (`onlinePluginCatalogChanged`).
int onlinePluginChangesOf(PluginsOnlineStatus? s) =>
    s == null ? 0 : s.newCount + s.updatedCount + s.missingCount;

LauncherLine? launcherLineOf(LauncherUpdateController c) {
  if (c.isDownloading) return const LauncherLine(LauncherLineKind.downloading);
  if (c.hasUpdateReady) {
    return LauncherLine(
      c.canInstall ? LauncherLineKind.ready : LauncherLineKind.readyManual,
      version: c.downloadedVersion,
    );
  }
  if (c.status == LauncherUpdateStatus.error && c.errorMessage != null) {
    return LauncherLine(
      LauncherLineKind.error,
      version: c.onlineUpdateVersion,
      error: c.errorMessage,
    );
  }
  if (c.hasOnlineUpdate) {
    return LauncherLine(LauncherLineKind.online,
        version: c.onlineUpdateVersion);
  }
  return null;
}

/// גרסה כפי שהמשתמש רואה אותה: בלי "v" ובלי "+build". ה-build נשאר רק כש-[other]
/// (גרסה שמוצגת לצידה) זהה בלעדיו, ושתיהן נושאות build שונה (`sameBuild`).
String displayVersion(String version, {String? other}) {
  final core = OtzariaUpdateCheckResult.normalizeVersion(version);
  if (other == null ||
      OtzariaUpdateCheckResult.normalizeVersion(other) != core ||
      OtzariaUpdateCheckResult.sameBuild(version, other)) {
    return core;
  }
  return _withoutV(version);
}

String _withoutV(String version) {
  final v = version.trim();
  return v.startsWith('v') || v.startsWith('V') ? v.substring(1) : v;
}

/// "E:" מתוך נתיב בווינדוס; בשאר המערכות ובנתיב רשת — `null`.
String? driveNameOf(String dataDir) {
  if (!Platform.isWindows) return null;
  final root = p.windows.rootPrefix(dataDir);
  final match = RegExp(r'^([A-Za-z]:)').firstMatch(root);
  return match?.group(1)?.toUpperCase();
}
