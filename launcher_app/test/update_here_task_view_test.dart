import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/tasks/task_parts.dart';
import 'package:launcher_app/src/screens/tasks/update_here_task_view.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';

import 'task_fixtures.dart';
import 'test_harness.dart';

void main() {
  final t = stringsOf().task;
  late List<String> calls;

  setUp(() => calls = []);

  Future<void> show(WidgetTester tester, String name) =>
      pumpScreen(tester, taskScenario(name, calls: calls),
          size: const Size(1000, 1400));

  List<StageState> stageStates(WidgetTester tester) => tester
      .widgetList<StageRow>(find.byType(StageRow))
      .map((r) => r.state)
      .toList();

  ResultBadge badge(WidgetTester tester) =>
      tester.widget<ResultBadge>(find.byType(ResultBadge));

  testWidgets('הכלי פועל כמנהל בחשבון אחר: "ביטול" ו"המשך בכל זאת"',
      (tester) async {
    await show(tester, 'otherUser');
    expect(find.text(t.otherUserTitle), findsOneWidget);
    // ההתקנה תיכנס לחשבון של המנהל — וההמלצה היא בלי "הפעל כמנהל".
    final body = t.otherUserBody(firstInstall: false, account: 'Admin');
    expect(find.text(body), findsOneWidget);
    expect(body, contains('Admin'));
    expect(t.otherUserHint, contains('בלי'));
    await tester.tap(find.text(t.continueAnyway));
    await tester.tap(find.text(stringsOf().common.cancel));
    expect(calls, ['respond true', 'respond false']);
  });

  testWidgets('צריך לסגור את אוצריא — "סגירה והמשך" ראשי, ותוספים נאמרים',
      (tester) async {
    await show(tester, 'close');
    expect(find.text(t.closeTitle), findsOneWidget);
    expect(find.text(t.closeHint(plugins: true)), findsOneWidget);
    final primary =
        tester.widget<ActionButton>(find.byKey(ShellKeys.taskPrimary));
    expect(primary.text, t.closeAndContinue);
    await tester.tap(find.byKey(ShellKeys.taskPrimary));
    expect(calls, ['respond true']);
  });

  testWidgets('שלב הספרייה: התקדמות מה-progress, "אל תנתקו את הכונן"',
      (tester) async {
    final progress = ValueNotifier(0);
    var fraction = 0.1;
    var parentBuilds = 0;
    await pumpScreen(
      tester,
      Builder(builder: (context) {
        parentBuilds++;
        return UpdateHereTaskView(
          task: updateScenarios['instLib']!,
          libraryProgress: progress,
          librarySnapshot: () =>
              LibraryApplySnapshot(fraction: fraction, stage: 'מחיל'),
          actions: UpdateHereActions(
            onRespond: (_) {},
            onStopWaiting: () {},
            onFinishWithoutWaiting: () {},
            onLaunch: () {},
            onHome: () {},
            onRetry: () {},
            onOpenPage: (_) {},
          ),
        );
      }),
    );
    expect(find.text(t.updatingLibrary), findsOneWidget);
    expect(find.text(t.stepOf(1, 3)), findsOneWidget);
    expect(find.text(t.keepDrive), findsOneWidget);
    expect(stageStates(tester),
        [StageState.current, StageState.waiting, StageState.waiting]);
    expect(find.text('10% · ${t.libraryVersion(27)}'), findsOneWidget);

    fraction = 0.46;
    progress.value++;
    await tester.pump();
    expect(parentBuilds, 1);
    expect(find.text('46% · ${t.libraryVersion(27)}'), findsOneWidget);
  });

  testWidgets('שלב התוכנה: האשף פתוח — פס בלי ערך ו"הפסק להמתין"',
      (tester) async {
    await show(tester, 'instApp');
    expect(find.text(t.updatingApp), findsOneWidget);
    expect(find.text(t.appWizardOpen), findsOneWidget);
    expect(stageStates(tester),
        [StageState.done, StageState.current, StageState.waiting]);
    final bars = tester.widgetList<AppProgressBar>(find.byType(AppProgressBar));
    expect(bars.single.value, isNull);
    await tester.tap(find.byKey(ShellKeys.taskStopWaiting));
    expect(calls, ['stop waiting']);
    expect(find.text(t.keepDrive), findsNothing);
  });

  testWidgets('שלב התוספים: "נשלח לאוצריא", לעולם לא "אושר"; "סיום בלי לחכות"',
      (tester) async {
    await show(tester, 'instPlug');
    expect(find.text(t.sendingPlugins), findsOneWidget);
    expect(find.text('לוח שנה עברי · ${t.pluginRowSent}'), findsOneWidget);
    expect(find.text('מזומנים · ${t.pluginRowWaiting}'), findsOneWidget);
    await tester.tap(find.text(t.finishWithoutWaiting));
    expect(calls, ['finish now']);
  });

  testWidgets('אוצריא מעודכנת: סיכום, אינדוקס ו"מעבר לאוצריא"', (tester) async {
    await show(tester, 'installDone');
    expect(find.text(t.updatedTitle), findsOneWidget);
    expect(badge(tester).kind, ResultBadgeKind.ok);
    expect(
      find.text(t.doneHereBody(
        firstInstall: false,
        app: true,
        library: true,
        plugins: true,
      )),
      findsOneWidget,
    );
    expect(find.text(t.pluginsSent), findsOneWidget);
    expect(find.text(t.reindexTitle), findsOneWidget);
    await tester.tap(find.byKey(ShellKeys.taskReindex));
    await tester.tap(find.text(t.toOtzaria));
    expect(calls, ['reindex', 'launch']);
  });

  testWidgets('בלי תוספים — "פתח את אוצריא"; בלי אינדוקס — אין שורה',
      (tester) async {
    await show(tester, 'firstDone');
    expect(find.text(t.installedTitle), findsOneWidget);
    expect(find.text(stringsOf().guide.launchButton), findsOneWidget);
    expect(find.text(t.reindexTitle), findsNothing);
  });

  testWidgets('האשף נסגר לפני הסוף: רגוע, והספרייה שעודכנה נשארת',
      (tester) async {
    await show(tester, 'wizardClosed');
    expect(find.text(t.wizardClosedTitle), findsOneWidget);
    expect(
      find.text(t.wizardClosedBody(firstInstall: false, libraryDone: true)),
      findsOneWidget,
    );
    expect(badge(tester).kind, ResultBadgeKind.calm);
    await tester.tap(find.text(stringsOf().common.retry));
    expect(calls, ['retry']);
  });

  testWidgets('סירוב לסגור באמצע — "העדכון נעצר", לא כשל', (tester) async {
    await pumpScreen(
      tester,
      UpdateHereTaskView(
        task: const UpdateHereTask(
          phase: UpdateHereTaskPhase.cancelledByUser,
          stages: [GuidanceItem.library, GuidanceItem.app],
        ),
        libraryProgress: ValueNotifier(0),
        librarySnapshot: () => const LibraryApplySnapshot(),
        actions: UpdateHereActions(
          onRespond: (_) {},
          onStopWaiting: () {},
          onFinishWithoutWaiting: () {},
          onLaunch: () {},
          onHome: () {},
          onRetry: () {},
          onOpenPage: (_) {},
        ),
      ),
    );
    expect(find.text(t.stoppedTitle), findsOneWidget);
    expect(badge(tester).kind, ResultBadgeKind.calm);
  });

  testWidgets('עדכון הספרייה נכשל: אדום, ההודעה, "נסה שוב" ודף הספרייה',
      (tester) async {
    await show(tester, 'instFail');
    expect(find.text(t.libraryFailedTitle), findsOneWidget);
    expect(badge(tester).kind, ResultBadgeKind.error);
    expect(find.textContaining('נדרשים 2.4 GB'), findsOneWidget);
    expect(find.textContaining(t.libraryFailedKeep), findsOneWidget);
    expect(find.byKey(ShellKeys.taskElevation), findsNothing);
    await tester.tap(find.text(stringsOf().common.retry));
    await tester.tap(find.text(t.toLibraryPage));
    expect(calls, ['retry', 'page library']);
  });

  testWidgets('כשל הרשאות: גוף ידידותי, השגיאה בפרטים, בלי "לדף התוכנה"',
      (tester) async {
    await show(tester, 'instFailAdmin');
    expect(find.text(t.permissionFailedTitle), findsOneWidget);
    expect(find.text(t.permissionAppBody), findsOneWidget);
    expect(find.byKey(ShellKeys.taskElevation), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ShellKeys.taskElevation),
        matching: find.text(t.elevateTitle),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Access is denied'), findsNothing);
    expect(find.text(t.toAppPage), findsNothing);
    final primary =
        tester.widget<ActionButton>(find.byKey(ShellKeys.taskPrimary));
    expect(primary.text, t.elevateButton);
    await tester.tap(find.text(t.techDetails));
    await tester.pump();
    expect(find.textContaining('Access is denied'), findsOneWidget);
    await tester.tap(find.byKey(ShellKeys.taskPrimary));
    expect(calls, ['elevate']);
  });

  testWidgets('התקנה ראשונה: אוצריא שהאשף פתח — "סגירת אוצריא והמשך"',
      (tester) async {
    await show(tester, 'firstClose');
    expect(find.text(t.closeAfterWizardBody), findsOneWidget);
    expect(find.text(t.libraryWaitingClose), findsOneWidget);
    await tester.tap(find.text(t.closeAfterWizardButton));
    await tester.tap(find.text(t.notNow));
    expect(calls, ['respond true', 'respond false']);
  });

  group('תיקוני QA של 2b', () {
    testWidgets('אחרי "הפסק להמתין" בעדכון: לא "מעודכנת", ותוספים לא נשלחו',
        (tester) async {
      await show(tester, 'stoppedDone');
      expect(find.text(t.stoppedWaitingTitle), findsOneWidget);
      expect(find.text(t.updatedTitle), findsNothing);
      expect(
        find.text(t.stoppedWaitingBody(firstInstall: false, libraryDone: true)),
        findsOneWidget,
      );
      expect(find.text(t.pluginsAfterInstall), findsOneWidget);
      expect(find.text(t.pluginsSent), findsNothing);
      expect(badge(tester).kind, ResultBadgeKind.calm);
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      expect(calls, ['page app']);
    });

    testWidgets('"הפסק להמתין" בהתקנה ראשונה — בלי "אוצריא נשארה פתוחה"',
        (tester) async {
      await show(tester, 'firstStopped');
      expect(find.text(t.stoppedWaitingTitle), findsOneWidget);
      expect(find.text(t.stoppedBody), findsNothing);
      expect(find.text(stringsOf().common.retry), findsNothing);
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      expect(calls, ['page app']);
    });

    testWidgets('האשף עדיין פתוח אחרי הזמן הקצוב — לא "נסגר לפני הסוף"',
        (tester) async {
      await show(tester, 'wizardStillOpen');
      expect(find.text(t.wizardStillOpenTitle), findsOneWidget);
      expect(find.text(t.wizardClosedTitle), findsNothing);
    });

    testWidgets('מסירה מעורבת: רק מה שנשלח נקרא "נשלח"', (tester) async {
      await show(tester, 'pluginsMixed');
      expect(find.text(t.pluginsSent), findsNothing);
      expect(
        find.text('${t.pluginsSentNames('לוח שנה עברי')} · '
            '${t.pluginsNotSent('מזומנים')}'),
        findsOneWidget,
      );
      expect(
        find.text(t.doneHereBody(
          firstInstall: false,
          app: false,
          library: false,
          plugins: true,
        )),
        findsOneWidget,
      );
    });

    testWidgets('ספרייה שהותקנה עם הערה — הצלחה, וההערה בשורה', (tester) async {
      await show(tester, 'libraryNote');
      expect(find.text(t.installedTitle), findsOneWidget);
      expect(badge(tester).kind, ResultBadgeKind.ok);
      expect(find.textContaining('בחרו אותה בהגדרות'), findsOneWidget);
      expect(find.text(t.libraryFailedTitle), findsNothing);
    });

    testWidgets('ממתין לסגירת אוצריא — מנעול ולא טבעת מסתובבת', (tester) async {
      await show(tester, 'firstClose');
      final library = tester
          .widgetList<StageRow>(find.byType(StageRow))
          .firstWhere((r) => r.title == t.componentLibrary);
      expect(library.state, StageState.current);
      expect(library.mark, isA<Icon>());
    });

    testWidgets('שלב הספרייה: האומדן מוצג כשידוע', (tester) async {
      await pumpScreen(
        tester,
        UpdateHereTaskView(
          task: const UpdateHereTask(
            phase: UpdateHereTaskPhase.running,
            stages: [GuidanceItem.library],
            libraryMinutes: (low: 3, high: 12),
          ),
          libraryProgress: ValueNotifier(0),
          librarySnapshot: () => const LibraryApplySnapshot(),
          actions: UpdateHereActions(
            onRespond: (_) {},
            onStopWaiting: () {},
            onFinishWithoutWaiting: () {},
            onLaunch: () {},
            onHome: () {},
            onRetry: () {},
            onOpenPage: (_) {},
          ),
        ),
      );
      expect(find.text(t.libraryBody(3, 12)), findsOneWidget);
    });

    test('הודעת כשל: מקומית לגוף, טקסט חריג לפרטים בלבד', () {
      expect(
        splitFailureMessage('אין מספיק מקום\nפרט נוסף'),
        (body: 'אין מספיק מקום', details: 'פרט נוסף'),
      );
      expect(
        splitFailureMessage('Bad state: Access is denied (OS Error 5)'),
        (body: null, details: 'Bad state: Access is denied (OS Error 5)'),
      );
      expect(splitFailureMessage(null), (body: null, details: null));
    });

    test('כיוון הפרטים הטכניים לפי התו החזק הראשון', () {
      expect(
          textDirectionOf('library: Bad state: אין מקום'), TextDirection.ltr);
      expect(textDirectionOf('אין מספיק מקום (C:)'), TextDirection.rtl);
      expect(textDirectionOf('12345'), TextDirection.ltr);
    });
  });

  group('חלון צר (760×560)', () {
    for (final name in taskScenarioNames) {
      testWidgets('$name: הפעולה הראשית גלויה בלי גלילה', (tester) async {
        await pumpScreen(
          tester,
          taskScenarioInWindow(name),
          size: const Size(760, 560),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final primary = find.byKey(ShellKeys.taskPrimary);
        if (primary.evaluate().isEmpty) return;
        final rect = tester.getRect(primary);
        expect(rect.top, greaterThanOrEqualTo(36), reason: name);
        expect(rect.bottom, lessThanOrEqualTo(560), reason: name);
      });
    }

    testWidgets('שורות השלב קומפקטיות, והתג 56', (tester) async {
      await pumpScreen(
        tester,
        taskScenarioInWindow('installDone'),
        size: const Size(760, 560),
      );
      expect(tester.getSize(find.byType(ResultBadge)).width, 56);
      await pumpScreen(
        tester,
        taskScenarioInWindow('instApp'),
        size: const Size(760, 560),
      );
      expect(
        tester
            .widgetList<StageRow>(find.byType(StageRow))
            .map((r) => r.compact),
        everyElement(isTrue),
      );
    });
  });
}
