import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/error_reports_controller.dart';
import '../../controllers/search_feedback_controller.dart';
import '../../shell/shell_keys.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/widgets_exports.dart';
import '../reports_upload_section.dart';

/// דף הדיווחים: מה ממתין באוצריא לאיסוף, ומה בכונן מחכה לשליחה.
class ReportsSection extends StatelessWidget {
  const ReportsSection({
    super.key,
    required this.errorReports,
    required this.searchFeedback,
    required this.connection,
    required this.isUploadingAll,
    required this.busy,
    required this.reportsToCollect,
    this.searchRecordsToCollect = 0,
    required this.onCollect,
    required this.onUpload,
    this.onStop,
    this.readOnly = false,
    this.driveFull = false,
  });

  final ErrorReportsController? errorReports;
  final SearchFeedbackController? searchFeedback;

  /// `null` — עוד לא נבדק חיבור; ראו `onlineState`.
  final bool? connection;
  final bool isUploadingAll;

  /// פעולה ארוכה רצה — אין איסוף ואין שליחה עכשיו.
  final bool busy;

  /// דיווחי תקלות שממתינים באוצריא, ורשומות החיפוש החכם שלצידם.
  final int reportsToCollect;
  final int searchRecordsToCollect;
  final VoidCallback onCollect;
  final Future<void> Function()? onUpload;
  final VoidCallback? onStop;

  /// כונן מוגן או מלא: אין איסוף ואין שליחה (שליחה מוחקת מהכונן).
  final bool readOnly;
  final bool driveFull;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = context.strings.guide;
    final sub = AppTextStyles.rowSub.copyWith(color: cs.onSurfaceVariant);
    final collecting = reportsToCollect + searchRecordsToCollect;
    final listenable = Listenable.merge([
      if (errorReports != null) errorReports!,
      if (searchFeedback != null) searchFeedback!,
    ]);

    return ScreenBody(
      title: g.tileReports,
      children: [
        const SizedBox(height: AppTokens.spaceMD),
        if (collecting > 0 && !readOnly) ...[
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconTile(icon: FluentIcons.arrow_upload_24_regular),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.reportsCollectTitle(
                          reports: reportsToCollect,
                          searchRecords: searchRecordsToCollect,
                        ),
                        style: AppTextStyles.rowTitle.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(g.reportsCollectBody, style: sub),
                      // הגילוי הוא ההסכמה: אין דו-שיח אחרי הלחיצה.
                      KeyedSubtree(
                        key: ShellKeys.reportsDisclosure,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (reportsToCollect > 0)
                              _bullet(g.reportsDisclosureReports, sub),
                            if (searchRecordsToCollect > 0)
                              _bullet(g.reportsDisclosureSearch, sub),
                            const SizedBox(height: 6),
                            Text(g.reportsDisclosureStorage, style: sub),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: ActionButton.neutral(
                          key: ShellKeys.reportsCollect,
                          text: g.reportsCollectButton,
                          onPressed: busy ? null : onCollect,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (readOnly)
          Text(
            g.reportsLockedNote(driveFull: driveFull),
            style: AppTextStyles.small.copyWith(color: cs.onSurfaceVariant),
          )
        else
          ListenableBuilder(
            listenable: listenable,
            builder: (context, _) {
              final waiting = (errorReports?.outboxCount ?? 0) +
                  (searchFeedback?.outboxCount ?? 0);
              final uploading = isUploadingAll ||
                  (errorReports?.isUploading ?? false) ||
                  (searchFeedback?.isUploading ?? false);
              if (waiting <= 0 && !uploading) {
                return collecting > 0
                    ? const SizedBox.shrink()
                    : Text(
                        g.reportsNothing,
                        style: AppTextStyles.small.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      );
              }
              return AppCard(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ReportsUploadSection(
                  errorReports: errorReports,
                  searchFeedback: searchFeedback,
                  connection: connection,
                  isUploadingAll: isUploadingAll,
                  busy: busy,
                  onUpload: onUpload,
                  onStop: onStop,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _bullet(String text, TextStyle style) => Padding(
        padding: const EdgeInsetsDirectional.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: style),
            Expanded(child: Text(text, style: style)),
          ],
        ),
      );
}
