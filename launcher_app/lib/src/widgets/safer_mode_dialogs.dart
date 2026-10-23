import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings_scope.dart';
import '../settings/safer_mode.dart';
import '../theme/theme_exports.dart';
import 'action_buttons.dart';
import 'rtl_text_field.dart';

/// מבקש את סיסמת מצב הסייפר. מחזיר `true` רק כשהוזנה הסיסמה הנכונה.
///
/// [hint] אומר *למה* מבקשים אותה עכשיו — כניסה להגדרות, עריכת השאלות,
/// הפעלת הנעילה או כיבויה.
Future<bool> showSaferModePasswordDialog(
  BuildContext context, {
  required String storedPassword,
  required String hint,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _VerifyDialog(
        storedPassword: storedPassword,
        hint: hint,
      ),
    ) ??
    false;

/// קביעת סיסמה ראשונה. מחזיר את הערך המעורבל לשמירה, או `null` בביטול.
Future<String?> showSaferModeSetPasswordDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _SetPasswordDialog(),
    );

/// החלפת סיסמה: הנוכחית והחדשה פעמיים בדו-שיח אחד. מחזיר את הערך המעורבל
/// החדש, או `null` בביטול.
Future<String?> showSaferModeChangePasswordDialog(
  BuildContext context, {
  required String storedPassword,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _SetPasswordDialog(storedPassword: storedPassword),
    );

/// מחיקת הסיסמה — אזהרה עם הסיסמה הנוכחית. `true` רק כשהיא נכונה ואושרה.
Future<bool> showSaferModeClearPasswordDialog(
  BuildContext context, {
  required String storedPassword,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ClearPasswordDialog(storedPassword: storedPassword),
    ) ??
    false;

class _VerifyDialog extends StatefulWidget {
  const _VerifyDialog({required this.storedPassword, required this.hint});

  final String storedPassword;
  final String hint;

  @override
  State<_VerifyDialog> createState() => _VerifyDialogState();
}

class _VerifyDialogState extends State<_VerifyDialog> {
  final TextEditingController _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _verify() {
    final t = context.strings.saferMode;
    if (_password.text.isEmpty) {
      setState(() => _error = t.passwordRequired);
      return;
    }
    if (SaferModePassword.verify(widget.storedPassword, _password.text)) {
      Navigator.of(context).pop(true);
      return;
    }
    // שגיאה בתוך הדו-שיח ולא סגירה: מי שהקליד שגוי מנסה שוב.
    _password.clear();
    setState(() => _error = t.wrongPassword);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;
    return _FormDialog(
      title: t.verifyTitle,
      intro: widget.hint,
      error: _error,
      fields: [
        _PasswordField(
          controller: _password,
          label: t.passwordLabel,
          autofocus: true,
          onSubmitted: _verify,
        ),
      ],
      actions: [
        ActionButton.ghost(
          text: context.strings.common.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ActionButton.recommended(
          text: context.strings.common.confirm,
          onPressed: _verify,
        ),
      ],
    );
  }
}

/// קביעה, ועם [storedPassword] — החלפה (שדה הסיסמה הנוכחית נוסף בראש).
class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog({this.storedPassword});

  final String? storedPassword;

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();
  String? _error;

  bool get _changing => widget.storedPassword != null;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _save() {
    final t = context.strings.saferMode;
    final error = switch (_password.text) {
      _
          when _changing &&
              !SaferModePassword.verify(
                  widget.storedPassword!, _current.text) =>
        t.wrongPassword,
      '' => t.passwordRequired,
      final p when p.length < SaferModePassword.minLength =>
        t.passwordTooShort(SaferModePassword.minLength),
      final p when p != _confirm.text => t.passwordsDoNotMatch,
      _ => null,
    };
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    // הדו-שיח מחזיר את הערך המעורבל ולא את הסיסמה — היא לא יוצאת מכאן.
    Navigator.of(context).pop(SaferModePassword.encode(_password.text));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;
    return _FormDialog(
      title: _changing ? t.changeTitle : t.setTitle,
      intro: _changing ? null : t.setIntro(SaferModePassword.minLength),
      error: _error,
      fields: [
        if (_changing)
          _PasswordField(
            controller: _current,
            label: t.currentPasswordLabel,
            autofocus: true,
            onSubmitted: _passwordFocus.requestFocus,
          ),
        _PasswordField(
          controller: _password,
          focusNode: _passwordFocus,
          label: _changing ? t.newPasswordLabel : t.passwordLabel,
          autofocus: !_changing,
          onSubmitted: _confirmFocus.requestFocus,
        ),
        _PasswordField(
          controller: _confirm,
          focusNode: _confirmFocus,
          label: t.confirmPasswordLabel,
          onSubmitted: _save,
        ),
      ],
      actions: [
        ActionButton.ghost(
          text: context.strings.common.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(
          text: _changing ? t.changeButton : t.setConfirm,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _ClearPasswordDialog extends StatefulWidget {
  const _ClearPasswordDialog({required this.storedPassword});

  final String storedPassword;

  @override
  State<_ClearPasswordDialog> createState() => _ClearPasswordDialogState();
}

class _ClearPasswordDialogState extends State<_ClearPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _clear() {
    final t = context.strings.saferMode;
    if (SaferModePassword.verify(widget.storedPassword, _password.text)) {
      Navigator.of(context).pop(true);
      return;
    }
    _password.clear();
    setState(() => _error = t.wrongPassword);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;
    // אזהרה: הבטוח (ביטול) מומלץ, והפעולה ההרסנית בקצה — כמו `showWarningDialog`.
    return _FormDialog(
      title: t.clearDialogTitle,
      intro: t.clearDialogContent,
      error: _error,
      fields: [
        _PasswordField(
          controller: _password,
          label: t.currentPasswordLabel,
          autofocus: true,
          onSubmitted: _clear,
        ),
      ],
      actions: [
        ActionButton.recommended(
          text: context.strings.common.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ActionButton.warning(text: t.clearButton, onPressed: _clear),
      ],
    );
  }
}

/// דו-שיח שדות (`.dialog.form`): 440, ריפוד 24, הסבר, שדות עם תווית מעליהם
/// ושורת שגיאה (`.errline`) — השגיאה בתוך הדו-שיח, לא בהודעה צפה.
class _FormDialog extends StatelessWidget {
  const _FormDialog({
    required this.title,
    required this.fields,
    required this.actions,
    this.intro,
    this.error,
  });

  final String title;
  final String? intro;
  final List<Widget> fields;
  final String? error;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const pad = AppTokens.spaceLG;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(pad),
      titlePadding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
      contentPadding: const EdgeInsets.fromLTRB(pad, 10, pad, 0),
      actionsPadding: const EdgeInsets.all(pad),
      buttonPadding: EdgeInsets.zero,
      title: Text(title),
      content: SizedBox(
        width: AppTokens.dialogFormWidth - 2 * pad,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (intro != null) ...[Text(intro!), const SizedBox(height: 16)],
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                fields[i],
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: AppTextStyles.rowSub.copyWith(color: cs.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppTokens.spaceSM,
          runSpacing: AppTokens.spaceSM,
          children: [
            for (final action in actions)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 104),
                child: action,
              ),
          ],
        ),
      ],
    );
  }
}

/// שדה סיסמה (`.field`): תווית 13/600 מעליו וכפתור "הצג/הסתר" בקצה.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.sectionLabel.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: widget.label,
          child: RtlTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            obscureText: _obscured,
            autofocus: widget.autofocus,
            onSubmitted: (_) => widget.onSubmitted(),
            decoration: InputDecoration(
              suffixIcon: IconButton(
                // 40 ולא 48 של יעד המגע, כדי שהשדה יישאר 44.
                visualDensity: VisualDensity.compact,
                tooltip:
                    _obscured ? t.showPasswordTooltip : t.hidePasswordTooltip,
                icon: Icon(
                  _obscured
                      ? FluentIcons.eye_24_regular
                      : FluentIcons.eye_off_24_regular,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
