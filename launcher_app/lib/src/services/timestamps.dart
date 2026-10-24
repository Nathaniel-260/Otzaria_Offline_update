import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'hebrew_date.dart';

/// חותמות זמן ותאריכים לתצוגה.
///
/// חותמות של **המסגרת** ("סונכרן ב…", "נבדק לאחרונה ב…") מספריות בלוח הלועזי:
/// כך קל להשוות בין שתי הרצות. תאריכי **החנויות** ([formatStoreDate]) — בלוח
/// העברי בעברית, כמו באתר.

String _two(int n) => n.toString().padLeft(2, '0');

/// שעה:דקה. שעון 24 שעות — חד-משמעי בשתי השפות, ולכן אינו תלוי בשפה.
String formatClock(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// תאריך ושעה מלאים.
///
/// סדר התאריך נגזר משפת הממשק: `dd.mm.yyyy` בעברית, ו-ISO (`yyyy-mm-dd`)
/// באנגלית — שם `dd.mm.yyyy` נקרא כתאריך אמריקאי שהפכו בו את היום והחודש.
String formatTimestamp(DateTime value) {
  final local = value.toLocal();
  final time = '${formatClock(local)}:${_two(local.second)}';
  if (!AppL10n.language.isRtl) {
    return '${local.year}-${_two(local.month)}-${_two(local.day)} $time';
  }
  return '${_two(local.day)}.${_two(local.month)}.${local.year}, $time';
}

/// תאריך בלבד, באותו סדר כמו [formatTimestamp].
String formatDate(DateTime value) {
  final local = value.toLocal();
  if (!AppL10n.language.isRtl) {
    return '${local.year}-${_two(local.month)}-${_two(local.day)}';
  }
  return '${_two(local.day)}.${_two(local.month)}.${local.year}';
}

/// תאריך בחנות התוספים ובתוכנות הנוספות — הפורמט האחד לשתיהן. בעברית תאריך
/// עברי כמו באתר ("ט' בחשוון תשפ"ז"), באנגלית "October 18, 2026".
String formatStoreDate(DateTime value) => _storeDay(value.toLocal());

/// [formatStoreDate] למחרוזת תאריך מה-API (`YYYY-MM-DD` או ISO-8601 מלא).
/// מחרוזת שאינה תאריך מוחזרת כמות שהיא — עדיף על שגיאה במסך.
String formatStoreDateRaw(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  // תאריך בלי שעה הוא יום בלוח, לא רגע — המרה לשעון המקומי הייתה מזיזה אותו.
  return _storeDay(raw.length <= 10 ? date : date.toLocal());
}

String _storeDay(DateTime day) => AppL10n.language.isRtl
    ? HebrewDate.fromDateTime(day).toString()
    : AppL10n.strings.units.longDate(day.day, day.month, day.year);
