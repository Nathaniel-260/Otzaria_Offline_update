import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/app_reports_controller.dart';
import '../../widgets/widgets_exports.dart';

/// כרטיס "דיווח על תקלות" בהגדרות: מצב הדיווח אחרי קריסה, וכניסה לדף
/// הדיווחים — שם הטופס, התור וההיסטוריה.
class AppReportsSettingsCard extends StatefulWidget {
  const AppReportsSettingsCard({
    super.key,
    required this.reports,
    this.onOpenReports,
  });

  final AppReportsController reports;
  final VoidCallback? onOpenReports;

  @override
  State<AppReportsSettingsCard> createState() => _AppReportsSettingsCardState();
}

class _AppReportsSettingsCardState extends State<AppReportsSettingsCard> {
  AppReportsController get _reports => widget.reports;

  @override
  void initState() {
    super.initState();
    _reports.addListener(_onChanged);
    _reports.settings.addListener(_onChanged);
  }

  @override
  void dispose() {
    _reports.removeListener(_onChanged);
    _reports.settings.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.appReports;
    return SettingsCard(
      title: t.cardTitle,
      children: [
        SettingsActionTile.segmentedTile<AppCrashReportMode>(
          key: const ValueKey('app-reports-crash-mode'),
          icon: FluentIcons.warning_24_regular,
          title: t.crashModeTitle,
          subtitle: t.crashModeSubtitle,
          options: [
            SegmentOption(value: AppCrashReportMode.ask, label: t.crashModeAsk),
            SegmentOption(
              value: AppCrashReportMode.always,
              label: t.crashModeAlways,
            ),
            SegmentOption(
              value: AppCrashReportMode.never,
              label: t.crashModeNever,
            ),
          ],
          currentValue: _reports.crashMode,
          onChanged: _reports.setCrashMode,
        ),
        if (widget.onOpenReports case final open?)
          SettingsActionTile.text(
            icon: FluentIcons.task_list_ltr_24_regular,
            title: t.manageTileTitle,
            subtitle: t.manageTileSubtitle(
              _reports.pendingCount,
              _reports.sentTotal,
            ),
            actions: [
              ActionButton.neutral(
                key: const ValueKey('app-reports-manage'),
                text: t.manageButton,
                onPressed: open,
              ),
            ],
          ),
      ],
    );
  }
}
