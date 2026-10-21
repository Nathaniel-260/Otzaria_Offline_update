import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/sandbox.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('caps_'));
  tearDown(() => temp.deleteSync(recursive: true));

  void write(String text) =>
      File(p.join(temp.path, OtzariaCapabilities.fileName))
          .writeAsStringSync(text);

  test('אין קובץ או קובץ פגום — לא ידוע', () async {
    expect(await OtzariaCapabilities.read(temp.path), isNull);
    write('{not json');
    expect(await OtzariaCapabilities.read(temp.path), isNull);
    write('[1]');
    expect(await OtzariaCapabilities.read(temp.path), isNull);
  });

  test('השדות נקראים, גם אחרי BOM; מפתח חסר או מסוג אחר הוא לא ידוע', () async {
    write('\uFEFF{"formatVersion":1,"reportsQueueFormat":1,'
        '"pluginInstallResults":"1","appVersion":"0.9.98"}');

    final caps = await OtzariaCapabilities.read(temp.path);

    expect(caps?.reportsQueueFormat, 1);
    expect(caps?.pluginInstallResults, isNull);
  });

  test('C1 של exe אחר אינו קובע את הסכמה הקריאה', () {
    final exe = p.join(temp.path, 'otzaria.exe');
    int? resolve(String? exePath) =>
        OtzariaCapabilities.resolveReadableDbSchema(
          capabilities: OtzariaCapabilities(
            appVersion: '0.9.98',
            readableDbSchemaVersion: 6,
            exePath: exePath,
          ),
          launchPath: exe,
        );

    expect(resolve(exe), 6);
    expect(resolve(null), 6);
    expect(resolve(p.join(temp.path, 'other', 'otzaria.exe')), isNull);
  });

  test('משפחות הוקטורים נקראות בזהירות', () async {
    write('{"semanticVectorFamilies":["vectors-windows",3,"","vectors"]}');
    final caps = await OtzariaCapabilities.read(temp.path);
    expect(caps?.semanticVectorFamilies, ['vectors-windows', 'vectors']);
    expect(
      OtzariaCapabilities.supportsWindowsVectors(capabilities: caps),
      isTrue,
    );

    write('{"semanticVectorFamilies":"vectors-windows"}');
    final wrongType = await OtzariaCapabilities.read(temp.path);
    expect(wrongType?.semanticVectorFamilies, isNull);
    expect(
      OtzariaCapabilities.supportsWindowsVectors(capabilities: wrongType),
      isFalse,
    );

    write('{"semanticVectorFamilies":["vectors"]}');
    expect(
      OtzariaCapabilities.supportsWindowsVectors(
        capabilities: await OtzariaCapabilities.read(temp.path),
      ),
      isFalse,
    );
    expect(OtzariaCapabilities.supportsWindowsVectors(), isFalse);
  });

  test('תמיכה בחלונות מ-exe אחר אינה נחשבת', () {
    final exe = p.join(temp.path, 'otzaria.exe');
    bool supports(String? exePath) =>
        OtzariaCapabilities.supportsWindowsVectors(
          capabilities: OtzariaCapabilities(
            exePath: exePath,
            semanticVectorFamilies: const ['vectors-windows', 'vectors'],
          ),
          launchPath: exe,
        );

    expect(supports(exe), isTrue);
    expect(supports(null), isTrue);
    expect(supports(p.join(temp.path, 'other', 'otzaria.exe')), isFalse);
  });

  test('אוצריא ישנה מכותבת הקובץ אינה תומכת בחלונות', () {
    bool supports(String? installed) =>
        OtzariaCapabilities.supportsWindowsVectors(
          capabilities: const OtzariaCapabilities(
            appVersion: '0.9.99',
            semanticVectorFamilies: ['vectors-windows', 'vectors'],
          ),
          installedVersion: installed,
        );

    expect(supports('0.9.98+900'), isFalse);
    expect(supports('0.9.99+901'), isTrue);
    expect(supports('1.0.0'), isTrue);
    expect(supports(null), isTrue);
  });

  test('מחרוזת ריקה וסכמה לא חיובית הן לא ידוע', () async {
    write('{"appVersion":"","exePath":"","readableDbSchemaVersion":0}');

    final caps = await OtzariaCapabilities.read(temp.path);

    expect(caps?.appVersion, isNull);
    expect(caps?.exePath, isNull);
    expect(caps?.readableDbSchemaVersion, isNull);
  });

  test('בבדיקות, קריאה משורש הנתונים האמיתי של אוצריא נכשלת', () async {
    sandboxRealDataRoot();
    final real =
        Platform.environment['APPDATA'] ?? Platform.environment['HOME'];
    final root = Platform.environment['APPDATA'] != null
        ? p.join(real!, 'otzaria')
        : p.join(real!, 'Library', 'Application Support', 'otzaria');

    await expectLater(
      OtzariaCapabilities.read(root),
      throwsA(isA<AssertionError>()),
    );
    expect(
        OtzariaManager.defaultEnvironment()['APPDATA'],
        isNot(
          Platform.environment['APPDATA'],
        ));
  });
}
