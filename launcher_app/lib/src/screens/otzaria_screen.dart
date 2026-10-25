import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controllers/otzaria_module_controller.dart';
import '../services/native_file_dialogs.dart';
import '../services/timestamps.dart';
import '../settings/safer_mode.dart';
import '../settings/settings_controller.dart';
import '../shell/shell_keys.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'home/home_view_model.dart' show displayVersion;

/// דף "תוכנת אוצריא": כרטיס מצב, מה חדש ומתקדם. ההתקנה רצה במסך המשימה,
/// ואין התקנה של גרסה ישנה יותר.
class OtzariaScreen extends StatelessWidget {
  const OtzariaScreen({
    super.key,
    required this.otzaria,
    required this.settings,
    required this.otzariaIsRunning,
    required this.onCloseOtzaria,
    this.onInstallAdopted,
    this.saferMode,
    this.onUpdateHere,
    this.onReinstall,
    this.busy = false,
  });

  final OtzariaModuleController otzaria;

  /// בחירת ערוץ הגרסה נשמרת בהגדרות, כדי שתישאר בין הפעלות.
  final SettingsController settings;
  final bool otzariaIsRunning;

  /// מבקשת מאוצריא הפתוחה להיסגר ומחזירה אם היא אכן נסגרה.
  final Future<bool> Function() onCloseOtzaria;

  /// נקרא אחרי שהמשתמש הצביע ידנית על תיקיית ההתקנה — תיקיית התוספים
  /// נגזרת מהנתיב הזה, ולכן צריך לסרוק אותה מחדש.
  final Future<void> Function()? onInstallAdopted;

  /// בורר הערוץ הוא הגדרה שמחוץ למסך ההגדרות, ולכן הוא צריך שער משלו.
  final SaferModeGate? saferMode;

  /// התקנה או עדכון של התוכנה במסך המשימה.
  final VoidCallback? onUpdateHere;

  /// התקנה מחדש של אותה גרסה, באותו מסך משימה.
  final VoidCallback? onReinstall;

  /// משימה ארוכה רצה במקום אחר — אין התקנה עכשיו.
  final bool busy;

  bool get _installing => otzaria.status == OtzariaModuleStatus.installing;

  /// **לא** תלוי בהורדה של רכיב אחר: בחירת מיקום ובדיקה מחדש מקומיות.
  bool get _isBusy => _installing;

  bool get _installed => otzaria.currentVersion != null;

  @override
  Widget build(BuildContext context) {
    final c = otzaria;
    final t = context.strings.pages;
    final drive = c.latestVersion;
    return ScreenBody(
      children: [
        if (otzariaIsRunning && _installed) _runningNotice(context),
        _statusCard(context),
        if (drive != null &&
            c.status != OtzariaModuleStatus.installedIsNewer &&
            ReleaseNotesCard.hasNotes(c.latestReleaseNotes)) ...[
          SectionLabel(t.appWhatsNew(displayVersion(drive))),
          ReleaseNotesCard(markdown: c.latestReleaseNotes),
        ],
        AdvancedSection(
          key: ShellKeys.pageAdvanced,
          title: t.advancedTitle,
          summary: t.appAdvancedSummary(channel: c.hasChannelChoice),
          child: _advanced(context),
        ),
      ],
    );
  }

  Widget _runningNotice(BuildContext context) {
    final g = context.strings.guide;
    return NoticeBanner(
      kind: NoticeKind.banner,
      leading: const IconTile(child: OtzariaLogo()),
      title: g.otzariaOpenTitle,
      body: g.otzariaOpenBody,
      actions: [CloseOtzariaButton(onClose: onCloseOtzaria)],
    );
  }

