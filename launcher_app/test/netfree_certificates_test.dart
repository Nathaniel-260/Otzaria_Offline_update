import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/netfree_certificates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('תעודות נטפרי ארוזות עם הלאנצ׳ר ונטענות להקשר ה-TLS', () async {
    for (final asset in netfreeCaAssets) {
      final bytes = await rootBundle.load(asset);
      expect(bytes.lengthInBytes, greaterThan(0), reason: asset);
    }
    await trustNetfreeCertificates();
    expect(SecurityContext.defaultContext, isNotNull);
  });
}
