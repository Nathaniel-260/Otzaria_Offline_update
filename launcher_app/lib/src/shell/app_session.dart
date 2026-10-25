import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart' show StorePlugin;

import '../app_report/launcher_crash_session.dart';
import '../controllers/app_reports_controller.dart';
import '../controllers/auto_install_flow.dart';
import '../controllers/custom_apps_controller.dart';
import '../controllers/download_plan.dart';
import '../controllers/error_reports_controller.dart';
import '../controllers/faq_controller.dart';
import '../controllers/launcher_update_controller.dart';
import '../controllers/launcher_update_flow.dart';
import '../controllers/library_module_controller.dart';
import '../controllers/mirror_download_flow.dart';
import '../controllers/otzaria_module_controller.dart';
import '../controllers/plugins_module_controller.dart';
import '../controllers/search_feedback_controller.dart';
import '../controllers/shell_module_ports.dart';
import '../flows/update_here_flow.dart';
import '../services/app_logger.dart';
import '../services/app_paths.dart';
import '../services/byte_size.dart';
import '../services/elevation.dart';
import '../services/file_reveal.dart';
import '../services/mirror_junk_sweeper.dart';
import '../services/notices_seen_store.dart';
import '../services/report_offer_coordinator.dart';
import '../services/sleep_inhibitor.dart';
import '../settings/app_settings.dart';
import '../settings/safer_mode.dart';
import '../settings/settings_controller.dart';
import '../widgets/ui_snack.dart';
import 'download_failure.dart';
import 'home_guidance.dart' show GuidanceItem;
import 'session_prompts.dart';
import 'shell_tasks.dart';

/// המצב והזרימות של הרצה אחת: המודולים, הבדיקות, ההורדה והדגלים שחוסמים
/// יציאה. כל מה שדורש `BuildContext` עובר דרך [prompts].
class AppSession extends ChangeNotifier {
  AppSession({
    required this.dataDir,
    required this.stateDir,
    required this.settings,
    required this.prompts,
    this.readOnly = false,
    this.driveFull = false,
    this.runningLocator = const RunningOtzariaLocator(),
    NoticesSeenStore? noticesStore,
    this.appReports,
    SleepInhibitor? sleepInhibitor,
  })  : _noticesStore = noticesStore,
        _injectedSleepInhibitor = sleepInhibitor {
    final s = settings.settings;

    _otzaria = OtzariaModuleController(
      dataDir: dataDir,
      stateDir: stateFilesDir,
      preferPrerelease: s.preferAppPrerelease,
      runningLocator: runningLocator,
      pendingLaunchUri: () async =>
          _library.hasPendingReindex ? OtzariaDeepLinks.libraryReindex : null,
      onLaunchUriDelivered: () => _library.markReindexRequestDelivered(),
      isLibraryApplying: () => _library.isApplying,
    )..addListener(_onChange);
    _library = LibraryModuleController(
      dataDir: dataDir,
      stateDir: stateFilesDir,
      otzariaLaunchPath: () async => _otzaria.launchPath,
      otzariaAppVersion: () async => _otzaria.currentVersion,
      mirroredOtzariaUpdate: () async =>
          _otzaria.status == OtzariaModuleStatus.updateAvailable
              ? _otzaria.latestVersion
              : null,
      instanceLock: const OtzariaInstanceLock(),
    )..addListener(_onChange);
    _plugins = PluginsModuleController(
      mirrorRootDir: p.join(dataDir, 'mirror'),
      stateDir: stateFilesDir,
      otzariaLaunchPath: () async => _otzaria.launchPath,
      locatePluginsDb: PluginsModuleController.locateOtzariaPluginsDb,
      mirroredAppVersions: () async => [
        if (_otzaria.stableVersion != null) _otzaria.stableVersion!,
        if (_otzaria.prereleaseVersion != null) _otzaria.prereleaseVersion!,
      ],
      installedAppVersion: () async =>
          _otzaria.currentVersion ?? _otzaria.latestVersion,
      ensureAppVersionsKnown: _otzaria.ensureChecked,
    )..addListener(_onChange);
    _installDone = _plugins.installCompletions.listen((name) {
      if (isActive) {
        UiSnack.showSuccess(AppL10n.strings.plugins.installDoneSnack(name));
      }
    });
    _installRejected = _plugins.installRejections.listen((entry) {
      if (!isActive) return;
      final t = AppL10n.strings.plugins;
      if (entry.report.cancelled) {
        UiSnack.show(t.installCancelledSnack(entry.name));
      } else {
        UiSnack.showError(
          t.installRejectedSnack(entry.name, entry.report.message),
        );
      }
    });
    _customApps = CustomAppsController(
      mirrorRootDir: p.join(dataDir, 'mirror'),
      stateDir: stateFilesDir,
      trustFilePath: _customAppsTrustFile(),
    )..addListener(_onChange);
    _launcherUpdate = LauncherUpdateController(dataDir: dataDir)
      ..addListener(_onChange);
    _faq = FaqController(dataDir: stateDir);
    _errorReports = ErrorReportsController.forDrive(
      stateDir: stateDir,
      dataDir: dataDir,
      stateFilesDir: stateFilesDir,
      launchPath: () async => _otzaria.launchPath,
    )..addListener(_onReportsChange);
    _searchFeedback = SearchFeedbackController.forDrive(
      dataDir: dataDir,
      stateDir: stateDir,
      stateFilesDir: stateFilesDir,
      launchPath: () async => _otzaria.launchPath,
      runningLocator: runningLocator,
    )..addListener(_onReportsChange);
  }

