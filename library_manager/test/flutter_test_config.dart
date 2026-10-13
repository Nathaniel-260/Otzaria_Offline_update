import 'dart:async';
import 'dart:io';

import 'package:library_manager/library_manager.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sandbox = Directory.systemTemp.createTempSync('otzaria-test-sandbox-');
  LibraryDbLocator.sandboxForTests(sandbox.path);
  OtzariaManager.sandboxForTests(sandbox.path);
  await testMain();
}
