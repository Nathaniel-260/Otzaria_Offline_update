import 'package:equatable/equatable.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../services/windows_arch.dart';
import 'otzaria_release_channel.dart';

/// הגרסאות שנמצאו ברשת, לפי ערוץ — ראו [OtzariaChannelPair].
typedef OtzariaChannelReleases = OtzariaChannelPair<OtzariaRelease>;

/// הפלטפורמה שעבורה בוחרים אסט להתקנה. **לא** נגזר ישירות מ-`Platform`
/// בכל מקום שצריך אותו, כדי שבחירת האסט תישאר פונקציה טהורה שאפשר לבדוק
/// עבור שתי הפלטפורמות מאותה מכונה.
enum OtzariaTargetPlatform {
  windows,
  macos;

  /// הפלטפורמה שהלאנצ'ר רץ עליה בפועל. זורק [UnsupportedError] בפלטפורמה
  /// שאין לה מסלול התקנה (לינוקס/מובייל) — הלאנצ'ר עצמו נבנה רק ל-Windows
  /// ול-macOS.
  static OtzariaTargetPlatform detect(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => OtzariaTargetPlatform.windows,
      'macos' => OtzariaTargetPlatform.macos,
      _ => throw UnsupportedError(
          AppL10n.strings.appDomain.unsupportedPlatform(operatingSystem),
        ),
    };
  }

  /// כמו [detect], אבל `null` במקום חריג. למי שהפלטפורמה היא אצלו *סינון*
  /// ולא הכרעה — למשל `OtzariaAppMirror`, שרץ גם בלינוקס תחת הבדיקות
  /// ואסור לו להפיל אותן שם.
  static OtzariaTargetPlatform? detectOrNull(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => OtzariaTargetPlatform.windows,
      'macos' => OtzariaTargetPlatform.macos,
      _ => null,
    };
  }

  /// תווית לשימוש בהודעות שגיאה למשתמש.
  String get label => switch (this) {
        OtzariaTargetPlatform.windows => 'Windows',
        OtzariaTargetPlatform.macos => 'macOS',
      };
}

/// סוג האסט שממנו מתקינים — קובע איזה מסלול התקנה [OtzariaInstaller] מריץ.
enum OtzariaInstallerKind {
  /// installer של Inno Setup לווינדוס (`otzaria-<ver>-windows.exe`) — מורץ
  /// בשקט עם דגלי `/VERYSILENT`.
  windowsSetupExe,

  /// ארכיון zip שבתוכו bundle של `.app` ל-macOS (`otzaria-macos.zip`) —
  /// מחולץ עם `ditto` לתיקיית ההתקנה.
  macAppZip,

  /// דמות דיסק ל-macOS (`otzaria-macos.dmg`) — מורכבת עם `hdiutil`,
  /// ה-`.app` מועתק ממנה, והדמות מנותקת. מסלול גיבוי למקרה שאין zip.
  macAppDmg;

  bool get isMac =>
      this == OtzariaInstallerKind.macAppZip ||
      this == OtzariaInstallerKind.macAppDmg;

  /// הפלטפורמה שהאסט הזה מתקין עליה. הכונן נוסע בין מחשבים, ולכן מראה
  /// שנכתבה בווינדוס עלולה להיקרא במק — ראו `OtzariaAppMirror.load`.
  OtzariaTargetPlatform get targetPlatform =>
      isMac ? OtzariaTargetPlatform.macos : OtzariaTargetPlatform.windows;
}

/// Release אחד מתוך github.com/Otzaria/otzaria/releases, מצומצם לשדות
/// שרלוונטיים להתקנה: תג הגרסה וקובץ ההתקנה לפלטפורמה הנוכחית.
///
/// **ערוצים:** release רגיל = יציב, pre-release = לא יציב. ההורדה מביאה את
/// שניהם (ראו `OtzariaReleaseClient.fetchChannelReleases`), והמשתמש בוחר
/// איזה מהם להתקין — אבל רק כשה-pre-release חדש מהיציב; אחרת אין בחירה
/// אמיתית ומורידים את היציב בלבד.
///
/// [toJson]/[fromJson] משמשים את `OtzariaAppMirror` כדי לשמור את המטא־דאטה
/// לצד קובץ ההתקנה — כך שבדיקת גרסה עובדת גם בלי רשת בכלל.
class OtzariaRelease extends Equatable {
  const OtzariaRelease({
    required this.tagName,
    required this.name,
    required this.isPrerelease,
    required this.isDraft,
    required this.publishedAt,
    required this.installerKind,
    required this.installerAssetName,
    required this.installerDownloadUrl,
    required this.installerSizeBytes,
    this.installerSha256,
    this.releaseNotes,
    this.installerArch = OtzariaArch.x64,
    this.arm64Variant,
  });

  final String tagName;
  final String name;
  final bool isPrerelease;
  final bool isDraft;
  final DateTime? publishedAt;

  /// תיאור ה-release כפי שנכתב ב-GitHub ("מה התחדש") — טקסט חופשי
  /// (Markdown גולמי, לא מרונדר), או `null` אם ה-release לא כלל תיאור.
  /// נשמר לצד שאר המטא-דאטה במראה המקומית כדי שיהיה קריא גם בלי רשת.
  final String? releaseNotes;

