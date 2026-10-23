import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/download_plan.dart' show MirrorComponent;
import '../../services/byte_size.dart';
import '../../shell/shell_keys.dart';
import '../../shell/shell_tasks.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'task_parts.dart';
import 'transfer_rate.dart';

/// מה שמסך ההורדה קורא בכל דיווח התקדמות — נבנה מהקונטרולרים בתוך
/// `ListenableBuilder` על ה-progress שלהם.
class DownloadSnapshot {
  const DownloadSnapshot({
    this.current,
    this.fraction,
    this.received,
    this.total,
  });

  final MirrorComponent? current;
  final double? fraction;
  final int? received;
  final int? total;
}

/// אחרי ההורדה: מה אפשר לעשות במחשב הזה.
enum DownloadHereOffer { none, update, install }

/// מה שמוצג במסך הסיום על כל רכיב שירד.
class DownloadDoneInfo {
  const DownloadDoneInfo({
    this.appVersion,
    this.libraryVersion,
    this.pluginCount,
    this.offer = DownloadHereOffer.none,
  });

  final String? appVersion;
  final int? libraryVersion;
  final int? pluginCount;
  final DownloadHereOffer offer;
}

class DownloadTaskActions {
  const DownloadTaskActions({
    required this.onAnswer,
    required this.onCancel,
    required this.onRetry,
    required this.onHome,
    required this.onHere,
  });

  /// התשובה לשאלת החיפוש החכם; `null` = חזרה.
  final ValueChanged<bool?> onAnswer;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  /// "לעדכן גם במחשב הזה" / "להתקין את אוצריא גם כאן".
  final VoidCallback onHere;
}

/// מסך המשימה "הורדה לכונן": שאלה, התקדמות, בוטל, הסתיים או נכשל.
class DownloadTaskView extends StatelessWidget {
  const DownloadTaskView({
    super.key,
    required this.task,
    required this.progress,
    required this.snapshot,
    required this.actions,
    this.cancelling = false,
    this.done = const DownloadDoneInfo(),
    this.clock,
  });

  final DownloadTask task;
  final Listenable progress;
  final DownloadSnapshot Function() snapshot;
  final DownloadTaskActions actions;
  final bool cancelling;
  final DownloadDoneInfo done;

