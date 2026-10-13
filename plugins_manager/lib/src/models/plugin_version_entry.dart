import 'package:equatable/equatable.dart';

/// בילד אחד של תוסף — הגרסה החיה או אחת מההיסטוריות — עם **טווח התאימות
/// שלו לגרסת אוצריא**. זהו הנתון שמאפשר להוריד למחשב המנותק את הבילד
/// שבאמת ירוץ אצלו, ולא את האחרון שפורסם.
///
/// `compatibleWith` הוא גרסת אוצריא המינימלית ו-`maxAppVersion` המקסימלית;
/// שדה ריק פירושו גבול פתוח (ראו `isCompatibleWithApp`).
class PluginVersionEntry extends Equatable {
  const PluginVersionEntry({
    required this.version,
    required this.status,
    required this.compatibleWith,
    required this.maxAppVersion,
    required this.downloadUrl,
    this.requiresNetwork = false,
    this.fileSize = 0,
    this.releasedAt = '',
    this.supportsDirectInstall = true,
    this.isLatest = false,
    this.sha256,
  });

  final String version;

  /// `stable` / `beta` / `experimental` — בשלות הבילד, לא ערוץ של אוצריא.
  final String status;

  /// גרסת אוצריא המינימלית. ריק = אין רצפה.
  final String compatibleWith;

  /// גרסת אוצריא המקסימלית. `null` = אין תקרה.
  final String? maxAppVersion;

  /// כתובת מוחלטת לקובץ ה-`.otzplugin` של הבילד הזה בדיוק.
  final String downloadUrl;

  final bool requiresNetwork;
  final int fileSize;
  final String releasedAt;
  final bool supportsDirectInstall;

  /// זו הגרסה החיה של התוסף באתר.
  final bool isLatest;

  final String? sha256;

  /// בונה רשומה מתוך `versions[]` של `/api/plugins`. [baseUrl] הופך את
  /// `downloadUrl` היחסי למוחלט, בדיוק כמו ב-`StorePlugin.fromApi`.
  static PluginVersionEntry? fromApi(Object? json, String baseUrl) {
    if (json is! Map) return null;
    final version = _string(json['version']);
    if (version.isEmpty) return null;
    return PluginVersionEntry(
      version: version,
      status: _string(json['status']),
      compatibleWith: _string(json['compatibleWith']),
      maxAppVersion: json['maxAppVersion'] is String &&
              (json['maxAppVersion'] as String).isNotEmpty
          ? json['maxAppVersion'] as String
          : null,
      downloadUrl: _absolute(_string(json['downloadUrl']), baseUrl),
      requiresNetwork: json['requiresNetwork'] == true,
      fileSize:
          json['pluginFileSize'] is int ? json['pluginFileSize'] as int : 0,
      releasedAt: _string(json['releasedAt']),
      supportsDirectInstall: json['supportsDirectInstall'] != false,
      isLatest: json['isLatest'] == true,
      sha256: normalizeSha256(json['sha256']),
    );
  }

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  static String? normalizeSha256(Object? value) {
    if (value is! String) return null;
    final hex = value.trim().toLowerCase();
    return _sha256Pattern.hasMatch(hex) ? hex : null;
  }

  PluginVersionEntry withDownloadUrl(String url) => PluginVersionEntry(
        version: version,
        status: status,
        compatibleWith: compatibleWith,
        maxAppVersion: maxAppVersion,
        downloadUrl: url,
        requiresNetwork: requiresNetwork,
        fileSize: fileSize,
        releasedAt: releasedAt,
        supportsDirectInstall: supportsDirectInstall,
        isLatest: isLatest,
        sha256: sha256,
      );

  /// קריאה מהקטלוג השמור. הכתובת כבר מוחלטת שם, ולכן אין [baseUrl].
  static PluginVersionEntry? fromJson(Object? json) => fromApi(json, '');

  Map<String, dynamic> toJson() => {
        'version': version,
        'status': status,
        'compatibleWith': compatibleWith,
        'maxAppVersion': maxAppVersion,
        'downloadUrl': downloadUrl,
        'requiresNetwork': requiresNetwork,
        'pluginFileSize': fileSize,
        'releasedAt': releasedAt,
        'supportsDirectInstall': supportsDirectInstall,
        'isLatest': isLatest,
        if (sha256 != null) 'sha256': sha256,
      };

  static String _string(Object? value) => value is String ? value : '';

  static String _absolute(String url, String baseUrl) {
    if (url.isEmpty || baseUrl.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$baseUrl$url';
  }

  @override
  List<Object?> get props => [
        version,
        status,
        compatibleWith,
        maxAppVersion,
        downloadUrl,
        requiresNetwork,
        fileSize,
        releasedAt,
        supportsDirectInstall,
        isLatest,
        sha256,
      ];
}
