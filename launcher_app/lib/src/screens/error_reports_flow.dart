import 'package:flutter/widgets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/error_reports_controller.dart';
import '../controllers/search_feedback_controller.dart';
import '../services/app_logger.dart';
import '../services/notices_seen_store.dart';
import '../widgets/widgets_exports.dart';

Future<bool> showErrorReportsIntroOnce(
  BuildContext context,
  NoticesSeenStore store, {
  bool readOnly = false,
  bool driveFull = false,
  Future<bool> Function()? waitUntilFree,
}) async {
  if (await store.hasSeen(NoticesSeenStore.errorReportsIntro)) return false;
  if (waitUntilFree != null && !await waitUntilFree()) return false;
  if (!context.mounted) return false;

  final t = context.strings.errorReports;
  await showSingleActionDialog(
    context: context,
    title: t.introDialogTitle,
    content: !readOnly
        ? t.introDialogContent
        : driveFull
            ? t.introDialogContentReadOnlyDriveFull
            : t.introDialogContentReadOnly,
    confirmText: t.introDialogConfirm,
  );
  await store.markSeen(NoticesSeenStore.errorReportsIntro);
  return true;
}

enum ReportOfferOutcome { notOffered, declined, otzariaOpened, collected }

Future<ReportOfferOutcome> offerErrorReportCollection(
  BuildContext context,
  ErrorReportsController controller, {
  bool readOnly = false,
  required Future<bool> Function() isOtzariaRunning,
  NoticesSeenStore? notices,
  SearchFeedbackController? searchFeedback,
}) async {
  if (readOnly) return ReportOfferOutcome.notOffered;
  if (await isOtzariaRunning()) return ReportOfferOutcome.notOffered;
  final count = await controller.pendingToOffer();
  final feedbackCount = await searchFeedback?.pendingToOffer() ?? 0;
  if (!context.mounted) return ReportOfferOutcome.notOffered;
  final t = context.strings.errorReports;
  const legacyKey = NoticesSeenStore.legacyReportsNotice;
  if (controller.unmigratedLegacy.isNotEmpty &&
      notices != null &&
      !await notices.hasSeen(legacyKey) &&
      context.mounted) {
    await showSingleActionDialog(
      context: context,
      title: t.legacyReportsDialogTitle,
      content: t.legacyReportsDialogContent,
      confirmText: t.introDialogConfirm,
    );
    await notices.markSeen(legacyKey);
    if (!context.mounted) return ReportOfferOutcome.notOffered;
  }
  if (count + feedbackCount <= 0) return ReportOfferOutcome.notOffered;
  if (await isOtzariaRunning() || !context.mounted) {
    return ReportOfferOutcome.notOffered;
  }

  final approved = await showTwoActionsDialog(
    context: context,
    title: feedbackCount > 0 ? t.collectAllDialogTitle : t.collectDialogTitle,
    content: [
      if (count > 0) t.collectDialogContent(count),
      if (feedbackCount > 0)
        context.strings.libraryDomain
            .semanticFeedbackCollectBody(feedbackCount),
    ].join('\n\n'),
    cancelText: t.collectLater,
    confirmText: t.collectConfirm,
  );
  if (!approved) {
    if (count > 0) controller.markDeclined(count);
    if (feedbackCount > 0) searchFeedback?.markDeclined(feedbackCount);
    return ReportOfferOutcome.declined;
  }

  final s = AppL10n.strings.errorReports;
  if (await isOtzariaRunning()) {
    UiSnack.show(s.collectOtzariaOpenSnack);
    return ReportOfferOutcome.otzariaOpened;
  }

  final outcome =
      count > 0 ? await controller.collect() : (collected: 0, error: null);
  final error = outcome.error;
  final lines = <String>[];
  if (count > 0) {
    lines.add(error == null
        ? s.collectedSnack(outcome.collected)
        : outcome.collected > 0
            ? s.collectPartialSnack(outcome.collected, error)
            : s.collectFailedSnack(error));
  }
  var feedbackFailed = false;
  var feedbackCollected = 0;
  if (feedbackCount > 0 && searchFeedback != null) {
    final libraryStrings = AppL10n.strings.libraryDomain;
    try {
      if (!await isOtzariaRunning()) {
        feedbackCollected = await searchFeedback.collect();
      }
      lines.add(feedbackCollected > 0
          ? libraryStrings.semanticFeedbackCollected(feedbackCollected)
          : libraryStrings.semanticFeedbackNotCollected);
    } catch (error) {
      AppLogger.maybeInstance?.error('איסוף משוב החיפוש נכשל', error);
      feedbackFailed = true;
      lines.add(libraryStrings.semanticFeedbackFailed);
    }
  }
  final message = lines.join('\n');
  if (error != null || feedbackFailed) {
    UiSnack.showError(message);
  } else if (feedbackCount > 0 && feedbackCollected == 0) {
    UiSnack.show(message);
  } else {
    UiSnack.showSuccess(message);
  }
  return ReportOfferOutcome.collected;
}
