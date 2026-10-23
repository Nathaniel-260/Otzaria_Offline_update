import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controllers/download_plan.dart' show MirrorComponent;
import 'home_guidance.dart' show GuidanceItem;

enum DownloadTaskPhase { preparing, question, running, cancelled, done, failed }

enum UpdateHereTaskPhase {
  confirmElevatedOtherUser,
  closeOtzaria,
  running,
  done,
  cancelledByUser,
  failed,
}

/// למה ההורדה נכשלה — קובע את התג ואת הנוסח של מסך הכשל.
enum DownloadFailureKind { network, shabbat, diskSpace, snapshot, other }

class DownloadFailure {
  const DownloadFailure(
    this.kind, {
    this.components = const [],
    this.details,
    this.needed,
    this.free,
  });

  final DownloadFailureKind kind;

  /// הרכיבים שלא ירדו. מה שירד לפניהם נשאר בכונן.
  final List<MirrorComponent> components;

  /// "פרטים טכניים" — הודעות החריגים כמו שהן.
  final String? details;

  /// ב-[DownloadFailureKind.diskSpace]: כמה נדרש וכמה פנוי, מעוצבים.
  final String? needed;
  final String? free;
}

/// איך הסתיים שלב ב"עדכון כאן".
enum StageOutcome {
  done,

  /// "הפסק להמתין" לאשף — לא ידוע אם ההתקנה הסתיימה.
  stoppedWaiting,

  /// לא נדרש בסוף (למשל הספרייה אחרי התקנה ראשונה), או נדחה לפעם אחרת.
  skipped,
}

enum PluginDeliveryState { waiting, sent, failed }

/// שורת תוסף בשלב המסירה. "נשלח" ולא "הותקן": את ההתקנה מאשרים באוצריא.
class PluginDelivery {
  const PluginDelivery(this.name, this.state);

  final String name;
  final PluginDeliveryState state;
}

class UpdateFailure {
  const UpdateFailure(this.stage, {this.message, this.needsElevation = false});

  final GuidanceItem stage;
  final String? message;
  final bool needsElevation;
}

/// משימה שמוצגת בשכבת המשימה של הגוף. בלתי משתנה: כל מעבר יוצר עותק.
sealed class ShellTask {
  const ShellTask();

  /// סיום (טוב או רע) — רק אז מותר לסגור את המסך.
  bool get isFinished;
}

final class DownloadTask extends ShellTask {
  const DownloadTask({
    required this.phase,
    this.components = const [],
    this.skipped = const [],
    this.failure,
    this.revertFailed = false,
  });

  final DownloadTaskPhase phase;

  /// מה ירד בהורדה הזו, לפי הסדר.
  final List<MirrorComponent> components;

  /// מה דולג כי באתר אין בו חדש.
  final List<MirrorComponent> skipped;
  final DownloadFailure? failure;

  /// הביטול לא הצליח להחזיר את הכונן במלואו.
  final bool revertFailed;

  @override
  bool get isFinished => switch (phase) {
        DownloadTaskPhase.cancelled ||
        DownloadTaskPhase.done ||
        DownloadTaskPhase.failed =>
          true,
        _ => false,
      };

  DownloadTask _copy({
    DownloadTaskPhase? phase,
    List<MirrorComponent>? components,
    List<MirrorComponent>? skipped,
    DownloadFailure? failure,
    bool? revertFailed,
  }) =>
      DownloadTask(
        phase: phase ?? this.phase,
        components: components ?? this.components,
        skipped: skipped ?? this.skipped,
        failure: failure ?? this.failure,
        revertFailed: revertFailed ?? this.revertFailed,
      );
}

final class UpdateHereTask extends ShellTask {
  const UpdateHereTask({
    required this.phase,
    required this.stages,
    this.stageIndex = 0,
    this.firstInstall = false,
    this.appVersion,
    this.libraryVersion,
    this.outcomes = const {},
    this.plugins = const [],
    this.closeAfterWizard = false,
    this.stopWaitingRequested = false,
    this.failure,
  });

  final UpdateHereTaskPhase phase;

  /// סדר ההתקנה — ראו `UpdateHereFlow.stagesFor`.
  final List<GuidanceItem> stages;
  final int stageIndex;

  /// אין אוצריא במחשב: "התקנת אוצריא" ולא "עדכון".
  final bool firstInstall;
  final String? appVersion;
  final int? libraryVersion;
  final Map<GuidanceItem, StageOutcome> outcomes;
  final List<PluginDelivery> plugins;

  /// הסגירה נדרשת אחרי האשף (שפתח את אוצריא), לא לפני ההתחלה.
  final bool closeAfterWizard;
  final bool stopWaitingRequested;
  final UpdateFailure? failure;

  GuidanceItem? get currentStage =>
      !isFinished && stageIndex < stages.length ? stages[stageIndex] : null;

  @override
  bool get isFinished => switch (phase) {
        UpdateHereTaskPhase.done ||
        UpdateHereTaskPhase.cancelledByUser ||
        UpdateHereTaskPhase.failed =>
          true,
        _ => false,
      };

