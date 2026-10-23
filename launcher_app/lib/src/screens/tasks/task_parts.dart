import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// כותרת שלב (`.ph-title`, `.ph-desc`, `.ph-hint`), ממורכזת.
class TaskHeading extends StatelessWidget {
  const TaskHeading({super.key, required this.title, this.body, this.hint});

  final String title;
  final String? body;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.pageTitle.copyWith(color: cs.onSurface),
        ),
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: AppTextStyles.small.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// דף תוצאה (`resPage`): תג, כותרת, גוף, תוספת, ועמודת פעולות ברוחב 352.
/// בחלון צר הפעולות קבועות בתחתית (`.win.narrow .res-actions`), כדי שהפעולה
/// הראשית תיראה בלי גלילה.
class TaskResult extends StatelessWidget {
  const TaskResult({
    super.key,
    required this.badge,
    required this.title,
    required this.body,
    required this.actions,
    this.extra = const [],
    this.wide = false,
  });

  final Widget badge;
  final String title;
  final String body;
  final List<Widget> extra;
  final List<Widget> actions;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final narrow = TaskFrame.isNarrow(context);
    final content = Column(
      children: [
        badge,
        SizedBox(height: narrow ? 12 : 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.pageTitle.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        ...extra,
      ],
    );
    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, action) in actions.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          SizedBox(width: 352, child: action),
        ],
      ],
    );
    if (!narrow) {
      return TaskFrame(
        center: true,
        wide: wide,
        child: Column(
          children: [content, const SizedBox(height: 24), buttons],
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: TaskFrame.mainPadding(context),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 560 : 460),
                child: content,
              ),
            ),
          ),
        ),
        Container(
          key: const ValueKey('task.result.actions'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: AppSurfaces.panelBackground(context),
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: buttons,
        ),
      ],
    );
  }
}

/// "פרטים טכניים" מקופלים, עם העתקה (`.tech`).
class TechDetails extends StatefulWidget {
  const TechDetails({super.key, required this.text});

  final String text;

  @override
  State<TechDetails> createState() => _TechDetailsState();
}

class _TechDetailsState extends State<TechDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = context.strings.task;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: TextLink(
              text: _open ? t.hideTechDetails : t.techDetails,
              onTap: () => setState(() => _open = !_open),
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppSurfaces.card(context),
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: SelectableText(
                widget.text,
                textDirection: textDirectionOf(widget.text),
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: ActionButton.ghost(
                text: t.copyDetails,
                icon: FluentIcons.copy_20_regular,
                size: ActionButtonSize.sm,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.text));
                  UiSnack.show(t.detailsCopied);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final RegExp _rtlChar = RegExp('[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');
final RegExp _ltrChar = RegExp('[A-Za-z\u00C0-\u024F]');

/// הכיוון לפי התו החזק הראשון — "library: Bad state: אין מספיק מקום" הוא
/// LTR, והודעה עברית מקומית היא RTL, ופיסוק לא מתהפך באף אחת.
TextDirection textDirectionOf(String text) {
  final rtl = _rtlChar.firstMatch(text)?.start;
  final ltr = _ltrChar.firstMatch(text)?.start;
  if (rtl == null) return TextDirection.ltr;
  if (ltr == null) return TextDirection.rtl;
  return rtl < ltr ? TextDirection.rtl : TextDirection.ltr;
}

/// "אל תנתקו את הכונן עד הסוף" (`.keep`).
class KeepDriveNotice extends StatelessWidget {
  const KeepDriveNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppSurfaces.keepNotice(context),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.usb_stick_20_regular,
            size: 18,
            color: cs.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              context.strings.task.keepDrive,
              style: AppTextStyles.small.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: AppTextStyles.semibold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// כרטיס הדרכה (`.guide`): כותרת קטנה ושלבים ממוספרים.
class TaskGuide extends StatelessWidget {
  const TaskGuide({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: AppTextStyles.small.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: AppTextStyles.semibold,
              ),
            ),
            const SizedBox(height: 8),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// שלב ממוספר בכרטיס הדרכה (`.gstep`).
class GuideStep extends StatelessWidget {
  const GuideStep({
    super.key,
    required this.number,
    required this.text,
    this.hint,
    this.strong,
  });

  final int number;
  final String text;
  final String? hint;

  /// חלק מ-[text] שמודגש — למשל שם הכלי.
  final String? strong;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.secondaryContainer,
            ),
            child: Text(
              '$number',
              style: AppTextStyles.meta.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: AppTextStyles.semibold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  ..._spans(),
                  if (hint != null)
                    TextSpan(
                      text: ' $hint',
                      style: AppTextStyles.small.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              style: AppTextStyles.body.copyWith(color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _spans() {
    final bold = strong;
    final at = bold == null ? -1 : text.indexOf(bold);
    if (bold == null || at < 0) return [TextSpan(text: text)];
    return [
      TextSpan(text: text.substring(0, at)),
      TextSpan(
        text: bold,
        style: const TextStyle(fontWeight: AppTextStyles.semibold),
      ),
      TextSpan(text: text.substring(at + bold.length)),
    ];
  }
}

/// נקודות השלבים (`.dots`): הנוכחי ארוך, שהסתיימו בצבע dotDone.
class StepDots extends StatelessWidget {
  const StepDots({super.key, required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Container(
            width: i == current ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: i == current
                  ? cs.primary
                  : i < current
                      ? palette.dotDone
                      : cs.outlineVariant,
            ),
          ),
        ],
      ],
    );
  }
}
