import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/otzaria_module_controller.dart';
import '../screens/home/home_view_model.dart' show displayVersion;
import '../widgets/widgets_exports.dart';

String appInstallPrompt(BuildContext context, OtzariaModuleController c) =>
    context.strings.appScreen.installPrompt(
      latestVersion: _shown(c.latestVersion, other: c.currentVersion),
      currentVersion: _shown(c.currentVersion, other: c.latestVersion),
      prereleaseNote: c.hasChannelChoice && c.preferPrerelease,
    );

String? _shown(String? version, {String? other}) =>
    version == null ? null : displayVersion(version, other: other);

StatusKind otzariaStatusKind(OtzariaModuleStatus status) => switch (status) {
      OtzariaModuleStatus.idle => StatusKind.unknown,
      OtzariaModuleStatus.checking => StatusKind.working,
      OtzariaModuleStatus.upToDate => StatusKind.ok,
      OtzariaModuleStatus.updateAvailable => StatusKind.updateAvailable,
      OtzariaModuleStatus.installing => StatusKind.working,
      OtzariaModuleStatus.needsDownload => StatusKind.needsAction,
      OtzariaModuleStatus.installedIsNewer => StatusKind.ok,
      OtzariaModuleStatus.error => StatusKind.error,
    };

String otzariaStatusLabel(
  BuildContext context,
  OtzariaModuleStatus status, {
  required String updateAvailable,
  required String needsDownload,
  String? installStage,
}) {
  final common = context.strings.common;

  return switch (status) {
    OtzariaModuleStatus.idle => common.notCheckedYet,
    OtzariaModuleStatus.checking => common.checking,
    OtzariaModuleStatus.upToDate => common.upToDate,
    OtzariaModuleStatus.updateAvailable => updateAvailable,
    OtzariaModuleStatus.installing => installStage ?? common.installing,
    OtzariaModuleStatus.needsDownload => needsDownload,
    OtzariaModuleStatus.installedIsNewer => common.installedIsNewer,
    OtzariaModuleStatus.error => common.error,
  };
}

Future<bool> confirmOtzariaInstall(
  BuildContext context, {
  required OtzariaModuleController otzaria,
  required String title,
  required String content,
  required String confirmText,
}) async {
  final approved = await showTwoActionsDialog(
    context: context,
    title: title,
    content: content,
    subtitle: otzaria.elevatedAsOtherUser
        ? context.strings.home.elevatedAsOtherUserWarning
        : null,
    confirmText: confirmText,
  );
  if (!approved || !context.mounted) return false;
  if (!await _closedForInstall(context, otzaria)) return false;
  await otzaria.install();
  final notice = otzaria.noticeMessage;
  if (notice != null) {
    UiSnack.show(notice);
    return false;
  }
  if (otzaria.status != OtzariaModuleStatus.upToDate) return false;
  UiSnack.showSuccess(
    AppL10n.strings.home.appInstalledSnack(
      displayVersion('${otzaria.currentVersion}'),
    ),
  );
  return true;
}

Future<bool> _closedForInstall(
  BuildContext context,
  OtzariaModuleController otzaria,
) async {
  if (!await otzaria.refreshRunningState(force: true)) return true;
  if (!context.mounted) return false;
  final home = context.strings.home;
  final close = await showTwoActionsDialog(
    context: context,
    title: home.closeOtzariaForAppInstallDialogTitle,
    content: home.closeOtzariaForAppInstallPrompt,
    confirmText: home.closeOtzariaAndInstallConfirm,
  );
  if (!close) return false;
  if (await otzaria.closeRunning()) return true;
  UiSnack.showError(AppL10n.strings.common.closeOtzariaFailedSnack);
  return false;
}
