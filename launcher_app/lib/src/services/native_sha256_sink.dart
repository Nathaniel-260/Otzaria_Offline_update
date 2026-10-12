import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show Sha256Stream;

/// `otzaria_downloads.startSha256` backed by the OS crypto (`Sha256Stream`),
/// so verifying a download no longer runs pure-Dart SHA on the UI isolate.
class NativeSha256Sink extends ByteConversionSink {
  NativeSha256Sink(this._output);

  final Sink<Digest> _output;
  final Sha256Stream _hash = Sha256Stream();
  bool _closed = false;

  @override
  void add(List<int> chunk) => _hash.add(chunk);

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    _hash.addSlice(chunk, start, end);
    if (isLast) close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      final hex = _hash.close();
      _output
        ..add(Digest([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ]))
        ..close();
    } finally {
      _hash.dispose();
    }
  }
}
