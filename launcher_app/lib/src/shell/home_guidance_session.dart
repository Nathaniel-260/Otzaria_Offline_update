import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../controllers/plugins_module_controller.dart';
import 'app_session.dart';
import 'home_guidance.dart';

/// העובדות של [deriveHomeGuidance] מתוך הסשן. בקובץ נפרד כדי ש-
/// `home_guidance.dart` יישאר בלי Flutter.
GuidanceFacts guidanceFactsFromSession(AppSession s) {
  final otzaria = s.otzaria;
  final library = s.library;
  final plugins = s.plugins;
  final settings = s.settings.settings;
  final pluginsReady = plugins.status == PluginsModuleStatus.ready;
  final pluginsLoading = plugins.status == PluginsModuleStatus.idle ||
      plugins.status == PluginsModuleStatus.loading;
  return GuidanceFacts(
    readOnly: s.readOnly,
    driveFull: s.driveFull,
    otzariaStatus: AppStatusFact.values.byName(otzaria.status.name),
    otzariaInstalled: otzaria.currentVersion != null,
    otzariaMirrorVersion: otzaria.latestVersion,
    otzariaRunning: s.otzariaIsRunning,
    libraryApplyActive: library.isApplying,
    libraryStatus: LibraryStatusFact.values.byName(library.status.name),
    libraryFreshInstall: library.isFreshInstall,
    semanticConsentRequired: library.semanticConsentRequired,
    pluginsLoading: pluginsLoading,
    pluginUpdatesOnDrive: pluginsReady ? plugins.updatablePlugins.length : 0,
    online: onlineState(s),
    onlineApp: otzaria.hasOnlineUpdate,
    onlineLibrary: library.hasOnlineUpdate,
    onlinePlugins: plugins.hasOnlineUpdate,
    syncApp: settings.syncApp,
    syncLibrary: settings.downloadsLibrary,
    syncPlugins: settings.syncPlugins,
    autoCheckUpdates: settings.autoCheckUpdates,
    isCheckingOnline: s.isCheckingOnline,
    longTaskRunning: s.longTaskRunning,
    installing: otzaria.status == OtzariaModuleStatus.installing ||
        library.status == LibraryModuleStatus.updating,
  );
}

/// אותו כלל כמו כרטיס הבדיקה בדף הבית: `null` כשאף בדיקה לא רצה, `true`
/// כשלפחות אחת הצליחה.
bool? onlineState(AppSession s) {
  final checks = [
    (s.otzaria.onlineCheckedAt, s.otzaria.onlineCheckError),
    (s.library.onlineCheckedAt, s.library.onlineCheckError),
    (s.plugins.onlineCheckedAt, s.plugins.onlineCheckError),
    (s.launcherUpdate.onlineCheckedAt, s.launcherUpdate.onlineCheckError),
  ];
  if (checks.every((c) => c.$1 == null)) return null;
  return checks.any((c) => c.$1 != null && c.$2 == null);
}
