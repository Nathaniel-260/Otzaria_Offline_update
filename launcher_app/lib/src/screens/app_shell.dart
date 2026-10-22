import 'dart:async';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

import '../controllers/app_reports_controller.dart';
import '../controllers/download_plan.dart';
import '../controllers/download_summary.dart';
import '../controllers/launcher_update_flow.dart';
import '../self_update/launcher_release.dart';
import '../services/app_paths.dart';
import '../services/byte_size.dart';
import '../services/dialog_queue.dart';
import '../services/notices_seen_store.dart';
import '../services/sleep_inhibitor.dart';
import '../settings/safer_mode.dart';
import '../settings/settings_controller.dart';
import '../shell/app_session.dart';
import '../shell/session_prompts.dart';
import '../shell/shell_navigator.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';
import 'app_report/crash_prompt_dialog.dart';
import 'custom_apps/custom_apps_screen.dart';
import 'error_reports_flow.dart';
import 'faq/faq_dialog.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'otzaria_screen.dart';
import 'plugins/plugins_screen.dart';
import 'reports_upload_flow.dart';
import 'settings_screen.dart';

/// המסך הפעיל בסרגל הניווט. [customApps] מופיע בסרגל רק אחרי שהמשתמש
/// הוסיף תוכנה משלו.
enum LauncherScreen { home, otzaria, library, plugins, customApps, settings }