  /// איך להתקין את [installerAssetName] — ראו [OtzariaInstallerKind].
  final OtzariaInstallerKind installerKind;

  /// שם הקובץ, לדוגמה `otzaria-0.9.96-windows.exe` בווינדוס או
  /// `otzaria-macos.zip` ב-macOS.
  final String installerAssetName;
  final String installerDownloadUrl;
  final int installerSizeBytes;
  final String? installerSha256;

  final OtzariaArch installerArch;

  final OtzariaRelease? arm64Variant;

  /// עותק עם [releaseNotes] מוחלף — משמש להעדיף פסקה מיומן השינויים
  /// המרוכז (ראו `OtzariaChangelogClient`) על פני תיאור ה-release הגולמי.
  OtzariaRelease copyWithReleaseNotes(String? releaseNotes) => OtzariaRelease(
        tagName: tagName,
        name: name,
        isPrerelease: isPrerelease,
        isDraft: isDraft,
        publishedAt: publishedAt,
        installerKind: installerKind,
        installerAssetName: installerAssetName,
        installerDownloadUrl: installerDownloadUrl,
        installerSizeBytes: installerSizeBytes,
        installerSha256: installerSha256,
        releaseNotes: releaseNotes,
        installerArch: installerArch,
        arm64Variant: arm64Variant?.copyWithReleaseNotes(releaseNotes),
      );

  OtzariaRelease withArm64Variant(OtzariaRelease? variant) => OtzariaRelease(
        tagName: tagName,
        name: name,
        isPrerelease: isPrerelease,
        isDraft: isDraft,
        publishedAt: publishedAt,
        installerKind: installerKind,
        installerAssetName: installerAssetName,
        installerDownloadUrl: installerDownloadUrl,
        installerSizeBytes: installerSizeBytes,
        installerSha256: installerSha256,
        releaseNotes: releaseNotes,
        installerArch: installerArch,
        arm64Variant: variant,
      );

  Map<String, dynamic> toJson() => {
        'tagName': tagName,
        'name': name,
        'isPrerelease': isPrerelease,
        'isDraft': isDraft,
        'publishedAt': publishedAt?.toIso8601String(),
        'installerKind': installerKind.name,
        'installerAssetName': installerAssetName,
        'installerDownloadUrl': installerDownloadUrl,
        'installerSizeBytes': installerSizeBytes,
        if (installerSha256 != null) 'installerSha256': installerSha256,
        'releaseNotes': releaseNotes,
        if (installerArch != OtzariaArch.x64)
          'installerArch': installerArch.name,
      };

  static String? normalizedSha256(Object? raw) {
    if (raw is! String) return null;
    final hex = raw.trim().toLowerCase().replaceFirst('sha256:', '');
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
  }

  /// זורק [FormatException] על JSON חסר/פגום — הקורא מתייחס לזה כ"אין מראה
  /// תקינה" ומבקש הורדה מחדש.
  factory OtzariaRelease.fromJson(Map<String, dynamic> json) {
    final kindName = json['installerKind'];
    final kind = OtzariaInstallerKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    final archName = json['installerArch'];
    final arch = archName == null
        ? OtzariaArch.x64
        : OtzariaArch.values.where((a) => a.name == archName).firstOrNull;
    if (arch == null ||
        json['tagName'] is! String ||
        json['installerAssetName'] is! String ||
        json['installerSizeBytes'] is! int ||
        kind == null) {
      throw FormatException(AppL10n.strings.appDomain.corruptReleaseMetadata);
    }

    final publishedAt = json['publishedAt'];
    return OtzariaRelease(
      tagName: json['tagName'] as String,
      name: (json['name'] as String?) ?? json['tagName'] as String,
      isPrerelease: json['isPrerelease'] as bool? ?? false,
      isDraft: json['isDraft'] as bool? ?? false,
      publishedAt:
          publishedAt is String ? DateTime.tryParse(publishedAt) : null,
      installerKind: kind,
      installerAssetName: json['installerAssetName'] as String,
      installerDownloadUrl: (json['installerDownloadUrl'] as String?) ?? '',
      installerSizeBytes: json['installerSizeBytes'] as int,
      installerSha256: normalizedSha256(json['installerSha256']),
      releaseNotes: json['releaseNotes'] as String?,
      installerArch: arch,
    );
  }

  @override
  List<Object?> get props => [
        tagName,
        name,
        isPrerelease,
        isDraft,
        publishedAt,
        installerKind,
        installerAssetName,
        installerDownloadUrl,
        installerSizeBytes,
        installerSha256,
        releaseNotes,
        installerArch,
        arm64Variant,
      ];
}

/// נזרקת כשל-release אין אסט התקנה מתאים לפלטפורמה הנוכחית (למשל release
/// עם אנדרואיד/לינוקס בלבד, או אסט עם שם לא צפוי).
class NoInstallerAssetException implements Exception {
  const NoInstallerAssetException({
    required this.tagName,
    required this.platform,
    required this.expectedSuffixes,
  });

  final String tagName;
  final OtzariaTargetPlatform platform;

  /// הסיומות שחיפשנו — נכנס להודעה כדי שיהיה ברור מה בדיוק לא נמצא.
  final List<String> expectedSuffixes;

  @override
  String toString() => AppL10n.strings.appDomain.noAssetForPlatform(
        tagName,
        platform.label,
        expectedSuffixes,
      );
}
