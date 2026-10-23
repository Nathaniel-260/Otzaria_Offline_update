import 'dart:io';

import 'package:test/test.dart';

/// גדלים במלל העברי באותו פורמט כמו `units`: מספר ויחידה לטינית בתוך
/// LRI…PDI ועם רווח קשיח — לא "כ-1.5GB" ולא "2 ג׳יגה".
void main() {
  test('אין גודל קשיח מחוץ לבידוד בעברית', () {
    final source = File('lib/src/strings_he.dart').readAsStringSync();
    final outsideIsolates = source.replaceAll(RegExp(r'\\u2066.*?\\u2069'), '');
    final bare = RegExp(r"(?<![A-Za-z])[GMK]B\b|ג[׳']יגה|ג\\'יגה");
    final hits = [
      for (final line in outsideIsolates.split('\n'))
        if (bare.hasMatch(line)) line.trim(),
    ];
    expect(hits, isEmpty);
  });
}
