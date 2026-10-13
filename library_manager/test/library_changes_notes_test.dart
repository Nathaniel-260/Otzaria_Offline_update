import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

LibraryRelease _release(
  String tag, {
  int? notesSize,
  bool prerelease = false,
  bool draft = false,
}) => LibraryRelease(
  tag: tag,
  isPrerelease: prerelease,
  isDraft: draft,
  publishedAt: null,
  assets: [
    if (notesSize != null)
      ReleaseAsset(
        name: LibraryChangesNotes.assetName,
        downloadUrl: 'https://dl/$tag/${LibraryChangesNotes.assetName}',
        size: notesSize,
      ),
  ],
);

void main() {
  late Directory tempDir;
  late String mirrorDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library-changes-');
    mirrorDir = p.join(tempDir.path, 'mirror', 'library');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  File mirrorNote(String tag) =>
      File(p.join(mirrorDir, LibraryChangesNotes.mirrorFolderName, '$tag.md'));

  group('coveredReleases', () {
    test('the version range of the mirrored releases, newest first', () {
      final covered = LibraryChangesNotes.coveredReleases(
        online: [
          for (var v = 20; v <= 36; v++) _release('v$v-2026'),
          _release('v31-pre', prerelease: true),
          _release('v32-draft', draft: true),
          _release('bad tag'),
        ],
        mirrored: [_release('v30-2026'), _release('v33-2026')],
        allowPrerelease: false,
      );

      expect(covered.map((r) => r.tag), [
        'v33-2026',
        'v32-2026',
        'v31-2026',
        'v30-2026',
      ]);
    });

    test('prereleases count only on the prerelease channel', () {
      final covered = LibraryChangesNotes.coveredReleases(
        online: [_release('v31-pre', prerelease: true)],
        mirrored: [_release('v31-pre')],
        allowPrerelease: true,
      );

      expect(covered.single.tag, 'v31-pre');
    });

    test('keeps at most the ten newest', () {
      final covered = LibraryChangesNotes.coveredReleases(
        online: [for (var v = 1; v <= 30; v++) _release('v$v')],
        mirrored: [_release('v1'), _release('v30')],
        allowPrerelease: false,
      );

      expect(covered, hasLength(LibraryChangesNotes.maxNotes));
      expect(covered.first.tag, 'v30');
      expect(covered.last.tag, 'v21');
    });

    test('an empty mirror covers nothing', () {
      expect(
        LibraryChangesNotes.coveredReleases(
          online: [_release('v1')],
          mirrored: const [],
          allowPrerelease: false,
        ),
        isEmpty,
      );
    });
  });

  group('syncMirror', () {
    late List<Uri> requests;

    MockClient client(Map<String, http.Response> byTag) => MockClient((req) {
      requests.add(req.url);
      return Future.value(
        byTag[req.url.pathSegments.first] ?? http.Response('', 404),
      );
    });

    setUp(() => requests = []);

    test('saves the file and treats 404 as "not yet"', () async {
      final warnings = <String>[];
      final saved = await LibraryChangesNotes.syncMirror(
        mirrorDir: mirrorDir,
        covered: [_release('v33', notesSize: 7), _release('v32', notesSize: 7)],
        client: client({
          'v33': http.Response.bytes(utf8.encode('# שלום'), 200),
        }),
        onWarning: (tag, _) => warnings.add(tag),
      );

      expect(saved, 1);
      expect(mirrorNote('v33').readAsStringSync(), '# שלום');
      expect(mirrorNote('v32').existsSync(), isFalse);
      expect(warnings, isEmpty);
    });

    test('a release without the asset is not requested at all', () async {
      await LibraryChangesNotes.syncMirror(
        mirrorDir: mirrorDir,
        covered: [_release('v32')],
        client: client(const {}),
      );

      expect(requests, isEmpty);
    });

    test('a server error is a warning, never a failure', () async {
      final warnings = <String>[];
      final saved = await LibraryChangesNotes.syncMirror(
        mirrorDir: mirrorDir,
        covered: [_release('v33', notesSize: 3), _release('v32', notesSize: 3)],
        client: client({
          'v33': http.Response('', 500),
          'v32': http.Response('abc', 200),
        }),
        onWarning: (tag, _) => warnings.add(tag),
      );

      expect(saved, 1);
      expect(warnings, ['v33']);
      expect(mirrorNote('v32').existsSync(), isTrue);
    });

    test('a file over the size cap is skipped with a warning', () async {
      final warnings = <String>[];
      const big = LibraryChangesNotes.maxBytes + 1;
      await LibraryChangesNotes.syncMirror(
        mirrorDir: mirrorDir,
        covered: [
          _release('v33', notesSize: big),
          _release('v32', notesSize: 1),
        ],
        client: client({'v32': http.Response.bytes(List.filled(big, 65), 200)}),
        onWarning: (tag, _) => warnings.add(tag),
      );

      expect(warnings, ['v33', 'v32']);
      expect(requests.map((u) => u.pathSegments.first), ['v32']);
      expect(mirrorNote('v33').existsSync(), isFalse);
      expect(mirrorNote('v32').existsSync(), isFalse);
    });

    test('a file already on the drive is not downloaded again', () async {
      mirrorNote('v33')
        ..createSync(recursive: true)
        ..writeAsStringSync('abc');

      await LibraryChangesNotes.syncMirror(
        mirrorDir: mirrorDir,
        covered: [_release('v33', notesSize: 3)],
        client: client(const {}),
      );

      expect(requests, isEmpty);
      expect(mirrorNote('v33').readAsStringSync(), 'abc');
    });

    test('notes of releases the mirror no longer covers are deleted', () async {
      for (final tag in ['v20', 'v33']) {
        mirrorNote(tag)
          ..createSync(recursive: true)
          ..writeAsStringSync(tag);
      }

      await LibraryChangesNotes.syncMirror(
        mirrorDir: mirrorDir,
        covered: [_release('v33')],
        client: client(const {}),
      );

      expect(mirrorNote('v20').existsSync(), isFalse);
      expect(mirrorNote('v33').existsSync(), isTrue);
    });
  });

  group('inMirror', () {
    test(
      'only (from, to], newest first, without temp or unsafe names',
      () async {
        for (final name in [
          'v29-1.md',
          'v30-1.md',
          'v31-1.md',
          'v32-1.md',
          'v32-2.md',
          'v33-1.md',
          'v31-1.md.123.tmp',
          '-v31.md',
        ]) {
          File(p.join(mirrorDir, LibraryChangesNotes.mirrorFolderName, name))
            ..createSync(recursive: true)
            ..writeAsStringSync(name);
        }

        final notes = await LibraryChangesNotes.inMirror(
          mirrorDir,
          fromVersion: 30,
          toVersion: 32,
        );

        expect(notes.map((n) => n.releaseTag), ['v32-2', 'v32-1', 'v31-1']);
      },
    );

    test('a mirror without notes yields nothing', () async {
      expect(
        await LibraryChangesNotes.inMirror(
          mirrorDir,
          fromVersion: 0,
          toVersion: 99,
        ),
        isEmpty,
      );
    });
  });

  group('handOff', () {
    late String dataRoot;

    setUp(() => dataRoot = p.join(tempDir.path, 'otzaria_data'));

    Directory folder(String name) => Directory(p.join(dataRoot, name));

    Future<LibraryChangesNote> note(String tag, String text) async {
      final file = mirrorNote(tag)..createSync(recursive: true);
      await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
      return LibraryChangesNote(releaseTag: tag, path: file.path);
    }

    test('writes <tag>.md as UTF-8 without BOM and no temp files', () async {
      final written = await LibraryChangesNotes.handOff(
        dataRoot: dataRoot,
        notes: [await note('v33-1', '# ספרים')],
      );

      expect(written, ['v33-1']);
      final pending = folder(LibraryChangesNotes.pendingFolderName);
      expect(pending.listSync().map((e) => p.basename(e.path)), ['v33-1.md']);
      expect(
        File(p.join(pending.path, 'v33-1.md')).readAsBytesSync(),
        utf8.encode('# ספרים'),
      );
    });

    test(
      'a note already pending or already seen is not written again',
      () async {
        File(
            p.join(
              folder(LibraryChangesNotes.pendingFolderName).path,
              'v32.md',
            ),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('otzaria');
        File(p.join(folder(LibraryChangesNotes.seenFolderName).path, 'v31.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('seen');

        final written = await LibraryChangesNotes.handOff(
          dataRoot: dataRoot,
          notes: [
            await note('v32', 'mine'),
            await note('v31', 'mine'),
            await note('v30', 'mine'),
          ],
        );

        expect(written, ['v30']);
        expect(
          File(
            p.join(
              folder(LibraryChangesNotes.pendingFolderName).path,
              'v32.md',
            ),
          ).readAsStringSync(),
          'otzaria',
        );
        expect(
          File(
            p.join(
              folder(LibraryChangesNotes.pendingFolderName).path,
              'v31.md',
            ),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('keeps only the ten newest pending files, by version', () async {
      final pending = folder(LibraryChangesNotes.pendingFolderName);
      for (var v = 1; v <= 9; v++) {
        File(p.join(pending.path, 'v$v.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('old');
      }

      await LibraryChangesNotes.handOff(
        dataRoot: dataRoot,
        notes: [await note('v11', 'new'), await note('v10', 'new')],
      );

      final names = pending.listSync().map((e) => p.basename(e.path)).toSet();
      expect(names, hasLength(LibraryChangesNotes.maxNotes));
      expect(names, isNot(contains('v1.md')));
      expect(names, containsAll(['v2.md', 'v10.md', 'v11.md']));
    });

    test(
      'a pending file that cannot be deleted does not fail the hand-off',
      () async {
        final pending = folder(LibraryChangesNotes.pendingFolderName);
        for (var v = 1; v <= 10; v++) {
          File(p.join(pending.path, 'v$v.md'))
            ..createSync(recursive: true)
            ..writeAsStringSync('old');
        }
        final held = File(p.join(pending.path, 'v1.md')).openSync();
        addTearDown(held.closeSync);

        final written = await LibraryChangesNotes.handOff(
          dataRoot: dataRoot,
          notes: [await note('v11', 'new')],
        );

        expect(written, ['v11']);
      },
      skip: !Platform.isWindows
          ? 'an open file blocks deletion only on Windows'
          : false,
    );

    test('an empty note and an unsafe tag are skipped', () async {
      final written = await LibraryChangesNotes.handOff(
        dataRoot: dataRoot,
        notes: [
          await note('v5', '  \n'),
          LibraryChangesNote(releaseTag: '../x', path: mirrorNote('v5').path),
        ],
      );

      expect(written, isEmpty);
      expect(
        folder(LibraryChangesNotes.pendingFolderName).existsSync(),
        isFalse,
      );
    });
  });
}
