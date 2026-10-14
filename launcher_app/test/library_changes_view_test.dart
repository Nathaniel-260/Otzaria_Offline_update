import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';

import 'test_harness.dart';

const _bookCount = 3000;

String _bigNotes() {
  final buffer =
      StringBuffer('# גרסה 33\n\n**13/10/2026**\n\n## ספרים חדשים\n');
  for (var i = 1; i <= _bookCount; i++) {
    buffer.writeln('* ספר מספר $i בספרייה');
  }
  return buffer.toString();
}

Future<void> _pumpView(WidgetTester tester, List<String> markdowns) async {
  useViewSize(tester, const Size(900, 900));
  await tester.pumpWidget(
    wrap(
      Scaffold(
        body: Center(
          child: LibraryChangesView(markdowns: markdowns, emptyText: 'empty'),
        ),
      ),
    ),
  );
}

void main() {
  test('the markdown becomes flat lines, one note after another', () {
    final lines = parseLibraryChanges([
      '# v33\n**13/10**\n## חדשים\n* **ספר א**\n- ספר ב\nמלל\n---',
      '# v32',
    ]);

    expect(lines.map((l) => l.kind), [
      LibraryChangesLineKind.title,
      LibraryChangesLineKind.subtitle,
      LibraryChangesLineKind.section,
      LibraryChangesLineKind.item,
      LibraryChangesLineKind.item,
      LibraryChangesLineKind.text,
      LibraryChangesLineKind.separator,
      LibraryChangesLineKind.title,
    ]);
    expect(lines[3].text, 'ספר א');
  });

  testWidgets(
      '3,000 books: parsed off the UI isolate, built lazily, RTL, '
      'scrolls to the end', (tester) async {
    final notes = _bigNotes();
    expect(notes.length, greaterThan(LibraryChangesView.parseInIsolateChars));

    final stopwatch = Stopwatch()..start();
    await _pumpView(tester, [notes]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    stopwatch.stop();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));

    final first = find.text('• ספר מספר 1 בספרייה');
    expect(first, findsOneWidget);
    expect(
      find.textContaining('• ספר מספר', findRichText: false).evaluate().length,
      lessThan(100),
    );

    expect(Directionality.of(tester.element(first)), TextDirection.rtl);
    final list = tester.getRect(find.byType(ListView));
    final item = tester.getRect(first);
    // ההזחה של פריט יושבת בצד ההתחלה — מימין ב-RTL.
    expect(list.right - item.right, AppTokens.spaceMD);
    expect(item.left, list.left);
    expect(
      tester.renderObject<RenderParagraph>(first).textDirection,
      TextDirection.rtl,
    );

    await tester.scrollUntilVisible(
      find.text('• ספר מספר $_bookCount בספרייה'),
      2000,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('• ספר מספר $_bookCount בספרייה'), findsOneWidget);
    expect(first, findsNothing);
  });

  testWidgets('a mouse wheel on Windows scrolls without a controller error', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _pumpView(tester, [
      List.generate(200, (i) => '* ספר $i').join('\n'),
    ]);
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(ListView))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 600)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('• ספר 0'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a partial list says so above the books', (tester) async {
    useViewSize(tester, const Size(900, 900));
    await tester.pumpWidget(
      wrap(
        const Scaffold(
          body: LibraryChangesView(
            markdowns: ['* ספר'],
            emptyText: 'empty',
            note: 'partial',
          ),
        ),
      ),
    );

    expect(find.text('partial'), findsOneWidget);
  });

  testWidgets('a small file is shown at once, without an isolate', (
    tester,
  ) async {
    await _pumpView(tester, ['# v33\n* ספר']);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('• ספר'), findsOneWidget);
  });

  testWidgets('nothing readable shows the empty text', (tester) async {
    await _pumpView(tester, const []);

    expect(find.text('empty'), findsOneWidget);
  });
}
