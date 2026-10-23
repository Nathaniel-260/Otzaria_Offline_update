import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../services/timestamps.dart';
import '../../shell/home_guidance.dart';
import '../../shell/shell_keys.dart';
import '../../shell/shell_navigator.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'home_view_model.dart';
import 'welcome_view.dart';

void _noop() {}
void _noopSection(ShellSection _) {}

/// מה שהבית מפעיל. הכול מוזרק, כך שבדיקה וצילום בונים את הדף בלי סשן.
class HomeActions {
  const HomeActions({
    this.onInstallHere = _noop,
    this.onUpdateHere = _noop,
    this.onDownload = _noop,
    this.onLaunch = _noop,
    this.onRecheck = _noop,
    this.onCancelDownload = _noop,
    this.onOpenSection = _noopSection,
    this.onOpenSettings = _noop,
    this.onHelp = _noop,
    this.onToggleLanguage = _noop,
    this.onDismissReportsIntro = _noop,
    this.onDismissLegacyReports = _noop,
    this.onRestartElevated = _noop,
    this.onDismissElevation = _noop,
    this.onReviewLauncherUpdate = _noop,
    this.onInstallLauncherUpdate = _noop,
  });

  final VoidCallback onInstallHere;
  final VoidCallback onUpdateHere;
  final VoidCallback onDownload;
  final VoidCallback onLaunch;
  final VoidCallback onRecheck;
  final VoidCallback onCancelDownload;
  final ValueChanged<ShellSection> onOpenSection;
  final VoidCallback onOpenSettings;
  final VoidCallback onHelp;
  final VoidCallback onToggleLanguage;
  final VoidCallback onDismissReportsIntro;
  final VoidCallback onDismissLegacyReports;
  final VoidCallback onRestartElevated;
  final VoidCallback onDismissElevation;
  final VoidCallback onReviewLauncherUpdate;
  final VoidCallback onInstallLauncherUpdate;
}

