import 'dart:async';
import 'dart:io';

import 'package:library_manager/library_manager.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sandbox = Directory.systemTemp.createTempSync('otzaria-test-sandbox-');
  LibraryDbLocator.sandboxForTests(sandbox.path);
  await testMain();
}
