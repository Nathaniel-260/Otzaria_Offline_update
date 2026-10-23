import 'package:plugins_manager/plugins_manager.dart' show StorePlugin;

import '../flows/update_here_flow.dart';
import '../services/mirror_download_undo.dart';
import '../shell/shell_tasks.dart' show PluginDelivery, PluginDeliveryState;
import 'auto_install_flow.dart';
import 'cancelled_download_refresh.dart';
import 'download_plan.dart';
import 'launcher_update_controller.dart';
import 'launcher_update_flow.dart';
import 'library_module_controller.dart';
import 'mirror_download_flow.dart';
import 'otzaria_module_controller.dart';
import 'plugins_module_controller.dart';

class OtzariaModulePort
    implements AppMirrorModule, AutoInstallApp, UpdateHereApp {
  OtzariaModulePort(this._otzaria);

  final OtzariaModuleController _otzaria;

  @override
  bool get hasStaleFullPackage => _otzaria.hasStaleFullPackage;

  @override
  OnlineProof get onlineProof => OnlineProof(
        checkedAt: _otzaria.onlineCheckedAt,
        error: _otzaria.onlineCheckError,
        hasUpdate: _otzaria.hasOnlineUpdate,
      );

  @override
  Future<void> download({required bool Function() isCancelled}) =>
      _otzaria.download(isCancelled: isCancelled);

  @override
  bool get downloadFailed => _otzaria.downloadError != null;

  @override
  bool get isInstalled => _otzaria.currentVersion != null;

  @override
  bool get hasUpdateAvailable =>
      _otzaria.status == OtzariaModuleStatus.updateAvailable;

  @override
  Future<void> install({required bool useWizard}) =>
      _otzaria.install(useWizard: useWizard);

  @override
  bool get elevatedAsOtherUser => _otzaria.elevatedAsOtherUser;

  @override
  String? get versionToInstall => _otzaria.latestVersion;

  @override
  String? get errorMessage => _otzaria.errorMessage ?? _otzaria.noticeMessage;

  @override
  bool get needsElevation => _otzaria.needsElevation;

  @override
  bool get canReinstall => _otzaria.status == OtzariaModuleStatus.upToDate;

  @override
  void stopWaiting() => _otzaria.stopWaitingForSetup();

  @override
  Future<AppInstallOutcome> installWithWizard() async {
    _otzaria.lastInstallResult = null;
    await _otzaria.install();
    return switch (_otzaria.lastInstallResult) {
      OtzariaInstallResult.installed => AppInstallOutcome.installed,
      OtzariaInstallResult.cancelled => AppInstallOutcome.cancelled,
      OtzariaInstallResult.wizardStillOpen => AppInstallOutcome.stillOpen,
      OtzariaInstallResult.failed || null => AppInstallOutcome.failed,
    };
  }
}

class LibraryModulePort
    implements LibraryMirrorModule, AutoInstallLibrary, UpdateHereLibrary {
  LibraryModulePort(this._library);

  final LibraryModuleController _library;

  @override
  bool get shouldOfferSemanticDownload => _library.shouldOfferSemanticDownload;

  @override
  bool get personalUpdateMode => _library.personalUpdateMode;

  @override
  OnlineProof get libraryOnlineProof => OnlineProof(
        checkedAt: _library.onlineCheckedAt,
        error: _library.onlineLibraryProofError,
        hasUpdate: _library.hasOnlineLibraryUpdate,
      );

  @override
  Future<void> download({
    required bool includeSemanticSearch,
    required bool Function() isCancelled,
  }) =>
      _library.download(
        includeSemanticSearch: includeSemanticSearch,
        isCancelled: isCancelled,
      );

  @override
  bool get downloadFailed => _library.downloadError != null;

  @override
  bool get downloadNeedsRetry => _library.downloadNeedsRetry;

  @override
  bool get isFreshInstall => _library.isFreshInstall;

  @override
  bool get hasUpdateAvailable =>
      _library.status == LibraryModuleStatus.updateAvailable;

  @override
  Future<void> update() => _library.update();

  @override
  Future<void> recheck() => _library.checkForUpdate();

  @override
  int? get targetVersion => _library.targetVersion;

  @override
  String? get errorMessage => _library.errorMessage;

  @override
  bool get needsElevation => _library.needsElevation;

  @override
  bool get canApplyFull => _library.canRetryWithFullDownload;

  @override
  Future<bool> apply() async {
    await _library.update();
    return _appliedCleanly;
  }

  @override
  Future<bool> applyFull() async {
    await _library.updateWithFullDownload();
    return _appliedCleanly;
  }

  bool get _appliedCleanly =>
      _library.status == LibraryModuleStatus.upToDate &&
      _library.errorMessage == null;
}

