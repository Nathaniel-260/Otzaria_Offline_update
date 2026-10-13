import 'app_descriptor_id.dart';

/// שם קובץ (מדיה או קובץ התקנה) שבטוח לצרף לנתיב, או `null`. הרשומה
/// מגיעה מכונן שנדד, ולכן `../../windows/system32` כאן הוא גבול אמיתי ולא
/// ניקיון — אותו שיקול בדיוק כמו ב-[AppDescriptorId].
String? safeFileName(Object? value) {
  if (value is! String || value.isEmpty) return null;
  // Windows silently strips trailing spaces and dots, so the name on disk
  // would differ from the stored one; this also rejects `.` and `..`.
  if (value != value.trim() || value.endsWith('.')) return null;
  if (_forbiddenChars.hasMatch(value)) return null;
  if (_reservedDeviceName.hasMatch(value)) return null;
  return value;
}

final RegExp _forbiddenChars = RegExp(r'[\x00-\x1F<>:"/\\|?*]');

/// `CON.txt` פותח בווינדוס את התקן הקונסולה, בכל סיומת.
final RegExp _reservedDeviceName = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
  caseSensitive: false,
);
