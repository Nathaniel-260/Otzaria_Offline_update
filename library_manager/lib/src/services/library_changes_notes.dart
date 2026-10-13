import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'atomic_file.dart';
import 'github_fetch.dart' show githubUserAgentHeaders;

/// "מה חדש" של release אחד בספרייה — ה-`library-changes.md` שלו, כפי שנסע
/// במראה.
class LibraryChangesNote {
  const LibraryChangesNote({required this.releaseTag, required this.path});

  final String releaseTag;
  final String path;

  /// גרסת הספרייה לפי התג (`v32-20261010190601` → 32) — כמו באוצריא.
  int get version => LibraryChangesNotes.versionOfTag(releaseTag);

  Future<String> readMarkdown() async =>
      LibraryChangesNotes.decode(await File(path).readAsBytes());

  @override
  String toString() => releaseTag;
}

/// הקבצים `library-changes.md` של SeforimLibrary: הבאתם למראה במחשב המקוון,
/// בחירתם לטווח עדכון, ומסירתם לאוצריא (`pending_library_changes`).
class LibraryChangesNotes {
  const LibraryChangesNotes._();

  static const String assetName = 'library-changes.md';

  /// תיקיית ההערות בתוך מראת הספרייה — מחוץ ל-`assets/`, שאת תוכנה מוחקים
  /// הייצוא והניקוי לפי `releases.json`.
  static const String mirrorFolderName = 'changes';

  /// קובץ ההערות של עדכון ענק הוא מאות KB; גדול מזה אינו הקובץ הצפוי.
  static const int maxBytes = 4 << 20;

  /// גם המראה וגם התיקייה של אוצריא שומרות לכל היותר כמה הכי חדשות.
  static const int maxNotes = 10;

  static const String pendingFolderName = 'pending_library_changes';
  static const String seenFolderName = 'library_changes_seen';

  static final RegExp _safeTag = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  /// התג הוא שם קובץ — אותו כלל כמו ב-`LibraryChangesStore` של אוצריא.
  static bool isSafeTag(String tag) =>
      _safeTag.hasMatch(tag) && !tag.contains('..');

  static int versionOfTag(String tag) =>
      LibraryUpdateDiscovery.parseVersionFromTag(tag) ?? 0;

  /// החדש קודם: לפי גרסה, ובאותה גרסה לפי התג (שכולל חותמת זמן).
  static int newestTagFirst(String a, String b) {
    final byVersion = versionOfTag(b).compareTo(versionOfTag(a));
    return byVersion != 0 ? byVersion : b.compareTo(a);
  }

  static String decode(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return text.startsWith('﻿') ? text.substring(1) : text;
  }

  static String mirrorFolder(String mirrorDir) =>
      p.join(mirrorDir, mirrorFolderName);

  /// ה-releases שהמראה מכסה: מ-[online], בטווח הגרסאות של [mirrored], עד
  /// [maxNotes] החדשים.
  static List<LibraryRelease> coveredReleases({
    required List<LibraryRelease> online,
    required List<LibraryRelease> mirrored,
    required bool allowPrerelease,
  }) {
    final versions = [
      for (final release in mirrored) versionOfTag(release.tag),
    ].where((v) => v > 0).toList();
    if (versions.isEmpty) return const [];
    final low = versions.reduce((a, b) => a < b ? a : b);
    final high = versions.reduce((a, b) => a > b ? a : b);
    final covered = online.where((release) {
      final version = versionOfTag(release.tag);
      return !release.isDraft &&
          (allowPrerelease || !release.isPrerelease) &&
          isSafeTag(release.tag) &&
          version >= low &&
          version <= high;
    }).toList()..sort((a, b) => newestTagFirst(a.tag, b.tag));
    return covered.take(maxNotes).toList(growable: false);
  }

