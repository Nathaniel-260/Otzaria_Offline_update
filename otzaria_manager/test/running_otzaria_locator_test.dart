import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:win32/win32.dart' show CloseHandle;

/// הזיהוי לפי התהליך הרץ הוא המקור **הסמכותי** למיקום ההתקנה: הוא אינו
/// ניחוש של תיקייה מוכרת אלא הקובץ שהמשתמש באמת מפעיל. הבדיקות כאן
/// מכסות את הפירוק הטהור בשתי הפלטפורמות, ובווינדוס גם את מסלול ה-FFI
/// עצמו — מול תהליך הבדיקה הזה, שהנתיב שלו ידוע מראש.
void main() {
  group('selectMacExecutablePath', () {
    const names = ['אוצריא', 'otzaria'];

    test('מחזיר את הנתיב המלא של הבינארי שבתוך החבילה', () {
      const psOutput = [
        '/usr/libexec/secinitd',
        '/Applications/אוצריא.app/Contents/MacOS/אוצריא',
      ];

      expect(
        RunningOtzariaLocator.selectMacExecutablePath(psOutput, names),
        '/Applications/אוצריא.app/Contents/MacOS/אוצריא',
      );
    });

    // הלאנצ'ר עצמו יושב בנתיב שמכיל את המילה otzaria; התאמה על תת-מחרוזת
    // הייתה מזהה אותו כאוצריא ומדווחת על תיקיית ההתקנה של עצמנו.
    test("לא נתפס על הלאנצ'ר, שנתיבו מכיל otzaria", () {
      const psOutput = [
        '/Volumes/USB/Otzaria Launcher.app/Contents/MacOS/Otzaria Launcher',
        '/Users/x/otzaria_update/launcher_app',
      ];

      expect(
        RunningOtzariaLocator.selectMacExecutablePath(psOutput, names),
        isNull,
      );
    });

    // חגורה שנייה מעל "ההתאמה היא על השם במלואו": גם אם הלאנצ'ר ייקרא יום
    // אחד בדיוק כמו אוצריא, התהליך שרץ מקובץ ההרצה שלנו נפסל.
    test('תהליך שרץ מקובץ ההרצה שלנו עצמו נפסל', () {
      const self = '/Volumes/USB/Otzaria Launcher.app/Contents/MacOS/otzaria';

      expect(
        RunningOtzariaLocator.selectMacExecutablePath(
          const [self, '/Applications/אוצריא.app/Contents/MacOS/אוצריא'],
          names,
          selfExecutable: self,
        ),
        '/Applications/אוצריא.app/Contents/MacOS/אוצריא',
      );
      expect(
        RunningOtzariaLocator.selectMacExecutablePath(
          const [self],
          names,
          selfExecutable: self,
        ),
        isNull,
      );
    });

    test('שורות ריקות מדולגות', () {
      expect(
        RunningOtzariaLocator.selectMacExecutablePath(
          ['', '   ', '/Applications/Safari.app/Contents/MacOS/Safari'],
          names,
        ),
        isNull,
      );
    });
  });

  group('שמות התהליך', () {
    test('ווינדוס: שם הקובץ המדויק בלבד', () {
      expect(RunningOtzariaLocator.processNamesFor('windows'), ['otzaria.exe']);
    });

    test('macOS: השם בעברית ראשון, האנגלי כגיבוי', () {
      expect(RunningOtzariaLocator.processNamesFor('macos'),
          ['אוצריא', 'otzaria']);
    });

    test('אף שם אינו נתיב — אחרת ההתאמה הייתה תלויה במיקום ההתקנה', () {
      for (final os in const ['windows', 'macos', 'linux']) {
        for (final name in RunningOtzariaLocator.processNamesFor(os)) {
          expect(name, isNot(contains('/')));
          expect(name, isNot(contains(r'\')));
        }
      }
    });
  });

  // מסלול ה-FFI האמיתי, מול תהליך שהנתיב שלו ידוע: התהליך שמריץ את
  // הבדיקה. זו הבדיקה היחידה שמאמתת ש-OpenProcess/QueryFullProcessImageName
  // אכן מקומפלים ורצים נכון.
  group('Windows בלבד — מול תהליך אמיתי', () {
    // לא מושווה ל-`Platform.resolvedExecutable`: הוא מדווח את המפעיל
    // (`dart.exe`) ואילו התהליך שרץ בפועל הוא `dartvm.exe`. זה בדיוק
    // ההבדל שבגללו שואלים את מערכת ההפעלה ולא את התהליך על עצמו.
    test('windowsImagePathOfPid מחזיר נתיב אמיתי של התהליך הנוכחי', () {
      final path = RunningOtzariaLocator.windowsImagePathOfPid(pid);

      expect(path, isNotNull);
      expect(p.isAbsolute(path!), isTrue);
      expect(File(path).existsSync(), isTrue);
      expect(
        p.dirname(path),
        equalsIgnoringCase(p.dirname(Platform.resolvedExecutable)),
      );
    });

    test('windowsPidsOf מוצא את התהליך הנוכחי לפי שמו', () async {
      final imageName = p.basename(
        RunningOtzariaLocator.windowsImagePathOfPid(pid)!,
      );

      expect(
          await RunningOtzariaLocator.windowsPidsOf(imageName), contains(pid));
    });

    test('windowsRunningImagePaths כולל את התהליך הנוכחי', () {
      final self = RunningOtzariaLocator.windowsImagePathOfPid(pid)!;

      expect(
        RunningOtzariaLocator.windowsRunningImagePaths()
            .map((path) => path.toLowerCase()),
        contains(self.toLowerCase()),
      );
    });

    test('שם שאינו קיים מחזיר רשימה ריקה', () async {
      expect(
        await RunningOtzariaLocator.windowsPidsOf('no-such-process-xyz.exe'),
        isEmpty,
      );
    });

    test('PID שאינו קיים מחזיר null במקום לקרוס', () {
      // 0 הוא System Idle Process — OpenProcess עליו נכשל תמיד.
      expect(RunningOtzariaLocator.windowsImagePathOfPid(0), isNull);
    });

    // המסלול המלא מקצה לקצה: תהליך אמיתי בשם otzaria.exe, במיקום שאינו
    // אף אחת מתיקיות ברירת המחדל — בדיוק המקרה שהמנגנון נבנה בשבילו.
    test('מוצא נתיב של otzaria.exe אמיתי שרץ מתיקייה שרירותית', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-locator-test-');
      final fakeOtzaria = p.join(tempDir.path, 'otzaria.exe');
      final process = await _startLongLivedCopyOfPing(fakeOtzaria);
      if (process == null) {
        markTestSkipped('לא ניתן להריץ תהליך עזר בסביבה הזו');
        return;
      }
      addTearDown(() async {
        process.kill();
        // ההרג אינו מיידי; בלי ההמתנה המחיקה נכשלת על קובץ נעול.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        } catch (_) {
          // עדיין נעול — לא מפילים את הבדיקה על ניקוי.
        }
      });

      // נבדק על **כל** ה-otzaria.exe שרצים, ולא על התוצאה היחידה של
      // findLaunchPath: במכונה שאוצריא אמיתית פתוחה בה, היא עלולה להיבחר.
      final paths = <String?>[];
      for (var i = 0; i < 20 && !paths.contains(fakeOtzaria); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        paths
          ..clear()
          ..addAll([
            for (final id
                in await RunningOtzariaLocator.windowsPidsOf('otzaria.exe'))
              RunningOtzariaLocator.windowsImagePathOfPid(id),
          ]);
      }

      expect(paths, contains(fakeOtzaria));
      expect(await const RunningOtzariaLocator().findLaunchPath(), isNull);

      final mutexName = 'OtzariaLocatorTest-$pid';
      final mutex = _createMutex(mutexName);
      addTearDown(() => CloseHandle(mutex));
      final probe = await RunningOtzariaLocator(mutexName: mutexName).probe();
      expect(probe.isRunning, isTrue);
      expect(probe.launchPath, isNotNull);
    });

    test('המיוטקס של אוצריא הוא הסימן ל"רצה"', () async {
      final mutexName = 'OtzariaLocatorMutexTest-$pid';
      final locator = RunningOtzariaLocator(mutexName: mutexName);
      expect(
        RunningOtzariaLocator.windowsMutexState(mutexName),
        WindowsMutexState.absent,
      );
      expect((await locator.probe()).isRunning, isFalse);

      final mutex = _createMutex(mutexName);
      addTearDown(() => CloseHandle(mutex));

      expect(
        RunningOtzariaLocator.windowsMutexState(mutexName),
        WindowsMutexState.present,
      );
      expect((await locator.probe()).isRunning, isTrue);
      expect(RunningOtzariaLocator.lastProbeFailure, isNull);
    });

    test('מיוטקס שהתהליך הזה עצמו מחזיק אינו "אוצריא רצה"', () async {
      final mutexName = 'OtzariaLocatorOwnMutexTest-$pid';
      final mutex = _createMutex(mutexName);
      addTearDown(() => CloseHandle(mutex));

      final probe = await RunningOtzariaLocator(
        mutexName: mutexName,
        isMutexHeldByThisProcess: () => true,
      ).probe();

      final otzariaPids = await RunningOtzariaLocator.windowsOtzariaPids();
      expect(probe.isRunning, otzariaPids.isNotEmpty);
    });

    test('waitForExit חוזר מיד כשאין תהליך להמתין לו', () async {
      final started = DateTime.now();
      final result = await const RunningOtzariaLocator()
          .waitForExit(const Duration(seconds: 5));
      if (result == null) {
        expect(
          DateTime.now().difference(started),
          lessThan(const Duration(seconds: 4)),
        );
      }
    });
  }, skip: !Platform.isWindows);
}

/// מריץ עותק של `ping.exe` תחת [destPath] — תהליך אמיתי, ארוך-חיים ובלי
/// תלויות, שמאפשר לבדוק מול שם קובץ שאנחנו קובעים. אותה תבנית כמו
/// בבדיקות של `OtzariaProcessGuard`.
Future<Process?> _startLongLivedCopyOfPing(String destPath) async {
  try {
    final source = File(p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'System32',
      'PING.EXE',
    ));
    if (!source.existsSync()) return null;
    source.copySync(destPath);
    return await Process.start(destPath, const ['-n', '30', '127.0.0.1']);
  } catch (_) {
    return null;
  }
}

int _createMutex(String name) {
  final create = DynamicLibrary.open('kernel32.dll').lookupFunction<
      IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
      int Function(Pointer<Void>, int, Pointer<Utf16>)>('CreateMutexW');
  final namePtr = name.toNativeUtf16();
  try {
    return create(nullptr, 0, namePtr);
  } finally {
    calloc.free(namePtr);
  }
}
