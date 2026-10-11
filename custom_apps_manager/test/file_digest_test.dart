import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:custom_apps_manager/src/services/file_digest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('העתקה מחשבת את אותו hash שחישוב נפרד היה נותן', () async {
    final root = tempMirrorRoot();
    final source = p.join(root, 'source.bin');
    final bytes = List<int>.generate(500000, (i) => i % 251);
    File(source).writeAsBytesSync(bytes);
    final target = p.join(root, 'copy.bin');

    final digest = await copyFileWithSha256(source, target);

    expect(digest, sha256.convert(bytes).toString());
    expect(digest, await sha256OfFile(target));
    expect(File(target).readAsBytesSync(), bytes);
  });

  test('קובץ ריק מקבל את ה-hash של ריק', () async {
    final root = tempMirrorRoot();
    final source = writeFile(p.join(root, 'empty.bin'), '');

    final digest = await copyFileWithSha256(source, p.join(root, 'out.bin'));

    expect(digest, sha256.convert(const <int>[]).toString());
  });

  test('העתקה מרוקנת את הכתיבה כל כמה בייטים ולא מצברת בזיכרון', () async {
    final sink = _CountingSink();
    final chunks = List.generate(10, (_) => List<int>.filled(1000, 7));

    final digest = await copyStreamWithSha256(
      Stream.fromIterable(chunks),
      sink,
      flushEvery: 3000,
    );

    expect(sink.flushes, 3);
    expect(sink.closed, isTrue);
    expect(digest, sha256.convert(chunks.expand((c) => c).toList()).toString());
  });

  test('שגיאת סגירה לא מסתירה את שגיאת המקור', () async {
    final sink = _CountingSink(closeFails: true);
    final source = Stream<List<int>>.error(StateError('מקור'));

    await expectLater(
      copyStreamWithSha256(source, sink),
      throwsA(isA<StateError>()),
    );
  });
}

class _CountingSink implements IOSink {
  _CountingSink({this.closeFails = false});

  final bool closeFails;
  int flushes = 0;
  bool closed = false;

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  Future<void> flush() async => flushes++;

  @override
  Future<void> close() async {
    closed = true;
    if (closeFails) throw const FileSystemException('close');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
