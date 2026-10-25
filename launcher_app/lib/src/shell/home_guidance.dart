// הכוונת דף הבית: פונקציה טהורה מעובדות למשפט אחד ולפעולה אחת. בלי
// Flutter ובלי קונטרולרים, כדי שכל מצב ייבדק בטבלה.

/// מקביל ל-`OtzariaModuleStatus` בשם ובסדר — ראו
/// `guidanceFactsFromSession`.
enum AppStatusFact {
  idle,
  checking,
  upToDate,
  updateAvailable,
  installing,
  error,
  needsDownload,
  installedIsNewer,
}

/// מקביל ל-`LibraryModuleStatus` בשם ובסדר.
enum LibraryStatusFact {
  idle,
  checking,
  upToDate,
  updateAvailable,
  updating,
  error,
  needsManualPath,
  needsDownload,
  personalTargetElsewhere,
}

/// רכיב שנכלל בפעולה — בסדר הביצוע שלה.
enum GuidanceItem { app, library, plugins }

enum GuidancePrimary {
  checking,
  welcome,
  installHere,
  updateHere,
  downloadToDrive,
  upToDate,
  newerHereThanDrive,
  attention,
  taskInProgress,
}

/// "הורדה" שלא מצאה מה להביא — מה הבית אומר במקום מסך משימה.
enum FoundNothing {
  /// בדיקה ברשת רצה ממש לפני ההחלטה.
  rechecked,

  /// הבדיקות היו טריות, וההחלטה נשענה עליהן.
  earlierCheck,
}

enum GuidanceSecondary {
  none,
  updateHereToo,

  /// "בדוק עכשיו": משהו עוד לא נבדק — ברשת, או מקומית כשהבדיקה
  /// האוטומטית כבויה.
  checkOnlineNow,
  offlineHint,
  noSyncSelection,
}

/// מה האריח אומר על הרכיב שלו.
enum TileStatus {
  unknown,
  checking,
  working,
  upToDate,
  newerHere,
  installHere,
  updateHere,
  needsConsent,
  nothingOnDrive,
  attention,

  /// באתר יש חדש שההורדה לכונן תביא — כמו "מה ייכלל" בגיבור.
  onlineAvailable,
}

class GuidanceFacts {
  const GuidanceFacts({
    this.readOnly = false,
    this.driveFull = false,
    this.otzariaStatus = AppStatusFact.upToDate,
    this.otzariaInstalled = true,
    this.otzariaMirrorVersion,
    this.otzariaRunning = false,
    this.libraryApplyActive = false,
    this.libraryStatus = LibraryStatusFact.upToDate,
    this.libraryFreshInstall = false,
    this.semanticConsentRequired = false,
    this.pluginsLoading = false,
    this.pluginUpdatesOnDrive = 0,
    this.online,
    this.onlineApp = false,
    this.onlineLibrary = false,
    this.onlinePlugins = false,
    this.syncApp = true,
    this.syncLibrary = true,
    this.syncPlugins = true,
    this.autoCheckUpdates = false,
    this.isCheckingOnline = false,
    this.longTaskRunning = false,
    this.installing = false,
  });

  final bool readOnly;
  final bool driveFull;
  final AppStatusFact otzariaStatus;
  final bool otzariaInstalled;
  final String? otzariaMirrorVersion;
  final bool otzariaRunning;
  final bool libraryApplyActive;
  final LibraryStatusFact libraryStatus;
  final bool libraryFreshInstall;
  final bool semanticConsentRequired;
  final bool pluginsLoading;

  /// תוספים מותקנים שבכונן יש להם גרסה חדשה יותר.
  final int pluginUpdatesOnDrive;

  /// `null` = לא נבדק; `true` = לפחות בדיקה אחת הצליחה; `false` = כולן נכשלו.
  final bool? online;

  /// יש ברשת משהו שעוד אינו בכונן (`hasOnlineUpdate` של כל מודול).
  final bool onlineApp;
  final bool onlineLibrary;
  final bool onlinePlugins;

  /// מה מסומן להורדה בהגדרות (`downloadsLibrary` לספרייה).
  final bool syncApp;
  final bool syncLibrary;
  final bool syncPlugins;
  final bool autoCheckUpdates;
  final bool isCheckingOnline;

  /// הורדה, סנכרון, ייצוא, תוכנה מותאמת — `AppSession.longTaskRunning`.
  final bool longTaskRunning;
  final bool installing;

  bool get hasSyncSelection => syncApp || syncLibrary || syncPlugins;
}

class HomeGuidance {
  const HomeGuidance({
    required this.primary,
    this.secondary = GuidanceSecondary.none,
    this.hereItems = const [],
    this.downloadItems = const [],
    this.attentionItem,
    this.showOtzariaOpenBanner = false,
    this.readOnly = false,
    this.driveFull = false,
  });

