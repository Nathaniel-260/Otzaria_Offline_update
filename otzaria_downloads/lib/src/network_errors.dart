import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria_l10n/otzaria_l10n.dart';

bool isFilterBlockStatus(int statusCode) =>
    statusCode == 418 || statusCode == 403;

class NetworkBlockedException implements Exception {
  const NetworkBlockedException({required this.uri, required this.statusCode});

  final Uri uri;
  final int statusCode;

  @override
  String toString() =>
      AppL10n.strings.appDomain.networkBlockedByFilter(statusCode, uri.host);
}

class NetworkCertificateException implements Exception {
  const NetworkCertificateException({required this.uri, required this.cause});

  final Uri uri;
  final TlsException cause;

  @override
  String toString() =>
      AppL10n.strings.appDomain.networkCertificateRejected(uri.host);
}

void trustCertificates(List<Uint8List> certificates) {
  for (final bytes in certificates) {
    try {
      SecurityContext.defaultContext.setTrustedCertificatesBytes(bytes);
    } on TlsException {
      continue;
    }
  }
}
