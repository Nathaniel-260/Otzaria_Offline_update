import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// מחלץ את ה-id האמיתי של התוסף מתוך `manifest.json` שבקובץ ה-`.otzplugin`.
///
/// **למה זה קריטי:** ה-`id` שה-API הציבורי מחזיר הוא מזהה מסד-הנתונים של
/// האתר, ואילו אוצריא מתקינה תחת `installed/<manifest.id>/`. השוואה לפי
/// ה-id של הקטלוג לעולם לא תזהה תוסף מותקן.
abstract final class PluginManifestReader {
  static const _manifestEntryName = 'manifest.json';
  static const maxManifestBytes = 1024 * 1024;

  /// מחזיר את ה-id, או `null` אם הקובץ אינו ZIP תקין / חסר manifest / ה-id
  /// ריק. **לא זורק** — תוסף בודד עם קובץ פגום פשוט לא ישווה למותקן, וזה
  /// עדיף על הפלת הסנכרון כולו.
  static String? readId(String pluginFilePath) {
    return idOf(read(pluginFilePath));
  }

  static String? idOf(Map<String, dynamic>? manifest) {
    final id = manifest?['id'];
    return id is String && id.trim().isNotEmpty ? id.trim() : null;
  }

  static Map<String, dynamic>? read(String pluginFilePath) {
    InputFileStream? input;
    try {
      input = InputFileStream(pluginFilePath);
      final archive = ZipDecoder().decodeStream(input, verify: false);
      final entry = archive.files.where(
        (f) => f.isFile && f.name == _manifestEntryName,
      );
      if (entry.isEmpty) return null;

      if (entry.first.size > maxManifestBytes) return null;

      final bytes = boundedBytes(entry.first, maxManifestBytes);
      if (bytes == null) return null;
      final text =
          utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    } finally {
      input?.closeSync();
    }
  }

  static Uint8List? boundedBytes(ArchiveFile file, int limit) {
    final raw = file.rawContent;
    if (raw == null) return Uint8List(0);
    final stored = raw.getStream(decompress: false).toUint8List();
    if (stored.length > limit) return null;
    if (!raw.isCompressed) return stored;
    if (file.compression != CompressionType.deflate) return null;
    final sink = _CappedSink(limit);
    try {
      final conversion =
          io.ZLibCodec(raw: true).decoder.startChunkedConversion(sink);
      conversion.add(stored);
      conversion.close();
    } on _LimitExceeded {
      return null;
    }
    return sink.takeBytes();
  }
}

class _LimitExceeded implements Exception {
  const _LimitExceeded();
}

class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.limit);

  final int limit;
  final BytesBuilder _out = BytesBuilder();

  @override
  void add(List<int> data) {
    _out.add(data);
    if (_out.length > limit) throw const _LimitExceeded();
  }

  @override
  void close() {}

  Uint8List takeBytes() => _out.takeBytes();
}
