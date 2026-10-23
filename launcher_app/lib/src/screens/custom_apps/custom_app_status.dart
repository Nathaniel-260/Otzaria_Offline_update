import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../services/byte_size.dart';
import '../../widgets/widgets_exports.dart';

/// התוויות שמתארות את מצב התוכנה — משותפות לכרטיס ולדף, כדי שהשניים לא
/// יאמרו על אותה תוכנה שני דברים שונים.

/// "אינה מותקנת" נאמר **רק** כשבאמת חיפשנו. בלי שם קובץ הרצה התשובה
/// הנכונה היא "לא ניתן לדעת", וזה לא אותו דבר.
String customAppInstalledLabel(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  if (!app.canDetect) return t.noDetectRules;

  final installed = app.installed;
  if (installed == null) return t.notInstalled;
  final version = installed.version;
  return version == null
      ? t.installedUnknownVersion
      : t.installedVersion(version);
}

String customAppStoredLabel(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  final stored = app.storedInstaller;
  return stored == null
      ? t.noStoredInstaller
      : t.storedInstaller(stored.version);
}

/// מאיפה התוכנה: "מאתר המפתחים (GitHub)" או "מקובץ".
String customAppSourceLabel(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  return app.descriptor.sourceKind == AppSourceKind.github
      ? t.sourceGithubShort
      : t.sourceFileShort;
}

/// הגרסה שבכונן, ובלעדיה — המותקנת כאן.
String? customAppVersionOf(CustomAppView app) =>
    app.storedInstaller?.version ?? app.installed?.version;

/// שורת המטא: גרסה, גודל ומקור.
List<String> customAppMeta(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  final version = customAppVersionOf(app);
  final size = app.storedInstaller?.sizeBytes ?? 0;
  return [
    if (version != null && version.isNotEmpty) t.versionLabel(version),
    if (size > 0) formatBytes(size),
    customAppSourceLabel(context, app),
  ];
}

/// ההערה מתחת לפעולה: למה אין מה להתקין, או מה ידוע על ההתקנה כאן.
String? customAppNoteOf(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  if (!app.canInstall && !app.canLaunch) return t.noStoredInstaller;
  if (app.canLaunch) return null;
  return customAppInstalledLabel(context, app);
}

String? customAppOnlineLabel(
  BuildContext context,
  CustomAppsController controller,
  CustomAppView app,
) {
  if (app.descriptor.sourceKind != AppSourceKind.github) return null;
  final t = context.strings.customApps;
  final id = app.descriptor.id;

  if (controller.onlineUnavailable.contains(id)) return t.onlineUnavailable;
  final online = controller.onlineVersions[id];
  if (online == null) return null;
  return customAppOnlineIsNewer(online, app.storedInstaller?.version)
      ? t.onlineVersionAvailable(online)
      : t.onlineUpToDate;
}
