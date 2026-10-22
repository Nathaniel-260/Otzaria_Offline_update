import 'dart:io';

import 'package:seforim_library_updater/seforim_library_updater.dart'
    show
        LocalDbVersionReader,
        LogicalContentHasher,
        hashRowOrderForSchemaVersion,
        hashTableOrderForSchemaVersion,
        kHashRowOrder,
        kHashTableOrder;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// כלי עזר: מחשב את ה-logical content hash של DB נתון ומדפיס אותו.
void main(List<String> args) {
  // ה-hash כולל את שם כל טבלה בסדר, ולכן הסדר נבחר לפי סכמת ה-DB עצמו.
  final schema = const LocalDbVersionReader().read(args.single).schemaVersion;
  final order =
      schema == null ? kHashTableOrder : hashTableOrderForSchemaVersion(schema);
  final rows =
      schema == null ? kHashRowOrder : hashRowOrderForSchemaVersion(schema);
  final db = sqlite3.sqlite3.open(args.single, mode: sqlite3.OpenMode.readOnly);
  try {
    final sw = Stopwatch()..start();
    final hash = const LogicalContentHasher()
        .compute(db, tableOrder: order, rowOrder: rows);
    stdout.writeln('$hash  ${args.single}  (${sw.elapsed})');
  } finally {
    db.close();
  }
}
