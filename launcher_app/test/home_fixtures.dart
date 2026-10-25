// מצבי הבית של המוקאפ (`#scn=<name>`) כמודלים — לבדיקות הבית ולצילומי
// הסקירה. העובדות עוברות ב-`deriveHomeGuidance`, כך שהגיבור הוא מה שהמוצר
// היה מחליט, ולא מה שהבדיקה מניחה. אחרי מצבי המוקאפ — מצבים נוספים שאין
// להם מקבילה במוקאפ (בדיקה, הורדה בלבד, כונן ריק עם תוכנות נוספות).

import 'package:launcher_app/src/screens/home/home_view_model.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';

const homeScenarios = [
  'offline',
  'online',
  'uptodate',
  'newer',
  'first',
  'firstOffline',
  'open',
  'readonly',
  'drivefull',
  'checking',
  'downloadOnly',
  'firstWithApps',
];

final _checkedAt = DateTime(2026, 10, 23, 23, 14);
const _newPlugins = ['דף יומי', 'מילון ארמית'];

HomeViewModel _model(
  GuidanceFacts f, {
  String? installed = '0.10.3',
  String? drive = '0.10.4',
  String? onlineApp,
  int? onlineLibrary,
  int onlinePlugins = 0,
  int pluginUpdates = 0,
  int customApps = 0,
  int customAppsPending = 0,
  int reportsToSend = 0,
  int reportsToCollect = 0,
  int toolReportsPending = 0,
  List<String> newPlugins = const [],
  bool autoInstallSkipped = false,
  bool onlineStoreApp = false,
  bool offersElevation = false,
  LauncherLine? launcher,
  bool canLaunch = true,
}) {
  final guidance = deriveHomeGuidance(f);
  TileStatus tile(GuidanceItem item) =>
      deriveTileStatus(item, f, download: guidance.downloadItems);
  return HomeViewModel(
    guidance: guidance,
    online: f.online,
    installedVersion: installed,
    driveAppVersion: drive,
    onlineAppVersion: onlineApp,
    libraryHereVersion: installed == null
        ? null
        : f.libraryStatus == LibraryStatusFact.updateAvailable
            ? 145
            : 146,
    libraryFreshInstall: installed == null,
    driveLibraryVersion: 146,
    onlineLibraryVersion: onlineLibrary,
    pluginUpdatesOnDrive: pluginUpdates,
    onlinePluginChanges: onlinePlugins,
    onlineStoreApp: onlineStoreApp,
    syncApp: f.syncApp,
    syncLibrary: f.syncLibrary,
    syncPlugins: f.syncPlugins,
    appTile: tile(GuidanceItem.app),
    libraryTile: tile(GuidanceItem.library),
    pluginsTile: tile(GuidanceItem.plugins),
    pluginsOnDrive: 11,
    pluginsInstalled: installed == null ? 0 : 6,
    customApps: customApps,
    customAppsPending: customAppsPending,
    customAppsUnannounced: customAppsPending > 0,
    reportsToSend: reportsToSend,
    reportsToCollect: reportsToCollect,
    toolReportsPending: toolReportsPending,
    autoInstallSkipped: autoInstallSkipped,
    offersElevation: offersElevation,
    newPlugins: newPlugins,
    canLaunch: canLaunch && installed != null,
    launcher: launcher,
    checkedAt: _checkedAt,
    driveName: 'E:',
  );
}

const _driveUpdate = GuidanceFacts(
  otzariaStatus: AppStatusFact.updateAvailable,
  libraryStatus: LibraryStatusFact.updateAvailable,
  pluginUpdatesOnDrive: 3,
  online: false,
);

