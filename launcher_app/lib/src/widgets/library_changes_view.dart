import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

enum LibraryChangesLineKind { title, subtitle, section, item, text, separator }

class LibraryChangesLine {
  const LibraryChangesLine(this.kind, this.text);

  final LibraryChangesLineKind kind;
  final String text;
}

final _headingLine = RegExp(r'^(#{1,6})\s+(.*)$');
final _itemLine = RegExp(r'^[*\-+]\s+(.*)$');
final _ruleLine = RegExp(r'^-{3,}$');

String _stripEmphasis(String text) => text.replaceAll('**', '').trim();

/// מפרק את `library-changes.md` של כל release (כותרת, תאריך מודגש, סעיפים
/// ופריטי רשימה) לשורות שטוחות, כדי שרשימה של אלפי ספרים תיבנה בעצלות.
List<LibraryChangesLine> parseLibraryChanges(List<String> notes) {
  final lines = <LibraryChangesLine>[];
  for (final note in notes) {
    if (lines.isNotEmpty) {
      lines.add(const LibraryChangesLine(LibraryChangesLineKind.separator, ''));
    }
    for (final raw in note.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || _ruleLine.hasMatch(line)) continue;
      final heading = _headingLine.firstMatch(line);
      if (heading != null) {
        lines.add(LibraryChangesLine(
          heading.group(1)!.length == 1
              ? LibraryChangesLineKind.title
              : LibraryChangesLineKind.section,
          _stripEmphasis(heading.group(2)!),
        ));
        continue;
      }
      final item = _itemLine.firstMatch(line);
      if (item != null) {
        lines.add(LibraryChangesLine(
          LibraryChangesLineKind.item,
          _stripEmphasis(item.group(1)!),
        ));
        continue;
      }
      final bold =
          line.startsWith('**') && line.endsWith('**') && line.length > 4;
      lines.add(LibraryChangesLine(
        bold ? LibraryChangesLineKind.subtitle : LibraryChangesLineKind.text,
        _stripEmphasis(line),
      ));
    }
  }
  return lines;
}

/// "מה חדש בספרייה" בתוך דיאלוג: רשימה עצלה, ופירוק קובץ גדול מחוץ ל-isolate
/// של הממשק — רשימות של אלפי ספרים הקפיאו אותו כשנבנו בבת אחת.
class LibraryChangesView extends StatefulWidget {
  const LibraryChangesView({
    super.key,
    required this.markdowns,
    required this.emptyText,
    this.note,
  });

  final List<String> markdowns;
  final String emptyText;

  /// שורה מעל הרשימה — למשל שהרשימה חלקית.
  final String? note;

  /// מעל הגודל הזה הפירוק רץ ב-isolate.
  static const int parseInIsolateChars = 64 * 1024;

  @override
  State<LibraryChangesView> createState() => _LibraryChangesViewState();
}

class _LibraryChangesViewState extends State<LibraryChangesView> {
  // משותף ל-Scrollbar ול-ListView: בלעדיו גלגלת העכבר בדסקטופ זורקת
  // "ScrollController has no ScrollPosition attached".
  final ScrollController _scroll = ScrollController();
  List<LibraryChangesLine>? _lines;

  @override
  void initState() {
    super.initState();
    final chars = widget.markdowns.fold<int>(0, (n, e) => n + e.length);
    if (chars < LibraryChangesView.parseInIsolateChars) {
      _lines = parseLibraryChanges(widget.markdowns);
    } else {
      compute(parseLibraryChanges, widget.markdowns).then((lines) {
        if (mounted) setState(() => _lines = lines);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.6;
    final note = widget.note;
    return SizedBox(
      width: 600,
      height: height < 480 ? height : 480,
      child: lines == null
          ? const Center(child: CircularProgressIndicator())
          : lines.isEmpty
              ? Text(widget.emptyText, style: theme.textTheme.bodyMedium)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTokens.spaceSM,
                        ),
                        child: Text(note, style: theme.textTheme.bodySmall),
                      ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scroll,
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount: lines.length,
                          itemBuilder: (context, index) =>
                              _LineView(line: lines[index]),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _LineView extends StatelessWidget {
  const _LineView({required this.line});

  final LibraryChangesLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final heading = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
    );
    return switch (line.kind) {
      LibraryChangesLineKind.title => Padding(
          padding: const EdgeInsets.only(
            top: AppTokens.spaceSM,
            bottom: AppTokens.spaceXS,
          ),
          child: Text(line.text, style: text.titleLarge?.merge(heading)),
        ),
      LibraryChangesLineKind.section => Padding(
          padding: const EdgeInsets.only(
            top: AppTokens.spaceSM,
            bottom: AppTokens.spaceXS,
          ),
          child: Text(line.text, style: text.titleMedium?.merge(heading)),
        ),
      LibraryChangesLineKind.subtitle => Text(
          line.text,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      LibraryChangesLineKind.item => Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppTokens.spaceMD,
            bottom: 2,
          ),
          child: Text('• ${line.text}', style: text.bodyMedium),
        ),
      LibraryChangesLineKind.text => Text(line.text, style: text.bodyMedium),
      LibraryChangesLineKind.separator => const Divider(
          height: AppTokens.spaceLG,
        ),
    };
  }
}
