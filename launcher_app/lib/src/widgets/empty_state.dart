import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'icon_tile.dart';

/// מצב ריק (`.empty`): כרטיס ממורכז עם אריח 56, כותרת 18, הסבר ופעולות.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actions = const [],
    this.quiet = false,
  });

  final IconData icon;
  final String title;
  final String? body;
  final List<Widget> actions;

  /// אריח שקט — "לא נמצא" ולא "עוד אין".
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTile(
            icon: icon,
            size: IconTileSize.lg,
            tone: quiet ? IconTileTone.quiet : IconTileTone.tonal,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.dialogTitle.copyWith(color: cs.onSurface),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Text(
                body!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}
