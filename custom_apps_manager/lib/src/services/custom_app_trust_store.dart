import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';

import '../models/app_descriptor.dart';

/// אישורי ההתקנה של המחשב הזה — קובץ **במחשב** ולא על הכונן, כדי שרשומה
/// שהגיעה על כונן לא תוכל להביא איתה אישור משלה.
///
/// אישור קשור לתוכן: מזהה + sha256 של קובץ ההתקנה + טביעת התיאור (מקור,
/// מיקום התקנה, שם). כל שינוי באחד מהם מבקש אישור מחדש.
class CustomAppTrustStore {
  CustomAppTrustStore(this.filePath);

  /// `null` = אין תיקייה במחשב לשמור בה; האישורים נשמרים לריצה הזו בלבד.
  final String? filePath;

  final Set<String> _session = {};

  static String keyFor(AppDescriptor descriptor, String installerSha256) {
    final json = descriptor.toJson();
    final relevant = {
      'id': json['id'],
      'name': json['name'],
      'source': json['source'],
      'install': json['install'],
    };
    final digest = sha256.convert(utf8.encode(jsonEncode(relevant)));
    return '${descriptor.id}|$installerSha256|$digest';
  }

  Future<Set<String>> _stored() async {
    final path = filePath;
    if (path == null) return {};
    try {
      final json = jsonDecode(await File(path).readAsString());
      final list = json is Map ? json['trusted'] : null;
      return {
        if (list is List)
          for (final key in list)
            if (key is String) key,
      };
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<bool> isTrusted(String key) async =>
      _session.contains(key) || (await _stored()).contains(key);

  Future<void> trust(String key) async {
    _session.add(key);
    final path = filePath;
    if (path == null) return;
    final keys = await _stored()
      ..add(key);
    await File(path).parent.create(recursive: true);
    await writeStringAtomically(
      path,
      jsonEncode({'trusted': keys.toList()..sort()}),
    );
  }
}
