// החלטת המשתמש: אין "התקנת גרסה ישנה יותר" בשום מקום. כשהמחשב מעודכן יותר
// מהכונן — מצב רגוע בלי פעולה (ראו screens_test). כאן: שום שריד בקוד ובמלל.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final appLib = Directory('lib');
  final l10nLib = Directory(p.join('..', 'otzaria_l10n', 'lib'));

  Iterable<File> dartFiles(Directory dir) => dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('אין מסלול התקנה של גרסה ישנה — לא בקוד ולא במחרוזות', () {
    final files = [...dartFiles(appLib), ...dartFiles(l10nLib)];
    expect(files, isNotEmpty);
    final forbidden = RegExp(
      r'installOlder|_Install\.older|נסיגת גרסה|Install the folder version',
    );
    final offenders = [
      for (final file in files)
        if (forbidden.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty);
  });
}
