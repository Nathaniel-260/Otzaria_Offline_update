import 'dart:async';

import '../shell/home_guidance.dart' show GuidanceItem;
import '../shell/shell_tasks.dart';

/// איך נגמרה הרצת אשף ההתקנה של אוצריא.
enum AppInstallOutcome {
  installed,

  /// האשף בוטל — החלטה של המשתמש.
  cancelled,

  /// האשף עוד פתוח (או שהפסקנו להמתין לו) — לא ידוע אם ההתקנה הסתיימה.
  stillOpen,
  failed,
}

abstract interface class UpdateHereApp {
  bool get isInstalled;
  bool get hasUpdateAvailable;
  bool get elevatedAsOtherUser;
  String? get versionToInstall;
  String? get errorMessage;
  bool get needsElevation;

  /// האשף של אוצריא — המשתמש ממשיך בו בחלון נפרד.
  Future<AppInstallOutcome> installWithWizard();
  void stopWaiting();
}

abstract interface class UpdateHereLibrary {
  bool get isFreshInstall;
  bool get hasUpdateAvailable;
  int? get targetVersion;
  String? get errorMessage;
  bool get needsElevation;

  /// `true` — הספרייה מעודכנת אחרי ההחלה.
  Future<bool> apply();
  Future<void> recheck();
}

abstract interface class UpdateHerePlugins {
  /// שמות התוספים שאפשר למסור לאוצריא עכשיו.
  List<String> get deliverableUpdates;

  /// מוסר אותם אחד אחד; [onRow] מקבל את מצב כל השורות אחרי כל שינוי.
  Future<void> deliver(void Function(List<PluginDelivery> rows) onRow);
}

/// מה הזרימה צריכה מהסשן ומשכבת המשימה (`ShellTasks`).
abstract interface class UpdateHereHost {
  bool get isActive;

  /// בדיקת תהליך טרייה — לא ערך שנלכד קודם.
  Future<bool> isOtzariaRunning();
  Future<bool> closeOtzaria();

  /// סגירה נכשלה — הודעה, והשאלה חוזרת.
  void closeFailed();
  ShellTasks get tasks;
}

/// "עדכון אוצריא במחשב הזה" כמסך משימה. **עדכון**: הספרייה, התוכנה ואז
/// מסירת התוספים — כמו `AutoInstallFlow`. **התקנה ראשונה**: התוכנה ואז
/// הספרייה, ולעולם בלי תוספים. אוצריא נסגרת רק אחרי "סגירה והמשך".
class UpdateHereFlow {
  UpdateHereFlow({
    required this.app,
    required this.library,
    required this.plugins,
    required this.host,
  });

  final UpdateHereApp app;
  final UpdateHereLibrary library;
  final UpdateHerePlugins plugins;
  final UpdateHereHost host;

  ShellTasks get _tasks => host.tasks;

  /// השלבים לפי מה שבאמת יש להתקין מתוך [items], בסדר ההרצה.
  List<GuidanceItem> stagesFor(List<GuidanceItem> items) {
    if (!app.isInstalled) {
      return [
        if (app.hasUpdateAvailable) GuidanceItem.app,
        if (app.hasUpdateAvailable &&
            library.isFreshInstall &&
            library.hasUpdateAvailable)
          GuidanceItem.library,
      ];
    }
    return [
      if (items.contains(GuidanceItem.library) && library.hasUpdateAvailable)
        GuidanceItem.library,
      if (items.contains(GuidanceItem.app) && app.hasUpdateAvailable)
        GuidanceItem.app,
      if (items.contains(GuidanceItem.plugins) &&
          plugins.deliverableUpdates.isNotEmpty)
        GuidanceItem.plugins,
    ];
  }

  /// `false` — אין מה להתקין, והמשימה לא נפתחה.
  Future<bool> run(List<GuidanceItem> items) async {
    final first = !app.isInstalled;
    final stages = stagesFor(items);
    if (stages.isEmpty) return false;
    _tasks.startUpdateHere(
      stages,
      firstInstall: first,
      appVersion:
          stages.contains(GuidanceItem.app) ? app.versionToInstall : null,
      libraryVersion:
          stages.contains(GuidanceItem.library) ? library.targetVersion : null,
      pluginNames: stages.contains(GuidanceItem.plugins)
          ? plugins.deliverableUpdates
          : const [],
    );
    if (stages.contains(GuidanceItem.app) && app.elevatedAsOtherUser) {
      if (!await _tasks.askOtherUser()) return _abandon();
      if (!host.isActive) return true;
    }

    var ranAny = false;
    for (final stage in stages) {
      if (!host.isActive) return true;
      final keepGoing = switch (stage) {
        GuidanceItem.library => await _library(first: first, ranAny: ranAny),
        GuidanceItem.app => await _app(first: first, ranAny: ranAny),
        GuidanceItem.plugins => await _plugins(),
      };
      if (keepGoing == null) return _abandon();
      if (!keepGoing) return true;
      ranAny = true;
    }
    if (host.isActive) _tasks.updateDone();
    return true;
  }

