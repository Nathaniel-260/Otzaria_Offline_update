import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

void main() {
  final api = Uri.parse('https://api.github.com/repos/o/r/releases');
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('network-errors-test-');
  });
  tearDown(() => temp.delete(recursive: true));

  Future<FileDownloadResult> download(http.Client client) => downloadFile(
        client: client,
        url: 'https://example.test/app.exe',
        destinationPath: '${temp.path}/app.exe',
        maxAttempts: 1,
        statusError: (status) => StateError('HTTP $status'),
        sizeError: (actual, expected) => StateError('size $actual/$expected'),
      );

  test('418 מגיטהאב הוא חסימת סינון ולא "סטטוס 418"', () async {
    final client = MockClient((_) async => http.Response('', 418));

    await expectLater(
      githubGet(client, api, timeout: const Duration(seconds: 5)),
      throwsA(
        isA<NetworkBlockedException>()
            .having((e) => e.statusCode, 'statusCode', 418)
            .having(
              (e) => e.toString(),
              'message',
              AppL10n.strings.appDomain.networkBlockedByFilter(
                418,
                'api.github.com',
              ),
            ),
      ),
    );
  });

  test('כשל אישור TLS מקבל הודעה ייעודית', () async {
    final client = MockClient(
      (_) async => throw const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
    );

    await expectLater(
      githubGet(client, api, timeout: const Duration(seconds: 5)),
      throwsA(
        isA<NetworkCertificateException>().having(
          (e) => e.toString(),
          'message',
          AppL10n.strings.appDomain
              .networkCertificateRejected('api.github.com'),
        ),
      ),
    );
  });

  test('הורדה: 418 ו-403 הם חסימה, TLS הוא כשל אישור', () async {
    for (final status in [418, 403]) {
      await expectLater(
        download(MockClient((_) async => http.Response('', status))),
        throwsA(isA<NetworkBlockedException>()),
      );
    }
    await expectLater(
      download(
        MockClient((_) async => throw const HandshakeException('bad cert')),
      ),
      throwsA(isA<NetworkCertificateException>()),
    );
    await expectLater(
      download(MockClient((_) async => http.Response('', 404))),
      throwsA(isA<StateError>()),
    );
  });

  test('trustCertificates מקבל את תעודות נטפרי פעמיים בלי לזרוק', () {
    final file = File('../launcher_app/assets/ca/netfree_root_ca_x2.pem');
    if (!file.existsSync()) {
      markTestSkipped('קובצי התעודות של הלאנצ׳ר אינם זמינים');
      return;
    }
    final bytes = file.readAsBytesSync();

    trustCertificates([bytes]);
    trustCertificates([bytes]);
  });
}
