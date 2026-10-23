import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';

typedef _Case = ({
  String name,
  GuidanceFacts facts,
  GuidancePrimary primary,
  GuidanceSecondary secondary,
  List<GuidanceItem> here,
  List<GuidanceItem> download,
  bool banner,
});

_Case _case(
  String name,
  GuidanceFacts facts,
  GuidancePrimary primary, {
  GuidanceSecondary secondary = GuidanceSecondary.none,
  List<GuidanceItem> here = const [],
  List<GuidanceItem> download = const [],
  bool banner = false,
}) =>
    (
      name: name,
      facts: facts,
      primary: primary,
      secondary: secondary,
      here: here,
      download: download,
      banner: banner,
    );

const _app = GuidanceItem.app;
const _library = GuidanceItem.library;
const _plugins = GuidanceItem.plugins;

void main() {
  group('ששת התרחישים של המוקאפ', () {
    final cases = [
      _case(
        'offline-with-updates: מחשב מנותק, בכונן תוכנה וספרייה חדשות',
        const GuidanceFacts(
          online: false,
          otzariaStatus: AppStatusFact.updateAvailable,
          libraryStatus: LibraryStatusFact.updateAvailable,
          pluginUpdatesOnDrive: 2,
        ),
        GuidancePrimary.updateHere,
        here: [_library, _app, _plugins],
      ),
      _case(
        'online-new-updates: מחשב מחובר, ברשת חדש שאין בכונן',
        const GuidanceFacts(
          online: true,
          onlineApp: true,
          onlineLibrary: true,
          onlinePlugins: true,
        ),
        GuidancePrimary.downloadToDrive,
        download: [_app, _library, _plugins],
      ),
      _case(
        'up-to-date: הכול מעודכן ואין חדש ברשת',
        const GuidanceFacts(online: true),
        GuidancePrimary.upToDate,
      ),
      _case(
        'first-time-empty-drive: אוצריא לא מותקנת והכונן ריק',
        const GuidanceFacts(
          online: true,
          otzariaInstalled: false,
          otzariaStatus: AppStatusFact.needsDownload,
          libraryStatus: LibraryStatusFact.needsDownload,
          onlineApp: true,
          onlineLibrary: true,
        ),
        GuidancePrimary.welcome,
        download: [_app, _library],
      ),
      _case(
        'otzaria-open: יש מה לעדכן ואוצריא פתוחה',
        const GuidanceFacts(
          online: false,
          otzariaRunning: true,
          libraryStatus: LibraryStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
        banner: true,
      ),
      _case(
        'read-only: כונן מוגן עם עדכון — התקנה מותרת',
        const GuidanceFacts(
          readOnly: true,
          otzariaStatus: AppStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_app],
      ),
    ];
    _runCases(cases);
  });

  group('קצוות', () {
    final cases = [
      _case(
        'הבדיקה המקומית עוד לא הסתיימה',
        const GuidanceFacts(otzariaStatus: AppStatusFact.checking),
        GuidancePrimary.checking,
      ),
      _case(
        'בדיקה ברשת ראשונה רצה ואין מה להתקין',
        const GuidanceFacts(isCheckingOnline: true),
        GuidancePrimary.checking,
      ),
      _case(
        'בדיקה ברשת רצה אבל יש מה להתקין כאן — לא מחכים לה',
        const GuidanceFacts(
          isCheckingOnline: true,
          libraryStatus: LibraryStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
      ),
      _case(
        'הורדה רצה',
        const GuidanceFacts(
            longTaskRunning: true, online: true, onlineApp: true),
        GuidancePrimary.taskInProgress,
      ),
      _case(
        'התקנה רצה',
        const GuidanceFacts(
          installing: true,
          otzariaStatus: AppStatusFact.updateAvailable,
        ),
        GuidancePrimary.taskInProgress,
      ),
      _case(
        'החלת ספרייה פעילה',
        const GuidanceFacts(libraryApplyActive: true),
        GuidancePrimary.taskInProgress,
      ),
      _case(
        'גם להוריד וגם לעדכן כאן — ההורדה ראשית',
        const GuidanceFacts(
          online: true,
          onlineLibrary: true,
          otzariaStatus: AppStatusFact.updateAvailable,
        ),
        GuidancePrimary.downloadToDrive,
        secondary: GuidanceSecondary.updateHereToo,
        here: [_app],
        download: [_library],
      ),
      _case(
        'המותקן חדש מהכונן — בלי פעולה',
        const GuidanceFacts(
          online: true,
          otzariaStatus: AppStatusFact.installedIsNewer,
        ),
        GuidancePrimary.newerHereThanDrive,
      ),
      _case(
        'המותקן חדש מהכונן, אבל לספרייה יש עדכון',
        const GuidanceFacts(
          online: false,
          otzariaStatus: AppStatusFact.installedIsNewer,
          libraryStatus: LibraryStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
      ),
      _case(
        'מחשב מנותק ומעודכן — רמז, לא תקלה',
        const GuidanceFacts(online: false),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.offlineHint,
      ),
      _case(
        'כונן כתיב שעוד לא נבדק ברשת',
        const GuidanceFacts(),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.checkOnlineNow,
      ),
      _case(
        'כונן מוגן שלא נבדק — אין הצעה לבדוק',
        const GuidanceFacts(readOnly: true),
        GuidancePrimary.upToDate,
      ),
      _case(
        'חדש ברשת אבל שום דבר לא מסומן להורדה',
        const GuidanceFacts(
          online: true,
          onlineApp: true,
          syncApp: false,
          syncLibrary: false,
          syncPlugins: false,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.noSyncSelection,
      ),
      _case(
        'חדש ברשת רק ברכיב שאינו מסומן',
        const GuidanceFacts(
            online: true, onlineLibrary: true, syncLibrary: false),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.noSyncSelection,
      ),
      _case(
        'רק רכיב מסומן נכלל בהורדה',
        const GuidanceFacts(
          online: true,
          onlineApp: true,
          onlinePlugins: true,
          syncPlugins: false,
        ),
        GuidancePrimary.downloadToDrive,
        download: [_app],
      ),
      // בכונן מוגן אין בדיקה ברשת (`AppSession.checkOnline`): online נשאר null,
      // ואין שורה משנית — לא "בדוק עכשיו" ולא הורדה.
      _case(
        'כונן מוגן עם עדכון כאן — עדכון כאן, בלי שורה משנית',
        const GuidanceFacts(
          readOnly: true,
          libraryStatus: LibraryStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
      ),
      _case(
        'כונן מלא והכול מעודכן — בלי "בדוק עכשיו"',
        const GuidanceFacts(readOnly: true, driveFull: true),
        GuidancePrimary.upToDate,
      ),
      _case(
        'כונן מוגן, גם אם הגיעה עובדה מקוונת — לא מציע הורדה',
        const GuidanceFacts(
          readOnly: true,
          online: true,
          onlineApp: true,
        ),
        GuidancePrimary.upToDate,
      ),
      _case(
        'התקנה ראשונה: תוכנה ואז ספרייה, בלי תוספים',
        const GuidanceFacts(
          online: false,
          otzariaInstalled: false,
          otzariaStatus: AppStatusFact.updateAvailable,
          libraryStatus: LibraryStatusFact.updateAvailable,
          libraryFreshInstall: true,
          pluginUpdatesOnDrive: 3,
        ),
        GuidancePrimary.installHere,
        here: [_app, _library],
      ),
      _case(
        'רק תוספים לעדכן — מותר גם בכונן מוגן',
        const GuidanceFacts(readOnly: true, pluginUpdatesOnDrive: 1),
        GuidancePrimary.updateHere,
        here: [_plugins],
      ),
      _case(
        'אוצריא פתוחה בלי מה לעדכן — אין פס',
        const GuidanceFacts(online: true, otzariaRunning: true),
        GuidancePrimary.upToDate,
      ),
      _case(
        'אוצריא לא מותקנת אבל בכונן יש אותה — לא "ברוכים הבאים"',
        const GuidanceFacts(
          online: true,
          otzariaInstalled: false,
          otzariaStatus: AppStatusFact.updateAvailable,
          otzariaMirrorVersion: 'v1.0.0',
          libraryStatus: LibraryStatusFact.needsDownload,
        ),
        GuidancePrimary.installHere,
        here: [_app],
      ),
      _case(
        'כונן ריק ומחשב מנותק בהרצה ראשונה',
        const GuidanceFacts(
          online: false,
          otzariaInstalled: false,
          otzariaStatus: AppStatusFact.needsDownload,
          libraryStatus: LibraryStatusFact.needsDownload,
        ),
        GuidancePrimary.welcome,
        secondary: GuidanceSecondary.offlineHint,
      ),
      _case(
        'בדיקה אוטומטית כבויה: הספרייה לא נבדקה — רגוע, עם "בדוק עכשיו"',
        const GuidanceFacts(
          online: false,
          libraryStatus: LibraryStatusFact.idle,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.checkOnlineNow,
      ),
      _case(
        'כונן מוגן, הספרייה לא נבדקה — גם כאן מציעים לבדוק',
        const GuidanceFacts(
          readOnly: true,
          libraryStatus: LibraryStatusFact.idle,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.checkOnlineNow,
      ),
      _case(
        'הספרייה לא נבדקה אבל לתוכנה יש עדכון — הפעולה קודמת',
        const GuidanceFacts(
          online: false,
          otzariaStatus: AppStatusFact.updateAvailable,
          libraryStatus: LibraryStatusFact.idle,
        ),
        GuidancePrimary.updateHere,
        here: [_app],
      ),
      _case(
        'בדיקה אוטומטית דולקת ועוד לא נבדק ברשת — בודק',
        const GuidanceFacts(
          autoCheckUpdates: true,
          libraryStatus: LibraryStatusFact.idle,
        ),
        GuidancePrimary.checking,
      ),
      _case(
        'התוספים עוד נטענים — לא "הכול מעודכן"',
        const GuidanceFacts(online: true, pluginsLoading: true),
        GuidancePrimary.checking,
      ),
      _case(
        'אוצריא פתוחה ורק תוספים לעדכן — בלי פס',
        const GuidanceFacts(
          online: false,
          otzariaRunning: true,
          pluginUpdatesOnDrive: 2,
        ),
        GuidancePrimary.updateHere,
        here: [_plugins],
      ),
      _case(
        'אוצריא פתוחה, תוכנה ותוספים לעדכן — פס',
        const GuidanceFacts(
          online: false,
          otzariaRunning: true,
          otzariaStatus: AppStatusFact.updateAvailable,
          pluginUpdatesOnDrive: 1,
        ),
        GuidancePrimary.updateHere,
        here: [_app, _plugins],
        banner: true,
      ),
      _case(
        'עדכון ספרייה בזמן שממתינה הסכמה — נכלל בעדכון כאן',
        const GuidanceFacts(
          online: false,
          libraryStatus: LibraryStatusFact.updateAvailable,
          semanticConsentRequired: true,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
      ),
    ];
    _runCases(cases);
  });

  test('הסכמה ממתינה: האריח והגיבור מסכימים על העדכון', () {
    const facts = GuidanceFacts(
      online: false,
      libraryStatus: LibraryStatusFact.updateAvailable,
      semanticConsentRequired: true,
    );
    expect(deriveHomeGuidance(facts).hereItems, contains(_library));
    expect(deriveTileStatus(_library, facts), TileStatus.updateHere);
  });

  group('דורש תשומת לב', () {
    for (final (status, item) in [
      (const GuidanceFacts(libraryStatus: LibraryStatusFact.error), _library),
      (
        const GuidanceFacts(libraryStatus: LibraryStatusFact.needsManualPath),
        _library,
      ),
      (
        const GuidanceFacts(
          libraryStatus: LibraryStatusFact.personalTargetElsewhere,
        ),
        _library,
      ),
      (const GuidanceFacts(otzariaStatus: AppStatusFact.error), _app),
    ]) {
      test('${status.otzariaStatus.name}/${status.libraryStatus.name}', () {
        final g = deriveHomeGuidance(status);
        expect(g.primary, GuidancePrimary.attention);
        expect(g.attentionItem, item);
      });
    }

    test('פעולה זמינה גוברת על תקלה ברכיב אחר', () {
      final g = deriveHomeGuidance(
        const GuidanceFacts(
          otzariaStatus: AppStatusFact.updateAvailable,
          libraryStatus: LibraryStatusFact.error,
        ),
      );
      expect(g.primary, GuidancePrimary.updateHere);
      expect(g.hereItems, [_app]);
    });
  });

  test('מצב הכונן עובר כמו שהוא', () {
    final g = deriveHomeGuidance(
      const GuidanceFacts(readOnly: true, driveFull: true),
    );
    expect(g.readOnly, isTrue);
    expect(g.driveFull, isTrue);
  });

  group('deriveTileStatus', () {
    test('תוכנה', () {
      TileStatus app(AppStatusFact s, {bool installed = true}) =>
          deriveTileStatus(
            _app,
            GuidanceFacts(otzariaStatus: s, otzariaInstalled: installed),
          );
      expect(app(AppStatusFact.idle), TileStatus.unknown);
      expect(app(AppStatusFact.checking), TileStatus.checking);
      expect(app(AppStatusFact.installing), TileStatus.working);
      expect(app(AppStatusFact.upToDate), TileStatus.upToDate);
      expect(app(AppStatusFact.installedIsNewer), TileStatus.newerHere);
      expect(app(AppStatusFact.updateAvailable), TileStatus.updateHere);
      expect(
        app(AppStatusFact.updateAvailable, installed: false),
        TileStatus.installHere,
      );
      expect(app(AppStatusFact.needsDownload), TileStatus.nothingOnDrive);
      expect(app(AppStatusFact.error), TileStatus.attention);
    });

    test('ספרייה', () {
      TileStatus library(
        LibraryStatusFact s, {
        bool consent = false,
        bool applying = false,
        bool fresh = false,
      }) =>
          deriveTileStatus(
            _library,
            GuidanceFacts(
              libraryStatus: s,
              semanticConsentRequired: consent,
              libraryApplyActive: applying,
              libraryFreshInstall: fresh,
            ),
          );
      expect(library(LibraryStatusFact.updating), TileStatus.working);
      expect(
        library(LibraryStatusFact.upToDate, applying: true),
        TileStatus.working,
      );
      expect(
        library(LibraryStatusFact.upToDate, consent: true),
        TileStatus.needsConsent,
      );
      expect(
        library(LibraryStatusFact.updating, consent: true),
        TileStatus.working,
      );
      expect(
        library(LibraryStatusFact.updateAvailable, consent: true),
        TileStatus.updateHere,
      );
      expect(library(LibraryStatusFact.idle), TileStatus.unknown);
      expect(library(LibraryStatusFact.updateAvailable), TileStatus.updateHere);
      expect(
        library(LibraryStatusFact.updateAvailable, fresh: true),
        TileStatus.installHere,
      );
      expect(
          library(LibraryStatusFact.needsDownload), TileStatus.nothingOnDrive);
      for (final s in [
        LibraryStatusFact.error,
        LibraryStatusFact.needsManualPath,
        LibraryStatusFact.personalTargetElsewhere,
      ]) {
        expect(library(s), TileStatus.attention, reason: s.name);
      }
    });

    test('תוספים', () {
      expect(
        deriveTileStatus(_plugins, const GuidanceFacts(pluginsLoading: true)),
        TileStatus.checking,
      );
      expect(
        deriveTileStatus(
            _plugins, const GuidanceFacts(pluginUpdatesOnDrive: 2)),
        TileStatus.updateHere,
      );
      expect(
        deriveTileStatus(_plugins, const GuidanceFacts()),
        TileStatus.upToDate,
      );
    });

    test('רכיב שההורדה מביאה — "חדש באינטרנט", גם כשהוא חסר בכונן', () {
      TileStatus tile(GuidanceItem item, GuidanceFacts f) =>
          deriveTileStatus(item, f, download: [item]);
      expect(
        tile(_app, const GuidanceFacts()),
        TileStatus.onlineAvailable,
      );
      expect(
        tile(
          _library,
          const GuidanceFacts(libraryStatus: LibraryStatusFact.needsDownload),
        ),
        TileStatus.onlineAvailable,
      );
      expect(
        tile(_plugins, const GuidanceFacts(pluginUpdatesOnDrive: 2)),
        TileStatus.onlineAvailable,
      );
      // מה שלא נכלל בהורדה — כמו קודם.
      expect(
        deriveTileStatus(_library, const GuidanceFacts(), download: [_app]),
        TileStatus.upToDate,
      );
    });

    test('פעולה רצה, בדיקה, תקלה והסכמה גוברות על "חדש באינטרנט"', () {
      TileStatus app(AppStatusFact s) => deriveTileStatus(
            _app,
            GuidanceFacts(otzariaStatus: s),
            download: const [_app],
          );
      expect(app(AppStatusFact.installing), TileStatus.working);
      expect(app(AppStatusFact.checking), TileStatus.checking);
      expect(app(AppStatusFact.error), TileStatus.attention);
      expect(
        deriveTileStatus(
          _library,
          const GuidanceFacts(semanticConsentRequired: true),
          download: const [_library],
        ),
        TileStatus.needsConsent,
      );
    });

    test('הגיבור והאריח מסכימים: כל מה שבהורדה מסומן באריח', () {
      const f = GuidanceFacts(
        online: true,
        onlineApp: true,
        onlineLibrary: true,
        libraryStatus: LibraryStatusFact.needsDownload,
      );
      final g = deriveHomeGuidance(f);
      expect(g.downloadItems, [_app, _library]);
      for (final item in g.downloadItems) {
        expect(
          deriveTileStatus(item, f, download: g.downloadItems),
          TileStatus.onlineAvailable,
        );
      }
    });
  });

  test('עדכון כאן: סדר השלבים', () {
    expect(
      updateHereStages(
          firstInstall: true, app: true, library: true, plugins: true),
      [_app, _library],
    );
    expect(
      updateHereStages(
          firstInstall: false, app: true, library: true, plugins: true),
      [_library, _app, _plugins],
    );
    expect(
      updateHereStages(
        firstInstall: false,
        app: false,
        library: false,
        plugins: true,
      ),
      [_plugins],
    );
  });

  test('העובדות מקבילות בשמן למצבי הקונטרולרים — המתאם נשען על זה', () {
    expect(
      AppStatusFact.values.map((v) => v.name),
      OtzariaModuleStatus.values.map((v) => v.name),
    );
    expect(
      LibraryStatusFact.values.map((v) => v.name),
      LibraryModuleStatus.values.map((v) => v.name),
    );
  });

  test('home_guidance.dart טהור: בלי Flutter ובלי ייבוא מקומי', () {
    final source = File('lib/src/shell/home_guidance.dart').readAsStringSync();
    expect(RegExp(r'^import ', multiLine: true).hasMatch(source), isFalse);
  });
}

void _runCases(List<_Case> cases) {
  for (final c in cases) {
    test(c.name, () {
      final g = deriveHomeGuidance(c.facts);
      expect(g.primary, c.primary, reason: '$g');
      expect(g.secondary, c.secondary, reason: '$g');
      expect(g.hereItems, c.here, reason: '$g');
      expect(g.downloadItems, c.download, reason: '$g');
      expect(g.showOtzariaOpenBanner, c.banner, reason: '$g');
    });
  }
}
