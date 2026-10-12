import 'dart:convert';
import 'dart:io';

import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:path/path.dart' as p;

/// Which machines may run this app's installer without asking again.
///
/// A record handed over by copying `apps/<id>/` arrives from another machine;
/// its installer runs only after the person at this machine confirms once.
/// `trust.json` beside the descriptor, keyed by machine key, never by path.
class CustomAppTrustStore {
  CustomAppTrustStore(this.appDir);

  final String appDir;

  static const String fileName = 'trust.json';

  String get _path => p.join(appDir, fileName);

  Future<Set<String>> _trusted() async {
    try {
      final json = jsonDecode(await File(_path).readAsString());
      final list = json is Map ? json['trustedOn'] : null;
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

  Future<bool> isTrusted(String machineKey) async =>
      (await _trusted()).contains(machineKey);

  Future<void> trust(String machineKey) async {
    final keys = await _trusted()
      ..add(machineKey);
    await Directory(appDir).create(recursive: true);
    await writeStringAtomically(
      _path,
      jsonEncode({'trustedOn': keys.toList()..sort()}),
    );
  }
}
