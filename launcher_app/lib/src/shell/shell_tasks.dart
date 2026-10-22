import 'dart:async';

import 'package:flutter/foundation.dart';

import 'home_guidance.dart';

enum DownloadTaskPhase { question, running, cancelled, done, failed }

enum UpdateHereTaskPhase {
  confirmElevatedOtherUser,
  closeOtzaria,
  running,
  done,
  cancelledByUser,
  failed,
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
    this.failed = const [],
    this.skipped = const [],
    this.error,
  });

  final DownloadTaskPhase phase;
  final List<GuidanceItem> failed;
  final List<GuidanceItem> skipped;
  final Object? error;

  @override
  bool get isFinished => switch (phase) {
        DownloadTaskPhase.question || DownloadTaskPhase.running => false,
        _ => true,
      };
}

final class UpdateHereTask extends ShellTask {
  const UpdateHereTask({
    required this.phase,
    required this.stages,
    this.stageIndex = 0,
    this.error,
  });

  final UpdateHereTaskPhase phase;

  /// סדר ההתקנה — ראו [updateHereStages].
  final List<GuidanceItem> stages;
  final int stageIndex;
  final Object? error;

  GuidanceItem? get currentStage =>
      phase == UpdateHereTaskPhase.running && stageIndex < stages.length
          ? stages[stageIndex]
          : null;

  @override
  bool get isFinished => switch (phase) {
        UpdateHereTaskPhase.done ||
        UpdateHereTaskPhase.cancelledByUser ||
        UpdateHereTaskPhase.failed =>
          true,
        _ => false,
      };
}

/// מכונת המצבים של מסכי המשימה. משימה אחת בכל פעם; מעבר לא חוקי נזרק,
/// כי הוא באג בזרימה ולא מצב שהמשתמש יכול להגיע אליו.
class ShellTasks extends ChangeNotifier {
  ShellTask? _current;
  Completer<bool?>? _question;

  ShellTask? get current => _current;
  bool get hasTask => _current != null;

  static const _downloadMoves = {
    DownloadTaskPhase.question: {DownloadTaskPhase.running},
    DownloadTaskPhase.running: {
      DownloadTaskPhase.cancelled,
      DownloadTaskPhase.done,
      DownloadTaskPhase.failed,
    },
    DownloadTaskPhase.failed: {DownloadTaskPhase.running},
    DownloadTaskPhase.cancelled: {DownloadTaskPhase.running},
  };

  static const _updateMoves = {
    UpdateHereTaskPhase.confirmElevatedOtherUser: {
      UpdateHereTaskPhase.closeOtzaria,
      UpdateHereTaskPhase.running,
      UpdateHereTaskPhase.cancelledByUser,
    },
    UpdateHereTaskPhase.closeOtzaria: {
      UpdateHereTaskPhase.running,
      UpdateHereTaskPhase.cancelledByUser,
    },
    UpdateHereTaskPhase.running: {
      UpdateHereTaskPhase.closeOtzaria,
      UpdateHereTaskPhase.done,
      UpdateHereTaskPhase.cancelledByUser,
      UpdateHereTaskPhase.failed,
    },
    UpdateHereTaskPhase.failed: {UpdateHereTaskPhase.running},
  };

  void startDownload() {
    _requireIdle();
    _set(const DownloadTask(phase: DownloadTaskPhase.running));
  }

  /// השאלה שלפני ההורדה ("להוריד גם חיפוש חכם?"). `null` = חזרה, כלומר
  /// ביטול לפני שההורדה התחילה.
  Future<bool?> askBeforeDownload() {
    _requireIdle();
    _set(const DownloadTask(phase: DownloadTaskPhase.question));
    return (_question = Completer<bool?>()).future;
  }

  void answer(bool? value) {
    final question = _question;
    if (question == null || question.isCompleted) return;
    _question = null;
    if (value == null) {
      _set(null);
    } else {
      _moveDownload(DownloadTaskPhase.running);
    }
    question.complete(value);
  }

  /// ביטול לפני שההורדה התחילה הוא תשובה ריקה לשאלה, לא מצב "בוטל".
  void downloadCancelled() => _question != null
      ? answer(null)
      : _moveDownload(DownloadTaskPhase.cancelled);

  void downloadFailed(Object error) =>
      _moveDownload(DownloadTaskPhase.failed, error: error);

  void downloadDone({
    List<GuidanceItem> failed = const [],
    List<GuidanceItem> skipped = const [],
  }) =>
      _moveDownload(DownloadTaskPhase.done, failed: failed, skipped: skipped);

  void retryDownload() => _moveDownload(DownloadTaskPhase.running);

  void startUpdateHere(
    List<GuidanceItem> stages, {
    bool otherUserElevated = false,
    bool otzariaRunning = false,
  }) {
    _requireIdle();
    if (stages.isEmpty) throw ArgumentError.value(stages, 'stages');
    _set(UpdateHereTask(
      phase: otherUserElevated
          ? UpdateHereTaskPhase.confirmElevatedOtherUser
          : otzariaRunning
              ? UpdateHereTaskPhase.closeOtzaria
              : UpdateHereTaskPhase.running,
      stages: List.unmodifiable(stages),
    ));
  }

  void needsOtzariaClosed() => _moveUpdate(UpdateHereTaskPhase.closeOtzaria);

  void updateRunning() => _moveUpdate(UpdateHereTaskPhase.running);

  /// השלב הנוכחי הסתיים; אחרי האחרון המשימה מסתיימת.
  void stageDone() {
    final task = _updateTask(UpdateHereTaskPhase.running);
    final next = task.stageIndex + 1;
    _set(UpdateHereTask(
      phase: next < task.stages.length
          ? UpdateHereTaskPhase.running
          : UpdateHereTaskPhase.done,
      stages: task.stages,
      stageIndex: next,
    ));
  }

  /// ביטול באשף של אוצריא הוא החלטה של המשתמש — סיום רגוע, לא כשל.
  void updateCancelledByUser() =>
      _moveUpdate(UpdateHereTaskPhase.cancelledByUser);

  void updateFailed(Object error) =>
      _moveUpdate(UpdateHereTaskPhase.failed, error: error);

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
    super.dispose();
  }

  void _requireIdle() {
    if (_current != null) throw StateError('a task is already shown');
  }

  void _moveDownload(
    DownloadTaskPhase to, {
    List<GuidanceItem> failed = const [],
    List<GuidanceItem> skipped = const [],
    Object? error,
  }) {
    final task = _current;
    if (task is! DownloadTask ||
        !(_downloadMoves[task.phase]?.contains(to) ?? false)) {
      throw StateError('illegal download move: $task -> $to');
    }
    _set(DownloadTask(
      phase: to,
      failed: failed,
      skipped: skipped,
      error: error,
    ));
  }

  void _moveUpdate(UpdateHereTaskPhase to, {Object? error}) {
    final task = _current;
    if (task is! UpdateHereTask ||
        !(_updateMoves[task.phase]?.contains(to) ?? false)) {
      throw StateError('illegal update move: $task -> $to');
    }
    _set(UpdateHereTask(
      phase: to,
      stages: task.stages,
      stageIndex: task.stageIndex,
      error: error,
    ));
  }

  UpdateHereTask _updateTask(UpdateHereTaskPhase phase) {
    final task = _current;
    if (task is! UpdateHereTask || task.phase != phase) {
      throw StateError('expected an update task in $phase, got $task');
    }
    return task;
  }

  void _set(ShellTask? task) {
    _current = task;
    notifyListeners();
  }
}
