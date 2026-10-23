import 'dart:async';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../controllers/app_reports_controller.dart';
import '../controllers/download_plan.dart';
import '../controllers/download_summary.dart';
import '../controllers/launcher_update_flow.dart';
import '../controllers/plugins_module_controller.dart' show PluginsModuleStatus;
import '../flows/home_flows.dart';
import '../self_update/launcher_release.dart';
import '../services/app_paths.dart';
import '../services/byte_size.dart';
import '../services/dialog_queue.dart';
import '../services/notices_seen_store.dart';
import '../services/sleep_inhibitor.dart';
import '../settings/app_settings.dart';
import '../settings/safer_mode.dart';
import '../settings/settings_controller.dart';
import '../shell/app_session.dart';
import '../shell/home_guidance.dart';
import '../shell/home_guidance_session.dart';
import '../shell/session_prompts.dart';
import '../shell/shell_keys.dart';
import '../shell/shell_navigator.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';
import 'app_report/crash_prompt_dialog.dart';
import 'custom_apps/custom_apps_screen.dart';
import 'error_reports_flow.dart';
import 'faq/faq_dialog.dart';
import 'home/home_page.dart';
import 'home/home_progress.dart';
import 'home/home_view_model.dart';
import 'library_screen.dart';
import 'otzaria_screen.dart';
import 'plugins/plugins_screen.dart';
import 'reports/reports_section.dart';
import 'reports_upload_flow.dart';
import 'settings_screen.dart';

/// כפתור השפה שבמסך הפתיחה: עברית ↔ אנגלית, ונשמר בהגדרות.
Future<void> toggleAppLanguage(SettingsController settings) {
  final current = settings.settings;
  final next = current.language == AppLanguage.hebrew
      ? AppLanguagePreference.english
      : AppLanguagePreference.hebrew;
  return settings.update(current.copyWith(languagePreference: next));
}

