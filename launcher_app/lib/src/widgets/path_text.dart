import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// נתיב (`.path`): Consolas 12 על surfaceContainer, LTR, שורה אחת ומקוצר.
class PathText extends StatelessWidget {
  const PathText(this.path, {super.key});

  final String path;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          fontFamily: 'Consolas',
          fontFamilyFallback: const ['Cascadia Mono', 'monospace'],
          fontSize: AppTokens.fontSM,
          color: cs.onSurface,
        ),
      ),
    );
  }
}
