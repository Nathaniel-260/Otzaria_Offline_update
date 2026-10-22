import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// [notice] — כרטיס הודעה (`.notice`), [warning] — אותו על רקע אזהרה,
/// [banner] — פס tonal בבית ובחנות (`.banner`).
enum NoticeKind { notice, warning, banner }

/// הודעה קבועה בדף: אריח (או לוגו), כותרת, פירוט ופעולות בקצה.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.leading,
    required this.title,
    this.body,
    this.actions = const [],
    this.kind = NoticeKind.notice,
  });

  final Widget leading;
  final String title;
  final String? body;
  final List<Widget> actions;
  final NoticeKind kind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final banner = kind == NoticeKind.banner;
    final background = switch (kind) {
      NoticeKind.notice => AppSurfaces.card(context),
      NoticeKind.warning => AppSurfaces.warningNotice(context),
      NoticeKind.banner => AppSurfaces.banner(context),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: banner
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
          : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        crossAxisAlignment:
            banner ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.rowTitle.copyWith(color: cs.onSurface),
                ),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    body!,
                    style: AppTextStyles.rowSub.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 14),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}