/// דף הבית: הודעות, הגיבור ("מה לעשות עכשיו"), אריחים ושורת תחתית. בכונן
/// ריק במחשב בלי אוצריא — מסך הפתיחה במקומם.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.model,
    this.actions = const HomeActions(),
    this.taskProgress,
    this.launcherProgress,
  });

  final HomeViewModel model;
  final HomeActions actions;

  /// מד ההתקדמות של המשימה שרצה — `ListenableBuilder` על ה-progress של
  /// הקונטרולרים, שהמסגרת בונה.
  final Widget? taskProgress;

  /// אחוז ההורדה של הכלי עצמו, באותו אופן.
  final Widget? launcherProgress;

  /// מתחת לרוחב הזה הגיבור מוותר על הסמל ומצמצם ריפוד (`@container` במוקאפ).
  static const double narrowWidth = 800;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth <= narrowWidth;
        if (model.guidance.primary == GuidancePrimary.welcome) {
          return WelcomeView(
            key: ShellKeys.welcome,
            offline: model.readOnly || model.online == false,
            narrow: narrow,
            notices: [..._driveNotices(context), ..._notices(context)],
            links: _welcomeLinks(context),
            onDownload: actions.onDownload,
            onHelp: actions.onHelp,
            onToggleLanguage: actions.onToggleLanguage,
          );
        }
        const padding = LayoutConstraints.pagePadding;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  LayoutConstraints.panelContentMaxWidth + padding.horizontal,
            ),
            child: ListView(
              padding: padding,
              children: [
                ..._driveNotices(context),
                ..._notices(context),
                _Hero(
                  model: model,
                  actions: actions,
                  narrow: narrow,
                  progress: taskProgress,
                ),
                if (model.showsNewPlugins) ...[
                  const SizedBox(height: 12),
                  _newPluginsBanner(context),
                  // הפס נושא מרווח תחתון של 12; המקטע שאחריו מתחיל ב-28.
                  const SizedBox(height: 16),
                  SectionLabel(context.strings.guide.tilesLabel, first: true),
                ] else
                  SectionLabel(context.strings.guide.tilesLabel),
                _Tiles(model: model, onOpen: actions.onOpenSection),
                _Foot(
                  model: model,
                  actions: actions,
                  launcherProgress: launcherProgress,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _driveNotices(BuildContext context) {
    if (!model.readOnly) return const [];
    final t = context.strings.readOnlyDrive;
    final full = model.driveFull;
    return [
      NoticeBanner(
        key: full ? ShellKeys.driveFullNotice : ShellKeys.readOnlyNotice,
        leading: IconTile(
          icon: full
              ? FluentIcons.storage_24_regular
              : FluentIcons.lock_closed_24_regular,
          tone: IconTileTone.quiet,
        ),
        title: full ? t.bannerTitleDriveFull : t.bannerTitle,
        body: full ? t.bannerSubtitleDriveFull : t.bannerSubtitle,
      ),
    ];
  }

  /// "עדכון כאן" עצמו מבקש לסגור את אוצריא, ולכן בפס אין כפתור שמתחרה בו.
  List<Widget> _notices(BuildContext context) {
    final g = context.strings.guide;
    final elevation = context.strings.elevation;
    return [
      if (model.reportsIntro) _reportsIntro(context),
      if (model.legacyReportsNotice) _legacyReports(context),
      if (model.guidance.showOtzariaOpenBanner)
        NoticeBanner(
          key: ShellKeys.otzariaOpenBanner,
          kind: NoticeKind.banner,
          leading: IconTile(child: _logo(24)),
          title: g.otzariaOpenTitle,
          body: model.autoInstallSkipped
              ? '${g.autoInstallSkippedLead}${g.otzariaOpenBody}'
              : g.otzariaOpenBody,
        ),
      if (model.offersElevation)
        NoticeBanner(
          key: ShellKeys.elevationBanner,
          kind: NoticeKind.banner,
          leading:
              const IconTile(icon: FluentIcons.shield_checkmark_24_regular),
          title: elevation.bannerTitle,
          body: elevation.bannerContent,
          actions: [
            ActionButton.ghost(
              text: elevation.bannerDismiss,
              onPressed: actions.onDismissElevation,
            ),
            ActionButton.neutral(
              text: elevation.bannerConfirm,
              onPressed: actions.onRestartElevated,
            ),
          ],
        ),
    ];
  }

  /// מה עוד יש בכונן שאין בו אוצריא — במסך הפתיחה אין אריחים.
  List<({String label, VoidCallback onTap})> _welcomeLinks(
    BuildContext context,
  ) {
    final g = context.strings.guide;
    return [
      if (model.customApps > 0)
        (
          label: g.tileCustomApps,
          onTap: () => actions.onOpenSection(ShellSection.customApps),
        ),
      if (model.showsReportsTile)
        (
          label: g.tileReports,
          onTap: () => actions.onOpenSection(ShellSection.reports),
        ),
    ];
  }

  Widget _legacyReports(BuildContext context) {
    final t = context.strings.errorReports;
    return NoticeBanner(
      key: ShellKeys.legacyReportsNotice,
      leading: const IconTile(
        icon: FluentIcons.bug_24_regular,
        tone: IconTileTone.quiet,
      ),
      title: t.legacyReportsDialogTitle,
      body: t.legacyReportsDialogContent,
      actions: [
        ActionButton.neutral(
          text: t.introDialogConfirm,
          onPressed: actions.onDismissLegacyReports,
        ),
      ],
    );
  }

  Widget _reportsIntro(BuildContext context) {
    final t = context.strings.errorReports;
    return NoticeBanner(
      key: ShellKeys.reportsIntroNotice,
      leading: const IconTile(
        icon: FluentIcons.bug_24_regular,
        tone: IconTileTone.quiet,
      ),
      title: t.introDialogTitle,
      // הנוסח נכתב לדו-שיח; בהודעה הפסקאות מתחברות לאחת.
      body: (!model.readOnly
              ? t.introDialogContent
              : model.driveFull
                  ? t.introDialogContentReadOnlyDriveFull
                  : t.introDialogContentReadOnly)
          .replaceAll('\n\n', ' '),
      actions: [
        ActionButton.neutral(
          text: t.introDialogConfirm,
          onPressed: actions.onDismissReportsIntro,
        ),
      ],
    );
  }

  Widget _newPluginsBanner(BuildContext context) {
    final g = context.strings.guide;
    final names = model.newPlugins;
    const shown = 3;
    return NoticeBanner(
      key: ShellKeys.newPluginsBanner,
      kind: NoticeKind.banner,
      leading: const IconTile(icon: FluentIcons.puzzle_piece_24_regular),
      title: g.newPluginsTitle(names.length),
      body: g.newPluginsBody(
        names.take(shown).toList(),
        names.length > shown ? names.length - shown : 0,
      ),
      actions: [
        ActionButton.ghost(
          text: g.toPluginsButton,
          onPressed: () => actions.onOpenSection(ShellSection.plugins),
        ),
      ],
    );
  }
}

Widget _logo(double size) => Image.asset(
      'assets/images/otzaria_logo.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
    );

// ── הגיבור ────────────────────────────────────────────────────────────────────

typedef _Pill = ({IconData icon, String text});

/// הערה קטנה בגיבור (`.hero-note`), עם קישור אופציונלי בסופה.
class _Note {
  const _Note(this.icon, this.text, {this.link, this.onLink});

  final IconData icon;
  final String text;
  final String? link;
  final VoidCallback? onLink;
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.model,
    required this.actions,
    required this.narrow,
    this.progress,
  });

  final HomeViewModel model;
  final HomeActions actions;
  final bool narrow;
  final Widget? progress;

  HomeGuidance get _g => model.guidance;

  @override
  Widget build(BuildContext context) {
    final pad = narrow
        ? const EdgeInsets.all(24)
        : const EdgeInsets.symmetric(horizontal: 32, vertical: 28);

    return Container(
      key: ShellKeys.hero,
      padding: pad,
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        children: [
          Expanded(child: _content(context)),
          if (!narrow) ...[
            const SizedBox(width: 24),
            _emblem(),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _emblem() => switch (_g.primary) {
        GuidancePrimary.upToDate ||
        GuidancePrimary.newerHereThanDrive =>
          const _Emblem(icon: FluentIcons.checkmark_24_regular, done: true),
        GuidancePrimary.downloadToDrive => const _Emblem(
            icon: FluentIcons.usb_stick_24_regular,
            mini: FluentIcons.arrow_download_16_regular,
          ),
        GuidancePrimary.installHere => const _Emblem(
            icon: FluentIcons.desktop_24_regular,
            mini: FluentIcons.arrow_download_16_regular,
          ),
        GuidancePrimary.attention => const _Emblem(
            icon: FluentIcons.desktop_24_regular,
            mini: FluentIcons.warning_16_regular,
          ),
        GuidancePrimary.taskInProgress
            when model.task == HomeTask.downloading =>
          const _Emblem(
            icon: FluentIcons.usb_stick_24_regular,
            mini: FluentIcons.arrow_download_16_regular,
          ),
        GuidancePrimary.checking => const _Emblem(
            icon: FluentIcons.desktop_24_regular,
            mini: FluentIcons.search_16_regular,
          ),
        _ => const _Emblem(
            icon: FluentIcons.desktop_24_regular,
            mini: FluentIcons.arrow_sync_16_regular,
          ),
      };

  Widget _content(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = _spec(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(context),
        const SizedBox(height: 10),
        Text(
          spec.title,
          style: AppTextStyles.heroTitle.copyWith(color: cs.onSurface),
        ),
        if (spec.body != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Text(
              spec.body!,
              style: AppTextStyles.body.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
        if (spec.pills.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final pill in spec.pills) _PillChip(pill)],
          ),
        ],
        if (progress != null && _g.primary == GuidancePrimary.taskInProgress)
          progress!,
        if (_g.primary == GuidancePrimary.checking) ...[
          const SizedBox(height: 22),
          const SizedBox(
            key: ShellKeys.heroChecking,
            width: 220,
            child: AppProgressBar(),
          ),
        ],
        if (spec.actions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: spec.actions,
          ),
        ],
        for (final note in spec.notes) ...[
          const SizedBox(height: 14),
          _HeroNote(note),
        ],
      ],
    );
  }

  Widget _eyebrow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = context.strings.guide;
    final style = AppTextStyles.small.copyWith(color: cs.onSurfaceVariant);
    final online = model.online;
    final installed = model.installedVersion;
    return Wrap(
      key: ShellKeys.eyebrow,
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(
          online == true
              ? FluentIcons.globe_desktop_20_regular
              : FluentIcons.desktop_16_regular,
          size: 16,
          color: cs.primary,
        ),
        Text(
          switch (online) {
            true => g.eyebrowOnline,
            false => g.eyebrowOffline,
            null => g.eyebrowThisComputer,
          },
          style: style,
        ),
        Text('·', style: style.copyWith(color: cs.outline)),
        Text(
          installed == null
              ? g.eyebrowNotInstalled
              : g.eyebrowOtzaria(
                  displayVersion(
                    installed,
                    other: model.onlineAppVersion ?? model.driveAppVersion,
                  ),
                ),
          style: style,
        ),
      ],
    );
  }

  ({
    String title,
    String? body,
    List<_Pill> pills,
    List<Widget> actions,
    List<_Note> notes,
  }) _spec(BuildContext context) {
    final g = context.strings.guide;
    final m = model;

    Widget primary(String text, VoidCallback? onPressed, {IconData? icon}) =>
        ActionButton.recommended(
          key: ShellKeys.heroPrimary,
          text: text,
          icon: icon,
          size: ActionButtonSize.lg,
          autofocus: true,
          onPressed: onPressed,
        );
    Widget secondary(String text, VoidCallback? onPressed, {IconData? icon}) =>
        ActionButton.ghost(
          key: ShellKeys.heroSecondary,
          text: text,
          icon: icon,
          spinning: icon != null && m.checkingNow,
          onPressed: onPressed,
        );

    final busy = m.isCheckingOnline;
    final quietActions = [
      primary(g.launchButton, m.canLaunch ? actions.onLaunch : null),
      secondary(
        g.recheckButton,
        m.checkingNow || m.checkBlocked ? null : actions.onRecheck,
        icon: FluentIcons.arrow_sync_24_regular,
      ),
    ];

    switch (_g.primary) {
      case GuidancePrimary.checking || GuidancePrimary.welcome:
        return (
          title: g.checkingTitle,
          body: g.checkingBody,
          pills: const [],
          actions: const [],
          notes: const [],
        );
      case GuidancePrimary.installHere:
        return (
          title: g.installHereTitle,
          body: g.installHereBody,
          pills: _herePills(context),
          actions: [primary(g.installHereButton, actions.onInstallHere)],
          notes: const [],
        );
      case GuidancePrimary.updateHere:
        return (
          title: g.updateHereTitle,
          body: g.updateHereBody,
          pills: _herePills(context),
          actions: [
            primary(g.updateHereButton, actions.onUpdateHere),
            secondary(g.whatsNewButton, () {
              actions.onOpenSection(_whatsNewSection());
            }),
          ],
          notes: const [],
        );
      case GuidancePrimary.downloadToDrive:
        final hereToo = _g.secondary == GuidanceSecondary.updateHereToo;
        return (
          title: g.downloadTitle,
          body: g.downloadBody,
          pills: _downloadPills(context),
          actions: [
            primary(
              g.downloadButton,
              busy ? null : actions.onDownload,
              icon: FluentIcons.arrow_download_24_regular,
            ),
            if (hereToo)
              secondary(
                g.updateHereTooButton,
                m.installedVersion == null
                    ? actions.onInstallHere
                    : actions.onUpdateHere,
              ),
          ],
          notes: [
            if (m.libraryDownloadFailed)
              _Note(FluentIcons.info_16_regular, g.libraryRetryNote),
            ..._syncOffNotes(context),
            if (hereToo)
              _Note(
                FluentIcons.info_16_regular,
                g.updateHereTooNote(
                  _g.hereItems.contains(GuidanceItem.app) &&
                          m.driveAppVersion != null
                      ? displayVersion(
                          m.driveAppVersion!,
                          other: m.onlineAppVersion,
                        )
                      : null,
                ),
              ),
          ],
        );
      case GuidancePrimary.newerHereThanDrive:
        return (
          title: g.newerTitle,
          body: g.newerBody(
            displayVersion(m.installedVersion ?? '', other: m.driveAppVersion),
            displayVersion(m.driveAppVersion ?? '', other: m.installedVersion),
          ),
          pills: const [],
          actions: quietActions,
          notes: [
            if (m.online != true)
              _Note(FluentIcons.usb_stick_20_regular, g.newerNote),
            ..._quietNotes(context, offline: false),
          ],
        );
      case GuidancePrimary.upToDate:
        return (
          title: g.upToDateTitle,
          body: g.upToDateBody(
            m.installedVersion == null
                ? null
                : displayVersion(m.installedVersion!),
            offline: m.online == false,
          ),
          pills: const [],
          actions: quietActions,
          notes: _quietNotes(context, offline: true),
        );
      case GuidancePrimary.attention:
        final library = _g.attentionItem == GuidanceItem.library;
        return (
          title: library ? g.attentionLibraryTitle : g.attentionAppTitle,
          body: g.attentionBody,
          pills: const [],
          actions: [
            primary(
              library ? g.attentionLibraryButton : g.attentionAppButton,
              () => actions.onOpenSection(
                library ? ShellSection.library : ShellSection.otzaria,
              ),
            ),
          ],
          notes: const [],
        );
      case GuidancePrimary.taskInProgress:
        return switch (m.task) {
          HomeTask.downloading => (
              title: g.taskDownloadingTitle,
              body: g.taskDownloadingBody,
              pills: _downloadPills(context),
              // הביטול עצמו נשאל בדו-שיח (`confirmCancelDownload`).
              actions: [
                ActionButton.neutral(
                  key: ShellKeys.heroCancel,
                  text: m.cancellingDownload
                      ? context.strings.home.cancelDownloadPending
                      : context.strings.common.cancel,
                  onPressed:
                      m.cancellingDownload ? null : actions.onCancelDownload,
                ),
              ],
              notes: const [],
            ),
          HomeTask.installingApp => (
              title: g.taskInstallingAppTitle,
              body: null,
              pills: const [],
              actions: const [],
              notes: const [],
            ),
          HomeTask.updatingLibrary => (
              title: g.taskUpdatingLibraryTitle,
              body: null,
              pills: const [],
              actions: const [],
              notes: const [],
            ),
          HomeTask.other => (
              title: g.taskBusyTitle,
              body: g.taskBusyBody,
              pills: const [],
              actions: const [],
              notes: const [],
            ),
        };
    }
  }

  ShellSection _whatsNewSection() {
    final items = _g.hereItems;
    if (items.contains(GuidanceItem.app)) return ShellSection.otzaria;
    if (items.contains(GuidanceItem.library)) return ShellSection.library;
    return ShellSection.plugins;
  }

  List<_Note> _quietNotes(BuildContext context, {required bool offline}) {
    final g = context.strings.guide;
    return switch (_g.secondary) {
      GuidanceSecondary.offlineHint when offline => [
          _Note(FluentIcons.usb_stick_20_regular, g.offlineNote),
        ],
      GuidanceSecondary.checkOnlineNow => [
          _Note(FluentIcons.info_16_regular, g.checkOnlineNowNote),
        ],
      GuidanceSecondary.noSyncSelection => [
          _Note(
            FluentIcons.info_16_regular,
            g.noSyncSelectionNote,
            link: g.chooseInSettingsLink,
            onLink: actions.onOpenSettings,
          ),
        ],
      _ => const [],
    };
  }

  /// מה שיש ברשת ואינו מסומן להורדה — נאמר, כדי שלא ידלג בשקט.
  List<_Note> _syncOffNotes(BuildContext context) {
    final g = context.strings.guide;
    final m = model;
    final app = m.onlineAppVersion != null && !m.syncApp;
    final library =
        (m.onlineLibraryVersion != null || m.onlineCompanionNames != null) &&
            !m.syncLibrary;
    final plugins = (m.onlinePluginChanges > 0 ||
            m.onlinePluginCatalogChanged ||
            m.onlineStoreApp) &&
        !m.syncPlugins;
    if (!app && !library && !plugins) return const [];
    return [
      _Note(
        FluentIcons.info_16_regular,
        g.syncOffNote(app: app, library: library, plugins: plugins),
        link: g.changeInSettingsLink,
        onLink: actions.onOpenSettings,
      ),
    ];
  }

  List<_Pill> _herePills(BuildContext context) {
    final g = context.strings.guide;
    final m = model;
    final firstInstall = m.installedVersion == null;
    // סדר התצוגה קבוע (תוכנה, ספרייה, תוספים), גם כשהעדכון רץ בסדר אחר.
    final items = [..._g.hereItems]..sort((a, b) => a.index - b.index);
    return [
      for (final item in items)
        switch (item) {
          GuidanceItem.app => (
              icon: FluentIcons.desktop_16_regular,
              text: g.pillApp(
                displayVersion(
                  m.driveAppVersion ?? '',
                  other: m.installedVersion,
                ),
              ),
            ),
          GuidanceItem.library => (
              icon: FluentIcons.library_16_regular,
              text: firstInstall
                  ? g.pillLibraryFull
                  : m.driveCompanionNames != null
                      ? g.pillLibraryCompanions(m.driveCompanionNames!)
                      : g.pillLibraryUpdate,
            ),
          GuidanceItem.plugins => (
              icon: FluentIcons.puzzle_piece_16_regular,
              text: g.pillPluginUpdates(m.pluginUpdatesOnDrive),
            ),
        },
    ];
  }

  List<_Pill> _downloadPills(BuildContext context) {
    final g = context.strings.guide;
    final m = model;
    return [
      for (final item in _g.downloadItems)
        ...switch (item) {
          GuidanceItem.app => [
              (
                icon: FluentIcons.desktop_16_regular,
                text: m.onlineAppVersion == null
                    ? g.tileApp
                    : g.pillApp(
                        displayVersion(
                          m.onlineAppVersion!,
                          other: m.installedVersion,
                        ),
                      ),
              ),
            ],
          GuidanceItem.library => [
              (
                icon: FluentIcons.library_16_regular,
                text: m.onlineLibraryVersion == null &&
                        m.onlineCompanionNames != null
                    ? g.pillLibraryCompanions(m.onlineCompanionNames!)
                    : g.pillLibraryUpdate,
              ),
            ],
          GuidanceItem.plugins => [
              if (_onlinePluginsPill(m, g) case final text?)
                (icon: FluentIcons.puzzle_piece_16_regular, text: text),
            ],
        },
    ];
  }
}