  final GuidancePrimary primary;
  final GuidanceSecondary secondary;

  /// מה יותקן במחשב הזה, בסדר ההתקנה.
  final List<GuidanceItem> hereItems;

  /// מה יורד לכונן, בסדר ההורדה.
  final List<GuidanceItem> downloadItems;

  /// הרכיב שהדף שלו מסביר מה לא בסדר, כש-[primary] הוא `attention`.
  final GuidanceItem? attentionItem;
  final bool showOtzariaOpenBanner;
  final bool readOnly;
  final bool driveFull;

  @override
  String toString() => 'HomeGuidance($primary, $secondary, here: $hereItems, '
      'download: $downloadItems, attention: $attentionItem, '
      'banner: $showOtzariaOpenBanner)';
}

/// סדר שלבי "עדכון כאן": התקנה ראשונה — תוכנה ואז ספרייה, בלי תוספים;
/// עדכון — ספרייה, תוכנה, ותוספים אחרונים.
List<GuidanceItem> updateHereStages({
  required bool firstInstall,
  required bool app,
  required bool library,
  required bool plugins,
}) =>
    firstInstall
        ? [if (app) GuidanceItem.app, if (library) GuidanceItem.library]
        : [
            if (library) GuidanceItem.library,
            if (app) GuidanceItem.app,
            if (plugins) GuidanceItem.plugins,
          ];

List<GuidanceItem> _hereItems(GuidanceFacts f) => updateHereStages(
      firstInstall: !f.otzariaInstalled,
      app: f.otzariaStatus == AppStatusFact.updateAvailable,
      library: f.libraryStatus == LibraryStatusFact.updateAvailable,
      plugins: f.pluginUpdatesOnDrive > 0,
    );

/// מה יש ברשת שעוד אינו בכונן, בלי להתחשב בבחירה בהגדרות.
List<GuidanceItem> _onlineItems(GuidanceFacts f) => [
      if (f.onlineApp) GuidanceItem.app,
      if (f.onlineLibrary) GuidanceItem.library,
      if (f.onlinePlugins) GuidanceItem.plugins,
    ];

bool _selected(GuidanceFacts f, GuidanceItem item) => switch (item) {
      GuidanceItem.app => f.syncApp,
      GuidanceItem.library => f.syncLibrary,
      GuidanceItem.plugins => f.syncPlugins,
    };

GuidanceItem? _attentionItem(GuidanceFacts f) {
  if (f.otzariaStatus == AppStatusFact.error) return GuidanceItem.app;
  return switch (f.libraryStatus) {
    LibraryStatusFact.error ||
    LibraryStatusFact.needsManualPath ||
    LibraryStatusFact.personalTargetElsewhere =>
      GuidanceItem.library,
    _ => null,
  };
}

HomeGuidance deriveHomeGuidance(GuidanceFacts f) {
  HomeGuidance result(
    GuidancePrimary primary, {
    GuidanceSecondary secondary = GuidanceSecondary.none,
    List<GuidanceItem> here = const [],
    List<GuidanceItem> download = const [],
    GuidanceItem? attention,
  }) =>
      HomeGuidance(
        primary: primary,
        secondary: secondary,
        hereItems: here,
        downloadItems: download,
        attentionItem: attention,
        showOtzariaOpenBanner:
            f.otzariaRunning && here.any((i) => i != GuidanceItem.plugins),
        readOnly: f.readOnly,
        driveFull: f.driveFull,
      );

  if (f.longTaskRunning || f.installing || f.libraryApplyActive) {
    return result(GuidancePrimary.taskInProgress);
  }

  final here = _hereItems(f);
  final onlineItems = _onlineItems(f);
  final canDownload = !f.readOnly && f.online == true;
  final download = canDownload
      ? [
          for (final item in onlineItems)
            if (_selected(f, item)) item,
        ]
      : const <GuidanceItem>[];

  // idle = לא נבדק (הבדיקה האוטומטית כבויה) — לא "בודק", אחרת הגיבור נתקע.
  final localChecking = f.otzariaStatus == AppStatusFact.checking ||
      f.libraryStatus == LibraryStatusFact.checking ||
      f.pluginsLoading;
  final localUnchecked = f.otzariaStatus == AppStatusFact.idle ||
      f.libraryStatus == LibraryStatusFact.idle;
  final onlinePending = !f.readOnly &&
      f.online == null &&
      (f.isCheckingOnline || f.autoCheckUpdates);
  if (localChecking || (onlinePending && here.isEmpty)) {
    return result(GuidancePrimary.checking);
  }

  final driveEmpty = f.otzariaMirrorVersion == null &&
      f.otzariaStatus == AppStatusFact.needsDownload &&
      f.libraryStatus == LibraryStatusFact.needsDownload;
  if (!f.otzariaInstalled && driveEmpty) {
    return result(
      GuidancePrimary.welcome,
      secondary: _quietSecondary(f, onlineItems, download),
      download: download,
    );
  }

  if (here.isNotEmpty && download.isNotEmpty) {
    return result(
      GuidancePrimary.downloadToDrive,
      secondary: GuidanceSecondary.updateHereToo,
      here: here,
      download: download,
    );
  }
  if (here.isNotEmpty) {
    return result(
      f.otzariaInstalled
          ? GuidancePrimary.updateHere
          : GuidancePrimary.installHere,
      here: here,
    );
  }
  if (download.isNotEmpty) {
    return result(GuidancePrimary.downloadToDrive, download: download);
  }

  if (_attentionItem(f) case final item?) {
    return result(GuidancePrimary.attention, attention: item);
  }
  return result(
    f.otzariaStatus == AppStatusFact.installedIsNewer
        ? GuidancePrimary.newerHereThanDrive
        : GuidancePrimary.upToDate,
    secondary: localUnchecked
        ? GuidanceSecondary.checkOnlineNow
        : _quietSecondary(f, onlineItems, download),
  );
}