  /// מביא למראה את ההערות של [covered] לפי רשימת הנכסים של כל release, ומוחק
  /// הערות של releases שהמראה כבר אינה מכסה. נכס שעוד לא הועלה (או 404) הוא
  /// "עדיין לא" — ינוסה שוב בהורדה הבאה. לעולם אינו זורק על release בודד.
  static Future<int> syncMirror({
    required String mirrorDir,
    required List<LibraryRelease> covered,
    required http.Client client,
    Duration timeout = const Duration(seconds: 30),
    bool Function()? isCancelled,
    void Function(String releaseTag, Object error)? onWarning,
  }) async {
    final folder = Directory(mirrorFolder(mirrorDir));
    var saved = 0;
    for (final release in covered) {
      if (isCancelled?.call() ?? false) break;
      final asset = release.assetByName(assetName);
      if (asset == null) continue;
      final target = File(p.join(folder.path, '${release.tag}.md'));
      try {
        if (asset.size > maxBytes) {
          throw FormatException('$assetName: ${asset.size} bytes');
        }
        if (asset.size > 0 &&
            await target.exists() &&
            await target.length() == asset.size) {
          continue;
        }
        final response = await client
            .get(Uri.parse(asset.downloadUrl), headers: githubUserAgentHeaders)
            .timeout(timeout);
        if (response.statusCode == HttpStatus.notFound) continue;
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            '$assetName: HTTP ${response.statusCode}',
            uri: Uri.parse(asset.downloadUrl),
          );
        }
        final bytes = response.bodyBytes;
        if (bytes.length > maxBytes) {
          throw FormatException('$assetName: ${bytes.length} bytes');
        }
        await folder.create(recursive: true);
        await writeBytesAtomically(target.path, bytes);
        saved++;
      } catch (error) {
        onWarning?.call(release.tag, error);
      }
    }
    await _pruneMirror(folder, {for (final r in covered) '${r.tag}.md'});
    return saved;
  }

  static Future<void> _pruneMirror(Directory folder, Set<String> keep) async {
    if (!await folder.exists()) return;
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || keep.contains(p.basename(entity.path))) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        // קובץ נעול יימחק בהורדה הבאה; זה מקום מבוזבז בלבד.
      }
    }
  }

  /// ההערות שבמראה ל-releases שבטווח ([fromVersion], [toVersion]], החדשה
  /// קודם, עד [maxNotes].
  static Future<List<LibraryChangesNote>> inMirror(
    String mirrorDir, {
    required int fromVersion,
    required int toVersion,
  }) async {
    final folder = Directory(mirrorFolder(mirrorDir));
    if (!await folder.exists()) return const [];
    final notes = <LibraryChangesNote>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || p.extension(entity.path) != '.md') continue;
      final tag = p.basenameWithoutExtension(entity.path);
      final version = versionOfTag(tag);
      if (!isSafeTag(tag) || version <= fromVersion || version > toVersion) {
        continue;
      }
      notes.add(LibraryChangesNote(releaseTag: tag, path: entity.path));
    }
    notes.sort((a, b) => newestTagFirst(a.releaseTag, b.releaseTag));
    return notes.take(maxNotes).toList(growable: false);
  }

  /// כותב את [notes] ל-`<dataRoot>/pending_library_changes/<tag>.md`, שם
  /// אוצריא מציגה אותן. תג שכבר ממתין או שכבר הוצג (`library_changes_seen`)
  /// אינו נכתב שוב. אחר כך נשארות בתיקייה רק [maxNotes] החדשות — אוצריא ישנה
  /// שאינה צורכת אותה לא תצבור בה קבצים בלי סוף. מחזיר את התגים שנכתבו.
  static Future<List<String>> handOff({
    required String dataRoot,
    required List<LibraryChangesNote> notes,
  }) async {
    final pending = Directory(p.join(dataRoot, pendingFolderName));
    final seen = p.join(dataRoot, seenFolderName);
    final written = <String>[];
    for (final note in notes) {
      final name = '${note.releaseTag}.md';
      if (!isSafeTag(note.releaseTag) ||
          await File(p.join(pending.path, name)).exists() ||
          await File(p.join(seen, name)).exists()) {
        continue;
      }
      final markdown = await note.readMarkdown();
      if (markdown.trim().isEmpty) continue;
      await pending.create(recursive: true);
      await writeBytesAtomically(
        p.join(pending.path, name),
        utf8.encode(markdown),
      );
      written.add(note.releaseTag);
    }
    await _prunePending(pending);
    return written;
  }

  static Future<void> _prunePending(Directory pending) async {
    if (!await pending.exists()) return;
    final files = <File>[];
    await for (final entity in pending.list(followLinks: false)) {
      if (entity is File && p.extension(entity.path) == '.md') {
        files.add(entity);
      }
    }
    if (files.length <= maxNotes) return;
    String tagOf(File f) => p.basenameWithoutExtension(f.path);
    files.sort((a, b) => newestTagFirst(tagOf(a), tagOf(b)));
    for (final file in files.skip(maxNotes)) {
      await file.delete();
    }
  }
}
