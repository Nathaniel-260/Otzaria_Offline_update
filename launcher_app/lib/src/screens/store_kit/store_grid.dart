// SliverConstraints ו-SliverGridLayout מגיעים מ-rendering, לא מ-material.
import 'package:flutter/rendering.dart';

/// מרוחב התוכן הזה הרשת בשתי עמודות, והכרטיס עובר מ"שורה" ל"כרטיס" —
/// כמו `@container body (min-width: 820px)` במוקאפ, פחות ריפוד הדף.
const double kStoreTwoColumnWidth = 772;

/// מחוץ לרשת (בלי גובה קבוע): מהרוחב הזה הכרטיס מוצג כשורה.
const double kStoreRowCardWidth = 480;

/// גובה הכרטיס בשתי הצורות: חלק קבוע (ריפוד, סמל, כפתור) וחלק שגדל עם
/// הטקסט. הגובה **קבוע** — התיאור תמיד בשתי שורות שמורות — כדי שהרשת לא
/// תצטרך למדוד אף כרטיס.
double storeRowCardExtent(double textScale) => 32 + 100 * textScale;
double storeTileCardExtent(double textScale) => 112 + 92 * textScale;

/// פריסת רשת הכרטיסים: עמודה אחת של שורות, או שתיים של כרטיסים.
///
/// ⚠️ החישוב ב-delegate ולא ב-`SliverLayoutBuilder`: ה-scrollOffset הוא חלק
/// מ-`SliverConstraints`, ושם הרשת הייתה נבנית מחדש בכל פריים של גלילה.
class StoreGridDelegate extends SliverGridDelegate {
  const StoreGridDelegate({required this.textScale});

  /// הגדלת הטקסט של המשתמש; תוכן הכרטיס גדל איתה, ולכן גם הגובה.
  final double textScale;

  static bool twoColumns(double width) => width >= kStoreTwoColumnWidth;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final two = twoColumns(constraints.crossAxisExtent);
    final spacing = two ? 12.0 : 10.0;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: two ? 2 : 1,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      mainAxisExtent:
          two ? storeTileCardExtent(textScale) : storeRowCardExtent(textScale),
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(StoreGridDelegate oldDelegate) =>
      oldDelegate.textScale != textScale;
}