HomeViewModel homeScenario(String name) => switch (name) {
      'offline' => _model(
          _driveUpdate,
          pluginUpdates: 3,
          customApps: 3,
          customAppsPending: 2,
          reportsToCollect: 3,
          newPlugins: _newPlugins,
          launcher: const LauncherLine(
            LauncherLineKind.ready,
            version: '3.3.0',
          ),
        ),
      'online' => _model(
          const GuidanceFacts(
            otzariaStatus: AppStatusFact.updateAvailable,
            libraryStatus: LibraryStatusFact.updateAvailable,
            pluginUpdatesOnDrive: 3,
            online: true,
            onlineApp: true,
            onlineLibrary: true,
            onlinePlugins: true,
          ),
          // גרסה גולמית כמו שהאתר מחזיר — המסך מציג "0.10.5".
          onlineApp: 'v0.10.5+812',
          onlineLibrary: 147,
          onlinePlugins: 3,
          onlineStoreApp: true,
          pluginUpdates: 3,
          customApps: 3,
          customAppsPending: 2,
          reportsToSend: 12,
          newPlugins: _newPlugins,
          launcher: const LauncherLine(
            LauncherLineKind.online,
            version: '3.3.0',
          ),
        ),
      'uptodate' => _model(
          const GuidanceFacts(online: false),
          installed: '0.10.4',
          customApps: 3,
          newPlugins: _newPlugins,
        ),
      'newer' => _model(
          const GuidanceFacts(
            otzariaStatus: AppStatusFact.installedIsNewer,
            online: false,
          ),
          installed: '0.10.5',
        ),
      'first' || 'firstOffline' => _model(
          GuidanceFacts(
            otzariaInstalled: false,
            otzariaStatus: AppStatusFact.needsDownload,
            libraryStatus: LibraryStatusFact.needsDownload,
            online: name == 'first',
            onlineApp: name == 'first',
            onlineLibrary: name == 'first',
          ),
          installed: null,
          drive: null,
          onlineApp: '0.10.5',
        ),
      'open' => _model(
          const GuidanceFacts(
            otzariaStatus: AppStatusFact.updateAvailable,
            libraryStatus: LibraryStatusFact.updateAvailable,
            pluginUpdatesOnDrive: 3,
            online: false,
            otzariaRunning: true,
          ),
          pluginUpdates: 3,
          customApps: 3,
          customAppsPending: 2,
          reportsToCollect: 3,
          newPlugins: _newPlugins,
          autoInstallSkipped: true,
          launcher: const LauncherLine(
            LauncherLineKind.ready,
            version: '3.3.0',
          ),
        ),
      // בכונן מוגן אין בדיקה ברשת (`AppSession.checkOnline`), ולכן online נשאר
      // null; הדיווחים שבו נספרים, אבל אין לשלוח אותם מכאן.
      'readonly' => _model(
          const GuidanceFacts(
            readOnly: true,
            otzariaStatus: AppStatusFact.updateAvailable,
            libraryStatus: LibraryStatusFact.updateAvailable,
            pluginUpdatesOnDrive: 3,
          ),
          pluginUpdates: 3,
          customApps: 3,
          customAppsPending: 1,
          reportsToSend: 12,
          newPlugins: _newPlugins,
        ),
      'drivefull' => _model(
          const GuidanceFacts(readOnly: true, driveFull: true),
          installed: '0.10.4',
          customApps: 3,
          reportsToSend: 4,
          newPlugins: _newPlugins,
        ),
      'checking' => _model(
          const GuidanceFacts(otzariaStatus: AppStatusFact.checking),
          customApps: 3,
        ),
      // הכול מותקן ומעודכן מהכונן, ובאתר יש חדש — האריחים אומרים מה יירד.
      'downloadOnly' => _model(
          const GuidanceFacts(
            online: true,
            onlineApp: true,
            onlineLibrary: true,
            onlinePlugins: true,
          ),
          installed: '0.10.4',
          onlineApp: '0.10.5',
          onlineLibrary: 147,
          onlinePlugins: 5,
          customApps: 2,
          reportsToSend: 3,
          offersElevation: true,
          launcher: const LauncherLine(
            LauncherLineKind.online,
            version: 'v3.3.0',
          ),
        ),
      // כונן ריק מאוצריא, אבל יש בו תוכנות נוספות ודיווחים, והוא מוגן.
      'firstWithApps' => _model(
          const GuidanceFacts(
            readOnly: true,
            otzariaInstalled: false,
            otzariaStatus: AppStatusFact.needsDownload,
            libraryStatus: LibraryStatusFact.needsDownload,
          ),
          installed: null,
          drive: null,
          customApps: 2,
          customAppsPending: 2,
          reportsToSend: 3,
        ),
      _ => throw ArgumentError.value(name, 'name'),
    };
