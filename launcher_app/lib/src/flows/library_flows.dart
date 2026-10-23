import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/library_module_controller.dart';
import '../services/byte_size.dart';
import '../widgets/widgets_exports.dart';

Widget libraryApplyProgressRow(
  BuildContext context,
  LibraryModuleController c,
) =>
    ListenableBuilder(
      listenable: c.progress,
      builder: (context, _) => InfoProgressRow(
        stage: c.stageText ?? context.strings.libraryScreen.updatingProgress,
        progress: c.applyProgress,
        detail: formatBytesProgress(c.applyReceivedBytes, c.applyTotalBytes),
        warning: context.strings.home.doNotRemoveDriveWarning,
      ),
    );

/// "מה חדש בספרייה" — ההערות של כל הגרסאות שבטווח, החדשה קודם.
Future<void> showLibraryChangesDialog(
  BuildContext context,
  LibraryModuleController library,
) async {
  final notes = library.changesNotes;
  final parts = <String>[];
  for (final note in notes) {
    try {
      final markdown = (await note.readMarkdown()).trim();
      if (markdown.isNotEmpty) parts.add(markdown);
    } on FileSystemException {
      // כונן שנשלף — מה שנקרא מוצג, והשאר נאמר כ"לא נמצא".
    }
  }
  if (!context.mounted) return;
  final t = context.strings.libraryScreen;
  await showSingleActionDialog(
    context: context,
    title: t.changesTitle,
    confirmText: context.strings.common.close,
    customContent: LibraryChangesView(
      markdowns: parts,
      emptyText: t.changesNotFound,
      note: library.changesNotesPartial
          ? t.changesPartial(notes.length, library.changesNotesRange)
          : null,
    ),
  );
}
