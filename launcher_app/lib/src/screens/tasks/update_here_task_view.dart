import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../screens/home/home_view_model.dart' show displayVersion;
import '../../shell/home_guidance.dart' show GuidanceItem;
import '../../shell/shell_keys.dart';
import '../../shell/shell_tasks.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'task_parts.dart';

/// התקדמות החלת הספרייה — נקראת בתוך `ListenableBuilder` על ה-progress.
class LibraryApplySnapshot {
  const LibraryApplySnapshot({this.fraction, this.stage});

  final double? fraction;
  final String? stage;
}

class UpdateHereActions {
  const UpdateHereActions({
    required this.onRespond,
    required this.onStopWaiting,
    required this.onFinishWithoutWaiting,
    required this.onLaunch,
    required this.onHome,
    required this.onRetry,
    required this.onOpenPage,
    this.onReindex,
    this.onRestartElevated,
    this.onLibraryChanges,
  });

  final ValueChanged<bool> onRespond;
  final VoidCallback onStopWaiting;
  final VoidCallback onFinishWithoutWaiting;
  final VoidCallback onLaunch;
  final VoidCallback onHome;
  final VoidCallback onRetry;

  /// "לדף הספרייה" / "לדף התוכנה" במסך הכשל.
  final ValueChanged<GuidanceItem> onOpenPage;

  /// `null` — אין בקשת אינדוקס שממתינה.
  final VoidCallback? onReindex;

  /// `null` — הכשל אינו על הרשאות, או שאי אפשר להרים כאן.
  final VoidCallback? onRestartElevated;

  /// `null` — אין "מה חדש" לספרייה שהותקנה.
  final VoidCallback? onLibraryChanges;
}

/// מסך המשימה "עדכון אוצריא במחשב הזה" (וגם "התקנת אוצריא").
class UpdateHereTaskView extends StatelessWidget {
  const UpdateHereTaskView({
    super.key,
    required this.task,
    required this.libraryProgress,
    required this.librarySnapshot,
    required this.actions,
  });

  final UpdateHereTask task;
  final Listenable libraryProgress;
  final LibraryApplySnapshot Function() librarySnapshot;
  final UpdateHereActions actions;

  @override
  Widget build(BuildContext context) => switch (task.phase) {
        UpdateHereTaskPhase.confirmElevatedOtherUser => _otherUser(context),
        UpdateHereTaskPhase.closeOtzaria when !task.closeAfterWizard =>
          _close(context),
        UpdateHereTaskPhase.closeOtzaria ||
        UpdateHereTaskPhase.running =>
          _running(context),
        UpdateHereTaskPhase.done => _done(context),
        UpdateHereTaskPhase.cancelledByUser => _cancelled(context),
        UpdateHereTaskPhase.failed => _failed(context),
      };

  Widget _otherUser(BuildContext context) {
    final t = context.strings.task;
    return TaskFrame(
      center: true,
      start: ActionButton.ghost(
        text: context.strings.common.cancel,
        onPressed: () => actions.onRespond(false),
      ),
      end: ActionButton.recommended(
        key: ShellKeys.taskPrimary,
        text: t.continueAnyway,
        autofocus: true,
        onPressed: () => actions.onRespond(true),
      ),
      child: Column(
        children: [
          const _BigTile(child: Icon(FluentIcons.person_24_regular, size: 32)),
          TaskHeading(
            title: t.otherUserTitle,
            body: t.otherUserBody,
            hint: t.otherUserHint,
          ),
        ],
      ),
    );
  }

  Widget _close(BuildContext context) {
    final t = context.strings.task;
    return TaskFrame(
      center: true,
      start: ActionButton.ghost(
        text: context.strings.common.cancel,
        onPressed: () => actions.onRespond(false),
      ),
      end: ActionButton.recommended(
        key: ShellKeys.taskPrimary,
        text: t.closeAndContinue,
        autofocus: true,
        onPressed: () => actions.onRespond(true),
      ),
      child: Column(
        children: [
          _BigTile(child: _logo(40)),
          TaskHeading(
            title: t.closeTitle,
            body: t.closeBody,
            hint: t.closeHint(
              plugins: task.stages.contains(GuidanceItem.plugins),
            ),
          ),
        ],
      ),
    );
  }

