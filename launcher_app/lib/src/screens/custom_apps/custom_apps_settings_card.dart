import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../widgets/widgets_exports.dart';

/// שורה אחת במסך ההגדרות, וכל תפקידה לפתוח את דף הניהול
/// (`CustomAppsManagePage`) — ההוספה, העריכה, הקטגוריות והסדר יושבים שם.
class CustomAppsSettingsCard extends StatelessWidget {
  const CustomAppsSettingsCard({
    super.key,
    required this.controller,
    required this.onOpenManager,
    this.readOnly = false,
    this.driveFull = false,
  });

  final CustomAppsController controller;

  /// נכנס לדף הניהול בנווט — דרך שער הסייפר.
  final VoidCallback onOpenManager;

  final bool readOnly;
  final bool driveFull;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    // מאזין בעצמו: מספר התוכנות משתנה בזמן שדף הניהול פתוח.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SettingsCard(
        title: t.settingsCardTitle,
        hint: t.settingsCardHint,
        children: [
          SettingsActionTile.text(
            icon: FluentIcons.box_24_regular,
            title: t.settingsCardTitle,
            subtitle: readOnly
                ? driveFull
                    ? context
                        .strings.readOnlyDrive.customAppsManageDisabledDriveFull
                    : context.strings.readOnlyDrive.customAppsManageDisabled
                : controller.hasApps
                    ? t.registeredAppCount(controller.apps.length)
                    : t.emptyHint,
            actions: [
              ActionButton.neutral(
                text: t.openManagerButton,
                onPressed: readOnly ? null : onOpenManager,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
