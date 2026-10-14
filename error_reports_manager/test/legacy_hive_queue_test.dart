import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// קבצים שנכתבו ב-hive_ce 2.20.2 (הגרסה של אוצריא) — `put` של רשימות.
const _twoPendingOneSent =
    'UQAAAAEPcGVuZGluZ19yZXBvcnRzCgIAAAALAgAAAAQCAAAAaWQEAQAAAHgEAQAAAG4BAAAAAAAA'
    '8D8LAQAAAAQCAAAAaWQEAQAAAHmDJV/vLQAAAAEMc2VudF9yZXBvcnRzCgEAAAALAQAAAAQCAAAA'
    'aWQEAQAAAHrN8gho';
const _pendingEmptiedLater =
    'MAAAAAEPcGVuZGluZ19yZXBvcnRzCgEAAAALAQAAAAQCAAAAaWQEAQAAAHhkBsFqHgAAAAEPcGVu'
    'ZGluZ19yZXBvcnRzCgAAAACK6hNxLQAAAAEMc2VudF9yZXBvcnRzCgEAAAALAQAAAAQCAAAAaWQE'
    'AQAAAHFFK9r/';
const _sentOnly =
    'LQAAAAEMc2VudF9yZXBvcnRzCgEAAAALAQAAAAQCAAAAaWQEAQAAAHFFK9r/';

Uint8List _bytes(String b64) => base64.decode(b64);

void main() {
  group('hivePendingReportCount', () {
    test('רשימת ממתינים בקובץ אמיתי', () {
      expect(hivePendingReportCount(_bytes(_twoPendingOneSent)), 2);
    });

    test('המסגרת האחרונה של המפתח קובעת — רשימה שהתרוקנה היא 0', () {
      expect(hivePendingReportCount(_bytes(_pendingEmptiedLater)), 0);
    });

    test('רק היסטוריה, קובץ ריק או פגום — אין ממתינים', () {
      expect(hivePendingReportCount(_bytes(_sentOnly)), isNull);
      expect(hivePendingReportCount(Uint8List(0)), isNull);
      expect(
          hivePendingReportCount(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    });
  });

  group('findUnmigratedReportBoxes', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('legacy_hive_'));
    tearDown(() => temp.deleteSync(recursive: true));

    void write(String box, String b64) =>
        File(p.join(temp.path, '$box.hive')).writeAsBytesSync(_bytes(b64));

    test('רק תור שיש בו ממתינים מדווח', () async {
      write('error_reports_queue', _twoPendingOneSent);
      write('app_reports_queue', _pendingEmptiedLater);
      write('plugin_reports_queue', _sentOnly);

      expect(
        await findUnmigratedReportBoxes(dataRoot: temp.path),
        ['error_reports_queue'],
      );
    });
  });
}