  Widget _running(BuildContext context) {
    final t = context.strings.task;
    final stage = task.currentStage;
    final closing = task.phase == UpdateHereTaskPhase.closeOtzaria;
    final first = task.firstInstall;
    final (title, body) = closing
        ? (t.closeTitle, t.closeAfterWizardBody)
        : switch (stage) {
            GuidanceItem.app => (
                first ? t.installingApp : t.updatingApp,
                first ? t.appWizardFirstBody : t.appWizardBody,
              ),
            GuidanceItem.library => (
                first ? t.installingLibrary : t.updatingLibrary,
                t.libraryBody,
              ),
            GuidanceItem.plugins || null => (t.sendingPlugins, t.pluginsBody),
          };
    final index = task.stageIndex.clamp(0, task.stages.length - 1);
    return TaskFrame(
      start: closing
          ? ActionButton.ghost(
              text: t.notNow,
              onPressed: () => actions.onRespond(false),
            )
          : null,
      end: closing
          ? ActionButton.recommended(
              key: ShellKeys.taskPrimary,
              text: t.closeAfterWizardButton,
              autofocus: true,
              onPressed: () => actions.onRespond(true),
            )
          : stage == GuidanceItem.plugins
              ? ActionButton.ghost(
                  key: ShellKeys.taskSecondary,
                  text: t.finishWithoutWaiting,
                  onPressed: actions.onFinishWithoutWaiting,
                )
              : null,
      child: Column(
        children: [
          StepDots(count: task.stages.length, current: index),
          const SizedBox(height: 8),
          Text(
            t.stepOf(index + 1, task.stages.length),
            style: AppTextStyles.meta.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TaskHeading(title: title, body: body),
          if (stage == GuidanceItem.library && !closing)
            const KeepDriveNotice(),
          const SizedBox(height: 24),
          RowsCard(
            children: [
              for (final (i, s) in task.stages.indexed)
                _stageRow(context, s, i, closing: closing),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stageRow(
    BuildContext context,
    GuidanceItem stage,
    int i, {
    required bool closing,
  }) {
    final t = context.strings.task;
    final cs = Theme.of(context).colorScheme;
    final state = i < task.stageIndex
        ? StageState.done
        : i == task.stageIndex
            ? StageState.current
            : StageState.waiting;
    final outcome = task.outcomes[stage];
    final version =
        task.appVersion == null ? null : displayVersion(task.appVersion!);
    switch (stage) {
      case GuidanceItem.app:
        return StageRow(
          icon: FluentIcons.desktop_24_regular,
          title: t.componentApp,
          state: state,
          detail: switch (state) {
            StageState.done => outcome == StageOutcome.stoppedWaiting
                ? t.appStoppedWaiting
                : version == null
                    ? t.stageDone(null)
                    : t.appInstalled(version),
            StageState.current => t.appWizardOpen,
            StageState.waiting =>
              version == null ? null : t.appVersion(version),
          },
          extra: state == StageState.current
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const AppProgressBar(thin: true),
                    const SizedBox(height: 6),
                    TextLink(
                      key: ShellKeys.taskStopWaiting,
                      text: t.stopWaiting,
                      style: AppTextStyles.meta,
                      onTap: task.stopWaitingRequested
                          ? null
                          : actions.onStopWaiting,
                    ),
                  ],
                )
              : null,
        );
      case GuidanceItem.library:
        final detail = task.firstInstall
            ? t.libraryFull
            : task.libraryVersion == null
                ? null
                : t.libraryVersion(task.libraryVersion!);
        if (state == StageState.current && !closing) {
          return ListenableBuilder(
            listenable: libraryProgress,
            builder: (context, _) {
              final s = librarySnapshot();
              final pct = s.fraction == null
                  ? null
                  : '${(s.fraction!.clamp(0.0, 1.0) * 100).floor()}%';
              return StageRow(
                icon: FluentIcons.library_24_regular,
                title: t.componentLibrary,
                state: state,
                detail: [if (pct != null) pct, if (detail != null) detail]
                    .join(' · '),
                extra: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    AppProgressBar(thin: true, value: s.fraction),
                    if (s.stage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        s.stage!,
                        style: AppTextStyles.meta.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        }
        return StageRow(
          icon: FluentIcons.library_24_regular,
          title: t.componentLibrary,
          state: state,
          detail: switch (state) {
            StageState.done => outcome == StageOutcome.skipped
                ? t.librarySkipped
                : t.libraryDone(detail ?? t.componentLibrary),
            StageState.current => t.libraryWaitingClose,
            StageState.waiting => detail,
          },
        );
      case GuidanceItem.plugins:
        return StageRow(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: t.componentPlugins,
          state: state,
          detail: switch (state) {
            StageState.done => t.pluginsSent,
            StageState.current => t.pluginsCurrent,
            StageState.waiting => t.pluginsWaiting(task.plugins.length),
          },
          extra: state == StageState.current
              ? _Deliveries(rows: task.plugins)
              : null,
        );
    }
  }

  Widget _done(BuildContext context) {
    final t = context.strings.task;
    final g = context.strings.guide;
    final cs = Theme.of(context).colorScheme;
    final plugins = task.stages.contains(GuidanceItem.plugins);
    final libraryInstalled =
        task.outcomes[GuidanceItem.library] == StageOutcome.done;
    final version =
        task.appVersion == null ? null : displayVersion(task.appVersion!);
    String rowValue(GuidanceItem s) => switch (s) {
          GuidanceItem.app => task.outcomes[s] == StageOutcome.stoppedWaiting
              ? t.appStoppedWaiting
              : version == null
                  ? t.stageDone(null)
                  : t.doneAppValue(version),
          GuidanceItem.library => task.outcomes[s] == StageOutcome.skipped
              ? t.librarySkipped
              : task.firstInstall
                  ? t.libraryFull
                  : task.libraryVersion == null
                      ? t.componentLibrary
                      : t.libraryVersion(task.libraryVersion!),
          GuidanceItem.plugins => task.plugins.map((p) => p.name).join(', '),
        };
    return TaskResult(
      badge: const ResultBadge(
        kind: ResultBadgeKind.ok,
        icon: FluentIcons.checkmark_24_regular,
      ),
      title: task.firstInstall ? t.installedTitle : t.updatedTitle,
      body: t.doneHereBody(
        firstInstall: task.firstInstall,
        withLibrary: libraryInstalled,
        plugins: plugins,
      ),
      extra: [
        const SizedBox(height: 20),
        RowsCard(
          children: [
            for (final s in task.stages)
              AppRow(
                leading: IconTile(
                  icon: switch (s) {
                    GuidanceItem.app => FluentIcons.desktop_24_regular,
                    GuidanceItem.library => FluentIcons.library_24_regular,
                    GuidanceItem.plugins => FluentIcons.puzzle_piece_24_regular,
                  },
                ),
                label: switch (s) {
                  GuidanceItem.app => t.componentApp,
                  GuidanceItem.library => t.componentLibrary,
                  GuidanceItem.plugins => t.componentPlugins,
                },
                title: rowValue(s),
                subtitle: s == GuidanceItem.plugins ? t.pluginsSent : null,
                trailing: Icon(
                  s == GuidanceItem.plugins
                      ? FluentIcons.send_24_regular
                      : FluentIcons.checkmark_circle_24_filled,
                  size: 22,
                  color: cs.primary,
                ),
              ),
          ],
        ),
        if (actions.onReindex != null && !task.firstInstall)
          TaskGuide(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.reindexTitle,
                          style: AppTextStyles.small.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: AppTextStyles.semibold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.reindexBody,
                          style: AppTextStyles.small.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ActionButton.neutral(
                    key: ShellKeys.taskReindex,
                    text: t.reindexButton,
                    size: ActionButtonSize.sm,
                    onPressed: actions.onReindex,
                  ),
                ],
              ),
            ],
          ),
        if (actions.onLibraryChanges != null) ...[
          const SizedBox(height: 12),
          TextLink(
            text: context.strings.libraryScreen.changesTitle,
            onTap: actions.onLibraryChanges,
          ),
        ],
      ],
      actions: [
        ActionButton.recommended(
          key: ShellKeys.taskPrimary,
          text: plugins ? t.toOtzaria : g.launchButton,
          size: ActionButtonSize.lg,
          autofocus: true,
          expand: true,
          onPressed: actions.onLaunch,
        ),
        ActionButton.ghost(
          text: t.backToHomePage,
          expand: true,
          onPressed: actions.onHome,
        ),
      ],
    );
  }

  Widget _cancelled(BuildContext context) {
    final t = context.strings.task;
    final atStage = task.stageIndex < task.stages.length
        ? task.stages[task.stageIndex]
        : null;
    final wizard = atStage == GuidanceItem.app;
    return TaskResult(
      badge: const ResultBadge(
        kind: ResultBadgeKind.calm,
        icon: FluentIcons.arrow_reset_24_regular,
      ),
      title: wizard ? t.wizardClosedTitle : t.stoppedTitle,
      body: wizard
          ? t.wizardClosedBody(
              firstInstall: task.firstInstall,
              libraryDone:
                  task.outcomes[GuidanceItem.library] == StageOutcome.done,
            )
          : t.stoppedBody,
      actions: [
        ActionButton.recommended(
          key: ShellKeys.taskPrimary,
          text: context.strings.common.retry,
          icon: FluentIcons.arrow_clockwise_24_regular,
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
    final e = context.strings.elevation;
    final failure = task.failure ?? const UpdateFailure(GuidanceItem.library);
    final library = failure.stage == GuidanceItem.library;
    final message = failure.message?.trim();
    final lines = message == null || message.isEmpty
        ? const <String>[]
        : message.split('\n');
    final keep = library ? t.libraryFailedKeep : t.appFailedKeep;
    final body = lines.isEmpty ? keep : '${lines.first} $keep';
    final elevate = actions.onRestartElevated;
    return TaskResult(
      badge: const ResultBadge(
        kind: ResultBadgeKind.error,
        icon: FluentIcons.important_24_filled,
      ),
      title: library ? t.libraryFailedTitle : t.appFailedTitle,
      body: body,
      extra: [
        if (elevate != null) ...[
          const SizedBox(height: 16),
          NoticeBanner(
            key: ShellKeys.taskElevation,
            kind: NoticeKind.banner,
            leading:
                const IconTile(icon: FluentIcons.shield_checkmark_24_regular),
            title: e.bannerTitle,
            body: e.bannerContent,
          ),
        ],
        if (lines.length > 1) TechDetails(text: lines.skip(1).join('\n')),
      ],
      actions: [
        if (elevate != null)
          ActionButton.recommended(
            key: ShellKeys.taskPrimary,
            text: e.bannerConfirm,
            icon: FluentIcons.shield_checkmark_24_regular,
            size: ActionButtonSize.lg,
            autofocus: true,
            expand: true,
            onPressed: elevate,
          )
        else
          ActionButton.recommended(
            key: ShellKeys.taskPrimary,
            text: context.strings.common.retry,
            icon: FluentIcons.arrow_clockwise_24_regular,
            size: ActionButtonSize.lg,
            autofocus: true,
            expand: true,
            onPressed: actions.onRetry,
          ),
        ActionButton.neutral(
          key: ShellKeys.taskSecondary,
          text: library ? t.toLibraryPage : t.toAppPage,
          expand: true,
          onPressed: () => actions.onOpenPage(failure.stage),
        ),
        ActionButton.ghost(
          text: t.backHome,
          expand: true,
          onPressed: actions.onHome,
        ),
      ],
    );
  }
}

Widget _logo(double size) => Image.asset(
      'assets/images/otzaria_logo.png',
      width: size,
      height: size,
    );

/// אריח 64 מעל כותרת השאלה.
class _BigTile extends StatelessWidget {
  const _BigTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      margin: const EdgeInsets.only(bottom: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: IconTheme(
        data: IconThemeData(color: cs.onSecondaryContainer),
        child: child,
      ),
    );
  }
}

class _Deliveries extends StatelessWidget {
  const _Deliveries({required this.rows});

  final List<PluginDelivery> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.task;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  switch (row.state) {
                    PluginDeliveryState.sent => Icon(
                        FluentIcons.send_16_regular,
                        size: 16,
                        color: cs.primary,
                      ),
                    PluginDeliveryState.failed => Icon(
                        FluentIcons.dismiss_circle_16_regular,
                        size: 16,
                        color: cs.error,
                      ),
                    PluginDeliveryState.waiting => SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                          backgroundColor: cs.secondaryContainer,
                        ),
                      ),
                  },
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${row.name} · ${switch (row.state) {
                        PluginDeliveryState.sent => t.pluginRowSent,
                        PluginDeliveryState.failed => t.pluginRowFailed,
                        PluginDeliveryState.waiting => t.pluginRowWaiting,
                      }}',
                      style: AppTextStyles.small.copyWith(color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