  bool _abandon() {
    _tasks.abandonUpdate();
    return true;
  }

  /// `null` — המשתמש ביטל לפני ששום דבר רץ.
  Future<bool?> _ensureClosed({required bool ranAny}) async {
    while (await host.isOtzariaRunning()) {
      if (!host.isActive) return false;
      if (!await _tasks.askToCloseOtzaria()) {
        if (!ranAny) return null;
        _tasks.updateCancelledByUser();
        return false;
      }
      if (await host.closeOtzaria()) return true;
      host.closeFailed();
    }
    return true;
  }

  Future<bool?> _library({required bool first, required bool ranAny}) async {
    if (first) {
      // מיקום המסד נגזר ממה שהאשף בחר — בודקים מחדש אחרי ההתקנה.
      await library.recheck();
      if (!library.hasUpdateAvailable) {
        _tasks.stageFinished(GuidanceItem.library, StageOutcome.skipped);
        return true;
      }
      // האשף פתח את אוצריא; סוגרים אותה לבד, ושואלים רק אם לא נסגרה.
      if (await host.isOtzariaRunning() && !await host.closeOtzaria()) {
        while (await host.isOtzariaRunning()) {
          if (!host.isActive) return false;
          if (!await _tasks.askToCloseOtzaria(afterWizard: true)) {
            _tasks.stageFinished(GuidanceItem.library, StageOutcome.skipped);
            return true;
          }
          if (await host.closeOtzaria()) break;
          host.closeFailed();
        }
      }
    } else {
      final closed = await _ensureClosed(ranAny: ranAny);
      if (closed != true) return closed;
    }
    if (!host.isActive) return false;
    _tasks.stageRunning(GuidanceItem.library);
    final ok = await library.apply();
    if (!host.isActive) return false;
    if (!ok) {
      _tasks.updateFailed(UpdateFailure(
        GuidanceItem.library,
        message: library.errorMessage,
        needsElevation: library.needsElevation,
      ));
      return false;
    }
    _tasks.stageFinished(GuidanceItem.library, StageOutcome.done);
    return true;
  }

  Future<bool?> _app({required bool first, required bool ranAny}) async {
    final closed = await _ensureClosed(ranAny: ranAny);
    if (closed != true) return closed;
    if (!app.hasUpdateAvailable) {
      _tasks.stageFinished(GuidanceItem.app, StageOutcome.skipped);
      return true;
    }
    _tasks.stageRunning(GuidanceItem.app);
    final outcome = await app.installWithWizard();
    if (!host.isActive) return false;
    final stopped = switch (_tasks.current) {
      UpdateHereTask(:final stopWaitingRequested) => stopWaitingRequested,
      _ => false,
    };
    switch (outcome) {
      case AppInstallOutcome.installed:
        _tasks.stageFinished(GuidanceItem.app, StageOutcome.done);
        return true;
      case AppInstallOutcome.stillOpen when stopped:
        _tasks.stageFinished(GuidanceItem.app, StageOutcome.stoppedWaiting);
        // בהתקנה ראשונה אין התקנה ודאית שהספרייה יכולה להיתלות בה.
        if (!first) return true;
        _tasks.updateCancelledByUser();
        return false;
      case AppInstallOutcome.cancelled || AppInstallOutcome.stillOpen:
        if (first && app.isInstalled) await library.recheck();
        if (host.isActive) _tasks.updateCancelledByUser();
        return false;
      case AppInstallOutcome.failed:
        _tasks.updateFailed(UpdateFailure(
          GuidanceItem.app,
          message: app.errorMessage,
          needsElevation: app.needsElevation,
        ));
        return false;
    }
  }

  Future<bool> _plugins() async {
    _tasks.stageRunning(GuidanceItem.plugins);
    final delivery = plugins.deliver((rows) {
      if (host.isActive && _tasks.current is UpdateHereTask) {
        _tasks.pluginDeliveries(rows);
      }
    });
    await Future.any([delivery, _tasks.finishRequested]);
    if (!host.isActive) return false;
    _tasks.stageFinished(GuidanceItem.plugins, StageOutcome.done);
    return true;
  }

  /// "הפסק להמתין" לאשף ההתקנה.
  void stopWaiting() {
    _tasks.requestStopWaiting();
    app.stopWaiting();
  }
}