class PluginsModulePort implements PluginsMirrorModule, UpdateHerePlugins {
  PluginsModulePort(this._plugins);

  final PluginsModuleController _plugins;

  @override
  OnlineProof get catalogOnlineProof => OnlineProof(
        checkedAt: _plugins.onlineCheckedAt,
        error: _plugins.onlineCheckError,
        hasUpdate: _plugins.hasCatalogOnlineUpdate,
      );

  @override
  OnlineProof get storeAppOnlineProof => OnlineProof(
        checkedAt: _plugins.storeAppCheckedAt,
        error: _plugins.storeAppCheckError,
        hasUpdate: _plugins.hasStoreAppOnlineUpdate,
      );

  @override
  Future<void> sync({required bool Function() isCancelled}) =>
      _plugins.sync(isCancelled: isCancelled);

  @override
  Future<void> syncStoreApp() => _plugins.syncStoreApp();

  @override
  bool get lastSyncFailed => _plugins.lastSyncFailed;

  @override
  List<String> get deliverableUpdates =>
      [for (final plugin in _plugins.deliverableUpdates) plugin.name];

  @override
  Future<void> deliver(void Function(List<PluginDelivery> rows) onRow) async {
    final targets = _plugins.deliverableUpdates;
    final states = {
      for (final plugin in targets) plugin.id: PluginDeliveryState.waiting,
    };
    List<PluginDelivery> rows() => [
          for (final StorePlugin plugin in targets)
            PluginDelivery(plugin.name, states[plugin.id]!),
        ];
    await _plugins.deliverUpdates(
      plugins: targets,
      onDelivered: (plugin, result) {
        states[plugin.id] = result.success
            ? PluginDeliveryState.sent
            : PluginDeliveryState.failed;
        onRow(rows());
      },
    );
  }
}

class LauncherUpdatePort implements LauncherUpdateTarget {
  LauncherUpdatePort(this._launcher);

  final LauncherUpdateController _launcher;

  @override
  bool get isDownloading => _launcher.isDownloading;

  @override
  bool get isInstalling => _launcher.isInstalling;

  @override
  bool get hasUpdateReady => _launcher.hasUpdateReady;

  @override
  bool get canInstall => _launcher.canInstall;

  @override
  String? get downloadedVersion => _launcher.downloadedVersion;

  @override
  String? get errorMessage => _launcher.errorMessage;

  @override
  Future<void> checkForUpdate() => _launcher.checkForUpdate();

  @override
  Future<bool> download() => _launcher.download();

  @override
  Future<bool> install() => _launcher.install();
}

class CancelledDownloadRollback implements DownloadRollback {
  CancelledDownloadRollback._(
    this._undo,
    this._before, {
    required OtzariaModuleController otzaria,
    required LibraryModuleController library,
    required PluginsModuleController plugins,
  })  : _otzaria = otzaria,
        _library = library,
        _plugins = plugins;

  static Future<CancelledDownloadRollback> capture({
    required OtzariaModuleController otzaria,
    required LibraryModuleController library,
    required PluginsModuleController plugins,
    required List<String> mirrorDirs,
  }) async {
    final before = OnlineAnswersBeforeDownload.capture(
      library: library,
      plugins: plugins,
    );
    final undo = await MirrorDownloadUndo.capture(mirrorDirs);
    return CancelledDownloadRollback._(
      undo,
      before,
      otzaria: otzaria,
      library: library,
      plugins: plugins,
    );
  }

  final MirrorDownloadUndo _undo;
  final OnlineAnswersBeforeDownload _before;
  final OtzariaModuleController _otzaria;
  final LibraryModuleController _library;
  final PluginsModuleController _plugins;

  @override
  Future<void> rollback() async {
    try {
      await _undo.revert();
    } finally {
      await refreshAfterCancelledDownload(
        otzaria: _otzaria,
        library: _library,
        plugins: _plugins,
        before: _before,
      );
    }
  }
}