  /// התיקייה שלצד התוכנה — המראה, כלומר המקור שממנו קוראים ומתקינים.
  final String dataDir;

  /// לאן נכתבים לוג, הגדרות ומצב — ראו [AppPaths.stateDir].
  final String stateDir;

  String get stateFilesDir => p.join(stateDir, AppPaths.logsDirName);

  final bool readOnly;
  final bool driveFull;
  final SettingsController settings;
  final SessionPrompts prompts;
  final RunningOtzariaLocator runningLocator;

  /// `null` בבדיקות: הוא מפעיל טיימר שליחה ופונה לרשת.
  final AppReportsController? appReports;

  final NoticesSeenStore? _noticesStore;
  final SleepInhibitor? _injectedSleepInhibitor;

  late final SleepInhibitor _sleepInhibitor =
      _injectedSleepInhibitor ?? SleepInhibitor();
  late final OtzariaModuleController _otzaria;
  late final LibraryModuleController _library;
  late final PluginsModuleController _plugins;
  late final StreamSubscription<String> _installDone;
  late final StreamSubscription<Object?> _installRejected;
  late final CustomAppsController _customApps;
  late final LauncherUpdateController _launcherUpdate;
  late final FaqController _faq;
  late final ErrorReportsController _errorReports;
  late final SearchFeedbackController _searchFeedback;

  late final NoticesSeenStore _notices =
      _noticesStore ?? NoticesSeenStore(stateFilesDir);

  /// אימות אחד מלווה את כל ההרצה — ראו `SaferModeGate`.
  late final SaferModeGate saferMode = SaferModeGate(settings);

  OtzariaModuleController get otzaria => _otzaria;
  LibraryModuleController get library => _library;
  PluginsModuleController get plugins => _plugins;
  CustomAppsController get customApps => _customApps;
  LauncherUpdateController get launcherUpdate => _launcherUpdate;
  FaqController get faq => _faq;
  ErrorReportsController get errorReports => _errorReports;
  SearchFeedbackController get searchFeedback => _searchFeedback;
  NoticesSeenStore get notices => _notices;

  /// מסכי המשימה (הורדה, עדכון כאן) — המסגרת מציגה אותם בשכבה מעל הגוף.
  final ShellTasks tasks = ShellTasks();

  bool _disposed = false;
  bool get isActive => !_disposed;

  Future<void> _errorReportsIntro = Future<void>.value();
  bool _reportsIntroPending = false;
  bool _autoInstallSkipped = false;
  int _errorReportsToCollect = 0;
  int _searchRecordsToCollect = 0;
  DateTime? _checkedAt;

  /// "מה התחדש" כבר מוצג בדף הכלי, ולכן אישור ההתקנה לא חוזר עליו.
  bool _whatsNewAlreadyShown = false;

  bool _elevationPending = false;
  bool _elevationDismissed = false;
  bool _legacyReportsNotice = false;
  bool _isCheckingOnline = false;
  bool _checkingNow = false;
  bool _markingPluginsVisited = false;
  bool _uploadingReports = false;
  bool _reportsStopRequested = false;

  bool get isCheckingOnline => _isCheckingOnline;

  /// בדיקה רצה — "בדוק עכשיו", הבדיקה שבעלייה, או בדיקה ברשת.
  bool get isCheckingNow => _checkingNow || _isCheckingOnline;

  /// משימה ארוכה חוסמת את "בדוק עכשיו" — אותו תנאי לקישור, לכפתור ולפעולה.
  bool get checkNowBlocked => longTaskRunning;

  /// תורי דיווחים ישנים שלא הועברו — הסבר בבית עד "הבנתי".
  bool get showsLegacyReportsNotice => _legacyReportsNotice;

  /// ההסבר החד-פעמי על הדיווחים: הודעה בבית עד "הבנתי".
  bool get showsReportsIntro => _reportsIntroPending;

  /// ההתקנה האוטומטית דילגה כי אוצריא הייתה פתוחה — הודעה קבועה בבית.
  bool get autoInstallSkipped => _autoInstallSkipped;

  /// כמה דיווחים ומשובים ממתינים באוצריא לאיסוף — המונה של אריח הדיווחים.
  int get reportsToCollect => _errorReportsToCollect + _searchRecordsToCollect;
  int get errorReportsToCollect => _errorReportsToCollect;
  int get searchRecordsToCollect => _searchRecordsToCollect;

  /// הבדיקה האחרונה, מקומית או ברשת — "נבדק ב-" בתחתית הבית.
  DateTime? get lastCheckedAt => [
        _checkedAt,
        _otzaria.onlineCheckedAt,
        _library.onlineCheckedAt,
        _plugins.onlineCheckedAt,
      ].whereType<DateTime>().fold<DateTime?>(
            null,
            (latest, at) => latest == null || at.isAfter(latest) ? at : latest,
          );
  bool get uploadingReports => _uploadingReports;

