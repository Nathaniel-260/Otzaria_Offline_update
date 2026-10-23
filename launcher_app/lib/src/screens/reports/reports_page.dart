import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/app_reports_controller.dart';
import '../../controllers/error_reports_controller.dart';
import '../../controllers/search_feedback_controller.dart';
import '../../shell/shell_keys.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/widgets_exports.dart';
import '../app_report/app_report_dialog.dart';
import '../app_report/app_reports_panel.dart';

/// דף הדיווחים: הדיווחים של אוצריא (איסוף לכונן ושליחה מהמחשב המחובר),
/// הדיווחים של הכלי על עצמו (תור והיסטוריה), ודיווח על בעיה בכלי.
class ReportsPage extends StatelessWidget {
  const ReportsPage({
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
    this.legacyNotice = false,
    this.onDismissLegacy,
    this.appReports,
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

  /// דיווחים ישנים (Hive) שאוצריא כבר אינה מעבירה.
  final bool legacyNotice;
  final VoidCallback? onDismissLegacy;

  /// הדיווחים של הכלי על עצמו — `null` בבדיקות.
  final AppReportsController? appReports;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.pages;
    final listenable = Listenable.merge([
      if (errorReports != null) errorReports!,
      if (searchFeedback != null) searchFeedback!,
    ]);
    final reports = appReports;

    return ScreenBody(
      title: context.strings.guide.tileReports,
      description: t.repDescription,
      children: [
        if (legacyNotice) _legacy(context),
        ListenableBuilder(
          listenable: listenable,
          builder: (context, _) => _statusCard(context),
        ),
        if (reports != null) AppReportsPanel(reports: reports),
        if (reports != null) ...[
          SectionLabel(t.repProblemSection),
          RowsCard(
            children: [
              AppRow(
                key: ShellKeys.reportsProblem,
                leading: const IconTile(
                  icon: FluentIcons.person_feedback_24_regular,
                ),
                title: t.repProblemTitle,
                subtitle: t.repProblemBody,
                onTap: () => _openForm(context, reports),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _openForm(
    BuildContext context,
    AppReportsController reports,
  ) async {
    await showAppReportDialog(context, reports: reports);
    await reports.refresh();
  }

  Widget _legacy(BuildContext context) {
    final t = context.strings.errorReports;
    return NoticeBanner(
      key: ShellKeys.reportsLegacy,
      leading: const IconTile(
        icon: FluentIcons.history_24_regular,
        tone: IconTileTone.quiet,
      ),
      title: t.legacyReportsDialogTitle,
      body: t.legacyReportsDialogContent,
      actions: [
        ActionButton.ghost(
          text: t.introDialogConfirm,
          size: ActionButtonSize.sm,
          onPressed: onDismissLegacy,
        ),
      ],
    );
  }

  Widget _statusCard(BuildContext context) {
    final t = context.strings.pages;
    final g = context.strings.guide;
    final e = context.strings.errorReports;
    final cs = Theme.of(context).colorScheme;
    final sub = AppTextStyles.rowSub.copyWith(color: cs.onSurfaceVariant);
    final reports = errorReports;
    final feedback = searchFeedback;
    final waitingReports = reports?.outboxCount ?? 0;
    final waitingFeedback = feedback?.outboxCount ?? 0;
    final waiting = waitingReports + waitingFeedback;
    final collecting = reportsToCollect + searchRecordsToCollect;
    final uploading = isUploadingAll ||
        (reports?.isUploading ?? false) ||
        (feedback?.isUploading ?? false);

    if (uploading) {
      final p = reports?.progress;
      final wait = p?.waitRemaining;
      final feedbackPhase =
          !(reports?.isUploading ?? false) && feedback?.isUploading == true;
      return StatusCard(
        icon: FluentIcons.send_24_regular,
        title: t.repSendingTitle,
        extra: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feedbackPhase
                    ? e.uploadingFeedbackStage
                    : wait != null
                        ? e.uploadWaitingStage(
                            (wait.inMilliseconds / 1000).ceil(),
                          )
                        : e.uploadingStage(p?.done ?? 0, p?.total ?? 0),
                style: sub,
              ),
              const SizedBox(height: 8),
              AppProgressBar(
                thin: true,
                value: feedbackPhase || p == null || p.total == 0
                    ? null
                    : p.done / p.total,
              ),
            ],
          ),
        ],
        actions: [
          ActionButton.neutral(
            key: ShellKeys.reportsStop,
            text: e.uploadStopButton,
            onPressed: () {
              onStop?.call();
              if (reports?.isUploading ?? false) reports!.stop();
              if (feedback?.isUploading ?? false) feedback!.stop();
            },
          ),
        ],
      );
    }

    if (readOnly) {
      return StatusCard(
        icon: FluentIcons.arrow_upload_24_regular,
        title: waiting > 0
            ? t.repStoredTitle(waiting)
            : collecting > 0
                ? g.reportsCollectTitle(
                    reports: reportsToCollect,
                    searchRecords: searchRecordsToCollect,
                  )
                : t.repNothingTitle,
        subtitle: g.reportsLockedNote(driveFull: driveFull),
        // בלי גילוי אין כפתור איסוף — גם לא מושבת.
        actions: [
          Text(t.repLockedShort(driveFull: driveFull), style: sub),
        ],
      );
    }

    if (collecting > 0) {
      return StatusCard(
        icon: FluentIcons.arrow_upload_24_regular,
        title: g.reportsCollectTitle(
          reports: reportsToCollect,
          searchRecords: searchRecordsToCollect,
        ),
        subtitle: [
          if (waiting > 0) t.repAlsoStored(waiting),
          g.reportsCollectBody,
        ].join(' '),
        extra: [
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
        ],
        actions: [
          ActionButton.recommended(
            key: ShellKeys.reportsCollect,
            text: g.reportsCollectButton,
            icon: FluentIcons.arrow_upload_24_regular,
            onPressed: busy ? null : onCollect,
          ),
        ],
      );
    }

    if (waiting > 0 && connection == true) {
      return StatusCard(
        icon: FluentIcons.send_24_regular,
        title: t.repWaitingTitle(waiting),
        subtitle: t.repWaitingBody(withSearch: waitingFeedback > 0),
        actions: [
          ActionButton.recommended(
            key: ShellKeys.reportsSend,
            text: t.repSendButton,
            icon: FluentIcons.send_24_regular,
            onPressed: busy || onUpload == null ? null : () => onUpload!(),
          ),
          ActionButton.ghost(
            text: t.repWhatIsSent,
            onPressed: () => _showDisclosure(
              context,
              reports: waitingReports > 0,
              search: waitingFeedback > 0,
            ),
          ),
        ],
      );
    }

    if (waiting > 0) {
      return StatusCard(
        icon: FluentIcons.arrow_upload_24_regular,
        title: t.repStoredTitle(waiting),
        subtitle: connection == null ? t.repUncheckedBody : t.repStoredBody,
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.info_16_regular,
                  size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(t.repOnlyOnline, style: sub),
            ],
          ),
        ],
      );
    }

    return StatusCard(
      icon: FluentIcons.checkmark_24_regular,
      quiet: true,
      title: t.repNothingTitle,
      subtitle: g.reportsNothing,
    );
  }

  Future<void> _showDisclosure(
    BuildContext context, {
    required bool reports,
    required bool search,
  }) {
    final g = context.strings.guide;
    return showSingleActionDialog(
      context: context,
      title: context.strings.pages.repWhatIsSent,
      content: [
        if (reports) g.reportsDisclosureReports,
        if (search) g.reportsDisclosureSearch,
        g.reportsDisclosureStorage,
      ].join('\n\n'),
      confirmText: context.strings.common.close,
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
