import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../services/native_file_dialogs.dart';
import '../../services/timestamps.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'plugin_detail_view.dart';
import 'plugin_filters_bar.dart';
import 'plugin_store_card.dart';
import 'plugin_visuals.dart';
import 'store_app_export_flow.dart';

/// חנות התוספים — בסגנון החנות שבאתר: חיפוש, בורר מותקנים, קטגוריות, פס
/// עדכונים, רשת כרטיסים ודף פרטים מלא.
///
/// הכול נטען מהכונן; "רענון" הוא הפעולה היחידה שפונה לאתר, תמיד בלחיצה.
class PluginsScreen extends StatefulWidget {
  const PluginsScreen({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.driveFull = false,
    this.busyElsewhere = false,
    this.online,
    this.otzariaInstalled = true,
    this.detailId,
    this.onDetailChanged,
  });

  final PluginsModuleController controller;

  final bool readOnly;
  final bool driveFull;
  final bool busyElsewhere;

  /// `false` — אין אינטרנט במחשב הזה, ו"רענון" אינו מוצג.
  final bool? online;

  /// בלי אוצריא אין למי למסור תוסף.
  final bool otzariaInstalled;

  /// עם [onDetailChanged] — התוסף שפרטיו מוצגים הוא נתיב בנווט, כך שחזרה
  /// ו-Esc מהפרטים מובילים לרשימה. בלעדיו המסך זוכר בעצמו.
  final String? detailId;
  final ValueChanged<String?>? onDetailChanged;

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  final TextEditingController _search = TextEditingController();

  String? _localSelectedId;

  String? get _selectedId =>
      widget.onDetailChanged == null ? _localSelectedId : widget.detailId;

  void _select(String? id) {
    final external = widget.onDetailChanged;
    if (external != null) {
      external(id);
    } else {
      setState(() => _localSelectedId = id);
    }
  }

  /// התוסף שנמסר כרגע לאוצריא.
  String? _busyId;

  /// "עדכון הכול" שרץ: כמה נשלחו מתוך כמה.
  ({int done, int total})? _updatingAll;

  /// התוספים שחדשים בהרצה הזו — מסומנים בשבב "חדש", ונרשמים כ"נראו" מיד.
  Set<String> _newIds = const {};
  bool _newCaptured = false;

  bool _stopSync = false;

