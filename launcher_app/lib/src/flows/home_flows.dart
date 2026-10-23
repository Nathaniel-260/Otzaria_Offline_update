import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../screens/home/home_view_model.dart' show displayVersion;
import '../shell/home_guidance.dart';
import '../widgets/widgets_exports.dart';
import 'library_flows.dart';
import 'otzaria_flows.dart';

/// מה שהזרימות של הבית צריכות מהסשן.
class HomeFlowDeps {
  const HomeFlowDeps({
    required this.otzaria,
    required this.library,
    required this.isOtzariaRunning,
    required this.closeOtzaria,
    required this.onRequestReindex,
  });

  final OtzariaModuleController otzaria;
  final LibraryModuleController library;

  /// בדיקת תהליך טרייה — לא הערך מרגע הבנייה.
  final Future<bool> Function() isOtzariaRunning;
  final Future<bool> Function() closeOtzaria;
  final Future<void> Function() onRequestReindex;
}

/// "עדכון כאן": הספרייה ואז התוכנה, כמו `AutoInstallFlow`. תוספים בלבד —
/// [onPluginsOnly] (החנות היא שמוסרת אותם לאוצריא). אוצריא פתוחה — מבקשים
/// לסגור אותה רק אחרי אישור העדכון; סירוב בדרך עוצר את כל השלבים שאחריו.
Future<void> updateHere(
  BuildContext context,
  HomeFlowDeps deps, {
  required List<GuidanceItem> items,
  required VoidCallback onPluginsOnly,
}) async {
  final library = items.contains(GuidanceItem.library);
  final app = items.contains(GuidanceItem.app);
  if (!library && !app) {
    if (items.contains(GuidanceItem.plugins)) onPluginsOnly();
    return;
  }
  if (library && context.mounted) {
    final updated = await confirmLibraryUpdate(
      context,
      library: deps.library,
      dialogTitle: (strings) => strings.home.libraryUpdateDialogTitle,
      isOtzariaRunning: deps.isOtzariaRunning,
      onRequestReindex: deps.onRequestReindex,
      closeOtzaria: () => _closedForUpdate(context, deps),
    );
    if (!updated) return;
  }
  if (!app || !context.mounted) return;
  if (deps.otzaria.status != OtzariaModuleStatus.updateAvailable) return;
  await installOtzariaHere(context, deps);
}

Future<bool> _closedForUpdate(BuildContext context, HomeFlowDeps deps) async {
  if (!await deps.isOtzariaRunning()) return true;
  if (!context.mounted) return false;
  final home = context.strings.home;
  final close = await showTwoActionsDialog(
    context: context,
    title: home.closeOtzariaForAppInstallDialogTitle,
    content: home.closeOtzariaForUpdatePrompt,
    confirmText: home.closeOtzariaAndUpdateConfirm,
  );
  if (!close || !context.mounted) return false;
  if (await deps.closeOtzaria()) return true;
  UiSnack.showError(AppL10n.strings.common.closeOtzariaFailedSnack);
  return false;
}

bool _offersLibraryToo(HomeFlowDeps deps) =>
    deps.otzaria.currentVersion == null &&
    deps.library.isFreshInstall &&
    deps.library.status == LibraryModuleStatus.updateAvailable;

/// התקנת אוצריא. במחשב ריק אותה לחיצה מציעה גם את הספרייה: התוכנה קודם,
/// כי מיקום המסד נגזר ממה שהאשף בחר.
Future<void> installOtzariaHere(
  BuildContext context,
  HomeFlowDeps deps,
) async {
  final t = context.strings.home;
  final otzaria = deps.otzaria;
  final library = deps.library;
  final withLibrary = _offersLibraryToo(deps);
  final installed = await confirmOtzariaInstall(
    context,
    otzaria: otzaria,
    title: withLibrary ? t.firstInstallDialogTitle : t.appInstallDialogTitle,
    content: withLibrary
        ? t.firstInstallPrompt(
            displayVersion('${otzaria.latestVersion}'),
            '${library.targetVersion}',
          )
        : appInstallPrompt(context, otzaria),
    confirmText: withLibrary ? t.firstInstallConfirm : t.appInstallConfirm,
  );
  if (!withLibrary || !context.mounted) return;
  if (!installed) {
    if (otzaria.currentVersion != null) await library.checkForUpdate();
    return;
  }

  await library.checkForUpdate();
  if (!context.mounted) return;
  await _installLibraryAfterApp(context, deps);
}

Future<void> _installLibraryAfterApp(
  BuildContext context,
  HomeFlowDeps deps,
) async {
  final t = context.strings.home;
  while (await deps.isOtzariaRunning()) {
    if (await deps.closeOtzaria()) break;
    if (!context.mounted) return;
    final retry = await showTwoActionsDialog(
      context: context,
      title: t.closeOtzariaForLibraryDialogTitle,
      content: t.closeOtzariaForLibraryPrompt,
      confirmText: context.strings.common.retry,
    );
    if (!retry) return;
  }
  if (!context.mounted) return;
  final library = deps.library;
  if (library.status != LibraryModuleStatus.updateAvailable) return;

  await applyLibraryAndReport(
    context,
    library,
    library.update,
    onRequestReindex: deps.onRequestReindex,
  );
}
