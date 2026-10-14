import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/sandbox.dart';

void main() {
  sandboxRealDataRoot();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('otzaria-detect-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  OtzariaManager managerFor(_CountingRegistry registry) {
    final manager = OtzariaManager(
      dataDir: p.join(root.path, 'data'),
      platform: OtzariaTargetPlatform.windows,
      environment: {'LOCALAPPDATA': p.join(root.path, 'local')},
      runningLocator: const _NotRunning(),
      installRegistry: registry,
      versionReader: const _FileContentVersionReader(),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  test('ההתקנה הישנה ב-%LOCALAPPDATA%\\Programs\\אוצריא מזוהה', () async {
    final dir = Directory(p.join(root.path, 'local', 'Programs', 'אוצריא'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'otzaria.exe')).writeAsStringSync('1.0.0');

    final check = await managerFor(_CountingRegistry()).checkForUpdate();

    expect(check.currentState?.installDir, dir.path);
  });

  test('הרג׳יסטרי נסרק פעם אחת בכל בדיקה', () async {
    final registry = _CountingRegistry();
    final manager = managerFor(registry);

    await manager.checkForUpdate();
    expect(registry.calls, 1);
    await manager.checkForUpdate();
    expect(registry.calls, 2);
  });
}

class _CountingRegistry extends WindowsInstallRegistry {
  int calls = 0;

  @override
  Future<List<String>> otzariaInstallDirs() async {
    calls++;
    return const [];
  }
}

class _FileContentVersionReader implements InstalledVersionReader {
  const _FileContentVersionReader();

  @override
  String? readVersion(String launchPath) =>
      File(launchPath).readAsStringSync().trim();
}

class _NotRunning extends RunningOtzariaLocator {
  const _NotRunning();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}
