import 'package:error_reports_manager/error_reports_manager.dart';

import '../controllers/app_reports_controller.dart';
import '../controllers/launcher_update_flow.dart';

/// כל מה ש-[AppSession] צריך מהממשק: דיאלוגים, הודעות וזרימות שתלויות
/// ב-`BuildContext`. המסגרת מממשת, והסשן עצמו אינו מחזיק `BuildContext`.
abstract interface class SessionPrompts {
  /// מריץ דיאלוג בתור המשותף — ראו `DialogQueue.run`.
  Future<T?> runDialog<T>(Future<T> Function() body, {bool forever});

  /// `null` כשהדיאלוג לא הוצג בכלל.
  Future<bool?> showCrashPrompt(
    AppReportsController reports,
    CrashCandidate candidate,
  );

  Future<bool> confirmLauncherInstall(String version, {String? whatsNew});

  void notifyLauncherUpdate(LauncherUpdateNotice notice, String detail);

  Future<bool> confirmCancelDownload();

  Future<bool> confirmClose({required bool downloading});

  Future<bool> confirmSemanticConsent();

  Future<bool> confirmLibraryReindex();

  Future<void> uploadReports({
    required bool Function() isCancelled,
    required void Function(bool active) onActiveChanged,
    required void Function(bool uploading) onUploadingChanged,
  });
}