  /// לבדיקות של מד המהירות.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => switch (task.phase) {
        DownloadTaskPhase.question => _SemanticQuestion(actions: actions),
        DownloadTaskPhase.preparing => const _Preparing(),
        DownloadTaskPhase.running => _DownloadProgress(
            components: task.components,
            progress: progress,
            snapshot: snapshot,
            cancelling: cancelling,
            onCancel: actions.onCancel,
            clock: clock,
          ),
        DownloadTaskPhase.cancelled => _cancelled(context),
        DownloadTaskPhase.done => _done(context),
        DownloadTaskPhase.failed => _failed(context),
      };

  Widget _cancelled(BuildContext context) {
    final t = context.strings.task;
    return TaskResult(
      badge: const ResultBadge(
        kind: ResultBadgeKind.calm,
        icon: FluentIcons.arrow_reset_24_regular,
      ),
      title: t.cancelledTitle,
      body: task.revertFailed ? t.cancelledRevertFailedBody : t.cancelledBody,
      actions: [
        ActionButton.recommended(
          key: ShellKeys.taskPrimary,
          text: t.downloadAgain,
          icon: FluentIcons.arrow_download_24_regular,
          size: ActionButtonSize.lg,
          autofocus: true,
          expand: true,
          onPressed: actions.onRetry,
        ),
        ActionButton.ghost(
          text: t.backHome,
          expand: true,
          onPressed: actions.onHome,
        ),
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final t = context.strings.task;
    final failure =
        task.failure ?? const DownloadFailure(DownloadFailureKind.other);
    final name = componentStepName(
      context,
      failure.components.firstOrNull ?? MirrorComponent.library,
    );
    final retry = ActionButton.recommended(
      key: ShellKeys.taskPrimary,
      text: context.strings.common.retry,
      icon: FluentIcons.arrow_clockwise_24_regular,
      size: ActionButtonSize.lg,
      autofocus: true,
      expand: true,
      onPressed: actions.onRetry,
    );
    final home = ActionButton.ghost(
      text: t.backToHomePage,
      expand: true,
      onPressed: actions.onHome,
    );
    final details = failure.details;
    final tech = [if (details != null) TechDetails(text: details)];
    return switch (failure.kind) {
      DownloadFailureKind.network => TaskResult(
          badge: const ResultBadge(
            kind: ResultBadgeKind.calm,
            icon: FluentIcons.wifi_off_24_regular,
          ),
          title: t.networkTitle,
          body: t.networkBody(name),
          extra: tech,
          actions: [retry, home],
        ),
      DownloadFailureKind.shabbat => TaskResult(
          badge: const ResultBadge(
            kind: ResultBadgeKind.calm,
            icon: FluentIcons.weather_moon_24_regular,
          ),
          title: t.shabbatTitle,
          body: t.shabbatBody,
          actions: [
            ActionButton.recommended(
              key: ShellKeys.taskPrimary,
              text: t.backToHomePage,
              size: ActionButtonSize.lg,
              autofocus: true,
              expand: true,
              onPressed: actions.onHome,
            ),
          ],
        ),
      DownloadFailureKind.diskSpace => TaskResult(
          badge: const ResultBadge(
            kind: ResultBadgeKind.calm,
            icon: FluentIcons.storage_24_regular,
          ),
          title: t.spaceTitle,
          body: t.spaceBody('${failure.needed}', '${failure.free}'),
          actions: [retry, home],
        ),
      DownloadFailureKind.snapshot => TaskResult(
          badge: const ResultBadge(
            kind: ResultBadgeKind.error,
            icon: FluentIcons.important_24_filled,
          ),
          title: t.snapshotTitle,
          body: t.snapshotBody,
          extra: tech,
          actions: [retry, home],
        ),
      DownloadFailureKind.other => TaskResult(
          badge: const ResultBadge(
            kind: ResultBadgeKind.error,
            icon: FluentIcons.important_24_filled,
          ),
          title: t.otherTitle(name),
          body: t.otherBody,
          extra: tech,
          actions: [retry, home],
        ),
    };
  }

  Widget _done(BuildContext context) {
    final t = context.strings.task;
    final cs = Theme.of(context).colorScheme;
    final skipped = task.skipped
        .where((c) => !task.components.contains(c))
        .map((c) => componentName(context, c))
        .toList();
    String? value(MirrorComponent c) => switch (c) {
          MirrorComponent.app =>
            done.appVersion == null ? null : t.doneAppValue(done.appVersion!),
          MirrorComponent.library => done.libraryVersion == null
              ? null
              : t.doneLibraryValue(done.libraryVersion!),
          MirrorComponent.plugins => done.pluginCount == null
              ? t.donePluginsUpdated
              : t.donePluginsValue(done.pluginCount!),
        };
    final here = switch (done.offer) {
      DownloadHereOffer.update => [
          ActionButton.recommended(
            key: ShellKeys.taskPrimary,
            text: t.updateHereToo,
            size: ActionButtonSize.lg,
            autofocus: true,
            expand: true,
            onPressed: actions.onHere,
          ),
          ActionButton.ghost(
            text: t.backToHomePage,
            expand: true,
            onPressed: actions.onHome,
          ),
        ],
      DownloadHereOffer.install => [
          ActionButton.recommended(
            key: ShellKeys.taskPrimary,
            text: t.finish,
            size: ActionButtonSize.lg,
            autofocus: true,
            expand: true,
            onPressed: actions.onHome,
          ),
          ActionButton.ghost(
            text: t.installHereToo,
            expand: true,
            onPressed: actions.onHere,
          ),
        ],
      DownloadHereOffer.none => [
          ActionButton.recommended(
            key: ShellKeys.taskPrimary,
            text: t.finish,
            size: ActionButtonSize.lg,
            autofocus: true,
            expand: true,
            onPressed: actions.onHome,
          ),
        ],
    };
    return TaskResult(
      wide: true,
      badge: const ResultBadge(
        kind: ResultBadgeKind.ok,
        icon: FluentIcons.checkmark_24_regular,
      ),
      title: t.doneTitle,
      body: t.doneBody,
      extra: [
        if (task.components.isNotEmpty) ...[
          const SizedBox(height: 20),
          RowsCard(
            children: [
              for (final c in task.components)
                AppRow(
                  leading: IconTile(icon: componentIcon(c)),
                  label: componentName(context, c),
                  title: value(c) ?? t.stageDone(null),
                ),
            ],
          ),
        ],
        if (skipped.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            t.doneSkipped(skipped.join(', ')),
            textAlign: TextAlign.center,
            style: AppTextStyles.small.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        TaskGuide(
          title: t.whatNow,
          children: [
            GuideStep(
              number: 1,
              text: t.whatNowEject,
              hint: t.whatNowEjectHint,
            ),
            GuideStep(number: 2, text: t.whatNowConnect),
            GuideStep(number: 3, text: t.whatNowOpen),
          ],
        ),
      ],
      actions: here,
    );
  }
}

String componentName(BuildContext context, MirrorComponent c) {
  final t = context.strings.task;
  return switch (c) {
    MirrorComponent.app => t.componentApp,
    MirrorComponent.library => t.componentLibrary,
    MirrorComponent.plugins => t.componentPlugins,
  };
}

String componentStepName(BuildContext context, MirrorComponent c) {
  final t = context.strings.task;
  return switch (c) {
    MirrorComponent.app => t.stepApp,
    MirrorComponent.library => t.stepLibrary,
    MirrorComponent.plugins => t.stepPlugins,
  };
}

IconData componentIcon(MirrorComponent c) => switch (c) {
      MirrorComponent.app => FluentIcons.desktop_24_regular,
      MirrorComponent.library => FluentIcons.library_24_regular,
      MirrorComponent.plugins => FluentIcons.puzzle_piece_24_regular,
    };

class _SemanticQuestion extends StatefulWidget {
  const _SemanticQuestion({required this.actions});

  final DownloadTaskActions actions;

  @override
  State<_SemanticQuestion> createState() => _SemanticQuestionState();
}

class _SemanticQuestionState extends State<_SemanticQuestion> {
  /// המומלץ מסומן מראש: בלי חיפוש חכם.
  bool _semantic = false;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.task;
    return TaskFrame(
      start: ActionButton.ghost(
        text: t.back,
        onPressed: () => widget.actions.onAnswer(null),
      ),
      end: ActionButton.recommended(
        key: ShellKeys.taskPrimary,
        text: t.startDownload,
        autofocus: true,
        onPressed: () => widget.actions.onAnswer(_semantic),
      ),
      child: Column(
        children: [
          TaskHeading(
            title: t.semanticTitle,
            body: t.semanticBody,
            hint: t.semanticHint,
          ),
          const SizedBox(height: 24),
          OptionCard(
            icon: FluentIcons.search_24_regular,
            title: t.semanticNoTitle,
            description: t.semanticNoBody,
            sizeLine: t.semanticNoSize,
            selected: !_semantic,
            onSelected: () => setState(() => _semantic = false),
          ),
          const SizedBox(height: 10),
          OptionCard(
            icon: FluentIcons.sparkle_24_regular,
            title: t.semanticYesTitle,
            description: t.semanticYesBody,
            selected: _semantic,
            onSelected: () => setState(() => _semantic = true),
          ),
        ],
      ),
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    final t = context.strings.task;
    return TaskFrame(
      child: Column(
        children: [
          TaskHeading(title: t.preparingTitle, body: t.preparingBody),
          const SizedBox(height: 40),
          const AppProgressBar(),
        ],
      ),
    );
  }
}

class _DownloadProgress extends StatefulWidget {
  const _DownloadProgress({
    required this.components,
    required this.progress,
    required this.snapshot,
    required this.cancelling,
    required this.onCancel,
    this.clock,
  });

  final List<MirrorComponent> components;
  final Listenable progress;
  final DownloadSnapshot Function() snapshot;
  final bool cancelling;
  final VoidCallback onCancel;
  final DateTime Function()? clock;

  @override
  State<_DownloadProgress> createState() => _DownloadProgressState();
}

class _DownloadProgressState extends State<_DownloadProgress> {
  late final TransferRateMeter _meter = TransferRateMeter(clock: widget.clock);
  MirrorComponent? _measuring;

  /// הגודל האחרון שנראה לכל רכיב — לשורה "ירד · X" אחרי שעבר.
  final Map<MirrorComponent, int> _sizes = {};

  @override
  Widget build(BuildContext context) {
    final t = context.strings.task;
    return TaskFrame(
      start: const SizedBox.shrink(),
      end: ActionButton.neutral(
        key: ShellKeys.taskCancel,
        text: widget.cancelling ? t.cancelling : context.strings.common.cancel,
        onPressed: widget.cancelling ? null : widget.onCancel,
      ),
      child: ListenableBuilder(
        listenable: widget.progress,
        builder: (context, _) => _content(context, widget.snapshot()),
      ),
    );
  }

  Widget _content(BuildContext context, DownloadSnapshot s) {
    final t = context.strings.task;
    final cs = Theme.of(context).colorScheme;
    final components = widget.components;
    final current = s.current;
    if (current != _measuring) {
      _meter.reset();
      _measuring = current;
    }
    final received = s.received;
    final total = s.total;
    if (current != null && received != null) {
      _meter.add(received);
      if (total != null && total > 0) _sizes[current] = total;
    }
    final index = current == null ? -1 : components.indexOf(current);
    final fraction = s.fraction?.clamp(0.0, 1.0);
    final rate = _meter.bytesPerSecond;
    final left = total != null && total > 0 ? _meter.remaining(total) : null;
    final shown = current ?? components.firstOrNull;

    return Column(
      children: [
        TaskHeading(title: t.downloadingTitle, body: t.downloadingBody),
        const SizedBox(height: 24),
        Text(
          fraction == null ? '…' : '${(fraction * 100).floor()}%',
          textDirection: TextDirection.ltr,
          style: AppTextStyles.percent.copyWith(color: cs.primary),
        ),
        if (shown != null) ...[
          const SizedBox(height: 4),
          Text(
            t.downloadingStep(
              componentStepName(context, shown),
              (index < 0 ? 0 : index) + 1,
              components.length,
            ),
            style: AppTextStyles.body.copyWith(color: cs.onSurface),
          ),
        ],
        const SizedBox(height: 16),
        AppProgressBar(value: fraction),
        if (rate != null) ...[
          const SizedBox(height: 16),
          Text(
            [
              t.transferRate(formatBytes(rate.round())),
              if (left != null) t.minutesLeft((left.inSeconds / 60).ceil()),
            ].join(' · '),
            style: AppTextStyles.small.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (current != null && received != null && total != null && total > 0)
          Padding(
            padding: EdgeInsets.only(top: rate == null ? 16 : 4),
            child: Text(
              t.bytesLine(
                componentName(context, current),
                formatBytes(received),
                formatBytes(total),
              ),
              style: AppTextStyles.small.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 24),
        RowsCard(
          children: [
            for (final (i, c) in components.indexed)
              StageRow(
                icon: componentIcon(c),
                title: componentName(context, c),
                state: i < index
                    ? StageState.done
                    : i == index
                        ? StageState.current
                        : StageState.waiting,
                detail: i < index
                    ? t.stageDone(
                        _sizes[c] == null ? null : formatBytes(_sizes[c]!),
                      )
                    : i == index
                        ? (fraction == null
                            ? null
                            : '${(fraction * 100).floor()}%')
                        : t.stageWaiting,
              ),
          ],
        ),
      ],
    );
  }
}
