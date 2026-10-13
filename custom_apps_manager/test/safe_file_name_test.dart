import 'package:custom_apps_manager/src/models/safe_file_name.dart';
import 'package:test/test.dart';

void main() {
  test('שמות התקני Windows נדחים, גם עם סיומת ובכל רישיות', () {
    for (final name in [
      'CON',
      'nul.txt',
      'Aux.png',
      'PRN',
      'com1.exe',
      'LPT9.msi',
    ]) {
      expect(safeFileName(name), isNull, reason: name);
    }
    expect(safeFileName('console.exe'), 'console.exe');
    expect(safeFileName('COM10.exe'), 'COM10.exe');
  });

  test('תווים אסורים ותווי בקרה נדחים', () {
    for (final name in [
      'a<b.exe',
      'a>b',
      'a|b',
      'a?b',
      'a*b',
      'a"b',
      'a\tb',
      'a\u0001b',
      'a/b',
      r'a\b',
      'a:b',
    ]) {
      expect(safeFileName(name), isNull, reason: name);
    }
    expect(safeFileName('הגדרות-1.4.exe'), 'הגדרות-1.4.exe');
  });
}
