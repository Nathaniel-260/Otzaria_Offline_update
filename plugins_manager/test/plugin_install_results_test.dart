import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  void write(List<Object> lines) =>
      File(p.join(temp.path, PluginInstallResults.fileName)).writeAsStringSync(
        '${lines.map((l) => l is String ? l : jsonEncode(l)).join('\n')}\n',
      );

  Map<String, Object?> entry(String path, String outcome, DateTime at) => {
        'path': path,
        'pluginId': 'x',
        'version': '1.0.0',
        'outcome': outcome,
        'message': null,
        'at': at.toUtc().toIso8601String(),
      };

  test('אין קובץ — אין תוצאות', () async {
    expect(await PluginInstallResults.read(temp.path), isEmpty);
  });

  test('שורות פגומות מדולגות, והתוצאה האחרונה לנתיב אחרי המסירה נבחרת',
      () async {
    final handoff = DateTime.utc(2026, 10, 12, 10);
    final path = p.join(temp.path, 'a.otzplugin');
    write([
      entry(path, 'failed', handoff.subtract(const Duration(minutes: 5))),
      '{not json',
      {'path': path},
      entry(p.join(temp.path, 'other.otzplugin'), 'installed', handoff),
      entry(path, 'cancelled', handoff.add(const Duration(seconds: 3))),
      entry(path, 'installed', handoff.add(const Duration(seconds: 9))),
    ]);

    final reports = await PluginInstallResults.read(temp.path);
    final latest = PluginInstallResults.latestFor(reports, path, handoff);

    expect(reports, hasLength(4));
    expect(latest?.outcome, 'installed');
    expect(latest?.succeeded, isTrue);
  });

  test('תוצאה ממסירה קודמת של אותו נתיב אינה נחשבת', () async {
    final handoff = DateTime.utc(2026, 10, 12, 10);
    final path = p.join(temp.path, 'a.otzplugin');
    write([
      entry(path, 'cancelled', handoff.subtract(const Duration(minutes: 1)))
    ]);

    final reports = await PluginInstallResults.read(temp.path);

    expect(PluginInstallResults.latestFor(reports, path, handoff), isNull);
  });
}