/// התוספים וחנות התוספים שבאוצריא — גלולה אחת.
String? _onlinePluginsPill(HomeViewModel m, GuidanceStrings g) {
  final changes = m.onlinePluginChanges;
  if (changes > 0) {
    return m.onlineStoreApp
        ? g.pillPluginsWithStore(changes)
        : g.pillPlugins(changes);
  }
  if (m.onlinePluginCatalogChanged) return g.pillPluginsCatalog;
  return m.onlineStoreApp ? g.pillStoreApp : null;
}

/// הסמל העגול שבצד הגיבור (`.emblem`): 72, טבעת 6, ותג קטן בפינה.
class _Emblem extends StatelessWidget {
  const _Emblem({required this.icon, this.mini, this.done = false});

  final IconData icon;
  final IconData? mini;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disc = done ? cs.primary : cs.secondaryContainer;
    final ring = done
        ? AppSurfaces.badgeRing(cs.primary)
        : AppSurfaces.emblemRing(cs.secondaryContainer);
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
          ),
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: disc),
            child: Icon(
              icon,
              size: done ? 34 : 32,
              color: done ? cs.onPrimary : cs.onSecondaryContainer,
            ),
          ),
          if (mini != null)
            PositionedDirectional(
              bottom: 1,
              end: -1,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppSurfaces.card(context),
                ),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                  ),
                  child: Icon(mini, size: 16, color: cs.onPrimary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "מה ייכלל" (`.inc`): גלולה עם מסגרת, סמל 16 ו-13.
class _PillChip extends StatelessWidget {
  const _PillChip(this.pill);

  final _Pill pill;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: AppTokens.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: AppTokens.pill,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pill.icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            pill.text,
            style: AppTextStyles.small.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _HeroNote extends StatelessWidget {
  const _HeroNote(this.note);

  final _Note note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = AppTextStyles.small.copyWith(color: cs.onSurfaceVariant);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(note.icon, size: 16, color: cs.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(note.text, style: style),
              if (note.link != null)
                TextLink(text: note.link!, onTap: note.onLink),
            ],
          ),
        ),
      ],
    );
  }
}

