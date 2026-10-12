import 'package:flutter/services.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart'
    show trustCertificates;

const List<String> netfreeCaAssets = [
  'assets/ca/netfree_cas.pem',
  'assets/ca/netfree_root_ca_unified_v1.pem',
  'assets/ca/netfree_root_ca_x2.pem',
];

Future<void> trustNetfreeCertificates({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  trustCertificates([
    for (final asset in netfreeCaAssets)
      (await assets.load(asset)).buffer.asUint8List(),
  ]);
}
