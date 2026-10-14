import 'dart:convert';
import 'dart:io';

abstract final class MediaSniffer {
  static const int headerBytes = 4096;

  static Future<bool> isImageFile(String path) async {
    final head = <int>[];
    await for (final chunk in File(path).openRead(0, headerBytes)) {
      head.addAll(chunk);
    }
    return isImage(head);
  }

  static bool isImage(List<int> head) =>
      _startsWith(
          head, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) ||
      _startsWith(head, const [0xFF, 0xD8, 0xFF]) ||
      _startsWith(head, ascii.encode('GIF87a')) ||
      _startsWith(head, ascii.encode('GIF89a')) ||
      (_startsWith(head, ascii.encode('RIFF')) &&
          head.length >= 12 &&
          ascii.decode(head.sublist(8, 12), allowInvalid: true) == 'WEBP');

  static bool _startsWith(List<int> data, List<int> prefix) {
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }
}
