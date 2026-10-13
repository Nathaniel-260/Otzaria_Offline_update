import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/exe_icon_extractor.dart';
import 'package:path/path.dart' as p;

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

void main() {
  test('PNG שמקודד נפתח במפענח של Flutter, באותם מידות ופיקסלים', () async {
    final rgba = Uint8List.fromList([
      255, 0, 0, 255, 0, 255, 0, 128, //
      0, 0, 255, 0, 10, 20, 30, 40,
    ]);
    final image = await _decode(encodeRgbaPng(2, 2, rgba));
    expect(image.width, 2);
    expect(image.height, 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes!.buffer.asUint8List()[0], 255);
    expect(bytes.buffer.asUint8List()[3], 255);
  });

  test('BGRA בלי אלפא מקבל שקיפות ממסכת ה-AND', () {
    final bgra = Uint8List.fromList([1, 2, 3, 0, 4, 5, 6, 0]);
    final mask = Uint8List.fromList([0, 0, 0, 0, 255, 255, 255, 0]);
    expect(bgraToRgba(bgra, mask), [3, 2, 1, 255, 6, 5, 4, 0]);
  });

  test('אייקון מונוכרום: AND=1/XOR=0 שקוף, XOR=1 לבן, השאר שחור', () {
    // שני פיקסלים, גובה 1: חצי עליון AND, חצי תחתון XOR.
    final bits = Uint8List.fromList([
      255, 255, 255, 0, 0, 0, 0, 0, // AND
      0, 0, 0, 0, 255, 255, 255, 0, // XOR
    ]);
    expect(monochromeToRgba(bits, 2, 1), [0, 0, 0, 0, 255, 255, 255, 255]);
  });

  test('BGRA עם אלפא שומר אותו ומתעלם מהמסכה', () {
    final bgra = Uint8List.fromList([1, 2, 3, 77]);
    expect(bgraToRgba(bgra, Uint8List(4)..[0] = 255), [3, 2, 1, 77]);
  });

  test('חילוץ אמיתי מקובץ מערכת, בלי PowerShell', () async {
    final temp = await Directory.systemTemp.createTemp('icon_test');
    addTearDown(() => temp.delete(recursive: true));
    final out = p.join(temp.path, 'icon.png');
    final exe = p.join(
        Platform.environment['SystemRoot'] ?? r'C:\Windows', 'explorer.exe');

    expect(writeExeIconPng(exe, out), isTrue);
    final image = await _decode(await File(out).readAsBytes());
    expect(image.width, greaterThanOrEqualTo(32));
  }, skip: !Platform.isWindows);

  test('קובץ בלי אייקון — false, ובלי קובץ פלט', () async {
    final temp = await Directory.systemTemp.createTemp('icon_test');
    addTearDown(() => temp.delete(recursive: true));
    final source = File(p.join(temp.path, 'empty.exe'))..writeAsBytesSync([]);
    final out = p.join(temp.path, 'icon.png');
    final path = await ExeIconExtractor.extract(
      source.path,
      writer: (exe, target) async => false,
    );
    expect(path, isNull);
    expect(File(out).existsSync(), isFalse);
  }, skip: !Platform.isWindows);
}
