import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('data-root-'));
  tearDown(() => temp.deleteSync(recursive: true));

  final os = Platform.operatingSystem;

  test('רק קובץ הסימון הופך התקנה לניידת', () {
    final exe = p.join(temp.path, 'otzaria.exe');
    Directory(p.join(temp.path, 'otzaria_data')).createSync();
    expect(OtzariaDataRoot.portableRoot(exe, operatingSystem: os), isNull);

    File(p.join(temp.path, OtzariaDataRoot.portableMarkerFileName))
        .writeAsStringSync('');
    expect(
      OtzariaDataRoot.resolve(exe, operatingSystem: os, environment: const {}),
      p.join(temp.path, 'otzaria_data'),
    );
  });

  test('חבילת .app — הסימון ב-Contents/MacOS', () {
    final bundle = p.join(temp.path, 'אוצריא.app');
    final exeDir = p.join(bundle, 'Contents', 'MacOS');
    Directory(exeDir).createSync(recursive: true);
    File(p.join(exeDir, OtzariaDataRoot.portableMarkerFileName))
        .writeAsStringSync('');

    expect(
      OtzariaDataRoot.portableRoot(bundle, operatingSystem: os),
      p.join(exeDir, 'otzaria_data'),
    );
  });

  test('שורש המשתמש לפי הפלטפורמה', () {
    expect(
      OtzariaDataRoot.userRoot(
        operatingSystem: 'windows',
        environment: const {'APPDATA': r'C:\Users\u\AppData\Roaming'},
      ),
      r'C:\Users\u\AppData\Roaming\otzaria',
    );
    expect(
      OtzariaDataRoot.userRoot(
        operatingSystem: 'macos',
        environment: const {'HOME': '/Users/u'},
      ),
      '/Users/u/Library/Application Support/otzaria',
    );
    expect(
      OtzariaDataRoot.userRoot(
        operatingSystem: 'windows',
        environment: const {},
      ),
      isNull,
    );
  });
}
