import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/mirror_download_undo.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  late Directory temp;
  late Directory root;
  late File dest;
  late String digest;
  final bytes = List<int>.generate(32, (i) => 65 + i);
  const url = 'https://example.com/asset.zst';

  File side(String suffix) => File('${dest.path}$suffix');

  void state(int assembled) => side('.segments').writeAsStringSync(jsonEncode({
        'v': 1,
        'token': 'token',
        'url': url,
        'size': bytes.length,
        'sha256': digest,
        'etag': '"etag"',
        'bounds': [0, 8, 16, 24, 32],
        'assembled': assembled,
      }));

  void seed(String relative) {
    dest = File(p.join(root.path, relative));
    dest.parent.createSync(recursive: true);
    dest.writeAsBytesSync(bytes.sublist(0, 4));
    side('.resume').writeAsStringSync('token\n"etag"');
    for (var i = 1; i < 4; i++) {
      side('.seg-$i').writeAsBytesSync(bytes.sublist(i * 8, (i + 1) * 8));
    }
    state(1);
  }

  Future<int> finish() async {
    var downloadedBytes = 0;
    final client = MockClient((request) async {
      final match =
          RegExp(r'bytes=(\d+)-(\d+)').firstMatch(request.headers['range']!)!;
      final start = int.parse(match[1]!);
      final end = int.parse(match[2]!);
      downloadedBytes += end - start + 1;
      return http.Response.bytes(bytes.sublist(start, end + 1), 206, headers: {
        'content-range': 'bytes $start-$end/${bytes.length}',
        'etag': '"etag"',
      });
    });
    final downloader = PatchDownloader(
      httpClient: client,
      decompress: (_) async => null,
      segmentThresholdBytes: 1,
    );
    try {
      await downloader.downloadToFile(
        url: url,
        destPath: dest.path,
        expectedSize: bytes.length,
        expectedSha256: digest,
        resumeToken: 'token',
      );
      expect(dest.readAsBytesSync(), bytes);
      return downloadedBytes;
    } finally {
      downloader.dispose();
      client.close();
    }
  }

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('mirror_segment_undo');
    await AppLogger.init(temp.path);
    root = Directory(p.join(temp.path, 'mirror'))..createSync();
    digest = sha256.convert(bytes).toString();
  });

  tearDown(() async {
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    temp.deleteSync(recursive: true);
  });

  for (final relative in [
    'library/assets/v7/seforim-schema7.db.zst',
    'companions/catalog.pb.zst',
    'companions/semantic/model-v1/model.onnx',
  ]) {
    test('completed assembly retains earlier ranges: $relative', () async {
      seed(relative);
      final manifest = File(p.join(root.path, 'releases.json'))
        ..writeAsStringSync('{"releases":["v6"]}');
      final undo = await MirrorDownloadUndo.capture([root.path]);
      expect(await finish(), 4);
      final verified = side('.resume').readAsStringSync();
      final newAsset = File(p.join(root.path, 'new', 'asset'))
        ..parent.createSync()
        ..writeAsStringSync('new');
      manifest.writeAsStringSync('{"releases":["v6","v7"]}');

      await undo.revert();

      expect(dest.readAsBytesSync(), bytes);
      expect(side('.resume').readAsStringSync(), verified);
      expect(side('.segments').existsSync(), isFalse);
      expect(newAsset.existsSync(), isFalse);
      expect(newAsset.parent.existsSync(), isFalse);
      expect(manifest.readAsStringSync(), '{"releases":["v6"]}');
      expect(await finish(), 0,
          reason: 'A retained complete asset is reusable');
    });
  }

  test('partial assembly retains its current state and resumes without loss',
      () async {
    seed('library/assets/v7/seforim.db.zst');
    final undo = await MirrorDownloadUndo.capture([root.path]);
    // The assembler flushed segment 1, advanced the journal, then deleted it.
    dest.writeAsBytesSync(bytes.sublist(0, 16));
    side('.seg-1').deleteSync();
    state(2);
    final currentState = side('.segments').readAsStringSync();

    await undo.revert();

    expect(dest.readAsBytesSync(), bytes.sublist(0, 16));
    expect(side('.segments').readAsStringSync(), currentState);
    expect(side('.seg-1').existsSync(), isFalse);
    expect(side('.seg-2').readAsBytesSync(), bytes.sublist(16, 24));
    expect(side('.seg-3').readAsBytesSync(), bytes.sublist(24, 32));
    expect(await finish(), 0);
  });

  test('before assembly, new bytes are removed and earlier ranges still resume',
      () async {
    seed('asset.zst');
    final undo = await MirrorDownloadUndo.capture([root.path]);
    dest.writeAsBytesSync(bytes.sublist(0, 8));
    side('.resume').writeAsStringSync('token\n"etag"\nnew-mark');

    await undo.revert();

    expect(dest.readAsBytesSync(), bytes.sublist(0, 4));
    expect(side('.resume').readAsStringSync(), 'token\n"etag"');
    expect(await finish(), 4);
  });

  for (final replacement in ['new identity', 'deleted sidecars']) {
    test('unverifiable consumed ranges keep a consistent root: $replacement',
        () async {
      seed('asset.zst');
      final manifest = File(p.join(root.path, 'releases.json'))
        ..writeAsStringSync('{"releases":["v6"]}');
      final undo = await MirrorDownloadUndo.capture([root.path]);
      expect(await finish(), 4);
      if (replacement == 'new identity') {
        side('.resume').writeAsStringSync('replacement\n"new-etag"');
      } else {
        side('.resume').deleteSync();
      }
      final newAsset = File(p.join(root.path, 'new-asset'))
        ..writeAsStringSync('new');
      manifest.writeAsStringSync('{"releases":["v7"]}');

      await undo.revert();

      expect(dest.readAsBytesSync(), bytes);
      expect(side('.segments').existsSync(), isFalse);
      expect(newAsset.existsSync(), isTrue);
      expect(manifest.readAsStringSync(), '{"releases":["v7"]}');
      if (replacement == 'new identity') {
        expect(side('.resume').readAsStringSync(), 'replacement\n"new-etag"');
      } else {
        expect(side('.resume').existsSync(), isFalse);
      }
    });
  }
}