  UpdateHereTask _copy({
    UpdateHereTaskPhase? phase,
    int? stageIndex,
    Map<GuidanceItem, StageOutcome>? outcomes,
    List<PluginDelivery>? plugins,
    bool? closeAfterWizard,
    bool? stopWaitingRequested,
    UpdateFailure? failure,
  }) =>
      UpdateHereTask(
        phase: phase ?? this.phase,
        stages: stages,
        stageIndex: stageIndex ?? this.stageIndex,
        firstInstall: firstInstall,
        appVersion: appVersion,
        libraryVersion: libraryVersion,
        outcomes: outcomes ?? this.outcomes,
        plugins: plugins ?? this.plugins,
        closeAfterWizard: closeAfterWizard ?? this.closeAfterWizard,
        stopWaitingRequested: stopWaitingRequested ?? this.stopWaitingRequested,
        failure: failure ?? this.failure,
      );
}

/// מכונת המצבים של מסכי המשימה. משימה אחת בכל פעם; מעבר לא חוקי נזרק,
/// כי הוא באג בזרימה ולא מצב שהמשתמש יכול להגיע אליו.
class ShellTasks extends ChangeNotifier {
  ShellTask? _current;
  Completer<bool?>? _question;
  Completer<bool>? _decision;
  Completer<void>? _finishNow;

  ShellTask? get current => _current;
  bool get hasTask => _current != null;

  /// משימה שעוד לא הסתיימה מוצגת — ולכן אין לצאת ממסך המשימה.
  bool get isRunning => _current?.isFinished == false;

  static const _downloadMoves = {
    DownloadTaskPhase.preparing: {
      DownloadTaskPhase.question,
      DownloadTaskPhase.running,
      DownloadTaskPhase.failed,
    },
    DownloadTaskPhase.question: {DownloadTaskPhase.preparing},
    DownloadTaskPhase.running: {
      DownloadTaskPhase.cancelled,
      DownloadTaskPhase.done,
      DownloadTaskPhase.failed,
    },
  };

  // ── הורדה לכונן ──

  /// ההורדה מתכוננת (בדיקה ברשת של מה שהתיישן). מחליף משימה שהסתיימה —
  /// "נסה שוב" ו"הורד שוב" מתחילים מכאן בלי לחזור לבית בדרך.
  void prepareDownload() {
    _requireIdle();
    _set(const DownloadTask(phase: DownloadTaskPhase.preparing));
  }

  /// השאלה שלפני ההורדה ("להוריד גם חיפוש חכם?"). `null` = חזרה, כלומר
  /// ביטול לפני שההורדה התחילה.
  Future<bool?> askBeforeDownload() {
    if (_current == null) prepareDownload();
    _moveDownload(DownloadTaskPhase.question);
    return (_question = Completer<bool?>()).future;
  }

  void answer(bool? value) {
    final question = _question;
    if (question == null || question.isCompleted) return;
    _question = null;
    if (value == null) {
      _set(null);
    } else {
      _moveDownload(DownloadTaskPhase.preparing);
    }
    question.complete(value);
  }

  /// ההורדה התחילה בפועל — [components] הם מה שירד, לפי הסדר.
  void downloadRunning(List<MirrorComponent> components) {
    if (_current == null) prepareDownload();
    final task = _current;
    if (task is DownloadTask && task.phase == DownloadTaskPhase.running) return;
    _moveDownload(DownloadTaskPhase.running, components: components);
  }

  /// הזרימה חזרה בלי להתחיל (חסימה, בלי בחירה) — המסך נסגר בשקט.
  void abandonDownload() {
    final task = _current;
    if (task is! DownloadTask) return;
    if (task.phase == DownloadTaskPhase.question) return answer(null);
    if (task.phase == DownloadTaskPhase.preparing) _set(null);
  }

  /// ביטול לפני שההורדה התחילה הוא תשובה ריקה לשאלה, לא מצב "בוטל".
  void downloadCancelled({bool revertFailed = false}) => _question != null
      ? answer(null)
      : _moveDownload(
          DownloadTaskPhase.cancelled,
          revertFailed: revertFailed,
        );

  void downloadFailed(DownloadFailure failure) =>
      _moveDownload(DownloadTaskPhase.failed, failure: failure);

  void downloadDone({List<MirrorComponent> skipped = const []}) =>
      _moveDownload(DownloadTaskPhase.done, skipped: skipped);

  // ── עדכון במחשב הזה ──

  void startUpdateHere(
    List<GuidanceItem> stages, {
    bool firstInstall = false,
    String? appVersion,
    int? libraryVersion,
    List<String> pluginNames = const [],
  }) {
    _requireIdle();
    if (stages.isEmpty) throw ArgumentError.value(stages, 'stages');
    _finishNow = Completer<void>();
    _set(UpdateHereTask(
      phase: UpdateHereTaskPhase.running,
      stages: List.unmodifiable(stages),
      firstInstall: firstInstall,
      appVersion: appVersion,
      libraryVersion: libraryVersion,
      plugins: [
        for (final name in pluginNames)
          PluginDelivery(name, PluginDeliveryState.waiting),
      ],
    ));
  }