/// מסגרת האפליקציה: שורת כותרת מותאמת למעלה, סרגל ניווט קבוע בצד, וחמשת
/// המסכים.
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

  LauncherScreen get _screen => _screenOf(_navigator.section);

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
    )..addListener(_onSessionChange);
    _navigator.addListener(_onSessionChange);
    _session.start();
  }

  @override
  void dispose() {
    _dialogs.dispose();
    _navigator
      ..removeListener(_onSessionChange)
      ..dispose();
    _session
      ..removeListener(_onSessionChange)
      ..dispose();
    super.dispose();
  }

  void _onSessionChange() {
    if (mounted) setState(() {});
  }

  @override
  Future<T?> runDialog<T>(Future<T> Function() body, {bool forever = false}) =>
      _dialogs.run(body, forever: forever);

  @override
  Future<void> showErrorReportsIntro() => _dialogs.run(
        () => showErrorReportsIntroOnce(
          context,
          _session.notices,
          readOnly: widget.readOnly,
          driveFull: widget.driveFull,
        ),
      );

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
  Future<void> announcePlugins({
    required List<StorePlugin> fresh,
    required bool hasUpdates,
  }) =>
      _dialogs.run(() async {
        final t = context.strings.plugins;
        final message = hasUpdates && fresh.isNotEmpty
            ? t.homeNoticeUpdatesAndNew
            : hasUpdates
                ? t.homeNoticeUpdates
                : fresh.length == 1
                    ? t.homeNoticeNewOne
                    : t.homeNoticeNewMany(fresh.length);

        unawaited(_session.plugins.markHomeNotified(fresh));
        final open = await showTwoActionsDialog(
          context: context,
          title: t.homeNoticeTitle,
          content: message,
          cancelText: context.strings.common.close,
          confirmText: t.homeNoticeOpenButton,
        );
        if (open && mounted) await _goTo(LauncherScreen.plugins);
      });

  @override
  Future<bool?> offerElevation() {
    final t = AppL10n.strings.elevation;
    return _dialogs.run(
      () => showTwoActionsDialog(
        context: context,
        title: t.dialogTitle,
        content: t.dialogContent,
        cancelText: t.dialogCancel,
        confirmText: t.dialogConfirm,
      ),
    );
  }

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
  Future<void> showAutoInstallSkipped() {
    final t = context.strings.home;
    return showSingleActionDialog(
      context: context,
      title: t.autoInstallSkippedTitle,
      content: t.autoInstallSkippedContent,
    );
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
          MirrorComponent.app => t.home.appTileTitle,
          MirrorComponent.library => t.home.libraryTileTitle,
          MirrorComponent.plugins => t.shell.navPlugins,
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
  Future<void> performReportOffer() async {
    await offerErrorReportCollection(
      context,
      _session.errorReports,
      readOnly: widget.readOnly,
      isOtzariaRunning: _session.refreshProcessState,
      notices: _session.notices,
      searchFeedback: _session.searchFeedback,
    );
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

  Future<void> _goTo(LauncherScreen screen) =>
      _navigator.select(_sectionOf(screen));

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

  Widget _screenWidget(LauncherScreen screen) {
    final s = _session;
    return switch (screen) {
      LauncherScreen.home => HomeScreen(
          otzaria: s.otzaria,
          library: s.library,
          plugins: s.plugins,
          launcherUpdate: s.launcherUpdate,
          settings: widget.settings,
          otzariaIsRunning: s.otzariaIsRunning,
          isDownloading: s.isDownloading,
          isCancellingDownload: s.isCancellingDownload,
          isCheckingOnline: s.isCheckingOnline,
          longTaskRunning: s.longTaskRunning,
          onProcessStateChanged: s.refreshProcessState,
          onCloseOtzaria: s.closeOtzaria,
          onCheckOnline: s.checkOnline,
          onDownloadAll: s.downloadAll,
          onCancelDownload: s.cancelDownload,
          onDownloadLauncherUpdate: s.downloadLauncherUpdate,
          onInstallLauncherUpdate: s.installLauncherUpdate,
          onRequestReindex: s.requestLibraryReindex,
          onGoToOtzaria: () => _goTo(LauncherScreen.otzaria),
          onGoToLibrary: () => _goTo(LauncherScreen.library),
          readOnly: widget.readOnly,
          driveFull: widget.driveFull,
          errorReports: s.errorReports,
          searchFeedback: s.searchFeedback,
          isUploadingReports: s.uploadingReports,
          onUploadReports: s.uploadReports,
          onStopReports: s.stopReports,
        ),
      LauncherScreen.otzaria => OtzariaScreen(
          otzaria: s.otzaria,
          settings: widget.settings,
          otzariaIsRunning: s.otzariaIsRunning,
          onCloseOtzaria: s.closeOtzaria,
          onInstallAdopted: s.plugins.refreshInstalled,
          saferMode: s.saferMode,
        ),
      LauncherScreen.customApps => CustomAppsScreen(
          controller: s.customApps,
          readOnly: widget.readOnly,
        ),
      LauncherScreen.library => LibraryScreen(
          library: s.library,
          otzariaIsRunning: s.otzariaIsRunning,
          isDownloading: s.isDownloading,
          onProcessStateChanged: s.refreshProcessState,
          onCloseOtzaria: s.closeOtzaria,
          onRequestReindex: s.requestLibraryReindex,
          onGoToSettings: () => _goTo(LauncherScreen.settings),
          onGrantSemanticConsent: s.grantSemanticConsent,
        ),
      LauncherScreen.plugins => PluginsScreen(
          controller: s.plugins,
          onRequestFocus: () => _goTo(LauncherScreen.plugins),
          readOnly: widget.readOnly,
          driveFull: widget.driveFull,
          busyElsewhere: s.pluginSyncBlockedElsewhere,
        ),
      LauncherScreen.settings => SettingsScreen(
          controller: widget.settings,
          onOpenLog: s.openLogFolder,
          launcherVersion: s.launcherUpdate.currentVersion,
          saferMode: s.saferMode,
          customApps: s.customApps,
          readOnly: widget.readOnly,
          driveFull: widget.driveFull,
          appReports: widget.appReports,
        ),
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
      },
      child: Focus(autofocus: true, child: _scaffold(context)),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      // שורת הכותרת נפרסת על כל הרוחב, מעל סרגל הניווט, כך שגרירת החלון
      // אפשרית לכל רוחבו. כפתורי החלון נשארים פעילים גם כשהיציאה ממתינה.
      body: Column(
        children: [
          AppTitleBar(
            onHelp: () => unawaited(
              showFaqDialog(
                context,
                faq: _session.faq,
                saferMode: _session.saferMode,
              ),
            ),
            onSettings: () => unawaited(_goTo(LauncherScreen.settings)),
            activeTool: _screen == LauncherScreen.settings
                ? TitleBarTool.settings
                : null,
            toolsEnabled: !_session.exitPending,
            showWindowButtons: widget.showWindowButtons,
          ),
          Expanded(
            child: AbsorbPointer(
              absorbing: _session.exitPending,
              child: ExcludeFocus(
                excluding: _session.exitPending,
                child: _shellRow(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shellRow(BuildContext context) => Row(
        children: [
          _NavRail(
            current: _screen,
            onSelect: _goTo,
            showCustomApps: _session.customApps.hasApps,
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: AppSurfaces.shellDivider(context),
          ),
          Expanded(
            child: IndexedStack(
              index: _screen.index,
              children: [
                for (final screen in LauncherScreen.values)
                  _navigator.isBuilt(_sectionOf(screen))
                      ? TickerMode(
                          enabled: screen == _screen,
                          child: _screenWidget(screen),
                        )
                      : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      );
}

ShellSection _sectionOf(LauncherScreen screen) => switch (screen) {
      LauncherScreen.home => ShellSection.home,
      LauncherScreen.otzaria => ShellSection.otzaria,
      LauncherScreen.library => ShellSection.library,
      LauncherScreen.plugins => ShellSection.plugins,
      LauncherScreen.customApps => ShellSection.customApps,
      LauncherScreen.settings => ShellSection.settings,
    };

/// למקטעים שאין להם מסך בסרגל (דיווחים, עזרה) עדיין אין יעד — הבית.
LauncherScreen _screenOf(ShellSection section) => switch (section) {
      ShellSection.home => LauncherScreen.home,
      ShellSection.otzaria => LauncherScreen.otzaria,
      ShellSection.library => LauncherScreen.library,
      ShellSection.plugins => LauncherScreen.plugins,
      ShellSection.customApps => LauncherScreen.customApps,
      ShellSection.settings => LauncherScreen.settings,
      ShellSection.reports || ShellSection.help => LauncherScreen.home,
    };

// ── סרגל הניווט ───────────────────────────────────────────────────────────────

/// שם המסך בסרגל הניווט.
String _screenLabel(BuildContext context, LauncherScreen screen) {
  final s = context.strings.shell;
  return switch (screen) {
    LauncherScreen.home => s.navHome,
    LauncherScreen.otzaria => s.navApp,
    LauncherScreen.library => s.navLibrary,
    LauncherScreen.plugins => s.navPlugins,
    LauncherScreen.customApps => s.navCustomApps,
    LauncherScreen.settings => s.navSettings,
  };
}

class _NavRail extends StatelessWidget {
  final LauncherScreen current;
  final ValueChanged<LauncherScreen> onSelect;

  /// מוסיף את "תוכנות נוספות" לסרגל. מוצג רק כשיש בפועל תוכנה כזו —
  /// הכניסה הראשונה היא מההגדרות.
  final bool showCustomApps;

  const _NavRail({
    required this.current,
    required this.onSelect,
    required this.showCustomApps,
  });

  /// הסמל הרגיל והמלא לכל מסך. הפריטים נגזרים מ-[LauncherScreen.values], כך
  /// שמסך חדש בלי סמל ייפול כאן במקום להיעלם מהסרגל בשקט.
  static const Map<LauncherScreen, (IconData, IconData)> _icons = {
    LauncherScreen.home: (
      FluentIcons.home_24_regular,
      FluentIcons.home_24_filled,
    ),
    LauncherScreen.otzaria: (
      FluentIcons.desktop_24_regular,
      FluentIcons.desktop_24_filled,
    ),
    LauncherScreen.library: (
      FluentIcons.library_24_regular,
      FluentIcons.library_24_filled,
    ),
    LauncherScreen.plugins: (
      FluentIcons.puzzle_piece_24_regular,
      FluentIcons.puzzle_piece_24_filled,
    ),
    LauncherScreen.customApps: (
      FluentIcons.box_24_regular,
      FluentIcons.box_24_filled,
    ),
    LauncherScreen.settings: (
      FluentIcons.settings_24_regular,
      FluentIcons.settings_24_filled,
    ),
  };

  @override
  Widget build(BuildContext context) {
    NavRailItem item(LauncherScreen screen) {
      final (icon, iconFilled) = _icons[screen]!;
      return NavRailItem(
        icon: icon,
        iconFilled: iconFilled,
        label: _screenLabel(context, screen),
        isSelected: current == screen,
        onTap: () => onSelect(screen),
      );
    }

    return Container(
      width: NavRailItem.width,
      color: AppSurfaces.navRailBackground(context),
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
      child: Column(
        children: [
          // ההגדרות נדחקות לתחתית; כל השאר בסדר ההכרזה של ה-enum.
          for (final screen in LauncherScreen.values)
            if (screen != LauncherScreen.settings &&
                (screen != LauncherScreen.customApps || showCustomApps))
              item(screen),
          const Spacer(),
          item(LauncherScreen.settings),
        ],
      ),
    );
  }
}