  /// נגזר מהקונטרולר ולא מועתק: העתק נשאר תקוע על "פתוחה" אחרי שנסגרה.
  bool get otzariaIsRunning => _otzariaIsRunning;
  bool get _otzariaIsRunning => _otzaria.isRunning;

  static const Duration _runningPollInterval = Duration(seconds: 3);
  static const Duration _runningWatchSlice = Duration(minutes: 1);
  Timer? _runningPoll;
  Future<void>? _runningWatch;

  late final OtzariaModulePort _otzariaPort = OtzariaModulePort(_otzaria);
  late final LibraryModulePort _libraryPort = LibraryModulePort(_library);
  late final PluginsModulePort _pluginsPort = PluginsModulePort(_plugins);

  late final MirrorDownloadFlow _downloads = MirrorDownloadFlow(
    app: _otzariaPort,
    library: _libraryPort,
    plugins: _pluginsPort,
    host: _SessionDownloadHost(this),
  );

  late final UpdateHereFlow _updateHere = UpdateHereFlow(
    app: _otzariaPort,
    library: _libraryPort,
    plugins: _pluginsPort,
    host: _SessionUpdateHost(this),
  );

  late final LauncherUpdateFlow _launcherFlow = LauncherUpdateFlow(
    launcher: LauncherUpdatePort(_launcherUpdate),
    downloads: _downloads,
    host: _SessionLauncherHost(this),
  );

  late final AutoInstallFlow _autoInstall = AutoInstallFlow(
    library: _libraryPort,
    app: _otzariaPort,
    isOtzariaRunning: refreshProcessState,
    isDownloading: () => _downloads.isDownloading,
    exitPending: () => exitPending,
    isActive: () => isActive,
  );

  late final ReportOfferCoordinator _offers = ReportOfferCoordinator(
    isTaskRunning: () =>
        exitWouldInterrupt || _downloads.isPreparing || tasks.isRunning,
    isActive: () => isActive,
    prepare: _prepareOffer,
    runDialog: prompts.runDialog,
    perform: recountReportsToCollect,
  );

  bool get isDownloading => _downloads.isDownloading;
  bool get isCancellingDownload => _downloads.isCancelling;

  /// מה יורד עכשיו — למסך ההתקדמות.
  MirrorComponent? get currentDownload => _downloads.currentComponent;

  /// מה שכל רכיב צפוי להוריד לפי הבדיקה ברשת; רכיב שגודלו לא ידוע חסר.
  Map<MirrorComponent, int> get expectedDownloadBytes {
    final plan = _downloads.activePlan;
    if (plan == null) return const {};
    final s = settings.settings;
    final app = _otzaria.onlineDownloadBytes;
    final plugins = [
      if (plan.runsPlugins(s)) _plugins.onlineStatus?.pendingBytes,
      if (plan.runsStoreApp(s)) _plugins.storeAppOnline?.sizeBytes,
    ];
    final pluginBytes = plugins.contains(null)
        ? 0
        : plugins.fold<int>(0, (sum, bytes) => sum + bytes!);
    return {
      if (app != null && plan.runsApp(s)) MirrorComponent.app: app,
      if (pluginBytes > 0) MirrorComponent.plugins: pluginBytes,
    };
  }

