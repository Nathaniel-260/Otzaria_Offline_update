import 'package:otzaria_l10n/otzaria_l10n.dart';

/// חותמות זמן של **המסגרת** — "סונכרן ב…", "נבדק לאחרונה ב…".
///
/// נפרד מ-`hebrew_date.dart` בכוונה: שם מדובר בתאריכי **תוכן** שמגיעים
/// מ-otzaria.org (מתי תוסף פורסם), ולכן הם מוצגים בלוח השנה העברי. כאן
/// מדובר בזמן שהתוכנה עצמה עשתה משהו, ולוח שנה עברי לחותמת כזו רק מקשה
/// על השוואה בין שתי הרצות.
///
/// שני מעצבים כאלה נכתבו בעבר inline בשני מסכים שונים, וכל אחד פורמט אחרת.

String _two(int n) => n.toString().padLeft(2, '0');

/// שעה:דקה. שעון 24 שעות — חד-משמעי בשתי השפות, ולכן אינו תלוי בשפה.
String formatClock(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// תאריך ושעה מלאים.
///
/// סדר התאריך נגזר משפת הממשק, לפי התקדים שכבר קיים ב-`HebrewDate.format`:
/// `dd.mm.yyyy` בעברית, ו-ISO (`yyyy-mm-dd`) באנגלית — שם `dd.mm.yyyy` נקרא
/// כתאריך אמריקאי שהפכו בו את היום והחודש.
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

/// תאריך בשם חודש — הפורמט האחיד של החנויות: "18 באוקטובר 2026".
String formatLongDate(DateTime value) {
  final local = value.toLocal();
  return AppL10n.strings.units.longDate(local.day, local.month, local.year);
}

/// [formatLongDate] למחרוזת תאריך מה-API (`YYYY-MM-DD` או ISO-8601 מלא).
/// מחרוזת שאינה תאריך מוחזרת כמות שהיא — עדיף על שגיאה במסך.
String formatLongDateRaw(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  // תאריך בלי שעה הוא יום בלוח, לא רגע — המרה לשעון המקומי הייתה מזיזה אותו.
  final day = raw.length <= 10 ? date : date.toLocal();
  return AppL10n.strings.units.longDate(day.day, day.month, day.year);
}
