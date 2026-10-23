import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/flows/update_here_flow.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';

class _App implements UpdateHereApp {
  _App(this.log);

  final List<String> log;

  @override
  bool isInstalled = true;
  @override
  bool hasUpdateAvailable = true;
  @override
  bool elevatedAsOtherUser = false;
  @override
  String? versionToInstall = '0.9.96';
  @override
  String? errorMessage;
  @override
  bool needsElevation = false;
  @override
  bool canReinstall = false;

  AppInstallOutcome outcome = AppInstallOutcome.installed;
  Completer<void>? gate;
  int installs = 0;
  int stops = 0;

  @override
  Future<AppInstallOutcome> installWithWizard() async {
    installs++;
    log.add('app');
    await gate?.future;
    if (outcome == AppInstallOutcome.installed) {
      isInstalled = true;
      hasUpdateAvailable = false;
    }
    return outcome;
  }

  @override
  void stopWaiting() {
    stops++;
    gate?.complete();
  }
}

class _Library implements UpdateHereLibrary {
  _Library(this.log);

  final List<String> log;

  @override
  bool isFreshInstall = false;
  @override
  bool hasUpdateAvailable = true;
  @override
  int? targetVersion = 27;
  @override
  String? errorMessage;
  @override
  bool needsElevation = false;
  @override
  bool canApplyFull = false;

  bool succeeds = true;
  int fullApplies = 0;
  bool availableAfterRecheck = true;
  int applies = 0;
  int rechecks = 0;
  void Function()? onApply;

  @override
  Future<bool> apply() async {
    applies++;
    log.add('library');
    onApply?.call();
    if (succeeds) hasUpdateAvailable = false;
    return succeeds;
  }

  @override
  Future<bool> applyFull() async {
    fullApplies++;
    log.add('library-full');
    if (succeeds) canApplyFull = false;
    return succeeds;
  }

  @override
  Future<void> recheck() async {
    rechecks++;
    log.add('recheck');
    hasUpdateAvailable = availableAfterRecheck;
  }
}

class _Plugins implements UpdateHerePlugins {
  _Plugins(this.log);

  final List<String> log;

  @override
  List<String> deliverableUpdates = const [];
  Completer<void>? gate;

  @override
  Future<void> deliver(void Function(List<PluginDelivery> rows) onRow) async {
    log.add('plugins');
    await gate?.future;
    onRow([
      for (final name in deliverableUpdates)
        PluginDelivery(name, PluginDeliveryState.sent),
    ]);
  }
}

class _Host implements UpdateHereHost {
  _Host(this.log);

  final List<String> log;

  @override
  final ShellTasks tasks = ShellTasks();
  @override
  bool isActive = true;

  bool running = false;
  bool closeSucceeds = true;
  int probes = 0;
  int closes = 0;
  int closeFailures = 0;

  @override
  Future<bool> isOtzariaRunning() async {
    probes++;
    return running;
  }

  @override
  Future<bool> closeOtzaria() async {
    closes++;
    log.add('close');
    if (closeSucceeds) running = false;
    return closeSucceeds;
  }

  @override
  void closeFailed() => closeFailures++;
}

