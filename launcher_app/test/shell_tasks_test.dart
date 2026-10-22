import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';

void main() {
  late ShellTasks tasks;

  setUp(() => tasks = ShellTasks());
  tearDown(() => tasks.dispose());

  DownloadTaskPhase? downloadPhase() => switch (tasks.current) {
        DownloadTask(:final phase) => phase,
        _ => null,
      };

  UpdateHereTask update() => tasks.current! as UpdateHereTask;

  group('הורדה', () {
    test('שאלה → תשובה → רצה → סיום → סגירה', () async {
      final answer = tasks.askBeforeDownload();
      expect(downloadPhase(), DownloadTaskPhase.question);
      tasks.answer(true);
      expect(await answer, isTrue);
      expect(downloadPhase(), DownloadTaskPhase.running);

      tasks.downloadDone(skipped: [GuidanceItem.plugins]);
      expect(downloadPhase(), DownloadTaskPhase.done);
      expect((tasks.current! as DownloadTask).skipped, [GuidanceItem.plugins]);
      tasks.dismiss();
      expect(tasks.hasTask, isFalse);
    });

    test('חזרה מהשאלה = ביטול לפני שההורדה התחילה', () async {
      final answer = tasks.askBeforeDownload();
      tasks.answer(null);
      expect(await answer, isNull);
      expect(tasks.hasTask, isFalse);
    });

    test('כשל → נסה שוב → רצה', () {
      tasks.startDownload();
      tasks.downloadFailed('boom');
      expect(downloadPhase(), DownloadTaskPhase.failed);
      expect((tasks.current! as DownloadTask).error, 'boom');
      tasks.retryDownload();
      expect(downloadPhase(), DownloadTaskPhase.running);
    });

    test('משימה רצה אינה נסגרת, ומשימה שנייה אינה נפתחת', () {
      tasks.startDownload();
      expect(tasks.dismiss, throwsStateError);
      expect(tasks.startDownload, throwsStateError);
      expect(() => tasks.downloadDone(), returnsNormally);
      expect(tasks.downloadCancelled, throwsStateError);
    });

    test('ביטול בזמן השאלה מחזיר null ומנקה את המשימה', () async {
      final answer = tasks.askBeforeDownload();
      tasks.downloadCancelled();
      expect(await answer, isNull);
      expect(tasks.hasTask, isFalse);

      // תשובה מאוחרת אינה עושה דבר, ושאלה חדשה נפתחת כרגיל.
      tasks.answer(true);
      expect(tasks.hasTask, isFalse);
      final again = tasks.askBeforeDownload();
      tasks.answer(true);
      expect(await again, isTrue);
      expect(downloadPhase(), DownloadTaskPhase.running);
    });

    test('ביטול בזמן ריצה → נסה שוב → רצה', () {
      tasks.startDownload();
      tasks.downloadCancelled();
      expect(downloadPhase(), DownloadTaskPhase.cancelled);
      tasks.retryDownload();
      expect(downloadPhase(), DownloadTaskPhase.running);
      tasks.downloadDone();
      expect(downloadPhase(), DownloadTaskPhase.done);
    });

    test('פירוק בזמן שאלה משחרר את הממתין', () async {
      final local = ShellTasks();
      final answer = local.askBeforeDownload();
      local.dispose();
      expect(await answer, isNull);
    });
  });

  group('עדכון כאן', () {
    test('אוצריא פתוחה → סגירה → שלבים לפי הסדר → סיום', () {
      tasks.startUpdateHere(
        [GuidanceItem.library, GuidanceItem.app],
        otzariaRunning: true,
      );
      expect(update().phase, UpdateHereTaskPhase.closeOtzaria);
      expect(update().currentStage, isNull);

      tasks.updateRunning();
      expect(update().currentStage, GuidanceItem.library);
      tasks.stageDone();
      expect(update().currentStage, GuidanceItem.app);
      tasks.stageDone();
      expect(update().phase, UpdateHereTaskPhase.done);
      expect(update().isFinished, isTrue);
    });

    test('ביטול באשף הוא סיום רגוע', () {
      tasks.startUpdateHere([GuidanceItem.app]);
      tasks.updateCancelledByUser();
      expect(update().phase, UpdateHereTaskPhase.cancelledByUser);
      expect(update().error, isNull);
      tasks.dismiss();
      expect(tasks.hasTask, isFalse);
    });

    test('כשל באמצע שומר את השלב, ונסה שוב ממשיך ממנו', () {
      tasks.startUpdateHere([GuidanceItem.library, GuidanceItem.app]);
      tasks.stageDone();
      tasks.updateFailed('locked');
      expect(update().phase, UpdateHereTaskPhase.failed);
      tasks.updateRunning();
      expect(update().currentStage, GuidanceItem.app);
    });

    test('מנהל של משתמש אחר נשאל קודם', () {
      tasks.startUpdateHere([GuidanceItem.app], otherUserElevated: true);
      expect(update().phase, UpdateHereTaskPhase.confirmElevatedOtherUser);
      expect(tasks.stageDone, throwsStateError);
    });

    test('בלי שלבים אין משימה', () {
      expect(() => tasks.startUpdateHere(const []), throwsArgumentError);
    });
  });
}
