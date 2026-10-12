import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
}
