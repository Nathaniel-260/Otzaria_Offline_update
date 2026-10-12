import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  group('OtzariaInstanceLock (Windows)', () {
    test(
      'מחזיק את המוטקס של אוצריא, ומחזיקה שנייה נחסמת כמו אוצריא שנפתחת',
      () async {
        const lock = OtzariaInstanceLock();
        final OtzariaInstanceLease first;
        try {
          first = await lock.acquire();
        } on OtzariaIsRunningException {
          markTestSkipped('אוצריא פתוחה במכונה הזו');
          return;
        }
        try {
          expect(OtzariaInstanceLock.isHeldByThisProcess, isTrue);
          await expectLater(
            lock.acquire(),
            throwsA(isA<OtzariaIsRunningException>()),
          );
        } finally {
          first.release();
        }
        expect(OtzariaInstanceLock.isHeldByThisProcess, isFalse);

        final again = await lock.acquire();
        again.release();
      },
      skip: Platform.isWindows ? false : 'Windows בלבד',
    );
  });

  group('LibraryManager.applyUpdate — נעילה לכל משך ההחלה', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('instance-lock-');
      dbPath = p.join(tempDir.path, 'books', 'seforim.db');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    LibraryUpdateCheckResult fullCheck() => LibraryUpdateCheckResult(
      dbPath: dbPath,
      isFreshInstall: true,
      latestVersion: 5,
      plan: LibraryUpdatePlan.fullDownload(
        localVersion: 0,
        targetVersion: 5,
        asset: const ReleaseAsset(
          name: 'seforim.db.zst',
          downloadUrl: 'x',
          size: 1,
        ),
        releaseTag: 'v5',
      ),
    );

    LibraryManager manager(_FakeLock lock, _RecordingApplier applier) =>
        LibraryManager(
          dataDir: p.join(tempDir.path, 'data'),
          operatingSystem: 'linux',
          environment: {'HOME': p.join(tempDir.path, 'home')},
          instanceLock: lock,
          applier: applier,
        );

    test('אוצריא שמחזיקה את המוטקס חוסמת לפני שנוגעים במסד', () async {
      final applier = _RecordingApplier();
      final m = manager(_FakeLock(running: true), applier);
      addTearDown(m.dispose);

      await expectLater(
        m.applyUpdate(fullCheck()),
        throwsA(isA<OtzariaIsRunningException>()),
      );
      expect(applier.calls, 0);
    });

    test('המוטקס מוחזק בזמן ההחלה ומשוחרר אחריה, גם בכישלון', () async {
      final lock = _FakeLock();
      final applier = _RecordingApplier(whileApplying: () => lock.held);
      final m = manager(lock, applier);
      addTearDown(m.dispose);

      await expectLater(m.applyUpdate(fullCheck()), throwsA(isA<StateError>()));

      expect(applier.calls, 1);
      expect(applier.heldDuringApply, isTrue);
      expect(lock.held, isFalse);
    });
  });
}

class _FakeLock implements OtzariaInstanceLock {
  _FakeLock({this.running = false});

  final bool running;
  bool held = false;

  @override
  Future<OtzariaInstanceLease> acquire() async {
    if (running) throw const OtzariaIsRunningException();
    held = true;
    return _FakeLease(this);
  }
}

class _FakeLease implements OtzariaInstanceLease {
  _FakeLease(this._lock);

  final _FakeLock _lock;

  @override
  void release() => _lock.held = false;
}

class _RecordingApplier extends LibraryUpdateApplier {
  _RecordingApplier({this.whileApplying});

  final bool Function()? whileApplying;
  int calls = 0;
  bool? heldDuringApply;

  @override
  Future<void> applyFullDownload({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    calls++;
    heldDuringApply = whileApplying?.call();
    throw StateError('stop');
  }
}
