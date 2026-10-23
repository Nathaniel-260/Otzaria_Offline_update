import '../settings/app_settings.dart';
import 'download_plan.dart';

abstract interface class AppMirrorModule {
  bool get hasStaleFullPackage;
  OnlineProof get onlineProof;
  Future<void> download({required bool Function() isCancelled});
  bool get downloadFailed;
}

abstract interface class LibraryMirrorModule {
  bool get shouldOfferSemanticDownload;
  bool get personalUpdateMode;
  OnlineProof get libraryOnlineProof;
  Future<void> download({
    required bool includeSemanticSearch,
    required bool Function() isCancelled,
  });
  bool get downloadFailed;
  bool get downloadNeedsRetry;
}

abstract interface class PluginsMirrorModule {
  OnlineProof get catalogOnlineProof;
  OnlineProof get storeAppOnlineProof;
  Future<void> sync({required bool Function() isCancelled});
  Future<void> syncStoreApp();
  bool get lastSyncFailed;
}

abstract interface class DownloadRollback {
  Future<void> rollback();
}

abstract interface class MirrorDownloadHost {
  bool get isActive;
  bool get isBlocked;
  bool get launcherDownloading;
  AppSettings get settings;
  Future<void> refreshStaleOnlineChecks(AppSettings s);

  /// `null` = חזרה מהשאלה: ההורדה לא מתחילה.
  Future<bool?> confirmSemanticSearch();
  Future<DownloadRollback> captureRollback();
  Future<void> sweepMirror();
  void stateChanged();
  void downloadSnapshotFailed(Object error);
  void downloadCancelled({Object? revertError});
  void downloadEnded();

  /// חריג שלא נתפס בזרימה — המסך עובר לכשל, ולא נשאר תקוע ב"מתכונן".
  /// [abandoned]: הזרימה בוטלה, והמסך שפתוח עכשיו שייך לבקשה אחרת.
  void downloadCrashed(
    Object error,
    StackTrace stackTrace, {
    bool abandoned = false,
  });
  void downloadFinished({
    required List<MirrorComponent> failed,
    required List<MirrorComponent> skipped,
  });
}

class MirrorDownloadFlow {
  MirrorDownloadFlow({
    required this.app,
    required this.library,
    required this.plugins,
    required this.host,
  });

  final AppMirrorModule app;
  final LibraryMirrorModule library;
  final PluginsMirrorModule plugins;
  final MirrorDownloadHost host;

  bool _isDownloading = false;
  bool _cancelRequested = false;
  bool _isPreparing = false;
  bool _abandonRequested = false;
  int _abandonCount = 0;
  Future<void>? _run;
  Future<void>? _sweep;
  DownloadPlan? _plan;
  List<MirrorComponent> _components = const [];
  MirrorComponent? _current;

  bool get isDownloading => _isDownloading;

  /// התוכנית של ההורדה שרצה עכשיו, ו[activeComponents] — מה ממנה ירוץ.
  DownloadPlan? get activePlan => _isDownloading ? _plan : null;
  List<MirrorComponent> get activeComponents =>
      _isDownloading ? _components : const [];

  /// הרכיב שיורד ברגע זה; `null` לפני הראשון ואחרי האחרון.
  MirrorComponent? get currentComponent => _isDownloading ? _current : null;
  bool get isCancelling => _cancelRequested;
  bool get isPreparing => _isPreparing;
  Future<void>? get pendingSweep => _sweep;

  Future<void> downloadAll() async {
    if (_isPreparing) {
      // "ביטול" ואז "הורדה" לפני שהזרימה שבוטלה חזרה: מחכים לה ומתחילים מחדש.
      final abandoned = _run;
      if (!_abandonRequested || abandoned == null) return;
      final abandonCount = _abandonCount;
      await abandoned.then((_) {}, onError: (_) {});
      // "ביטול" נוסף בזמן ההמתנה מבטל גם את הבקשה הזו.
      if (_isPreparing || !host.isActive || abandonCount != _abandonCount) {
        return;
      }
    }
    _isPreparing = true;
    _abandonRequested = false;
    final run = _run = _downloadAll();
    try {
      await run;
    } catch (error, stackTrace) {
      if (host.isActive) {
        host.downloadCrashed(error, stackTrace, abandoned: _abandonRequested);
      }
    } finally {
      _isPreparing = false;
      _run = null;
    }
  }

