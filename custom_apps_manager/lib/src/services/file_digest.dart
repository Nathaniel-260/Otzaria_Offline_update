import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// ה-sha256 של קובץ, ב-hex קטן — אותו פורמט שגיטהאב מפרסם ב-`digest`.
/// קורא בזרם וב-isolate: קובץ התקנה של מאות MB חסם את ה-UI.
Future<String> sha256OfFile(String path) => Isolate.run(
    () async => (await sha256.bind(File(path).openRead()).first).toString());

class _DigestCapture implements Sink<Digest> {
  late final Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

const copyFlushThreshold = 4 << 20;

Future<String> copyFileWithSha256(String from, String to) => Isolate.run(
    () => copyStreamWithSha256(File(from).openRead(), File(to).openWrite()));

Future<String> copyStreamWithSha256(
  Stream<List<int>> source,
  IOSink out, {
  int flushEvery = copyFlushThreshold,
}) async {
  final capture = _DigestCapture();
  final hasher = sha256.startChunkedConversion(capture);
  var succeeded = false;
  try {
    var buffered = 0;
    await for (final chunk in source) {
      hasher.add(chunk);
      out.add(chunk);
      buffered += chunk.length;
      if (buffered >= flushEvery) {
        await out.flush();
        buffered = 0;
      }
    }
    hasher.close();
    succeeded = true;
  } finally {
    try {
      await out.close();
    } catch (_) {
      if (succeeded) rethrow;
    }
  }
  return capture.value.toString();
}
