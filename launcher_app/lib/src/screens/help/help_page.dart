import 'package:flutter/material.dart';

import '../../controllers/faq_controller.dart';
import '../../settings/safer_mode.dart';
import '../../widgets/screen_body.dart';
import '../faq/faq_body.dart';

/// דף העזרה — נפתח מ-"?" שבשורת הכותרת, ומארח את השאלות הנפוצות.
class HelpPage extends StatelessWidget {
  const HelpPage({
    super.key,
    required this.faq,
    this.saferMode,
    this.editRequests,
    this.active = true,
    this.readOnly = false,
  });

  final FaqController faq;
  final SaferModeGate? saferMode;

  /// "עריכת השאלות הנפוצות" שבהגדרות — ראו [FaqBody.editRequests].
  final ValueNotifier<bool>? editRequests;

  /// ראו [FaqBody.active].
  final bool active;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => ScreenBody(
        children: [
          FaqBody(
            faq: faq,
            saferMode: saferMode,
            editRequests: editRequests,
            active: active,
            readOnly: readOnly,
          ),
        ],
      );
}
