import 'dart:async';
import 'dart:io';

import 'package:library_manager/library_manager.dart';
import 'package:plugins_manager/plugins_manager.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sandbox = Directory.systemTemp.createTempSync('otzaria-test-sandbox-');
  LibraryDbLocator.sandboxForTests(sandbox.path);
  InstalledPluginsScanner.sandboxForTests(sandbox.path);
  await testMain();
}