  PluginsModuleController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _search.text = _c.search;
    _c.addListener(_onControllerChange);
    _captureNew();
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChange);
    _search.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    if (_search.text != _c.search) _search.text = _c.search;
    setState(() {});
    _captureNew();
  }

  void _captureNew() {
    if (_newCaptured || _c.status != PluginsModuleStatus.ready) return;
    final fresh = _c.newPlugins;
    if (fresh.isEmpty) return;
    _newCaptured = true;
    _newIds = {for (final plugin in fresh) plugin.id};
    unawaited(_c.markNewSeen(fresh));
  }

  bool get _canSync => !widget.readOnly && widget.online != false;

  // ── פעולות ────────────────────────────────────────────────────────────────

  Future<void> _sync() async {
    if (widget.readOnly) {
      final t = context.strings.readOnlyDrive;
      UiSnack.show(widget.driveFull
          ? t.downloadsDisabledSnackDriveFull
          : t.downloadsDisabledSnack);
      return;
    }
    final t = context.strings.plugins;
    _stopSync = false;
    await _c.sync(isCancelled: () => _stopSync);
    if (!mounted) return;
    final warnings = _c.syncWarnings;
    final shabbat = _c.shabbatNotice;
    if (_stopSync) {
      UiSnack.show(t.syncStoppedSnack);
    } else if (shabbat != null) {
      UiSnack.show(shabbat);
    } else if (_c.status == PluginsModuleStatus.error) {
      UiSnack.showError(_c.errorMessage ?? t.syncFailedSnack);
    } else if (warnings.isNotEmpty) {
      // בלי ההודעה הזו סנכרון שבו קבצים לא ירדו נראה כהצלחה מלאה.
      UiSnack.showError(t.syncDoneWithWarningsSnack(warnings.length));
    } else {
      UiSnack.showSuccess(
        t.syncDoneSnack(_c.lastSyncOutcome?.fetched ?? 0, _c.plugins.length),
      );
    }
  }

  Future<void> _save(StorePlugin plugin) async {
    final t = context.strings.plugins;
    final destPath = await NativeFileDialogs.saveFile(
      dialogTitle: t.saveDialogTitle,
      fileName: _c.suggestedFileName(plugin),
      allowedExtensions: const ['otzplugin'],
    );
    if (destPath == null || !mounted) return;

    final result = await _c.saveCopy(plugin, destPath);
    if (!mounted) return;
    if (result.success) {
      UiSnack.showSuccess(t.saveDoneSnack);
    } else {
      UiSnack.showError(result.error ?? t.saveFailedSnack);
    }
  }

  Future<void> _install(StorePlugin plugin) async {
    final t = context.strings.plugins;
    setState(() => _busyId = plugin.id);
    final result = await _c.directInstall(plugin);
    if (!mounted) return;
    setState(() => _busyId = null);

    if (result.success) {
      UiSnack.show(t.installSentSnack(plugin.name));
    } else {
      UiSnack.showError(result.error ?? t.installFailedSnack);
    }
  }

  /// "עדכון הכול": אחד אחרי השני, במרווח — ראו `deliverUpdates`.
  Future<void> _updateAll() async {
    final t = context.strings.plugins;
    final targets =
        _pendingUpdates.where(_c.canDirectInstall).toList(growable: false);
    if (targets.isEmpty) return;
    setState(() => _updatingAll = (done: 0, total: targets.length));
    final sent = await _c.deliverUpdates(
      plugins: targets,
      isCancelled: () => !mounted,
      onDelivering: (plugin) => setState(() => _busyId = plugin.id),
      onDelivered: (plugin, result) {
        if (!mounted) return;
        setState(() {
          _busyId = null;
          final run = _updatingAll;
          if (run != null) {
            _updatingAll = (done: run.done + 1, total: run.total);
          }
        });
        if (!result.success) {
          UiSnack.showError(result.error ?? t.installFailedSnack);
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _updatingAll = null;
      _busyId = null;
    });
    if (sent.isNotEmpty) UiSnack.show(t.updatesSentSnack(sent.length));
  }

  /// עדכונים שעוד לא נשלחו לאוצריא.
  List<StorePlugin> get _pendingUpdates => [
        for (final plugin in _c.updatablePlugins)
          if (!_c.isAwaitingInstallOf(plugin)) plugin,
      ];

  void _clearFilters() {
    _search.clear();
    _c.clearFilters();
  }

  // ── תצוגה ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final id = _selectedId;
    final selected = id == null ? null : _c.byId(id);
    if (selected != null) {
      return PluginDetailView(
        plugin: selected,
        controller: _c,
        busy: _busyId == selected.id,
        blocked: _updatingAll != null,
        otzariaInstalled: widget.otzariaInstalled,
        onSave: () => _save(selected),
        onInstall: () => _install(selected),
        onTagSelected: (tag) {
          _clearFilters();
          _c.setTagFilter(tag);
          _select(null);
        },
        onCategorySelected: (slug) {
          _clearFilters();
          _c.setCategory(slug);
          _select(null);
        },
      );
    }
    return StoreBody(slivers: _slivers(context));
  }

  List<Widget> _slivers(BuildContext context) {
    final t = context.strings.plugins;
    final lastSync = _c.lastSync;
    final ready = _c.status == PluginsModuleStatus.ready;
    final empty = _c.plugins.isEmpty;
    final busy = _c.isSyncing || _c.isExporting || widget.busyElsewhere;

    return [
      StoreBody.block(
        StorePageHead(
          title: t.storeTitle,
          description: lastSync == null
              ? t.storeSubtitle
              : '${t.storeSubtitle} ${t.asOfDate(formatDate(lastSync))}',
          actions: [
            if (_canSync)
              ActionButton.ghost(
                text: t.refreshButton,
                icon: FluentIcons.arrow_sync_20_regular,
                spinning: _c.isSyncing,
                onPressed: busy ? null : () => unawaited(_sync()),
              ),
          ],
        ),
      ),
      if (_c.isSyncing) StoreBody.block(_syncProgress(context), bottom: 14),
      if (_c.errorMessage != null)
        StoreBody.block(
          AppCard(
            padding: const EdgeInsets.all(16),
            child: InfoErrorRow(message: _c.errorMessage!, onRetry: _c.load),
          ),
          bottom: 14,
        ),
      if (_c.status == PluginsModuleStatus.loading)
        StoreBody.block(
          AppCard(
            padding: const EdgeInsets.all(16),
            child: InfoProgressRow(stage: t.loadingCatalog),
          ),
        )
      else if (empty && !_c.isSyncing)
        StoreBody.block(
          EmptyState(
            icon: FluentIcons.puzzle_piece_24_regular,
            title: t.emptyTitle,
            body: _canSync ? t.emptyBodyOnline : t.emptyBodyOffline,
            actions: [
              if (_canSync)
                ActionButton.recommended(
                  text: t.refreshButton,
                  icon: FluentIcons.arrow_sync_20_regular,
                  onPressed: busy ? null : () => unawaited(_sync()),
                ),
            ],
          ),
        )
      else if (!empty) ...[
        StoreBody.block(
          PluginFiltersBar(controller: _c, searchController: _search),
          bottom: 6,
        ),
        if (ready) ..._updatesBar(context),
        if (_c.filtered.isEmpty)
          StoreBody.block(_noResults(context))
        else
          StoreQueryScope(query: _c.search, child: _grid(context)),
        StoreBody.block(_advanced(context), top: 8),
      ],
    ];
  }

  Widget _syncProgress(BuildContext context) {
    final t = context.strings.plugins;
    return ListenableBuilder(
      listenable: _c.progress,
      builder: (context, _) => AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.syncingTitle,
                    style: AppTextStyles.rowTitle.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                ActionButton.ghost(
                  text: t.syncStopButton,
                  size: ActionButtonSize.sm,
                  onPressed:
                      _stopSync ? null : () => setState(() => _stopSync = true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InfoProgressRow(
              stage: _c.syncMessage ?? t.syncingOverlayStarting,
              progress: _c.syncProgress,
              warning: t.syncingHint,
            ),
            for (final warning in _c.syncWarnings) ...[
              const SizedBox(height: 4),
              Text(
                warning,
                style: AppTextStyles.meta.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _updatesBar(BuildContext context) {
    final t = context.strings.plugins;
    final updatable = _c.updatablePlugins;
    if (updatable.isEmpty) return const [];
    final pending = _pendingUpdates;
    final run = _updatingAll;
    final names = [for (final plugin in pending) plugin.name];
    final deliverable = pending.any(_c.canDirectInstall);

    final Widget banner;
    if (run != null) {
      banner = NoticeBanner(
        kind: NoticeKind.banner,
        leading: const IconTile(icon: FluentIcons.arrow_sync_24_regular),
        title: t.updatingAllLabel(
            run.done + 1 > run.total ? run.total : run.done + 1, run.total),
        below: AppProgressBar(value: run.done / run.total, thin: true),
      );
    } else if (pending.isEmpty) {
      banner = NoticeBanner(
        kind: NoticeKind.banner,
        leading: const IconTile(icon: FluentIcons.send_24_regular),
        title: t.updatesSentTitle,
        body: t.updatesSentBody,
      );
    } else {
      banner = NoticeBanner(
        kind: NoticeKind.banner,
        leading: const IconTile(icon: FluentIcons.arrow_sync_24_regular),
        title: t.updatesAvailable(pending.length),
        body: t.updatesBarNames(t.joinNames(names)),
        actions: [
          if (deliverable)
            ActionButton.recommended(
              text: t.updateAllButton,
              onPressed: _busyId == null ? () => unawaited(_updateAll()) : null,
            ),
        ],
      );
    }
    return [StoreBody.block(banner, bottom: 2)];
  }

  Widget _noResults(BuildContext context) {
    final t = context.strings.plugins;
    final query = _c.search.trim();
    return EmptyState(
      icon: FluentIcons.search_24_regular,
      quiet: true,
      title: query.isEmpty ? t.noResultsTitle : t.noResultsForQuery(query),
      body: t.noResultsBody,
      actions: [
        ActionButton.neutral(
            text: t.clearFiltersButton, onPressed: _clearFilters),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    final plugins = _c.filtered;
    return SliverGrid.builder(
      gridDelegate: StoreGridDelegate(
        textScale: MediaQuery.textScalerOf(context).scale(1),
      ),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return PluginStoreCard(
          plugin: plugin,
          controller: _c,
          state: pluginCardStateOf(
            _c,
            plugin,
            busy: _busyId == plugin.id,
            otzariaInstalled: widget.otzariaInstalled,
          ),
          isNew: _newIds.contains(plugin.id),
          blocked: _updatingAll != null,
          onOpenDetail: () => _select(plugin.id),
          onSave: () => _save(plugin),
          onInstall: () => _install(plugin),
        );
      },
    );
  }

  Widget _advanced(BuildContext context) {
    final t = context.strings.plugins;
    return AdvancedSection(
      title: context.strings.pages.advancedTitle,
      summary: StoreAppExportButton.isSupported
          ? t.advancedSummary
          : t.reloadRowTitle,
      child: RowsCard(
        children: [
          if (StoreAppExportButton.isSupported)
            AppRow(
              title: t.storeAppButton,
              subtitle: t.storeAppRowBody,
              trailing: StoreAppExportButton(
                controller: _c,
                busyElsewhere: widget.busyElsewhere,
              ),
              below:
                  _c.isExporting ? StoreAppCopyProgress(controller: _c) : null,
            ),
          AppRow(
            title: t.reloadRowTitle,
            subtitle: _c.pluginsDir == null ? t.syncDirUnknownTooltip : null,
            below: _c.pluginsDir == null ? null : PathText(_c.pluginsDir!),
            trailing: ActionButton.neutral(
              text: t.reloadButton,
              icon: FluentIcons.arrow_clockwise_20_regular,
              onPressed: _c.isSyncing ? null : _c.load,
            ),
          ),
        ],
      ),
    );
  }
}
