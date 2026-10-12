import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  LibraryUpdatePlan full(int bytes) => LibraryUpdatePlan.fullDownload(
        localVersion: 20,
        targetVersion: 31,
        asset: ReleaseAsset(
          name: 'seforim.db.zst',
          downloadUrl: 'mirror://seforim.db.zst',
          size: bytes,
        ),
        releaseTag: 'v31',
      );

  test('מסלול מלא: טווח שמכיל את המדידות האמיתיות (129–581 שניות)', () {
    final range = libraryApplyMinutes(full(1310 << 20))!;
    expect(range.low, lessThanOrEqualTo(3));
    expect(range.high, greaterThanOrEqualTo(10));
    expect(range.low, lessThan(range.high));
  });

  test('אין תוכנית, אין מה להעריך, או גודל לא ידוע — אין אומדן', () {
    expect(libraryApplyMinutes(null), isNull);
    expect(
      libraryApplyMinutes(LibraryUpdatePlan.none(localVersion: 31)),
      isNull,
    );
    expect(libraryApplyMinutes(full(0)), isNull);
  });
}
