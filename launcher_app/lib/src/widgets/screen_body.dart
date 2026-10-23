import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'sub_page_header.dart';

/// גוף דף (`.page`): כותרת 20/600 ורשימת כרטיסים, ברוחב תוכן של עד 720
/// וממורכז, עם ריפוד 28/24/40.
class ScreenBody extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const ScreenBody({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const padding = LayoutConstraints.pagePadding;
    final header = SubPageHeaderScope.maybeOf(context);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: LayoutConstraints.panelContentMaxWidth + padding.horizontal,
        ),
        child: ListView(
          padding: padding,
          children: [
            if (header != null) header,
            Text(
              title,
              style: AppTextStyles.pageTitle.copyWith(color: cs.onSurface),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