void main() {
  late List<String> log;
  late _App app;
  late _Library library;
  late _Plugins plugins;
  late _Host host;
  late UpdateHereFlow flow;

  setUp(() {
    log = [];
    app = _App(log);
    library = _Library(log);
    plugins = _Plugins(log);
    host = _Host(log);
    flow = UpdateHereFlow(
      app: app,
      library: library,
      plugins: plugins,
      host: host,
    );
  });

  tearDown(() => host.tasks.dispose());

  UpdateHereTask? task() => host.tasks.current as UpdateHereTask?;

  /// מריץ עד שהזרימה מחכה למשתמש (או מסתיימת).
  Future<void> settle() => pumpEventQueue();

  const both = [GuidanceItem.library, GuidanceItem.app];

  group('עדכון', () {
    test('הספרייה ואז התוכנה, כמו ההתקנה האוטומטית', () async {
      await flow.run(both);
      expect(log, ['library', 'app']);
      expect(task()!.phase, UpdateHereTaskPhase.done);
      expect(task()!.outcomes, {
        GuidanceItem.library: StageOutcome.done,
        GuidanceItem.app: StageOutcome.done,
      });
      expect(task()!.libraryVersion, 27);
      expect(task()!.appVersion, '0.9.96');
    });

    // בדיקה טרייה לפני כל שלב — לא הערך מרגע הבנייה.
    test('בדיקת תהליך טרייה לפני כל שלב שאוצריא הפתוחה חוסמת', () async {
      await flow.run(both);
      expect(host.probes, 2);
      expect(host.closes, 0);
    });

    test('אוצריא פתוחה: מבקש לסגור, ורק אחרי "סגירה והמשך" סוגר', () async {
      host.running = true;
      final run = flow.run(both);
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      expect(task()!.closeAfterWizard, isFalse);
      expect(host.closes, 0);
      expect(library.applies, 0);

      host.tasks.respond(true);
      await run;
      expect(log, ['close', 'library', 'app']);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('"ביטול" בבקשת הסגירה — אוצריא לא נסגרת ושום דבר לא רץ', () async {
      host.running = true;
      final run = flow.run(both);
      await settle();
      host.tasks.respond(false);
      await run;
      expect(host.closes, 0);
      expect(library.applies, 0);
      expect(app.installs, 0);
      expect(host.tasks.hasTask, isFalse);
    });

    test('תוכנה בלבד, אוצריא פתוחה, "ביטול" — לא נסגרת ולא מותקנת', () async {
      host.running = true;
      final run = flow.run(const [GuidanceItem.app]);
      await settle();
      expect(task()!.stages, [GuidanceItem.app]);
      host.tasks.respond(false);
      await run;
      expect(host.closes, 0);
      expect(app.installs, 0);
    });

    test('אוצריא שלא נסגרה — הודעה, השאלה חוזרת, ושום דבר לא רץ', () async {
      host
        ..running = true
        ..closeSucceeds = false;
      final run = flow.run(const [GuidanceItem.library]);
      await settle();
      host.tasks.respond(true);
      await settle();
      expect(host.closeFailures, 1);
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      expect(library.applies, 0);
      host.tasks.respond(false);
      await run;
      expect(library.applies, 0);
    });

    test('אוצריא נפתחה שוב באמצע וסירבו לסגור — עצירה רגועה', () async {
      library.onApply = () => host.running = true;
      final run = flow.run(both);
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      host.tasks.respond(false);
      await run;
      expect(log, ['library']);
      expect(app.installs, 0);
      expect(host.closes, 0);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
      expect(task()!.outcomes[GuidanceItem.library], StageOutcome.done);
    });

    test('הספרייה נכשלה — מסך כשל עם ההודעה, והתוכנה לא רצה', () async {
      library
        ..succeeds = false
        ..errorMessage = 'אין מספיק מקום'
        ..needsElevation = true;
      await flow.run(both);
      expect(task()!.phase, UpdateHereTaskPhase.failed);
      expect(task()!.failure!.stage, GuidanceItem.library);
      expect(task()!.failure!.message, 'אין מספיק מקום');
      expect(task()!.failure!.needsElevation, isTrue);
      expect(app.installs, 0);
    });

    test('ביטול באשף — סיום רגוע, לא כשל', () async {
      app.outcome = AppInstallOutcome.cancelled;
      await flow.run(both);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
      expect(task()!.failure, isNull);
      expect(task()!.outcomes[GuidanceItem.library], StageOutcome.done);
    });

    test('התקנה שנכשלה — כשל עם הודעה והצעת הרשאות', () async {
      app
        ..outcome = AppInstallOutcome.failed
        ..errorMessage = 'Access is denied'
        ..needsElevation = true;
      await flow.run(const [GuidanceItem.app]);
      expect(task()!.phase, UpdateHereTaskPhase.failed);
      expect(task()!.failure!.stage, GuidanceItem.app);
      expect(task()!.failure!.needsElevation, isTrue);
    });

    test('"הפסק להמתין" לאשף — השלב נגמר, והתוספים ממשיכים', () async {
      app
        ..gate = Completer<void>()
        ..outcome = AppInstallOutcome.stillOpen;
      plugins.deliverableUpdates = const ['לוח'];
      final run = flow.run(const [GuidanceItem.app, GuidanceItem.plugins]);
      await settle();
      expect(task()!.currentStage, GuidanceItem.app);
      flow.stopWaiting();
      await run;
      expect(app.stops, 1);
      expect(task()!.outcomes[GuidanceItem.app], StageOutcome.stoppedWaiting);
      expect(log, ['app', 'plugins']);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('האשף עוד פתוח בלי שביקשו להפסיק — לא נקרא הצלחה', () async {
      app.outcome = AppInstallOutcome.stillOpen;
      await flow.run(const [GuidanceItem.app]);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
      expect(task()!.outcomes, isEmpty);
    });

    test('תוספים אחרונים, ורק כשיש מה למסור; בלי לסגור את אוצריא', () async {
      plugins.deliverableUpdates = const ['לוח', 'מזומנים'];
      host.running = true;
      await flow.run(const [GuidanceItem.plugins]);
      expect(host.closes, 0);
      expect(task()!.stages, [GuidanceItem.plugins]);
      expect(task()!.plugins.map((p) => p.state),
          everyElement(PluginDeliveryState.sent));
      expect(task()!.phase, UpdateHereTaskPhase.done);

      host.tasks.dismiss();
      plugins.deliverableUpdates = const [];
      expect(await flow.run(const [GuidanceItem.plugins]), isFalse);
      expect(host.tasks.hasTask, isFalse);
    });

    test('"סיום בלי לחכות" — המסך עובר לסיום והמסירה ממשיכה', () async {
      plugins
        ..deliverableUpdates = const ['לוח']
        ..gate = Completer<void>();
      final run = flow.run(const [GuidanceItem.plugins]);
      await settle();
      expect(task()!.currentStage, GuidanceItem.plugins);
      host.tasks.finishWithoutWaiting();
      await run;
      expect(task()!.phase, UpdateHereTaskPhase.done);
      expect(task()!.plugins.single.state, PluginDeliveryState.waiting);
      plugins.gate!.complete();
      await settle();
      expect(task()!.plugins.single.state, PluginDeliveryState.sent);
    });

    test('מנהל של משתמש אחר נשאל קודם; "ביטול" לא מריץ כלום', () async {
      app.elevatedAsOtherUser = true;
      final run = flow.run(both);
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.confirmElevatedOtherUser);
      host.tasks.respond(false);
      await run;
      expect(log, isEmpty);
      expect(host.tasks.hasTask, isFalse);
    });

    test('מנהל של משתמש אחר — רק כשהתוכנה בעדכון', () async {
      app.elevatedAsOtherUser = true;
      await flow.run(const [GuidanceItem.library]);
      expect(log, ['library']);
    });
  });

  group('התקנה ראשונה', () {
    setUp(() {
      app.isInstalled = false;
      library.isFreshInstall = true;
    });

    test('מחשב ריק: התוכנה, בדיקה מחדש, ואז הספרייה — בלי תוספים', () async {
      plugins.deliverableUpdates = const ['לוח'];
      await flow.run(const [
        GuidanceItem.app,
        GuidanceItem.library,
        GuidanceItem.plugins,
      ]);
      expect(log, ['app', 'recheck', 'library']);
      expect(task()!.firstInstall, isTrue);
      expect(task()!.stages, [GuidanceItem.app, GuidanceItem.library]);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('אין אוצריא אבל יש כבר מסד: התוכנה בלבד', () async {
      library.isFreshInstall = false;
      await flow.run(both);
      expect(log, ['app']);
      expect(task()!.stages, [GuidanceItem.app]);
    });

    test('אוצריא שהאשף פתח נסגרת לבד, בלי לשאול', () async {
      app.gate = Completer<void>();
      final run = flow.run(both);
      await settle();
      host.running = true;
      app.gate!.complete();
      await run;
      expect(log, ['app', 'recheck', 'close', 'library']);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('לא נסגרה לבד — שאלה; "לא עכשיו" משאיר את הספרייה', () async {
      app.gate = Completer<void>();
      host.closeSucceeds = false;
      final run = flow.run(both);
      await settle();
      host.running = true;
      app.gate!.complete();
      await settle();
      expect(task()!.phase, UpdateHereTaskPhase.closeOtzaria);
      expect(task()!.closeAfterWizard, isTrue);
      host.tasks.respond(false);
      await run;
      expect(library.applies, 0);
      expect(task()!.outcomes[GuidanceItem.library], StageOutcome.skipped);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });

    test('ביטול באשף אינו ממשיך לספרייה ואינו בודק אותה', () async {
      app.outcome = AppInstallOutcome.cancelled;
      await flow.run(both);
      expect(log, ['app']);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
    });

    test('האשף עוד פתוח אבל אוצריא כבר מותקנת — הספרייה נבדקת ולא מותקנת',
        () async {
      app.outcome = AppInstallOutcome.stillOpen;
      // האשף הניח את אוצריא לפני שחזר.
      app.gate = Completer<void>();
      final run = flow.run(both);
      await settle();
      app.isInstalled = true;
      app.gate!.complete();
      await run;
      expect(log, ['app', 'recheck']);
      expect(library.applies, 0);
      expect(task()!.phase, UpdateHereTaskPhase.cancelledByUser);
    });

    test('אחרי האשף אין בספרייה מה להתקין — השלב מדולג', () async {
      library.availableAfterRecheck = false;
      await flow.run(both);
      expect(log, ['app', 'recheck']);
      expect(task()!.outcomes[GuidanceItem.library], StageOutcome.skipped);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });
  });

  group('מדף התוכנה ומדף הספרייה', () {
    test('התקנה מחדש: אותה גרסה רצה באשף, ורק כשהיא בכונן', () async {
      app.hasUpdateAvailable = false;
      expect(await flow.run(const [GuidanceItem.app]), isFalse);
      expect(app.installs, 0);

      app.canReinstall = true;
      // בלי בקשה מפורשת — "אין עדכון" נשאר "אין מה להתקין".
      expect(await flow.run(const [GuidanceItem.app]), isFalse);
      expect(
        await flow.run(const [GuidanceItem.app], reinstallApp: true),
        isTrue,
      );
      expect(log, ['app']);
      expect(task()!.outcomes[GuidanceItem.app], StageOutcome.done);
    });

    test('הספרייה המלאה: רק אחרי כשל, ובמקום העדכון הרגיל', () async {
      library.hasUpdateAvailable = false;
      expect(
        await flow.run(const [GuidanceItem.library], fullLibrary: true),
        isFalse,
      );
      library.canApplyFull = true;
      await flow.run(const [GuidanceItem.library], fullLibrary: true);
      expect(log, ['library-full']);
      expect(library.applies, 0);
      expect(library.fullApplies, 1);
      expect(task()!.phase, UpdateHereTaskPhase.done);
    });
  });
}