  Widget _chip(BuildContext context) {
    final c = otzaria;
    final t = context.strings.pages;
    final g = context.strings.guide;
    final (kind, label) = switch (c.status) {
      OtzariaModuleStatus.idle => (
          StatusKind.unknown,
          context.strings.common.notCheckedYet,
        ),
      OtzariaModuleStatus.checking => (StatusKind.working, g.chipChecking),
      OtzariaModuleStatus.installing => (
          StatusKind.working,
          c.installStage ?? g.chipInstalling,
        ),
      OtzariaModuleStatus.error => (StatusKind.error, g.chipAttention),
      OtzariaModuleStatus.updateAvailable when !_installed => (
          StatusKind.needsAction,
          g.chipReadyToInstall,
        ),
      OtzariaModuleStatus.updateAvailable => (
          StatusKind.updateAvailable,
          t.chipUpdateOnDrive,
        ),
      OtzariaModuleStatus.installedIsNewer => (StatusKind.ok, g.chipNewerHere),
      // כמו האריח בבית: מה שההורדה תביא הוא "יש עדכון להוריד לכונן".
      OtzariaModuleStatus.needsDownload ||
      OtzariaModuleStatus.upToDate when c.hasOnlineUpdate =>
        (
          StatusKind.updateAvailable,
          g.chipNewOnline,
        ),
      OtzariaModuleStatus.needsDownload => (
          StatusKind.needsAction,
          g.chipNotOnDrive,
        ),
      OtzariaModuleStatus.upToDate => (StatusKind.ok, t.chipUpToDate),
    };
    return StatusChip(kind: kind, label: label);
  }