  /// העבודה שבעלייה. נפרד מהבנאי כדי שבדיקות יוכלו לבנות סשן בלי להריץ אותה.
  void start() {
    final s = settings.settings;
    unawaited(_faq.load());
    // ספירה בלבד — גם בכונן מוגן, כדי שהבית יאמר שיש בו דיווחים.
    unawaited(_searchFeedback.refreshOutbox());
    unawaited(_errorReports.refreshOutbox());
    _errorReportsIntro = _loadReportsIntro();
    settings.addListener(_onChange);
    _applySettings(s);

    unawaited(_plugins.load());
    unawaited(_customApps.load());
    if (s.autoCheckUpdates) {
      unawaited(_asCheck(checkAll));
    } else {
      unawaited(refreshProcessState());
      unawaited(_launcherFlow.checkMirror());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isActive) return;
        unawaited(_asCheck(() async {
          await _otzaria.ensureChecked();
          _markChecked();
        }).then((_) => _offers.request()));
      });
    }
    if (appReports case final reports?) {
      reports.stateProvider = _reportState;
      unawaited(_startReports(reports));
    }
    if (s.autoCheckUpdates) {
      unawaited(checkOnline());
    }
    LauncherCrashSession.closeGuard = confirmClose;
  }

  @override
  void dispose() {
    _disposed = true;
    _sleepInhibitor.dispose();
    if (LauncherCrashSession.closeGuard == confirmClose) {
      LauncherCrashSession.closeGuard = null;
    }
    _runningPoll?.cancel();
    _offers.dispose();
    unawaited(_installDone.cancel());
    unawaited(_installRejected.cancel());
    settings.removeListener(_onChange);
    _otzaria.removeListener(_onChange);
    _library.removeListener(_onChange);
    _plugins.removeListener(_onChange);
    _customApps.removeListener(_onChange);
    _launcherUpdate.removeListener(_onChange);
    _errorReports.removeListener(_onReportsChange);
    _searchFeedback.removeListener(_onReportsChange);
    _otzaria.dispose();
    _library.dispose();
    _plugins.dispose();
    _customApps.dispose();
    _launcherUpdate.dispose();
    _errorReports.dispose();
    _searchFeedback.dispose();
    _faq.dispose();
    tasks.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    change();
    if (isActive) notifyListeners();
  }

  void _onChange() {
    if (!isActive) return;
    _syncSleepInhibition();
    _offers.onRunningState(running: _otzariaIsRunning);
    _offers.resume();
    _applySettings(settings.settings);
    _syncRunningPoll();
    notifyListeners();
  }

  void _onReportsChange() {
    if (!isActive) return;
    _syncSleepInhibition();
    _offers.resume();
  }

  /// תוספים חדשים בכונן שהבית עוד לא הזכיר — פס בבית עד הכניסה לחנות.
  List<StorePlugin> get newPluginsForHome =>
      _plugins.status == PluginsModuleStatus.ready
          ? _plugins.newPluginsForHome
          : const [];

  /// הכניסה לחנות: התוספים החדשים נרשמים כמוזכרים, פעם אחת במחשב.
  Future<void> markPluginsVisited() async {
    final fresh = newPluginsForHome;
    if (fresh.isEmpty || _markingPluginsVisited) return;
    _markingPluginsVisited = true;
    try {
      await _plugins.markHomeNotified(fresh);
    } finally {
      _markingPluginsVisited = false;
    }
    if (isActive) notifyListeners();
  }

  Future<void> _loadReportsIntro() async {
    final seen = await _notices.hasSeen(NoticesSeenStore.errorReportsIntro);
    if (!seen && isActive) _update(() => _reportsIntroPending = true);
  }

  /// "הבנתי" בהודעה — נרשם רק עכשיו, ולא כשהיא הופיעה.
  Future<void> dismissReportsIntro() async {
    if (!_reportsIntroPending) return;
    _update(() => _reportsIntroPending = false);
    await _notices.markSeen(NoticesSeenStore.errorReportsIntro);
  }

  /// סופר מה ממתין באוצריא לאיסוף, בלי לאסוף. אוצריא פתוחה נועלת את התור.
  Future<void> recountReportsToCollect() async {
    if (readOnly || !isActive) return;
    if (await refreshProcessState()) return;
    final reports = await _errorReports.pendingToOffer();
    final feedback = await _searchFeedback.pendingToOffer();
    final legacy = _errorReports.unmigratedLegacy.isNotEmpty &&
        !await _notices.hasSeen(NoticesSeenStore.legacyReportsNotice);
    if (!isActive) return;
    _update(() {
      _errorReportsToCollect = reports;
      _searchRecordsToCollect = feedback;
      _legacyReportsNotice = legacy;
    });
  }

  Future<void> dismissLegacyReportsNotice() async {
    if (!_legacyReportsNotice) return;
    _update(() => _legacyReportsNotice = false);
    await _notices.markSeen(NoticesSeenStore.legacyReportsNotice);
  }

  void _markChecked() {
    if (isActive) _update(() => _checkedAt = DateTime.now());
  }

  /// מצב המודולים לאבחון הדיווח — בלי נתיבים ושמות קבצים של המשתמש.
  Map<String, dynamic> _reportState() {
    final s = settings.settings;
    return {
      'readOnly': readOnly,
      'otzaria': _otzaria.status.name,
      'otzariaRunning': _otzariaIsRunning,
      'library': _library.status.name,
      'plugins': _plugins.status.name,
      'customApps': _customApps.hasApps,
      'launcherUpdateReady': _launcherUpdate.hasUpdateReady,
      'autoCheckUpdates': s.autoCheckUpdates,
      'autoInstall': s.autoInstall,
      'personalUpdateMode': s.personalUpdateMode,
      'crashReportMode': s.crashReportMode.wireName,
      'language': s.language.name,
    };
  }

  Future<void> _startReports(AppReportsController reports) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!isActive) return;
    reports.startBackground();
    await reports.runCrashCheck(
      showPrompt: (candidate) async {
        final shown = await prompts.showCrashPrompt(reports, candidate);
        return shown ?? false;
      },
    );
  }

  bool get _needsElevation =>
      _library.needsElevation ||
      _otzaria.needsElevation ||
      _launcherUpdate.needsElevation;

  /// [restartElevated] יפעל עכשיו: רק ב-Windows, כשיש כשל הרשאות, ולא
  /// בזמן פעולה שיציאה קוטעת.
  bool get canRestartElevated =>
      Platform.isWindows &&
      _needsElevation &&
      !_elevationPending &&
      !exitWouldInterrupt;

  /// הפס "הפעלה מחדש כמנהל" בבית. "לא עכשיו" מסתיר אותו עד סוף ההרצה.
  bool get offersElevation => canRestartElevated && !_elevationDismissed;

  void dismissElevation() => _update(() => _elevationDismissed = true);

  Future<void> restartElevated() async {
    if (!Platform.isWindows || !_needsElevation || _elevationPending) return;
    final t = AppL10n.strings.elevation;
    if (exitWouldInterrupt) {
      UiSnack.show(t.busyNotice);
      return;
    }

    _update(() => _elevationPending = true);
    final Object? failure;
    try {
      failure = await Elevation.restartElevated();
    } finally {
      if (isActive) {
        _update(() => _elevationPending = false);
        _offers.resume();
      }
    }
    if (failure != null && failure != Elevation.cancelled) {
      UiSnack.showError(t.restartFailedSnack('$failure'));
    }
  }

  void _syncRunningPoll() {
    if (_otzariaIsRunning) _runningWatch ??= _watchUntilClosed();
  }

  Future<void> _watchUntilClosed() async {
    try {
      while (isActive && _otzariaIsRunning) {
        final exited = await runningLocator.waitForExit(_runningWatchSlice);
        if (!isActive) return;
        if (exited == null) {
          final elapsed = Completer<void>();
          _runningPoll = Timer(_runningPollInterval, elapsed.complete);
          await elapsed.future;
          if (!isActive) return;
        }
        await _otzaria.refreshRunningState();
      }
    } finally {
      _runningWatch = null;
    }
  }

  /// הצבת ערך idempotent — ה-setter מתעלם מאותו ערך, ולכן אין בדיקה חוזרת.
  void _applySettings(AppSettings s) {
    _otzaria.preferPrerelease = s.preferAppPrerelease;
    _library.personalUpdateMode = s.personalUpdateMode;
  }

  /// בדיקת תהליך טרייה מיד לפני פעולה שאוצריא הפתוחה חוסמת. `force`: אינה
  /// מסתפקת בתשובה של בדיקה שכבר הייתה באוויר.
  Future<bool> refreshProcessState() =>
      _otzaria.refreshRunningState(force: true);

  Future<bool> closeOtzaria() => _offers.holdFor(() async {
        final closed = await _otzaria.closeRunning();
        if (isActive) _syncRunningPoll();
        return closed;
      });

  bool _blockedByReadOnly() {
    if (!readOnly) return false;
    final t = AppL10n.strings.readOnlyDrive;
    UiSnack.show(
      driveFull ? t.downloadsDisabledSnackDriveFull : t.downloadsDisabledSnack,
    );
    return true;
  }

  Future<void> checkAll() async {
    await _launcherFlow.checkMirror();
    if (!isActive) return;

    await _otzaria.checkForUpdate();
    if (!isActive) return;
    unawaited(_plugins.refreshInstalled());

    await _library.checkForUpdate();
    if (!isActive) return;
    await _autoInstallIfEnabled();
    if (!isActive) return;
    _markChecked();
    await _offers.request();
  }

  Future<bool> _prepareOffer() async {
    await WidgetsBinding.instance.endOfFrame;
    await _errorReportsIntro;
    return isActive && _otzaria.launchPath != null;
  }

  Future<void> grantSemanticConsent() async {
    if (await refreshProcessState()) {
      UiSnack.showError(AppL10n.strings.home.otzariaOpenSnack);
      return;
    }
    if (!isActive) return;
    final agreed = await prompts.confirmSemanticConsent();
    if (!agreed || !isActive) return;
    final t = AppL10n.strings.libraryDomain;
    try {
      if (!await _searchFeedback.grantConsent()) {
        UiSnack.showError(t.semanticConsentRequired);
        return;
      }
      await _library.checkForUpdate();
    } catch (error, stack) {
      AppLogger.instance.error('כתיבת ההסכמה לחיפוש החכם נכשלה', error, stack);
      UiSnack.showError(t.semanticFeedbackFailed);
    }
  }

  Future<void> uploadReports() => _offers.guardedUpload(
        blocked: () => _blockedByReadOnly() || !isActive,
        run: (onActive) => prompts.uploadReports(
          isCancelled: () => _reportsStopRequested,
          onActiveChanged: onActive,
          onUploadingChanged: (uploading) {
            if (!isActive) return;
            if (uploading) _reportsStopRequested = false;
            _update(() => _uploadingReports = uploading);
            _syncSleepInhibition();
            _offers.resume();
          },
        ),
      );

  void stopReports() => _reportsStopRequested = true;

  Future<void> checkOnline() async {
    if (readOnly || _isCheckingOnline) return;
    _update(() => _isCheckingOnline = true);
    await _launcherFlow.checkMirror();
    if (!isActive) return;
    await Future.wait([
      _otzaria.checkOnline(),
      _library.checkOnline(),
      _plugins.checkOnline(),
      _launcherUpdate.checkOnline(),
    ]);
    if (!isActive) return;
    _update(() => _isCheckingOnline = false);
    _markChecked();
  }

  /// "הורדה והפעלה מחדש" בדף הכלי: מה חדש כבר מוצג בדף, ולכן אישור
  /// ההתקנה שאחרי ההורדה אינו חוזר עליו.
  Future<void> downloadLauncherUpdate() =>
      _fromLauncherPage(_launcherFlow.download);

  bool get longTaskRunning =>
      _downloads.isDownloading ||
      _library.isApplying ||
      _library.status == LibraryModuleStatus.updating ||
      _otzaria.status == OtzariaModuleStatus.installing ||
      _customApps.isBusy ||
      _customApps.isLearning ||
      _customApps.isDownloadingAll ||
      _plugins.isExporting ||
      _plugins.isSyncing ||
      _plugins.isUpdatingAll ||
      exitPending;

  bool get pluginSyncBlockedElsewhere =>
      _downloads.isDownloading ||
      _library.isApplying ||
      _library.status == LibraryModuleStatus.updating ||
      _otzaria.status == OtzariaModuleStatus.installing ||
      _customApps.isBusy;

  bool get exitPending => _elevationPending || _launcherUpdate.isInstalling;

  void _syncSleepInhibition() => _sleepInhibitor.setActive(
        exitWouldInterrupt ||
            _launcherUpdate.isDownloading ||
            _library.downloadStatus == MirrorDownloadStatus.downloading ||
            _otzaria.downloadStatus == OtzariaDownloadStatus.downloading ||
            _plugins.isAwaitingInstall,
      );

  bool get exitWouldInterrupt =>
      longTaskRunning ||
      _errorReports.isCollecting ||
      _errorReports.isUploading ||
      _searchFeedback.isCollecting ||
      _searchFeedback.isUploading ||
      _uploadingReports;

  Future<void> installLauncherUpdate() =>
      _fromLauncherPage(_launcherFlow.install);

  Future<void> _fromLauncherPage(Future<void> Function() action) async {
    if (!isActive) return;
    _whatsNewAlreadyShown = true;
    try {
      await action();
    } finally {
      _whatsNewAlreadyShown = false;
    }
  }

  Future<bool> _confirmLauncherInstall(String version) =>
      prompts.confirmLauncherInstall(
        version,
        whatsNew:
            _whatsNewAlreadyShown ? null : _launcherUpdate.downloadedWhatsNew,
      );

  Future<void> _autoInstallIfEnabled() async {
    final skippedWhileRunning = await _autoInstall.run(
      enabled: settings.settings.autoInstall,
    );
    if (isActive) _update(() => _autoInstallSkipped = skippedWhileRunning);
  }

  @visibleForTesting
  Map<MirrorComponent, List<String>> get downloadMirrorDirs => {
        MirrorComponent.app: [_otzaria.mirrorDir],
        MirrorComponent.library: [
          _library.mirrorDir,
          _library.companionsMirrorDir,
          _library.semanticMirrorDir,
        ],
        MirrorComponent.plugins: _plugins.mirrorDirs,
      };

  Future<void> cancelDownload() async {
    if (!_downloads.isDownloading || _downloads.isCancelling || !isActive) {
      return;
    }
    final approved = await prompts.confirmCancelDownload();
    if (!approved || !isActive || !_downloads.isDownloading) return;
    _downloads.requestCancel();
  }

  /// [LauncherCrashSession.closeGuard]: שואל רק בזמן פעולה ארוכה, ומבטל
  /// הורדה (עם שחזור המראה) לפני שהחלון נסגר.
  Future<bool> confirmClose() async {
    // הסגירה מסתיימת ב-`exit`, ושום dispose לא ירוץ אחריה.
    await _faq.flush().timeout(const Duration(seconds: 1), onTimeout: () {});
    // גם במסירת התוספים, שאינה longTask; בשאלות (סגירת אוצריא, משתמש אחר) עוד לא רץ דבר.
    final updatingHere = switch (tasks.current) {
      UpdateHereTask(phase: UpdateHereTaskPhase.running) => true,
      _ => false,
    };
    if (!isActive || !(longTaskRunning || updatingHere)) return true;
    final approved = await prompts.confirmClose(
      downloading: _downloads.isDownloading,
    );
    if (!approved) return false;
    if (!isActive) return true;
    await _downloads.cancelAndWait();
    return true;
  }

  /// המסך עובר ל"מתכונן" מיד — גם מ"נסה שוב" במסך שהסתיים, וגם כשניקוי
  /// קודם עוד רץ. זרימה שחזרה בלי להתחיל סוגרת אותו.
  Future<void> downloadAll() async {
    if (_blockedByReadOnly() || tasks.isRunning) return;
    if (!settings.settings.hasSyncSelection) {
      prompts.notifyNoSyncSelection();
      return;
    }
    if (longTaskRunning || _launcherUpdate.isDownloading) {
      UiSnack.show(AppL10n.strings.guide.downloadBusySnack);
      return;
    }
    final request = ++_downloadRequest;
    tasks.prepareDownload();
    await _downloads.downloadAll();
    // בקשה שבוטלה לא סוגרת את המסך של בקשה חדשה שנפתחה אחריה.
    if (isActive && request == _downloadRequest) tasks.abandonDownload();
  }

  int _downloadRequest = 0;

  /// "ביטול" ב"מתכונן להורדה": המסך נסגר, והזרימה עוצרת אחרי הבדיקה ברשת.
  void abandonPreparingDownload() {
    _downloads.abandonPreparing();
    tasks.abandonDownload();
  }

  /// "עדכון כאן". מדף התוכנה [reinstallApp] — אותה גרסה שוב; מדף הספרייה
  /// [fullLibrary] — הספרייה המלאה במקום עדכון שנכשל.
  Future<void> updateHere(
    List<GuidanceItem> items, {
    bool reinstallApp = false,
    bool fullLibrary = false,
  }) async {
    if (tasks.isRunning || exitPending || !isActive) return;
    await _updateHere.run(
      items,
      reinstallApp: reinstallApp,
      fullLibrary: fullLibrary,
    );
  }

  Future<void> retryUpdateHere() async {
    if (tasks.isRunning || exitPending || !isActive) return;
    if (await _updateHere.retry() || !isActive) return;
    tasks.dismiss();
    UiSnack.show(AppL10n.strings.task.retryNothingSnack);
  }

  void stopWaitingForSetup() => _updateHere.stopWaiting();

  Future<void> _refreshStaleOnlineChecks(AppSettings s) async {
    final stale = StaleOnlineChecks.of(
      s,
      app: OnlineCheckStamp(
        checkedAt: _otzaria.onlineCheckedAt,
        error: _otzaria.onlineCheckError,
      ),
      library: OnlineCheckStamp(
        checkedAt: _library.onlineCheckedAt,
        error: _library.onlineCheckError,
      ),
      catalog: OnlineCheckStamp(
        checkedAt: _plugins.onlineCheckedAt,
        error: _plugins.onlineCheckError,
      ),
      storeApp: OnlineCheckStamp(
        checkedAt: _plugins.storeAppCheckedAt,
        error: _plugins.storeAppCheckError,
      ),
    );
    if (!stale.any) return;
    final ownsCheckingFlag = !_isCheckingOnline;
    if (ownsCheckingFlag) _update(() => _isCheckingOnline = true);
    try {
      await Future.wait([
        if (stale.app) _otzaria.checkOnline(),
        if (stale.library) _library.checkOnline(),
        if (stale.plugins) _plugins.checkOnline(),
      ]);
    } finally {
      if (ownsCheckingFlag && isActive) {
        _update(() => _isCheckingOnline = false);
      }
    }
  }

  Future<DownloadRollback> _captureDownloadRollback() =>
      CancelledDownloadRollback.capture(
        otzaria: _otzaria,
        library: _library,
        plugins: _plugins,
        mirrorDirs: downloadMirrorDirs,
      );

  void _rebuild() {
    if (!isActive) return;
    _syncSleepInhibition();
    notifyListeners();
    _offers.resume();
  }

  Future<void> _sweepMirrorJunk() async {
    final freed = await MirrorJunkSweeper(dataDir: dataDir).sweep();
    if (freed > 0) {
      AppLogger.instance.info('ניקוי המראה פינה ${formatBytes(freed)}');
    }
  }

  /// מציע ומוסר לאוצריא את בקשת עדכון אינדקס החיפוש. הסימון נמחק רק אחרי
  /// מסירה מוצלחת — סירוב או כשל משאירים אותו, וההצעה תחזור.
  Future<void> requestLibraryReindex() async {
    if (!_library.hasPendingReindex || !isActive) return;

    final approved = await prompts.confirmLibraryReindex();
    if (!approved) return;
    await deliverLibraryReindex();
  }

  /// מוסר את הבקשה בלי לשאול — הלחיצה במסך הסיום היא האישור.
  Future<void> deliverLibraryReindex() async {
    if (!_library.hasPendingReindex || !isActive) return;
    final t = AppL10n.strings.libraryScreen;
    if (await _otzaria.requestLibraryReindex()) {
      await _library.markReindexRequestDelivered();
      UiSnack.showSuccess(t.reindexRequestedSnack);
      return;
    }
    UiSnack.showError(t.reindexFailedSnack(_otzaria.errorMessage ?? ''));
  }

  Future<void> openLogFolder() async {
    final logger = AppLogger.instance;
    if (await FileReveal.revealDirectory(logger.logDir)) return;
    UiSnack.show(AppL10n.strings.shell.logPathFallback(logger.filePath));
  }

  /// אישורי התוכנות הנוספות נשמרים במחשב, לעולם לא על הכונן.
  static String? _customAppsTrustFile() {
    final dir = AppPaths.machineStateDir(
      Platform.environment,
      isWindows: Platform.isWindows,
      isMacOS: Platform.isMacOS,
    );
    return dir == null ? null : p.join(dir, 'custom_apps_trust.json');
  }

  /// "בדוק עכשיו" ו"בדוק שוב" בבית: הכונן והמחשב, ואז האתר. בכונן מוגן —
  /// רק הבדיקה המקומית. `checkAll` כולל את ההתקנה האוטומטית, אם היא דלוקה.
  Future<void> checkNow() async {
    if (checkNowBlocked || isCheckingNow || !isActive) return;
    await _asCheck(() async {
      await checkAll();
      if (!isActive || readOnly) return;
      await checkOnline();
    });
  }

  Future<void> _asCheck(Future<void> Function() check) async {
    _update(() => _checkingNow = true);
    try {
      await check();
    } finally {
      if (isActive) _update(() => _checkingNow = false);
    }
  }

  /// Ctrl+R/F5: קורא מחדש מה מותקן ומה יש על הכונן, בלי ההצעות של העלייה.
  Future<void> refreshFromKeyboard() async {
    // לא `longTaskRunning` עצמו: `isBlocked` של ההורדה נשען עליו, והיה
    // עוצר את ההורדה של המשימה עצמה.
    if (longTaskRunning || tasks.isRunning) return;
    await _launcherFlow.checkMirror();
    if (!isActive) return;
    await _otzaria.checkForUpdate();
    if (!isActive) return;
    unawaited(_plugins.refreshInstalled());
    await _library.checkForUpdate();
    _markChecked();
  }
}

