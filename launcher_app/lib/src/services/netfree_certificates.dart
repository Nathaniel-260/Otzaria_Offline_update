import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart'
    show trustCertificates;

const List<String> netfreeCaAssets = [
  'assets/ca/netfree_cas.pem',
  'assets/ca/netfree_root_ca_unified_v1.pem',
  'assets/ca/netfree_root_ca_x2.pem',
];

Future<void> trustNetfreeCertificates({
  AssetBundle? bundle,
  List<String> assets = netfreeCaAssets,
}) async {
  final source = bundle ?? rootBundle;
  for (final asset in assets) {
    try {
      trustCertificates([(await source.load(asset)).buffer.asUint8List()]);
    } catch (error) {
      debugPrint('NetFree certificate $asset not loaded: $error');
    }
  }
}
