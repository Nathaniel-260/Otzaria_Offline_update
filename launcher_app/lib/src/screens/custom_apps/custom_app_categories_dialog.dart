import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// הקטגוריות נקבעות במחשב המקוון ונוסעות על הכונן. [editing] — נפתח ישר
/// על עריכת הקטגוריה הזו.
Future<void> showCustomAppCategoriesDialog({
  required BuildContext context,
  required CustomAppsController controller,
  CustomAppCategory? editing,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => ListenableBuilder(
        listenable: controller,
        builder: (_, child) =>
            _CategoriesDialog(controller: controller, editing: editing),
      ),
    );

/// שואל, ורק אז מוחק קטגוריה. התוכנות שבה עוברות ל"ללא קטגוריה".
Future<bool> confirmRemoveCustomAppCategory(
  BuildContext context,
  CustomAppsController controller,
  CustomAppCategory category,
) async {
  final t = context.strings.customApps;
  final count = controller.appsIn(category.slug).length;
  final approved = await showWarningDialog(
    context: context,
    title: t.removeCategoryDialogTitle(category.name),
    content: t.removeCategoryDialogContent(category.name, count),
    confirmText: t.removeCategoryTooltip,
  );
  if (!approved) return false;

  if (await controller.removeCategory(category.slug)) {
    UiSnack.show(
      AppL10n.strings.customApps.categoryRemovedSnack(category.name),
    );
    return true;
  }
  UiSnack.showFailure(controller.errorMessage);
  return false;
}

class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog({required this.controller, this.editing});

  final CustomAppsController controller;
  final CustomAppCategory? editing;

  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();

  /// אותו טופס משמש להוספה ולעריכה; `null` מציין הוספה.
  String? _editingSlug;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing case final category?) {
      _editingSlug = category.slug;
      _name.text = category.name;
      _description.text = category.description;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _startEditing(CustomAppCategory category) {
    setState(() {
      _editingSlug = category.slug;
      _name.text = category.name;
      _description.text = category.description;
    });
  }

  void _clearForm() {
    setState(() {
      _editingSlug = null;
      _name.clear();
      _description.clear();
    });
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);

    final slug = _editingSlug;
    final ok = slug == null
        ? await widget.controller.addCategory(
              _name.text,
              description: _description.text,
            ) !=
            null
        : await widget.controller.renameCategory(
            slug,
            name: _name.text,
            description: _description.text,
          );

    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      UiSnack.showFailure(widget.controller.errorMessage);
      return;
    }
    _clearForm();
  }

  Future<void> _confirmRemove(CustomAppCategory category) async {
    if (await confirmRemoveCustomAppCategory(
          context,
          widget.controller,
          category,
        ) &&
        _editingSlug == category.slug) {
      _clearForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final cs = Theme.of(context).colorScheme;
    final categories = widget.controller.categories;
    const pad = AppTokens.spaceLG;

    return AlertDialog(
      insetPadding: const EdgeInsets.all(pad),
      titlePadding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
      contentPadding: const EdgeInsets.fromLTRB(pad, 10, pad, 0),
      actionsPadding: const EdgeInsets.all(pad),
      title: Text(t.categoriesTitle),
      content: SizedBox(
        width: AppTokens.dialogFormWidth - 2 * pad,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.categoriesDialogHint),
              const SizedBox(height: AppTokens.spaceMD),
              RtlTextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: t.categoryNameLabel,
                  helperText: t.categoryNameHint,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppTokens.spaceMD),
              RtlTextField(
                controller: _description,
                decoration: InputDecoration(
                  labelText: t.categoryDescriptionLabel,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMD),
              Wrap(
                spacing: AppTokens.spaceSM,
                runSpacing: AppTokens.spaceSM,
                children: [
                  ActionButton.neutral(
                    text: _editingSlug == null
                        ? t.addCategoryButton
                        : t.saveEditButton,
                    icon: _editingSlug == null
                        ? FluentIcons.add_20_regular
                        : FluentIcons.checkmark_20_regular,
                    isLoading: _busy,
                    onPressed:
                        _busy || _name.text.trim().isEmpty ? null : _submit,
                  ),
                  if (_editingSlug != null)
                    ActionButton.ghost(
                      text: context.strings.common.cancel,
                      onPressed: _busy ? null : _clearForm,
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceLG),
              Material(
                color: cs.surfaceContainerLowest,
                borderRadius: AppTokens.borderRadiusAll,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (categories.isEmpty)
                      AppRow(
                        title: t.noCategoriesTitle,
                        subtitle: t.noCategoriesHint,
                      )
                    else
                      for (final (i, category) in categories.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        AppRow(
                          leading: const IconTile(
                            icon: FluentIcons.tag_20_regular,
                            size: IconTileSize.sm,
                            tone: IconTileTone.quiet,
                          ),
                          // שם הקטגוריה ותיאורה הם תוכן — לא מתורגמים.
                          title: category.name,
                          subtitle: category.description.isEmpty
                              ? t.categoryAppCount(
                                  widget.controller
                                      .appsIn(category.slug)
                                      .length,
                                )
                              : category.description,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIconButton(
                                icon: FluentIcons.edit_20_regular,
                                tooltip: t.editTooltip,
                                small: true,
                                onPressed: _busy
                                    ? null
                                    : () => _startEditing(category),
                              ),
                              AppIconButton(
                                icon: FluentIcons.delete_20_regular,
                                tooltip: t.removeCategoryTooltip,
                                small: true,
                                danger: true,
                                onPressed: _busy
                                    ? null
                                    : () => _confirmRemove(category),
                              ),
                            ],
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        ActionButton.recommended(
          text: context.strings.common.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