  /// "ביטול" לפני שההורדה התחילה: הזרימה חוזרת אחרי הבדיקה ברשת, בלי
  /// לשאול ובלי להוריד.
  void abandonPreparing() {
    if (!_isPreparing || _isDownloading) return;
    _abandonRequested = true;
    _abandonCount++;
  }

  void requestCancel() {
    _cancelRequested = true;
    host.stateChanged();
  }

  Future<void> cancelAndWait() async {
    if (_run case final run? when _isDownloading) {
      requestCancel();
      await run;
    }
  }

  Future<void> _downloadAll() async {
    if (_sweep case final sweep?) {
      await sweep;
      if (!host.isActive || _abandonRequested) return;
    }
    final s = host.settings;
    if (!s.hasSyncSelection || host.isBlocked) return;

    await host.refreshStaleOnlineChecks(s);
    if (!host.isActive || _abandonRequested) return;

    final skipApp = DownloadPlan.shouldSkipApp(
      s,
      hasStaleFullPackage: app.hasStaleFullPackage,
      online: app.onlineProof,
    );
    var includeSemanticSearch = false;
    if (s.downloadsLibrary && library.shouldOfferSemanticDownload) {
      final answer = await host.confirmSemanticSearch();
      if (answer == null) return;
      includeSemanticSearch = answer;
    }
    if (!host.isActive || host.isBlocked || _abandonRequested) return;
    final plan = DownloadPlan(
      skipApp: skipApp,
      includeSemanticSearch: includeSemanticSearch,
      skipLibrary: DownloadPlan.shouldSkipLibrary(
        s,
        includeSemanticSearch: includeSemanticSearch,
        personalUpdateMode: library.personalUpdateMode,
        online: library.libraryOnlineProof,
      ),
      skipPlugins: DownloadPlan.shouldSkipPlugins(
        s,
        catalog: plugins.catalogOnlineProof,
      ),
      skipStoreApp: DownloadPlan.shouldSkipStoreApp(
        s,
        storeApp: plugins.storeAppOnlineProof,
      ),
    );

    _plan = plan;
    _components = [
      if (plan.runsApp(s)) MirrorComponent.app,
      if (plan.runsLibrary(s)) MirrorComponent.library,
      if (plan.runsPlugins(s) || plan.runsStoreApp(s)) MirrorComponent.plugins,
    ];
    _current = null;
    _isDownloading = true;
    _cancelRequested = false;
    host.stateChanged();

    try {
      final DownloadRollback rollback;
      try {
        rollback = await host.captureRollback();
      } catch (error) {
        _isDownloading = false;
        _cancelRequested = false;
        host.stateChanged();
        host.downloadSnapshotFailed(error);
        return;
      }
      bool cancelled() => _cancelRequested;

      if (plan.runsApp(s)) {
        _current = MirrorComponent.app;
        await app.download(isCancelled: cancelled);
      }
      if (!cancelled() && plan.runsLibrary(s)) {
        _current = MirrorComponent.library;
        await library.download(
          includeSemanticSearch: includeSemanticSearch,
          isCancelled: cancelled,
        );
      }
      if (!cancelled() && plan.runsPlugins(s)) {
        _current = MirrorComponent.plugins;
        await plugins.sync(isCancelled: cancelled);
      }
      if (!cancelled() && plan.runsStoreApp(s)) {
        _current = MirrorComponent.plugins;
        await plugins.syncStoreApp();
      }
      _current = null;

      if (cancelled()) {
        Object? revertError;
        try {
          await rollback.rollback();
        } catch (error) {
          revertError = error;
        }
        if (!host.isActive) return;
        _isDownloading = false;
        _cancelRequested = false;
        host.stateChanged();
        host.downloadCancelled(revertError: revertError);
        return;
      }
      if (!host.isActive) return;

      _isDownloading = false;
      host.stateChanged();
      host.downloadEnded();

      final failed = plan.failed(
        s,
        appFailed: app.downloadFailed,
        libraryFailed: library.downloadFailed,
        pluginsFailed: plugins.lastSyncFailed,
      );
      if (failed.isEmpty &&
          !library.downloadNeedsRetry &&
          !host.launcherDownloading) {
        _sweep = _sweepMirror();
      }
      host.downloadFinished(failed: failed, skipped: plan.skipped);
    } finally {
      if (_isDownloading) {
        _isDownloading = false;
        _cancelRequested = false;
        if (host.isActive) host.stateChanged();
      }
    }
  }

  Future<void> _sweepMirror() async {
    try {
      await host.sweepMirror();
    } finally {
      _sweep = null;
    }
  }
}
