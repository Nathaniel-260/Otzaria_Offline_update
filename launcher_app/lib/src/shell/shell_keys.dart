import 'package:flutter/foundation.dart';

import 'shell_navigator.dart';

/// מפתחות קבועים לבדיקות ולצילומי הסקירה: מוצאים בהם חלק בדף בלי לתלות
/// את הבדיקה בנוסח.
abstract final class ShellKeys {
  static const hero = ValueKey('home.hero');
  static const heroPrimary = ValueKey('home.hero.primary');
  static const heroSecondary = ValueKey('home.hero.secondary');
  static const heroCancel = ValueKey('home.hero.cancel');
  static const eyebrow = ValueKey('home.eyebrow');
  static const heroChecking = ValueKey('home.hero.checking');

  static const readOnlyNotice = ValueKey('home.notice.readOnly');
  static const driveFullNotice = ValueKey('home.notice.driveFull');
  static const reportsIntroNotice = ValueKey('home.notice.reportsIntro');
  static const legacyReportsNotice = ValueKey('home.notice.legacyReports');
  static const otzariaOpenBanner = ValueKey('home.banner.otzariaOpen');
  static const elevationBanner = ValueKey('home.banner.elevation');
  static const newPluginsBanner = ValueKey('home.banner.newPlugins');

  static const launcherLine = ValueKey('home.foot.launcher');
  static const checkedAt = ValueKey('home.foot.checkedAt');
  static const checkNow = ValueKey('home.foot.checkNow');
  static const driveLine = ValueKey('home.foot.drive');

  static const welcome = ValueKey('home.welcome');
  static const welcomePrimary = ValueKey('home.welcome.primary');
  static const welcomeLanguage = ValueKey('home.welcome.language');
  static const welcomeLinks = ValueKey('home.welcome.links');

  static const sectionStack = ValueKey('shell.sections');
  static const reportsCollect = ValueKey('reports.collect');
  static const reportsDisclosure = ValueKey('reports.disclosure');

  static const taskLayer = ValueKey('task.layer');
  static const taskPrimary = ValueKey('task.primary');
  static const taskSecondary = ValueKey('task.secondary');
  static const taskCancel = ValueKey('task.cancel');
  static const taskStopWaiting = ValueKey('task.stopWaiting');
  static const taskReindex = ValueKey('task.reindex');
  static const taskElevation = ValueKey('task.elevation');
  static const heroShowProgress = ValueKey('home.hero.showProgress');

  /// אריח הבית שמוביל אל [section].
  static ValueKey<String> tile(ShellSection section) =>
      ValueKey('home.tile.${section.name}');
}