/// השורה המשנית כשאין מה לעשות: "אין אינטרנט" כאן הוא רמז, לא תקלה.
GuidanceSecondary _quietSecondary(
  GuidanceFacts f,
  List<GuidanceItem> onlineItems,
  List<GuidanceItem> download,
) {
  // בכונן מוגן אין בדיקה ברשת (`AppSession.checkOnline`), ולכן אין מה לומר.
  if (f.readOnly) return GuidanceSecondary.none;
  return switch (f.online) {
    false => GuidanceSecondary.offlineHint,
    null => GuidanceSecondary.checkOnlineNow,
    true when onlineItems.isNotEmpty && download.isEmpty =>
      GuidanceSecondary.noSyncSelection,
    true => GuidanceSecondary.none,
  };
}

/// [download] — `HomeGuidance.downloadItems`: רכיב שההורדה מביאה מוצג כך גם
/// באריח, אחרת האריח ("מעודכנת", "עוד לא בכונן") סותר את הגיבור.
TileStatus deriveTileStatus(
  GuidanceItem item,
  GuidanceFacts f, {
  List<GuidanceItem> download = const [],
}) {
  final local = _localTileStatus(item, f);
  if (!download.contains(item)) return local;
  return switch (local) {
    TileStatus.working ||
    TileStatus.checking ||
    TileStatus.attention ||
    TileStatus.needsConsent =>
      local,
    _ => TileStatus.onlineAvailable,
  };
}

TileStatus _localTileStatus(GuidanceItem item, GuidanceFacts f) =>
    switch (item) {
      GuidanceItem.app => switch (f.otzariaStatus) {
          AppStatusFact.idle => TileStatus.unknown,
          AppStatusFact.checking => TileStatus.checking,
          AppStatusFact.installing => TileStatus.working,
          AppStatusFact.upToDate => TileStatus.upToDate,
          AppStatusFact.installedIsNewer => TileStatus.newerHere,
          AppStatusFact.updateAvailable =>
            f.otzariaInstalled ? TileStatus.updateHere : TileStatus.installHere,
          AppStatusFact.needsDownload => TileStatus.nothingOnDrive,
          AppStatusFact.error => TileStatus.attention,
        },
      GuidanceItem.library => switch (f.libraryStatus) {
          _ when f.libraryApplyActive => TileStatus.working,
          LibraryStatusFact.updating => TileStatus.working,
          // העדכון קודם להסכמה, כמו בגיבור שכולל אותו ב"עדכון כאן".
          LibraryStatusFact.updateAvailable => f.libraryFreshInstall
              ? TileStatus.installHere
              : TileStatus.updateHere,
          _ when f.semanticConsentRequired => TileStatus.needsConsent,
          LibraryStatusFact.idle => TileStatus.unknown,
          LibraryStatusFact.checking => TileStatus.checking,
          LibraryStatusFact.upToDate => TileStatus.upToDate,
          LibraryStatusFact.needsDownload => TileStatus.nothingOnDrive,
          LibraryStatusFact.error ||
          LibraryStatusFact.needsManualPath ||
          LibraryStatusFact.personalTargetElsewhere =>
            TileStatus.attention,
        },
      GuidanceItem.plugins => f.pluginsLoading
          ? TileStatus.checking
          : f.otzariaInstalled && f.pluginUpdatesOnDrive > 0
              ? TileStatus.updateHere
              : TileStatus.upToDate,
    };
