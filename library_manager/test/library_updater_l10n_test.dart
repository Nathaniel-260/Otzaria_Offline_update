import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  tearDown(() {
    AppL10n.use(AppLanguage.hebrew);
    LibraryUpdaterMessages.current = const HebrewLibraryUpdaterMessages();
  });

  test('the engine messages follow the launcher language once installed', () {
    useLibraryUpdaterL10n();
    AppL10n.use(AppLanguage.english);
    final english = AppL10n.strings.libraryDomain;
    expect(
      LibraryUpdaterMessages.current.localVersionMismatch(5, 1),
      english.localVersionMismatch(5, 1),
    );
    expect(
      LibraryUpdaterMessages.current.networkInterrupted,
      english.networkInterrupted,
    );
    expect(
      LibraryUpdaterMessages.current.megabytes('3'),
      AppL10n.strings.units.megabytes('3'),
    );
    expect(
      const PatchNetworkException(SocketException('reset')).message,
      english.networkInterrupted,
    );
  });

  test('LibraryManager installs the adapter', () {
    final dir = Directory.systemTemp.createTempSync('lu_l10n');
    addTearDown(() => dir.deleteSync(recursive: true));
    LibraryManager(dataDir: dir.path).dispose();
    expect(LibraryUpdaterMessages.current, isA<L10nLibraryUpdaterMessages>());
  });
}