  /// "הותקנה על ידי משתמש אחר" — `true` = "המשך בכל זאת".
  Future<bool> askOtherUser() =>
      _ask(UpdateHereTaskPhase.confirmElevatedOtherUser);

  /// "צריך לסגור את אוצריא" — `true` = "סגירה והמשך".
  Future<bool> askToCloseOtzaria({bool afterWizard = false}) => _ask(
        UpdateHereTaskPhase.closeOtzaria,
        closeAfterWizard: afterWizard,
      );

  /// תשובת המשתמש לשאלה שבמסך המשימה.
  void respond(bool value) {
    final decision = _decision;
    if (decision == null || decision.isCompleted) return;
    _decision = null;
    _moveUpdate(UpdateHereTaskPhase.running);
    decision.complete(value);
  }

  void stageRunning(GuidanceItem stage) {
    final task = _updateTask();
    final index = task.stages.indexOf(stage);
    if (index < 0) throw ArgumentError.value(stage, 'stage');
    _set(task._copy(
      phase: UpdateHereTaskPhase.running,
      stageIndex: index,
      stopWaitingRequested: false,
    ));
  }

  void stageFinished(GuidanceItem stage, StageOutcome outcome) {
    final task = _updateTask();
    _set(task._copy(
      outcomes: {...task.outcomes, stage: outcome},
      stageIndex: task.stages.indexOf(stage) + 1,
    ));
  }

  void pluginDeliveries(List<PluginDelivery> rows) =>
      _set(_updateTask()._copy(plugins: List.unmodifiable(rows)));

  /// "הפסק להמתין" לאשף ההתקנה.
  void requestStopWaiting() {
    final task = _current;
    if (task is! UpdateHereTask || task.isFinished) return;
    _set(task._copy(stopWaitingRequested: true));
  }

  /// "סיום בלי לחכות" במסירת התוספים: המסירה ממשיכה, המסך עובר לסיום.
  void finishWithoutWaiting() {
    final finish = _finishNow;
    if (finish != null && !finish.isCompleted) finish.complete();
  }

  Future<void> get finishRequested => (_finishNow ??= Completer<void>()).future;

  void updateDone() => _moveUpdate(UpdateHereTaskPhase.done);

  /// ביטול באשף של אוצריא הוא החלטה של המשתמש — סיום רגוע, לא כשל.
  void updateCancelledByUser() =>
      _moveUpdate(UpdateHereTaskPhase.cancelledByUser);

  void updateFailed(UpdateFailure failure) =>
      _moveUpdate(UpdateHereTaskPhase.failed, failure: failure);

  /// "ביטול" לפני ששום שלב רץ — המסך נסגר וחוזרים למה שהיה.
  void abandonUpdate() {
    final task = _current;
    if (task is UpdateHereTask && !task.isFinished) _set(null);
  }

  /// סוגר משימה שהסתיימה. משימה רצה אינה נסגרת מכאן.
  void dismiss() {
    final task = _current;
    if (task == null) return;
    if (!task.isFinished) {
      throw StateError('cannot dismiss a running task: $task');
    }
    _set(null);
  }

  @override
  void dispose() {
    final question = _question;
    _question = null;
    if (question != null && !question.isCompleted) question.complete(null);
    final decision = _decision;
    _decision = null;
    if (decision != null && !decision.isCompleted) decision.complete(false);
    finishWithoutWaiting();
    super.dispose();
  }

  /// משימה חדשה מחליפה רק משימה שהסתיימה.
  void _requireIdle() {
    if (_current?.isFinished == false) {
      throw StateError('a task is already running');
    }
  }

  Future<bool> _ask(UpdateHereTaskPhase phase,
      {bool closeAfterWizard = false}) {
    final task = _updateTask();
    if (task.isFinished || _decision != null) {
      throw StateError('cannot ask in $task');
    }
    _set(task._copy(phase: phase, closeAfterWizard: closeAfterWizard));
    return (_decision = Completer<bool>()).future;
  }

  void _moveDownload(
    DownloadTaskPhase to, {
    List<MirrorComponent>? components,
    List<MirrorComponent>? skipped,
    DownloadFailure? failure,
    bool? revertFailed,
  }) {
    final task = _current;
    if (task is! DownloadTask ||
        !(_downloadMoves[task.phase]?.contains(to) ?? false)) {
      throw StateError('illegal download move: $task -> $to');
    }
    _set(task._copy(
      phase: to,
      components: components,
      skipped: skipped,
      failure: failure,
      revertFailed: revertFailed,
    ));
  }

  void _moveUpdate(UpdateHereTaskPhase to, {UpdateFailure? failure}) {
    final task = _current;
    if (task is! UpdateHereTask || task.isFinished) {
      throw StateError('illegal update move: $task -> $to');
    }
    _set(task._copy(phase: to, failure: failure));
  }

  UpdateHereTask _updateTask() {
    final task = _current;
    if (task is! UpdateHereTask) {
      throw StateError('expected an update task, got $task');
    }
    return task;
  }

  void _set(ShellTask? task) {
    _current = task;
    notifyListeners();
  }
}
