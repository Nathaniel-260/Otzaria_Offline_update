import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/instance_lock.dart';
import 'package:path/path.dart' as p;

void main() {
  group('InstanceLock.isContention', () {
    test('Windows: only ERROR_LOCK_VIOLATION means another holder', () {
      expect(InstanceLock.isContention(33, isWindows: true), isTrue);
      expect(InstanceLock.isContention(5, isWindows: true), isFalse);
      expect(InstanceLock.isContention(13, isWindows: true), isFalse);
      expect(InstanceLock.isContention(null, isWindows: true), isFalse);
    });

    test('macOS: EAGAIN and EACCES, not ENOTSUP', () {
      expect(
        InstanceLock.isContention(35, isWindows: false, isMacOS: true),
        isTrue,
      );
      expect(
        InstanceLock.isContention(13, isWindows: false, isMacOS: true),
        isTrue,
      );
      expect(
        InstanceLock.isContention(45, isWindows: false, isMacOS: true),
        isFalse,
      );
    });

    test('Linux: EAGAIN and EACCES', () {
      expect(
        InstanceLock.isContention(11, isWindows: false, isMacOS: false),
        isTrue,
      );
      expect(
        InstanceLock.isContention(13, isWindows: false, isMacOS: false),
        isTrue,
      );
      expect(
        InstanceLock.isContention(95, isWindows: false, isMacOS: false),
        isFalse,
      );
    });
  });

  group('InstanceLock machine-wide mutex', () {
    String uniqueName() =>
        'Local\\OtzariaOfflineUpdateTest-$pid-${DateTime.now().microsecondsSinceEpoch}';

    test('a free name is owned, and owning it again on this thread is fine',
        () {
      final name = uniqueName();
      final first = InstanceLock.tryOwnMutex(name);
      expect(first.result, InstanceLockResult.acquired);
      final again = InstanceLock.tryOwnMutex(name);
      expect(again.result, InstanceLockResult.acquired);
    }, skip: !Platform.isWindows);

    test('a name owned by another thread is held elsewhere', () async {
      final name = uniqueName();
      final release = ReceivePort();
      final owned = ReceivePort();
      final holder = await Isolate.spawn((List<Object> args) async {
        final result = InstanceLock.tryOwnMutex(args[0] as String);
        final stop = ReceivePort();
        (args[1] as SendPort).send([result.result.name, stop.sendPort]);
        await stop.first;
      }, [name, owned.sendPort]);
      addTearDown(() {
        holder.kill();
        release.close();
      });
      final reply = await owned.first as List;
      expect(reply[0], InstanceLockResult.acquired.name);

      expect(InstanceLock.tryOwnMutex(name).result,
          InstanceLockResult.heldElsewhere);
    }, skip: !Platform.isWindows);
  });

  group('InstanceLock.acquire', () {
    late Directory sandbox;
    late String lockDir;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('instance-lock-test-');
      lockDir = p.join(sandbox.path, 'logs');
    });
    tearDown(() async {
      await InstanceLock.release();
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    Future<Process> holdInOtherProcess() async {
      final script = File(p.join(sandbox.path, 'hold_lock.dart'))
        ..writeAsStringSync('''
import 'dart:io';

Future<void> main(List<String> args) async {
  await Directory(args[0]).create(recursive: true);
  final file = await File(args[1]).open(mode: FileMode.append);
  await file.lock(FileLock.exclusive);
  stdout.writeln('locked');
  await stdin.drain<void>();
}
''');
      final process = await Process.start(_dartExecutable(), [
        script.path,
        lockDir,
        p.join(lockDir, InstanceLock.fileName),
      ]);
      final first = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 60));
      expect(first, 'locked');
      return process;
    }

    test('creates the directory and takes the lock when nobody holds it',
        () async {
      expect(
        await InstanceLock.acquire(lockDir, wait: Duration.zero),
        InstanceLockResult.acquired,
      );
      expect(File(p.join(lockDir, InstanceLock.fileName)).existsSync(), isTrue);
    });

    test('a lock held by another process is reported, not stolen', () async {
      final holder = await holdInOtherProcess();
      addTearDown(() async {
        holder.kill();
        await holder.exitCode;
      });

      expect(
        await InstanceLock.acquire(lockDir, wait: Duration.zero),
        InstanceLockResult.heldElsewhere,
      );
    });

    test('a holder that exits releases the lock, even without cleanup',
        () async {
      final holder = await holdInOtherProcess();
      holder.kill(ProcessSignal.sigkill);
      await holder.exitCode;

      expect(
        await InstanceLock.acquire(lockDir, wait: Duration.zero),
        InstanceLockResult.acquired,
      );
    });

    test('waits for a holder that is on its way out', () async {
      final holder = await holdInOtherProcess();
      Timer(const Duration(milliseconds: 300), holder.kill);

      expect(
        await InstanceLock.acquire(
          lockDir,
          wait: const Duration(seconds: 10),
          retryInterval: const Duration(milliseconds: 50),
        ),
        InstanceLockResult.acquired,
      );
    });

    test('a folder that cannot hold the lock file does not block startup',
        () async {
      final blocker = File(p.join(sandbox.path, 'not-a-dir'))
        ..writeAsStringSync('x');

      expect(
        await InstanceLock.acquire(blocker.path, wait: Duration.zero),
        InstanceLockResult.unavailable,
      );
    });
  });

  test('the window it focuses is the one the Windows runner creates', () {
    final escaped = InstanceLock.windowTitle.codeUnits
        .map((c) => c < 0x80
            ? String.fromCharCode(c)
            : '\\u${c.toRadixString(16).toUpperCase().padLeft(4, '0')}')
        .join();
    expect(
      File('windows/runner/main.cpp').readAsStringSync(),
      contains('L"$escaped"'),
    );
    expect(
      File('windows/runner/win32_window.cpp').readAsStringSync(),
      contains('kWindowClassName[] = L"${InstanceLock.windowClassName}"'),
    );
  });
}

String _dartExecutable() {
  final cache = p.dirname(
    p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable))),
  );
  final bundled = p.join(
    cache,
    'dart-sdk',
    'bin',
    Platform.isWindows ? 'dart.exe' : 'dart',
  );
  return File(bundled).existsSync() ? bundled : 'dart';
}