class _SessionDownloadHost implements MirrorDownloadHost {
  _SessionDownloadHost(this._session);

  final AppSession _session;

  @override
  bool get isActive => _session.isActive;

  @override
  bool get isBlocked =>
      _session.longTaskRunning || _session._launcherUpdate.isDownloading;

  @override
  bool get launcherDownloading => _session._launcherUpdate.isDownloading;

  @override
  AppSettings get settings => _session.settings.settings;

  @override
  Future<void> refreshStaleOnlineChecks(AppSettings s) =>
      _session._refreshStaleOnlineChecks(s);

  @override
  Future<bool?> confirmSemanticSearch() => _session.tasks.askBeforeDownload();

  @override
  Future<DownloadRollback> captureRollback() =>
      _session._captureDownloadRollback();

  @override
  Future<void> sweepMirror() => _session._sweepMirrorJunk();

  @override
  void stateChanged() {
    final flow = _session._downloads;
    if (flow.isDownloading) {
      _session.tasks.downloadRunning(
        flow.activeComponents,
        expectedBytes: _session.expectedDownloadBytes,
      );
    }
    _session._rebuild();
  }

  @override
  void downloadSnapshotFailed(Object error) {
    AppLogger.instance.info('mirror snapshot failed: $error');
    _session.tasks.downloadFailed(
      DownloadFailure(DownloadFailureKind.snapshot, details: '$error'),
    );
  }