// ── האריחים ───────────────────────────────────────────────────────────────────

typedef _TileSpec = ({
  ShellSection section,
  Widget icon,
  String name,
  StatusKind kind,
  String label,
  IconData? chipIcon,
});

class _Tiles extends StatelessWidget {
  const _Tiles({required this.model, required this.onOpen});

  final HomeViewModel model;
  final ValueChanged<ShellSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final tiles = _specs(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 520 ? 1 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += columns) {
          final row = tiles.sublist(i, (i + columns).clamp(0, tiles.length));
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (j, spec) in row.indexed) ...[
                    if (j > 0) const SizedBox(width: 10),
                    Expanded(child: _Tile(spec: spec, onOpen: onOpen)),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }

  List<_TileSpec> _specs(BuildContext context) {
    final g = context.strings.guide;
    final common = context.strings.common;
    final m = model;

    (StatusKind, String, IconData?) shared(TileStatus status) =>
        switch (status) {
          TileStatus.unknown => (
              StatusKind.unknown,
              common.notCheckedYet,
              null
            ),
          TileStatus.checking => (StatusKind.working, g.chipChecking, null),
          TileStatus.attention => (StatusKind.error, g.chipAttention, null),
          TileStatus.installHere => (
              StatusKind.needsAction,
              g.chipReadyToInstall,
              FluentIcons.arrow_download_16_regular,
            ),
          TileStatus.nothingOnDrive => (
              StatusKind.needsAction,
              g.chipNotOnDrive,
              null,
            ),
          TileStatus.onlineAvailable => (
              StatusKind.updateAvailable,
              g.chipNewOnline,
              FluentIcons.arrow_download_16_regular,
            ),
          _ => (StatusKind.ok, common.upToDate, null),
        };
    final installed = m.installedVersion == null
        ? null
        : displayVersion(m.installedVersion!, other: m.driveAppVersion);

    final app = switch (m.appTile) {
      TileStatus.working => (StatusKind.working, g.chipInstalling, null),
      TileStatus.upToDate => (
          StatusKind.ok,
          installed == null ? common.upToDate : g.chipAppUpToDate(installed),
          null,
        ),
      TileStatus.newerHere => (StatusKind.ok, g.chipNewerHere, null),
      TileStatus.updateHere => (
          StatusKind.updateAvailable,
          g.chipAppUpdate(
            displayVersion(
              m.driveAppVersion ?? '',
              other: m.installedVersion,
            ),
          ),
          null,
        ),
      TileStatus.nothingOnDrive when installed != null => (
          StatusKind.ok,
          g.chipAppInstalled(installed),
          null,
        ),
      final other => shared(other),
    };
    final library = switch (m.libraryTile) {
      TileStatus.working => (StatusKind.working, g.chipUpdating, null),
      TileStatus.upToDate => (StatusKind.ok, g.chipLibraryUpToDate, null),
      TileStatus.updateHere => (
          StatusKind.updateAvailable,
          g.chipLibraryUpdate,
          null,
        ),
      TileStatus.needsConsent => (
          StatusKind.needsAction,
          context.strings.libraryDomain.semanticConsentRequired,
          FluentIcons.sparkle_16_regular,
        ),
      final other => shared(other),
    };
    final plugins = switch (m.pluginsTile) {
      TileStatus.checking => (StatusKind.working, g.chipChecking, null),
      TileStatus.onlineAvailable => shared(TileStatus.onlineAvailable),
      TileStatus.updateHere => (
          StatusKind.updateAvailable,
          g.chipPluginUpdates(m.pluginUpdatesOnDrive),
          null,
        ),
      _ when m.pluginsOnDrive == 0 => (
          StatusKind.needsAction,
          g.chipNoPlugins,
          FluentIcons.puzzle_piece_16_regular,
        ),
      _ when m.installedVersion == null || m.pluginsInstalled == 0 => (
          StatusKind.needsAction,
          g.chipPluginsOnDrive(m.pluginsOnDrive),
          FluentIcons.puzzle_piece_16_regular,
        ),
      _ => (StatusKind.ok, g.chipPluginsInstalled(m.pluginsInstalled), null),
    };

    _TileSpec spec(
      ShellSection section,
      Widget icon,
      String name,
      (StatusKind, String, IconData?) chip,
    ) =>
        (
          section: section,
          icon: icon,
          name: name,
          kind: chip.$1,
          label: chip.$2,
          chipIcon: chip.$3,
        );

    return [
      spec(ShellSection.otzaria, IconTile(child: _logo(26)), g.tileApp, app),
      spec(
        ShellSection.library,
        const IconTile(icon: FluentIcons.library_24_regular),
        g.tileLibrary,
        library,
      ),
      spec(
        ShellSection.plugins,
        const IconTile(icon: FluentIcons.puzzle_piece_24_regular),
        g.tilePlugins,
        plugins,
      ),
      if (m.customApps > 0)
        spec(
          ShellSection.customApps,
          const IconTile(icon: FluentIcons.apps_24_regular),
          g.tileCustomApps,
          m.customAppsPending > 0
              ? (
                  m.customAppsUnannounced
                      ? StatusKind.updateAvailable
                      : StatusKind.needsAction,
                  g.chipAppsPending(m.customAppsPending),
                  FluentIcons.arrow_download_16_regular,
                )
              : (StatusKind.ok, g.chipAppsInstalled(m.customApps), null),
        ),
      if (m.showsReportsTile)
        spec(
          ShellSection.reports,
          const IconTile(icon: FluentIcons.bug_24_regular),
          g.tileReports,
          m.reportsSending
              ? (StatusKind.working, g.chipReportsSending, null)
              // בכונן מוגן אין איסוף ואין שליחה: שליחה מוחקת מהכונן.
              : m.readOnly
                  ? (StatusKind.locked, g.chipReportsLocked, null)
                  : m.reportsToCollect > 0
                      ? (
                          StatusKind.updateAvailable,
                          g.chipReportsToCollect(m.reportsToCollect),
                          FluentIcons.arrow_upload_16_regular,
                        )
                      : (
                          StatusKind.updateAvailable,
                          g.chipReportsToSend(m.reportsToSend),
                          FluentIcons.send_16_regular,
                        ),
        ),
    ];
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.spec, required this.onOpen});

  final _TileSpec spec;
  final ValueChanged<ShellSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      key: ShellKeys.tile(spec.section),
      onTap: () => onOpen(spec.section),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              spec.icon,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.name,
                      style: AppTextStyles.rowValue.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StatusChip(
                      kind: spec.kind,
                      label: spec.label,
                      icon: spec.chipIcon,
                    ),
                  ],
                ),
              ),
              Icon(
                context.isRtl
                    ? FluentIcons.chevron_left_20_filled
                    : FluentIcons.chevron_right_20_filled,
                size: 20,
                color: cs.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── שורת התחתית ───────────────────────────────────────────────────────────────

class _Foot extends StatelessWidget {
  const _Foot({
    required this.model,
    required this.actions,
    this.launcherProgress,
  });

  final HomeViewModel model;
  final HomeActions actions;
  final Widget? launcherProgress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = context.strings.guide;
    final style = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);
    final checkedAt = model.checkedAt;
    final drive = model.driveName;

    final canCheck = !model.readOnly &&
        !model.checkBlocked &&
        model.guidance.primary != GuidancePrimary.taskInProgress;
    final meta = <Widget>[
      if (checkedAt != null || canCheck)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (checkedAt != null)
              Tooltip(
                key: ShellKeys.checkedAt,
                message: g.recheckHint,
                child: Text(g.checkedAt(formatClock(checkedAt)), style: style),
              ),
            if (checkedAt != null && canCheck) const SizedBox(width: 8),
            if (canCheck && model.checkingNow)
              Row(
                key: ShellKeys.checkNow,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(g.chipChecking, style: style),
                ],
              )
            else if (canCheck)
              TextLink(
                key: ShellKeys.checkNow,
                text: g.checkNowLink,
                onTap: actions.onRecheck,
                style: AppTextStyles.meta,
              ),
          ],
        ),
      if (drive != null)
        Row(
          key: ShellKeys.driveLine,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.usb_stick_20_regular, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              [
                g.drive(drive),
                if (model.driveFull)
                  g.driveFullSuffix
                else if (model.readOnly)
                  g.driveReadOnlySuffix,
              ].join(' · '),
              style: style,
            ),
          ],
        ),
    ];

    final launcher = model.launcher;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // כמו `.selfupd` (flex:1, min-width:260): המשבצת תמיד תופסת את
          // ההתחלה, כך שהמטא נשאר בקצה גם כשאין שורת כלי.
          if (constraints.maxWidth >= _wideFoot) {
            return Row(
              children: [
                Expanded(
                  child: launcher == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _launcher(context, launcher, style),
                        ),
                ),
                for (final item in meta) ...[
                  const SizedBox(width: 16),
                  item,
                ],
              ],
            );
          }
          return Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (launcher != null) _launcher(context, launcher, style),
              ...meta,
            ],
          );
        },
      ),
    );
  }

  /// מתחת לזה שורת הכלי והמטא לא נכנסים יחד בשורה אחת.
  static const double _wideFoot = 640;

  Widget _launcher(BuildContext context, LauncherLine line, TextStyle style) {
    final cs = Theme.of(context).colorScheme;
    final g = context.strings.guide;
    final t = context.strings.launcherUpdate;
    final busy = model.guidance.primary == GuidancePrimary.taskInProgress;
    final version = line.version == null ? '' : displayVersion(line.version!);
    final (IconData icon, String text, String? link, VoidCallback? onLink) =
        switch (line.kind) {
      LauncherLineKind.online => (
          FluentIcons.sparkle_16_regular,
          g.launcherOnline(version),
          g.launcherDetailsLink,
          busy ? null : actions.onReviewLauncherUpdate,
        ),
      LauncherLineKind.ready => (
          FluentIcons.sparkle_16_regular,
          g.launcherOnDrive(version),
          t.installButton,
          busy ? null : actions.onInstallLauncherUpdate,
        ),
      LauncherLineKind.readyManual => (
          FluentIcons.sparkle_16_regular,
          '${g.launcherOnDrive(version)} · ${t.installUnavailableNotice}',
          null,
          null,
        ),
      LauncherLineKind.downloading => (
          FluentIcons.arrow_download_16_regular,
          g.launcherDownloading,
          null,
          null,
        ),
      LauncherLineKind.error => (
          FluentIcons.warning_16_regular,
          line.error ?? '',
          line.version == null ? null : g.launcherDetailsLink,
          busy ? null : actions.onReviewLauncherUpdate,
        ),
    };
    return ConstrainedBox(
      key: ShellKeys.launcherLine,
      constraints: const BoxConstraints(minWidth: 260),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          Text(text, style: style),
          if (line.kind == LauncherLineKind.downloading &&
              launcherProgress != null)
            launcherProgress!,
          if (link != null)
            TextLink(text: link, onTap: onLink, style: AppTextStyles.meta),
        ],
      ),
    );
  }
}

/// שם השפה האחרת בשמה שלה — הכפתור שבמסך הפתיחה.
String otherLanguageName(AppStrings strings) =>
    strings.language == AppLanguage.hebrew
        ? strings.settings.languageEnglish
        : strings.settings.languageHebrew;
