/// אותו כלל בחירה כמו `src/lib/pluginCompatibility.js` באתר, אבל גרסת אוצריא
/// מושווית כמו `compareCoreVersions` של אוצריא (major.minor.patch, בלי סיומת).
library;

import '../models/plugin_version_entry.dart';
import 'plugin_version_compare.dart';

bool isCompatibleWithApp(PluginVersionEntry entry, String? appVersion) {
  if (appVersion == null || appVersion.isEmpty) return true;
  if (entry.compatibleWith.isNotEmpty &&
      compareAppVersions(appVersion, entry.compatibleWith) < 0) {
    return false;
  }
  final max = entry.maxAppVersion;
  if (max != null &&
      max.isNotEmpty &&
      compareAppVersions(appVersion, max) > 0) {
    return false;
  }
  return true;
}

/// הבילד הגבוה ביותר מתוך [entries] שתואם ל-[appVersion], או `null` כשאין
/// כזה. [entries] חייבת להיות ממוינת יורד — `StorePlugin` דואג לכך.
PluginVersionEntry? resolveCompatibleVersion(
  List<PluginVersionEntry> entries,
  String? appVersion,
) {
  for (final entry in entries) {
    if (isCompatibleWithApp(entry, appVersion)) return entry;
  }
  return null;
}

/// הבילדים שצריכים לרדת למראה עבור [appVersions] — אחד לכל גרסת אוצריא
/// שהכונן נושא, בלי כפילות כששתיהן נפתרות לאותו בילד.
///
/// רשימת גרסאות ריקה = אין מול מה לסנן (מראת תוכנה ריקה), ואז יורד הבילד
/// החי בלבד: בדיוק ההתנהגות שהייתה לפני שהתאימות נכנסה.
List<PluginVersionEntry> resolveTargets(
  List<PluginVersionEntry> entries,
  List<String> appVersions,
) {
  if (entries.isEmpty) return const [];
  if (appVersions.isEmpty) return [entries.first];

  final targets = <String, PluginVersionEntry>{};
  for (final appVersion in appVersions) {
    final entry = resolveCompatibleVersion(entries, appVersion);
    if (entry != null) targets[entry.version] = entry;
  }
  return targets.values.toList(growable: false);
}

String? lowestSupportedAppVersion(List<PluginVersionEntry> entries) {
  String? lowest;
  for (final entry in entries) {
    if (entry.compatibleWith.isEmpty) return null;
    if (lowest == null ||
        compareAppVersions(entry.compatibleWith, lowest) < 0) {
      lowest = entry.compatibleWith;
    }
  }
  return lowest;
}
