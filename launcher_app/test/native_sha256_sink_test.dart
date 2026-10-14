import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/native_sha256_sink.dart';

void main() {
  test('אותו digest כמו package:crypto, גם בהזרמה בחלקים', () {
    final random = Random(7);
    final data = Uint8List.fromList(
        List.generate(3 * 1024 * 1024 + 17, (_) => random.nextInt(256)));
    late Digest digest;
    final sink = NativeSha256Sink(
        ChunkedConversionSink<Digest>.withCallback((d) => digest = d.single));
    for (var i = 0; i < data.length; i += 65536) {
      sink.add(data.sublist(i, min(i + 65536, data.length)));
    }
    sink.close();
    sink.close();

    expect(digest, sha256.convert(data));
  });
}
