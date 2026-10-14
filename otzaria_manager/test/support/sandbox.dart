import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';

void sandboxRealDataRoot() {
  _sandbox ??= Directory.systemTemp.createTempSync('otzaria-manager-sandbox-');
  OtzariaManager.sandboxForTests(_sandbox!.path);
}

Directory? _sandbox;
