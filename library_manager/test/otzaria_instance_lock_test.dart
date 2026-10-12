import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  group('OtzariaInstanceLock — שם המוטקס של אוצריא ניידת', () {
    test('וקטורים משותפים עם windows/runner/main.cpp (FNV-1a 64, UTF-16)', () {
      const base = OtzariaInstanceLock.mutexName;
      expect(OtzariaInstanceLock.fnv1a64Hex(''), 'cbf29ce484222325');
      expect(
        OtzariaInstanceLock.portableMutexName(r'C:\Otzaria\otzaria_data'),
        '$base-5f767ae45f832305',
      );
      expect(
        OtzariaInstanceLock.portableMutexName(
          r'E:\PortableApps\Otzaria\otzaria_data',
        ),
        '$base-351ba4315c762f42',
      );
      expect(
        OtzariaInstanceLock.portableMutexName(
          r'e:/portableapps/otzaria/otzaria_data',
        ),
        '$base-351ba4315c762f42',
      );
      expect(
        OtzariaInstanceLock.portableMutexName(r'D:\אוצריא נייד\otzaria_data'),
        '$base-7e4574468825c86b',
      );
    });

    test('התקנה רגילה מחזיקה רק את השם הציבורי; ניידת את שניהם', () {
      expect(OtzariaInstanceLock.mutexNamesFor(), [
        OtzariaInstanceLock.mutexName,
      ]);
      expect(
        OtzariaInstanceLock.mutexNamesFor(
          portableDataRoot: r'C:\Otzaria\otzaria_data',
        ),
        [
          OtzariaInstanceLock.mutexName,
          '${OtzariaInstanceLock.mutexName}-5f767ae45f832305',
        ],
      );
    });
  });

  group('OtzariaInstanceLock (Windows)', () {
    test(
      'אוצריא ניידת: גם המוטקס של שורש הנתונים שלה מוחזק לכל ההחלה',
      () async {
        final root = p.join(
          Directory.systemTemp.path,
          'ou-lock-test',
          'otzaria_data',
        );
        final perRoot = OtzariaInstanceLock.portableMutexName(root);
        final OtzariaInstanceLease lease;
        try {
          lease = await const OtzariaInstanceLock().acquire(
            portableDataRoot: root,
          );
        } on OtzariaIsRunningException {
          markTestSkipped('אוצריא פתוחה במכונה הזו');
          return;
        }
        try {
          expect(OtzariaInstanceLock.isMutexPresent(perRoot), isTrue);
          expect(
            OtzariaInstanceLock.isMutexPresent(OtzariaInstanceLock.mutexName),
            isTrue,
          );
        } finally {
          lease.release();
        }
        expect(OtzariaInstanceLock.isMutexPresent(perRoot), isFalse);
      },
      skip: Platform.isWindows ? false : 'Windows בלבד',
    );

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
  Future<OtzariaInstanceLease> acquire({String? portableDataRoot}) async {
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
