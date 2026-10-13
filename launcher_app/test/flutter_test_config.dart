import 'dart:async';
import 'dart:io';

import 'package:plugins_manager/plugins_manager.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sandbox = Directory.systemTemp.createTempSync('otzaria-test-sandbox-');
  InstalledPluginsScanner.sandboxForTests(sandbox.path);
  await testMain();
}