  @override
  void downloadCancelled({
    Object? revertError,
    List<MirrorComponent> kept = const [],
  }) {
    if (revertError != null) {
      AppLogger.instance
          .info('revert after cancelled download failed: $revertError');
    }
    _session.tasks.downloadCancelled(
      revertFailed: revertError != null,
      kept: kept,
    );
  }

  @override
  void downloadEnded() {}

  @override
  void downloadCrashed(
    Object error,
    StackTrace stackTrace, {
    bool abandoned = false,
  }) {
    AppLogger.instance.error('ההורדה נעצרה בחריג', error, stackTrace);
    final task = _session.tasks.current;
    if (abandoned ||
        task is! DownloadTask ||
        task.isFinished ||
        task.phase == DownloadTaskPhase.question) {
      return;
    }
    _session.tasks.downloadFailed(
      DownloadFailure(DownloadFailureKind.other, details: '$error'),
    );
  }

  @override
  void downloadFinished({
    required List<MirrorComponent> failed,
    required List<MirrorComponent> skipped,
  }) {
    final s = _session;
    if (failed.isEmpty) {
      s.tasks.downloadDone(skipped: skipped);
    } else {
      s.tasks.downloadFailed(classifyDownloadFailure(
        failed: failed,
        errors: {
          MirrorComponent.app: s._otzaria.downloadError,
          MirrorComponent.library: s._library.downloadError,
          MirrorComponent.plugins:
              s._plugins.errorMessage ?? s._plugins.shabbatNotice,
        },
        shabbat: s._plugins.shabbatNotice != null,
      ));
    }
  }
}

class _SessionUpdateHost implements UpdateHereHost {
  _SessionUpdateHost(this._session);

  final AppSession _session;

  @override
  bool get isActive => _session.isActive;

  @override
  ShellTasks get tasks => _session.tasks;

  @override
  Future<bool> isOtzariaRunning() => _session.refreshProcessState();

  @override
  Future<bool> closeOtzaria() => _session.closeOtzaria();

  @override
  void closeFailed() =>
      UiSnack.showError(AppL10n.strings.common.closeOtzariaFailedSnack);
}

class _SessionLauncherHost implements LauncherUpdateHost {
  _SessionLauncherHost(this._session);

  final AppSession _session;

  @override
  bool get isActive => _session.isActive;

  @override
  bool get isReadOnly => _session.readOnly;

  @override
  bool blockedByReadOnly() => _session._blockedByReadOnly();

  @override
  bool get wouldInterrupt => _session.exitWouldInterrupt;

  @override
  Future<bool> confirmInstall(String version) =>
      _session._confirmLauncherInstall(version);

  @override
  void notify(LauncherUpdateNotice notice, {String? detail}) =>
      _session.prompts.notifyLauncherUpdate(notice, detail ?? '');
}