/// מסגרת האפליקציה: שורת כותרת מותאמת למעלה, ומתחתיה הגוף — הבית או דף
/// משנה שנפתח ממנו. אין סרגל ניווט ואין דף שמכסה את שורת הכותרת.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.dataDir,
    required this.settings,
    String? stateDir,
    this.readOnly = false,
    this.driveFull = false,
    this.runningLocator = const RunningOtzariaLocator(),
    this.showWindowButtons,
    this.noticesStore,
    this.appReports,
    this.sleepInhibitor,
    this.searchFeedback,
    this.errorReports,
  }) : _stateDir = stateDir;

  /// התיקייה שלצד התוכנה — המראה, כלומר המקור שממנו קוראים ומתקינים.
  final String dataDir;

  final String? _stateDir;

  /// לאן נכתבים לוג, הגדרות ומצב. זהה ל-[dataDir] בהרצה רגילה — ראו
  /// [AppPaths.stateDir].
  String get stateDir => _stateDir ?? dataDir;

  /// קובצי המצב יושבים בתיקיית הלוגים — ראו [AppPaths.stateFilesDir].
  String get stateFilesDir => p.join(stateDir, AppPaths.logsDirName);

  final bool readOnly;
  final bool driveFull;

  final SettingsController settings;

  /// בדיקת "אוצריא פתוחה?" — מוזרקת כדי שבדיקות widget לא יריצו בדיקה
  /// אמיתית ב-isolate, שמשאירה טיימר תלוי ומפילה את הבדיקה.
  final RunningOtzariaLocator runningLocator;

  /// ראו [AppTitleBar.showWindowButtons] — מוזרק `false` בבדיקות widget.
  final bool? showWindowButtons;

  /// "אילו הודעות הוצגו". מוזרק בבדיקות: קריאת דיסק אמיתית אינה מסתיימת
  /// בתוך ה-fake-async, ובלי זה הודעה יכולה לצוץ באמצע בדיקה שאינה שלה.
  final NoticesSeenStore? noticesStore;

  /// הדיווחים של הלאנצ'ר על עצמו — נוצר ב-`main`, ו-`null` בבדיקות: הוא
  /// מפעיל טיימר שליחה ופונה לרשת.
  final AppReportsController? appReports;

  final SleepInhibitor? sleepInhibitor;

  /// מוזרק בבדיקות; המסגרת לוקחת עליו בעלות ומשחררת אותו בפירוק.
  final SearchFeedbackController? searchFeedback;

  /// מוזרק בבדיקות; המסגרת לוקחת עליו בעלות ומשחררת אותו בפירוק.
  final ErrorReportsController? errorReports;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> implements SessionPrompts {
  late final AppSession _session;
  late final ShellNavigator _navigator = ShellNavigator(canEnter: _canEnter);

  late final DialogQueue _dialogs = DialogQueue(
    isActive: () => mounted,
    isBlocked: () =>
        _session.exitPending || !(ModalRoute.of(context)?.isCurrent ?? true),
  );

  @visibleForTesting
  AppSession get session => _session;

  @visibleForTesting
  ShellNavigator get navigator => _navigator;

  @override
  void initState() {
    super.initState();
    _session = AppSession(
      dataDir: widget.dataDir,
      stateDir: widget.stateDir,
      settings: widget.settings,
      prompts: this,
      readOnly: widget.readOnly,
      driveFull: widget.driveFull,
      runningLocator: widget.runningLocator,
      noticesStore: widget.noticesStore,
      appReports: widget.appReports,
      sleepInhibitor: widget.sleepInhibitor,
    )
      ..addListener(_onSessionChange)
      ..addListener(_onSessionChangeInStore);
    _navigator
      ..addListener(_onSessionChange)
      ..addListener(_onNavigation);
    _session.start();
  }

  @override
  void dispose() {
    _dialogs.dispose();
    _navigator
      ..removeListener(_onSessionChange)
      ..removeListener(_onNavigation)
      ..dispose();
    _session
      ..removeListener(_onSessionChange)
      ..removeListener(_onSessionChangeInStore)
      ..dispose();
    super.dispose();
  }

  void _onSessionChange() {
    if (mounted) setState(() {});
  }

  /// מה שמוצג בחנות "מוזכר" — גם תוסף שהגיע בסנכרון בזמן שהמשתמש בה, כדי
  /// שלא יופיע אחר כך בבית כ"חדש".
  void _onNavigation() {
    if (_navigator.section == ShellSection.plugins) {
      unawaited(_session.markPluginsVisited());
    }
  }

  void _onSessionChangeInStore() {
    // תוסף שנמחק בסנכרון בזמן שפרטיו מוצגים — חוזרים לרשימה, כדי שחזרה אחת תספיק.
    if (_navigator.current case PluginDetailRoute(:final id)
        when _session.plugins.status == PluginsModuleStatus.ready &&
            _session.plugins.byId(id) == null) {
      _navigator.back();
    }
    if (_navigator.section == ShellSection.plugins &&
        _session.newPluginsForHome.isNotEmpty) {
      unawaited(_session.markPluginsVisited());
    }
  }

  @override
  Future<T?> runDialog<T>(Future<T> Function() body, {bool forever = false}) =>
      _dialogs.run(body, forever: forever);

  @override
  Future<bool?> showCrashPrompt(
    AppReportsController reports,
    CrashCandidate candidate,
  ) =>
      _dialogs.run(
        () async {
          await showCrashPromptDialog(
            context,
            reports: reports,
            candidate: candidate,
            saferMode: _session.saferMode,
          );
          return true;
        },
        forever: true,
      );

  @override
  Future<bool?> offerLauncherUpdate(LauncherRelease release, String? whatsNew) {
    final t = context.strings.launcherUpdate;
    return _dialogs.run(
      () => showTwoActionsDialog(
        context: context,
        title: t.availableDialogTitle,
        content: '${t.availableDialogContent(release.version)}\n\n'
            '${t.availableDialogDetail(formatBytes(release.sizeBytes))}',
        customContent: whatsNew == null
            ? null
            : WhatsNewSection(heading: t.whatsNewHeading, markdown: whatsNew),
        cancelText: t.availableDialogCancel,
        confirmText: t.availableDialogConfirm,
      ),
    );
  }

  @override
  Future<bool> confirmLauncherInstall(String version, {String? whatsNew}) {
    final t = context.strings.launcherUpdate;
    return showTwoActionsDialog(
      context: context,
      title: t.readyDialogTitle,
      content: t.readyDialogContent(version),
      customContent: whatsNew == null
          ? null
          : WhatsNewSection(heading: t.whatsNewHeading, markdown: whatsNew),
      confirmText: t.readyDialogConfirm,
    );
  }

  @override
  void notifyLauncherUpdate(LauncherUpdateNotice notice, String detail) {
    final t = AppL10n.strings.launcherUpdate;
    switch (notice) {
      case LauncherUpdateNotice.downloaded:
        UiSnack.showSuccess(t.downloadedSnack(detail));
      case LauncherUpdateNotice.busy:
        UiSnack.show(t.busyNotice);
      case LauncherUpdateNotice.installing:
        UiSnack.show(t.installingSnack);
      case LauncherUpdateNotice.installFailed:
        UiSnack.showError(detail);
      case LauncherUpdateNotice.manualRestart:
        UiSnack.show(t.manualRestartNotice);
    }
  }

  @override
  Future<bool> confirmCancelDownload() {
    final t = context.strings.home;
    return showWarningDialog(
      context: context,
      title: t.cancelDownloadDialogTitle,
      content: t.cancelDownloadPrompt,
      cancelText: t.cancelDownloadKeepGoing,
      confirmText: t.cancelDownloadButton,
    );
  }

  @override
  Future<bool> confirmClose({required bool downloading}) {
    final t = context.strings.shell;
    return showWarningDialog(
      context: context,
      title: t.closeWhileBusyTitle,
      content: downloading
          ? t.closeWhileDownloadingPrompt
          : t.closeWhileInstallingPrompt,
      cancelText: t.closeWhileBusyKeepGoing,
      confirmText: downloading
          ? t.closeWhileDownloadingConfirm
          : t.closeWhileInstallingConfirm,
    );
  }

  @override
  Future<bool> confirmSemanticSearch() => showTwoActionsDialog(
        context: context,
        title: context.strings.libraryDomain.companionSemanticName,
        content: context.strings.libraryDomain.semanticDownloadPrompt,
        confirmText: context.strings.home.downloadNowButton,
      );

  @override
  Future<bool> confirmSemanticConsent() {
    final t = context.strings.libraryDomain;
    return showTwoActionsDialog(
      context: context,
      title: t.semanticConsentTitle,
      content: t.semanticConsentText,
      confirmText: t.semanticConsentConfirm,
    );
  }

  @override
  Future<bool> confirmLibraryReindex() {
    final t = context.strings.libraryScreen;
    return showTwoActionsDialog(
      context: context,
      title: t.reindexDialogTitle,
      content: t.reindexDialogContent,
      confirmText: t.reindexDialogConfirm,
    );
  }

  @override
  void reportDownload({
    required List<MirrorComponent> failed,
    required List<MirrorComponent> skipped,
  }) {
    final t = context.strings;
    String label(MirrorComponent component) => switch (component) {
          MirrorComponent.app => t.guide.tileApp,
          MirrorComponent.library => t.guide.tileLibrary,
          MirrorComponent.plugins => t.guide.tilePlugins,
        };
    final failedLabels = [for (final c in failed) label(c)];
    final skippedLabels = [for (final c in skipped) label(c)];

    switch (summarizeDownload(failed: failedLabels, skipped: skippedLabels)) {
      case DownloadSummary.failed:
        UiSnack.show(t.home.downloadFailedSnack(failedLabels.join(', ')));
      case DownloadSummary.skipped:
        UiSnack.show(t.home.downloadSkippedSnack(skippedLabels.join(', ')));
      case DownloadSummary.done:
        UiSnack.showSuccess(t.home.downloadDoneSnack);
    }
  }

  @override
  Future<void> uploadReports({
    required bool Function() isCancelled,
    required void Function(bool active) onActiveChanged,
    required void Function(bool uploading) onUploadingChanged,
  }) =>
      uploadAllReports(
        context,
        errorReports: _session.errorReports,
        searchFeedback: _session.searchFeedback,
        isCancelled: isCancelled,
        onActiveChanged: onActiveChanged,
        onUploadingChanged: onUploadingChanged,
      );

  Future<void> _goTo(ShellSection section) => _navigator.select(section);

  /// שער הניווט: ההגדרות (וניהול התוכנות שתחתן) נעולות במצב הסייפר. השער
  /// בנווט ולא במסך, כי מסך שנבנה נשאר בעץ ושער בתוכו היה נשאר פתוח.
  FutureOr<bool> _canEnter(ShellSection section) {
    final saferMode = _session.saferMode;
    if (section != ShellSection.settings || !saferMode.isLocked) return true;
    return _unlockSaferMode(saferMode);
  }

  Future<bool> _unlockSaferMode(SaferModeGate saferMode) async {
    final unlocked = await showSaferModePasswordDialog(
      context,
      storedPassword: widget.settings.settings.saferModePassword,
      hint: context.strings.saferMode.verifySettingsHint,
    );
    if (!unlocked || !mounted) return false;
    saferMode.unlock();
    return true;
  }

  void _openHelp() => unawaited(
        showFaqDialog(
          context,
          faq: _session.faq,
          saferMode: _session.saferMode,
        ),
      );

  void _toggleLanguage() => unawaited(toggleAppLanguage(widget.settings));

  HomeFlowDeps get _flowDeps => HomeFlowDeps(
        otzaria: _session.otzaria,
        library: _session.library,
        isOtzariaRunning: _session.refreshProcessState,
        closeOtzaria: _session.closeOtzaria,
        onRequestReindex: _session.requestLibraryReindex,
      );

  Future<void> _collectReports() async {
    final s = _session;
    await offerErrorReportCollection(
      context,
      s.errorReports,
      readOnly: widget.readOnly,
      isOtzariaRunning: s.refreshProcessState,
      searchFeedback: s.searchFeedback,
      // הגילוי בדף והלחיצה הם האישור; התורים הישנים — רק הפס שבבית.
      confirm: false,
    );
    if (mounted) await s.recountReportsToCollect();
  }

  late final HomeActions _homeActions = HomeActions(
    onInstallHere: () => unawaited(installOtzariaHere(context, _flowDeps)),
    onUpdateHere: () => unawaited(
      updateHere(
        context,
        _flowDeps,
        items: homeViewModelOf(_session).guidance.hereItems,
        onPluginsOnly: () => unawaited(_goTo(ShellSection.plugins)),
      ),
    ),
    onDownload: () => unawaited(_session.downloadAll()),
    onLaunch: () => unawaited(_session.otzaria.launch()),
    onRecheck: () => unawaited(_session.checkNow()),
    onCancelDownload: () => unawaited(_session.cancelDownload()),
    onOpenSection: (section) => unawaited(_goTo(section)),
    onOpenSettings: () => unawaited(_goTo(ShellSection.settings)),
    onHelp: _openHelp,
    onToggleLanguage: _toggleLanguage,
    onDismissReportsIntro: () => unawaited(_session.dismissReportsIntro()),
    onDismissLegacyReports: () =>
        unawaited(_session.dismissLegacyReportsNotice()),
    onRestartElevated: () => unawaited(_session.restartElevated()),
    onDismissElevation: _session.dismissElevation,
    onReviewLauncherUpdate: () => unawaited(_session.reviewLauncherUpdate()),
    onInstallLauncherUpdate: () => unawaited(_session.installLauncherUpdate()),
  );

  Widget _home() {
    final s = _session;
    return ListenableBuilder(
      // מוני הדיווחים והשליחה אינם מעירים את הסשן כולו.
      listenable: Listenable.merge([s.errorReports, s.searchFeedback]),
      builder: (context, _) {
        final model = homeViewModelOf(s);
        return HomePage(
          model: model,
          actions: _homeActions,
          taskProgress: model.guidance.primary == GuidancePrimary.taskInProgress
              ? HomeTaskProgress(
                  task: model.task,
                  otzaria: s.otzaria,
                  library: s.library,
                  plugins: s.plugins,
                )
              : null,
          launcherProgress:
              LauncherDownloadPercent(controller: s.launcherUpdate),
        );
      },
    );
  }

  String _sectionLabel(BuildContext context, ShellSection section) {
    final g = context.strings.guide;
    return switch (section) {
      ShellSection.home => context.strings.shell.breadcrumbHome,
      ShellSection.otzaria => g.tileApp,
      ShellSection.library => g.tileLibrary,
      ShellSection.plugins => g.tilePlugins,
      ShellSection.customApps => g.tileCustomApps,
      ShellSection.reports => g.tileReports,
      ShellSection.settings => context.strings.settings.title,
      ShellSection.help => context.strings.shell.helpTooltip,
    };
  }

  /// דף הפרטים שמוצג עכשיו במקטע — נתיב בנווט, כך שחזרה ו-Esc מובילים
  /// לרשימה, ובכניסה מחדש למקטע מוצגת הרשימה.
  String? _detailId(ShellSection section) => switch (_navigator.current) {
        PluginDetailRoute(:final id) when section == ShellSection.plugins => id,
        CustomAppDetailRoute(:final id)
            when section == ShellSection.customApps =>
          id,
        _ => null,
      };

  void _showDetail(ShellSection section, String? id) {
    if (id == null) {
      if (_detailId(section) != null) _navigator.back();
      return;
    }
    unawaited(
      _navigator.push(
        section == ShellSection.plugins
            ? PluginDetailRoute(id)
            : CustomAppDetailRoute(id),
      ),
    );
  }

  String? _detailLabel(ShellSection section, String id) => switch (section) {
        ShellSection.plugins => _session.plugins.byId(id)?.name,
        ShellSection.customApps => _session.customApps.apps
            .where((app) => app.descriptor.id == id)
            .firstOrNull
            ?.descriptor
            .name,
        _ => null,
      };

  Widget _sectionWidget(BuildContext context, ShellSection section) {
    if (section == ShellSection.home) return _home();
    final screen = _subPage(section);
    final label = _sectionLabel(context, section);
    final detail = _detailId(section);
    final detailLabel = detail == null ? null : _detailLabel(section, detail);
    return SubPageHeaderScope(
      header: SubPageHeader(
        onBack: _navigator.back,
        onHome: () => unawaited(_goTo(ShellSection.home)),
        trail: [
          if (detailLabel == null)
            (label: label, onTap: null)
          else ...[
            (label: label, onTap: _navigator.back),
            (label: detailLabel, onTap: null),
          ],
        ],
      ),
      child: screen,
    );
  }

  Widget _subPage(ShellSection section) {
    final s = _session;
    return switch (section) {
      ShellSection.otzaria => OtzariaScreen(
          otzaria: s.otzaria,
          settings: widget.settings,
          otzariaIsRunning: s.otzariaIsRunning,
          onCloseOtzaria: s.closeOtzaria,
          onInstallAdopted: s.plugins.refreshInstalled,
          saferMode: s.saferMode,
        ),
      ShellSection.customApps => CustomAppsScreen(
          controller: s.customApps,
          readOnly: widget.readOnly,
          detailId: _detailId(ShellSection.customApps),
          onDetailChanged: (id) => _showDetail(ShellSection.customApps, id),
        ),
      ShellSection.library => LibraryScreen(
          library: s.library,
          otzariaIsRunning: s.otzariaIsRunning,
          isDownloading: s.isDownloading,
          onProcessStateChanged: s.refreshProcessState,
          onCloseOtzaria: s.closeOtzaria,
          onRequestReindex: s.requestLibraryReindex,
          onGoToSettings: () => unawaited(_goTo(ShellSection.settings)),
          onGrantSemanticConsent: s.grantSemanticConsent,
        ),
      ShellSection.plugins => PluginsScreen(
          controller: s.plugins,
          onRequestFocus: () => unawaited(_goTo(ShellSection.plugins)),
          readOnly: widget.readOnly,
          driveFull: widget.driveFull,
          busyElsewhere: s.pluginSyncBlockedElsewhere,
          detailId: _detailId(ShellSection.plugins),
          onDetailChanged: (id) => _showDetail(ShellSection.plugins, id),
        ),
      ShellSection.reports => ReportsSection(
          errorReports: s.errorReports,
          searchFeedback: s.searchFeedback,
          connection: s.isCheckingOnline ? null : onlineState(s),
          isUploadingAll: s.uploadingReports,
          busy: s.longTaskRunning,
          reportsToCollect: s.errorReportsToCollect,
          searchRecordsToCollect: s.searchRecordsToCollect,
          onCollect: () => unawaited(_collectReports()),
          onUpload: s.uploadReports,
          onStop: s.stopReports,
          readOnly: widget.readOnly,
          driveFull: widget.driveFull,
        ),
      ShellSection.settings => SettingsScreen(
          controller: widget.settings,
          onOpenLog: s.openLogFolder,
          launcherVersion: s.launcherUpdate.currentVersion,
          saferMode: s.saferMode,
          customApps: s.customApps,
          readOnly: widget.readOnly,
          driveFull: widget.driveFull,
          appReports: widget.appReports,
        ),
      // העזרה עדיין דו-שיח (`showFaqDialog`), ואין אליה ניווט.
      ShellSection.home || ShellSection.help => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            unawaited(_session.refreshFromKeyboard()),
        const SingleActivator(LogicalKeyboardKey.f5): () =>
            unawaited(_session.refreshFromKeyboard()),
        const SingleActivator(LogicalKeyboardKey.escape): _navigator.back,
      },
      child: Focus(autofocus: true, child: _scaffold(context)),
    );
  }

  Widget _scaffold(BuildContext context) {
    final section = _navigator.section;
    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      // כפתורי החלון נשארים פעילים גם כשהיציאה ממתינה.
      body: Column(
        children: [
          AppTitleBar(
            onHelp: _openHelp,
            onSettings: () => unawaited(_goTo(ShellSection.settings)),
            activeTool:
                section == ShellSection.settings ? TitleBarTool.settings : null,
            toolsEnabled: !_session.exitPending,
            showWindowButtons: widget.showWindowButtons,
          ),
          Expanded(
            child: AbsorbPointer(
              absorbing: _session.exitPending,
              child: ExcludeFocus(
                excluding: _session.exitPending,
                child: _body(context, section),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// מקטע נבנה בכניסה הראשונה אליו ונשאר; רק המוצג מריץ טיקרים.
  Widget _body(BuildContext context, ShellSection current) => IndexedStack(
        key: ShellKeys.sectionStack,
        index: current.index,
        children: [
          for (final section in ShellSection.values)
            _navigator.isBuilt(section)
                ? TickerMode(
                    enabled: section == current,
                    child: _sectionWidget(context, section),
                  )
                : const SizedBox.shrink(),
        ],
      );
}
