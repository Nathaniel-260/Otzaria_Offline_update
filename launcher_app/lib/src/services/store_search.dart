/// חיפוש מקומי בחנות: אותיות סופיות כרגילות, בלי ניקוד וגרשיים, ובלי
/// רישיות — כמו `PluginSearchBox` באתר.
library;

/// אות סופית -> האות הרגילה, בקודי יוניקוד (ך ם ן ף ץ).
const Map<int, int> _finals = {
  0x05DA: 0x05DB,
  0x05DD: 0x05DE,
  0x05DF: 0x05E0,
  0x05E3: 0x05E4,
  0x05E5: 0x05E6,
};

/// ניקוד, טעמים, גרש וגרשיים — נמחקים מהטקסט ומהשאילתה.
bool _isIgnored(int code) =>
    (code >= 0x0591 && code <= 0x05C7) ||
    code == 0x22 || // "
    code == 0x27 || // '
    code == 0x05F3 || // ׳
    code == 0x05F4; // ״

/// הטקסט המנורמל, ולכל תו בו — המיקום שלו בטקסט המקורי.
({String text, List<int> origin}) _normalize(String value) {
  final out = StringBuffer();
  final origin = <int>[];
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (_isIgnored(code)) continue;
    out.write(String.fromCharCode(_finals[code] ?? code).toLowerCase());
    origin.add(i);
  }
  return (text: out.toString(), origin: origin);
}

/// השאילתה כפי שמשווים אותה — ריקה כשאין בה אלא רווחים.
String normalizeStoreQuery(String query) => _normalize(query.trim()).text;

/// האם [text] מכיל את [normalizedQuery] (שכבר עבר [normalizeStoreQuery]).
bool storeTextMatches(String text, String normalizedQuery) =>
    normalizedQuery.isEmpty || _normalize(text).text.contains(normalizedQuery);

/// הטווח שיש להדגיש ב-[text] — במיקומי הטקסט המקורי — או `null`.
({int start, int end})? storeMatchRange(String text, String query) {
  final q = normalizeStoreQuery(query);
  if (q.isEmpty) return null;
  final normalized = _normalize(text);
  final at = normalized.text.indexOf(q);
  if (at < 0) return null;
  final start = normalized.origin[at];
  final end = normalized.origin[at + q.length - 1] + 1;
  return (start: start, end: end);
}