  Widget _statusCard(BuildContext context) {
    final c = otzaria;
    final t = context.strings.pages;
    final g = context.strings.guide;
    final installed = c.currentVersion;
    final drive = c.latestVersion;
    final hasUpdate = c.status == OtzariaModuleStatus.updateAvailable;
    final downloadedAt = c.lastDownloadedAt;

    final launch = c.libraryApplyActive
        ? context.strings.home.libraryApplyActive
        : g.launchButton;
    Widget launchButton({required bool primary}) => primary
        ? ActionButton.recommended(
            key: ShellKeys.statusPrimary,
            text: launch,
            onPressed: c.canLaunch ? c.launch : null,
          )
        : ActionButton.ghost(
            text: launch,
            onPressed: c.canLaunch ? c.launch : null,
          );

    final actions = <Widget>[
      if (hasUpdate && drive != null)
        ActionButton.recommended(
          key: ShellKeys.statusPrimary,
          text: _installed
              ? t.appUpdateButton(displayVersion(drive, other: installed))
              : t.appInstallButton,
          onPressed: busy || _installing ? null : onUpdateHere,
        ),
      if (_installed) launchButton(primary: !hasUpdate),
    ];

    return StatusCard(
      logo: Image.asset(
        'assets/images/otzaria_logo.png',
        width: 32,
        height: 32,
        semanticLabel: context.strings.shell.otzariaLogoLabel,
      ),
      title: g.tileApp,
      chip: _chip(context),
      values: [
        StatusValue(
          label: t.onThisComputer,
          value: installed == null
              ? t.libNotInstalled
              : displayVersion(installed, other: drive),
          ltr: installed != null,
        ),
        StatusValue(
          label: t.onTheDrive,
          value: drive == null ? t.nothingYet : displayVersion(drive),
          ltr: drive != null,
          meta: drive != null && downloadedAt != null
              ? t.downloadedOn(formatDate(downloadedAt))
              : null,
        ),
        // רק אחרי בדיקה ברשת שהצליחה; בלעדיה אין מה לומר על הרשת.
        if (c.onlineChannels != null)
          StatusValue(
            label: t.onlineAvailable,
            value: switch (c.onlineUpdateVersion) {
              final online? => displayVersion(online, other: drive),
              null => t.nothingNewOnline,
            },
            ltr: c.onlineUpdateVersion != null,
          ),
      ],
      extra: [
        if (_installing) _installingProgress(context),
        // "בדוק שוב" שבכרטיס הוא הניסיון החוזר — בלי כפתור שני לאותה פעולה.
        if (c.errorMessage case final error?) InfoErrorRow(message: error),
        if (c.status == OtzariaModuleStatus.installedIsNewer &&
            c.awaitsNewerInSelectedChannel)
          Text(
            key: ShellKeys.appAwaitsNewer,
            t.appAwaitsNewer(stable: !c.preferPrerelease),
            style: AppTextStyles.rowSub.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (busy && !_installing)
          Text(
            key: ShellKeys.pageBusyNote,
            t.pageBusyNote,
            style: AppTextStyles.rowSub.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (!_installed && drive == null && !_installing)
          Text(
            t.appNeedsDownloadNote,
            style: AppTextStyles.rowSub.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
      actions: actions,
      endActions: [
        RecheckButton(onPressed: _isBusy ? null : c.checkForUpdate),
      ],
    );
  }

  Widget _installingProgress(BuildContext context) {
    final c = otzaria;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.installStage ?? context.strings.appScreen.installingProgress,
          style: AppTextStyles.rowSub.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        const AppProgressBar(thin: true),
        if (c.installStage != null) ...[
          const SizedBox(height: 8),
          ActionButton.ghost(
            text: context.strings.appDomain.stopWaitingForSetup,
            icon: FluentIcons.dismiss_circle_24_regular,
            size: ActionButtonSize.sm,
            onPressed: c.stopWaitingForSetup,
          ),
        ],
      ],
    );
  }

  // ── מתקדם ─────────────────────────────────────────────────────────────────

  Widget _advanced(BuildContext context) {
    final c = otzaria;
    final t = context.strings.pages;
    final a = context.strings.appScreen;
    final installed = c.currentVersion;
    final canReinstall = c.status == OtzariaModuleStatus.upToDate;
    final launchPath = c.launchPath;
    final downloadedAt = c.lastDownloadedAt;

    return RowsCard(
      children: [
        if (c.hasChannelChoice)
          AppRow(
            key: ShellKeys.appChannel,
            title: t.appChannelTitle,
            subtitle: '${t.appChannelBody}\n'
                '${a.channelPair('${c.stableVersion}', '${c.prereleaseVersion}')}',
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (saferMode?.isLocked ?? false)
                  StatusChip(kind: StatusKind.locked, label: t.lockedChip),
                AppSegmentedControl<bool>(
                  options: [
                    SegmentOption(value: false, label: a.channelStable),
                    SegmentOption(value: true, label: a.channelPrerelease),
                  ],
                  currentValue: c.preferPrerelease,
                  onChanged: _isBusy ? null : (v) => _setChannel(context, v),
                ),
              ],
            ),
          ),
        AppRow(
          key: ShellKeys.appReinstall,
          title: t.appReinstallTitle,
          subtitle: canReinstall && installed != null
              ? t.appReinstallBody(displayVersion(installed))
              : !_installed
                  ? t.appChipNotInstalled
                  : t.appReinstallUnavailable,
          trailing: ActionButton.neutral(
            text: a.reinstallButton,
            onPressed:
                canReinstall && !busy && !_installing ? onReinstall : null,
          ),
        ),
        AppRow(
          title: t.appLocationTitle,
          subtitle: launchPath == null ? a.noInstallDetected : null,
          trailing: ActionButton.ghost(
            text: a.pickInstallDirButton,
            icon: FluentIcons.folder_open_24_regular,
            onPressed: _isBusy ? null : () => _pickInstallDir(context),
          ),
          below: launchPath == null
              ? null
              : PathText(p.dirname(launchPath), copyable: true),
        ),
        AppRow(
          title: t.appSourceTitle,
          subtitle: downloadedAt == null
              ? null
              : '${context.strings.common.lastDownloaded}: '
                  '${formatDate(downloadedAt)}',
          below: PathText(c.mirrorDir),
          trailing: CopyPathButton(path: c.mirrorDir),
        ),
      ],
    );
  }

  /// נשמר בהגדרות; `AppSession` מזליג לקונטרולר, שבודק מחדש מהכונן.
  Future<void> _setChannel(BuildContext context, bool preferPrerelease) async {
    final gate = saferMode;
    if (gate != null && gate.isLocked) {
      final unlocked = await showSaferModePasswordDialog(
        context,
        storedPassword: gate.settings.settings.saferModePassword,
        hint: context.strings.saferMode.verifySettingsHint,
      );
      if (!unlocked) return;
      gate.unlock();
    }
    await settings.update(
      settings.settings.copyWith(preferAppPrerelease: preferPrerelease),
    );
  }

  Future<void> _pickInstallDir(BuildContext context) async {
    final t = context.strings.appScreen;
    final dir = await NativeFileDialogs.pickDirectory(
      dialogTitle: t.pickInstallDirDialogTitle,
    );
    if (dir == null) return;

    final adopted = await otzaria.adoptInstallDir(dir);
    if (adopted) {
      await onInstallAdopted?.call();
      UiSnack.showSuccess(t.installAdoptedSnack);
    } else {
      UiSnack.showError(t.installNotFoundSnack);
    }
  }
}
