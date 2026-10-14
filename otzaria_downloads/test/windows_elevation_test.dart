import 'dart:async';
import 'dart:io';

import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:test/test.dart';

void main() {
  test('ארגומנטים להפעלה לא-מורמת מצוטטים כמו ב-CommandLineToArgvW', () {
    expect(WindowsElevation.quoteArgument('otzaria://x'), 'otzaria://x');
    expect(
      WindowsElevation.quoteArgument(r'C:\Program Files\o.exe'),
      r'"C:\Program Files\o.exe"',
    );
    expect(WindowsElevation.quoteArgument(r'a"b'), r'"a\"b"');
    expect(
      WindowsElevation.quoteArgument('C:\\dir with space\\'),
      '"C:\\dir with space\\\\"',
    );
    expect(WindowsElevation.quoteArgument(''), '""');
  });

  test('פונקציית ציטוט אחת: כל רווח לבן, ולוכסנים לפני מרכאה', () {
    expect(WindowsElevation.quoteArgument(r'C:\dir\a.exe'), r'C:\dir\a.exe');
    expect(WindowsElevation.quoteArgument('a\tb'), '"a\tb"');
    expect(WindowsElevation.quoteArgument('a\nb'), '"a\nb"');
    expect(WindowsElevation.quoteArgument(r'a\"b'), r'"a\\\"b"');
    expect(WindowsElevation.quoteArgument(r'a\\b c'), r'"a\\b c"');
    expect(WindowsElevation.needsQuoting('/S'), isFalse);
    expect(WindowsElevation.needsQuoting('a\tb'), isTrue);
  });

  group('ElevatedProcess', () {
    test('שורת פקודה עם אחרון גולמי', () {
      expect(
        WindowsElevation.buildCommandLine(
          const ['/S', r'/D=C:\Program Files\X'],
          rawLastArgument: true,
        ),
        r'/S /D=C:\Program Files\X',
      );
      expect(
        WindowsElevation.buildCommandLine(
            const ['/S', r'/D=C:\Program Files\X']),
        r'/S "/D=C:\Program Files\X"',
      );
    });

    test('ציטוט כמו של Dart — רווחים, מרכאות ולוכסן בסוף', () {
      expect(WindowsElevation.quoteArgument('/S'), '/S');
      expect(WindowsElevation.quoteArgument(''), '""');
      expect(
          WindowsElevation.quoteArgument(r'C:\a b\c.msi'), r'"C:\a b\c.msi"');
      expect(WindowsElevation.quoteArgument(r'C:\a b\'), r'"C:\a b\\"');
      expect(WindowsElevation.quoteArgument('a"b'), r'"a\"b"');
    });

    test('ShellExecuteEx על קובץ שאינו קיים מחזיר את קוד השגיאה, לא זורק',
        () async {
      final result = await ElevatedProcess.run(
        r'C:\no\such\dir\setup.exe',
        const ['/S'],
        elevate: false,
      );
      expect(result.exitCode, 2);
      expect('${result.stderr}', contains('ShellExecuteEx'));
    }, testOn: 'windows');

    test('סירוב ל-UAC (access denied תחת runas) הוא ביטול, ובלי runas לא', () {
      expect(shellExecuteFailureCode(5, verb: 'runas'),
          ElevatedProcess.cancelledCode);
      expect(shellExecuteFailureCode(5), 5);
      expect(shellExecuteFailureCode(2, verb: 'runas'), 2);
      expect(shellExecuteFailureCode(0, verb: 'runas'), 1);
    });

    test('בלי runas התוכנה רצה, וקוד היציאה שלה חוזר', () async {
      final result = await ElevatedProcess.run(
        'cmd.exe',
        const ['/c', 'exit 7'],
        elevate: false,
      );
      expect(result.exitCode, 7);
    }, testOn: 'windows');
  });

  group('בדיקת הרשאות מנהל של התהליך', () {
    setUp(ElevatedProcess.resetElevatedCache);
    tearDown(ElevatedProcess.resetElevatedCache);

    test('שאילתת ה-token האמיתית עונה, בלי PowerShell', () async {
      expect(await ElevatedProcess.isCurrentProcessElevated(), isA<bool>());
    }, testOn: 'windows');

    test('התשובה נשמרת, והשאילתה רצה פעם אחת גם בקריאות מקבילות', () async {
      var calls = 0;
      final gate = Completer<bool>();
      Future<bool> query() {
        calls++;
        return gate.future;
      }

      final first = ElevatedProcess.resolveElevated(query);
      final second = ElevatedProcess.resolveElevated(query);
      gate.complete(true);

      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(await ElevatedProcess.resolveElevated(query), isTrue);
      expect(calls, 1);
    });

    test('תשובה שלילית נשמרת כ-false', () async {
      var calls = 0;
      Future<bool> query() async {
        calls++;
        return false;
      }

      expect(await ElevatedProcess.resolveElevated(query), isFalse);
      expect(await ElevatedProcess.resolveElevated(query), isFalse);
      expect(calls, 1);
    });

    test('חריגה בהרצה מחזירה false ונשמרת', () async {
      var calls = 0;
      Future<bool> query() async {
        calls++;
        throw const OSError('token', 5);
      }

      expect(await ElevatedProcess.resolveElevated(query), isFalse);
      expect(await ElevatedProcess.resolveElevated(query), isFalse);
      expect(calls, 1);
    });

    test('שאילתה תקועה — false אחרי ה-timeout, ולא נשמר', () async {
      var calls = 0;
      final answers = [Completer<bool>().future, Future.value(true)];
      Future<bool> query() => answers[calls++];

      expect(
        await ElevatedProcess.resolveElevated(
          query,
          timeout: const Duration(milliseconds: 20),
        ),
        isFalse,
      );
      expect(
        await ElevatedProcess.resolveElevated(
          query,
          timeout: const Duration(milliseconds: 20),
        ),
        isTrue,
      );
      expect(calls, 2);
    });
  });
}
