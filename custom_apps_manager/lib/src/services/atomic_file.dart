import 'dart:io';

int _sequence = 0;

String uniqueTempPath(String path) =>
    '$path.$pid-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}.tmp';

String Function(String path) atomicTempPathFor = uniqueTempPath;

Future<void> Function(String from, String to) replaceFile =
    (from, to) => File(from).rename(to);

bool isAtomicTempNameOf(String fileName, String target) {
  final name = fileName.toLowerCase();
  return name.startsWith('${target.toLowerCase()}.') && name.endsWith('.tmp');
}

final _atomicWriteQueues = <String, Future<void>>{};
const _transientWindowsRenameErrors = {5, 32, 33};

Future<void> writeStringAtomically(String path, String contents) {
  final key = _atomicWriteKey(path);
  final previous = _atomicWriteQueues[key] ?? Future<void>.value();
  final result = previous.then((_) => _writeStringAtomically(path, contents));
  final tail = result.then<void>((_) {}, onError: (Object _) {});
  _atomicWriteQueues[key] = tail;
  tail.whenComplete(() {
    if (identical(_atomicWriteQueues[key], tail)) {
      _atomicWriteQueues.remove(key);
    }
  });
  return result;
}

String _atomicWriteKey(String path) {
  final absolute = File(path).absolute.path;
  return Platform.isWindows
      ? absolute.replaceAll('/', r'\').toLowerCase()
      : absolute;
}

Future<void> _writeStringAtomically(String path, String contents) async {
  final temp = File(atomicTempPathFor(path));
  try {
    await temp.writeAsString(contents, flush: true);
    await _renameWithRetry(temp, path);
  } catch (_) {
    await _deleteQuietly(temp);
    rethrow;
  }
}

Future<void> _renameWithRetry(File temp, String path) async {
  for (var attempt = 1;; attempt++) {
    try {
      await temp.rename(path);
      return;
    } on FileSystemException catch (e) {
      final transient = Platform.isWindows &&
          _transientWindowsRenameErrors.contains(e.osError?.errorCode);
      if (!transient || attempt >= 5) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 25 * attempt));
    }
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    return;
  }
}
