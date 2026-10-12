import 'dart:convert';

import 'package:plugins_manager/src/services/media_sniffer.dart';
import 'package:test/test.dart';

void main() {
  test('חתימות התמונה שהחנות משתמשת בהן מתקבלות', () {
    expect(MediaSniffer.isImage(const [137, 80, 78, 71, 13, 10, 26, 10, 0]),
        isTrue);
    expect(MediaSniffer.isImage(const [0xFF, 0xD8, 0xFF, 0xE0]), isTrue);
    expect(MediaSniffer.isImage(ascii.encode('GIF89a....')), isTrue);
    expect(MediaSniffer.isImage(ascii.encode('RIFF\x00\x00\x00\x00WEBPVP8 ')),
        isTrue);
  });

  test('דף HTML, JSON או קובץ קטוע אינם תמונה', () {
    expect(MediaSniffer.isImage(utf8.encode('<!doctype html><html>')), isFalse);
    expect(MediaSniffer.isImage(utf8.encode('<html><svg/></html>')), isFalse);
    expect(MediaSniffer.isImage(utf8.encode('{"error":"shabbat"}')), isFalse);
    expect(MediaSniffer.isImage(const [137, 80, 78, 71]), isFalse);
    expect(MediaSniffer.isImage(const []), isFalse);
    expect(
      MediaSniffer.isImage(utf8.encode('\uFEFF<?xml version="1.0"?><svg/>')),
      isFalse,
    );
  });
}
