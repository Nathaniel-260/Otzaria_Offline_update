import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/app_shell.dart';
import 'package:launcher_app/src/shell/shell_navigator.dart';

void main() {
  late ShellNavigator nav;
  late int notified;

  setUp(() {
    nav = ShellNavigator()..addListener(() => notified++);
    notified = 0;
  });

  tearDown(() => nav.dispose());

  test('מתחיל בבית, ורק הבית בנוי', () {
    expect(nav.current, const HomeRoute());
    expect(nav.section, ShellSection.home);
    expect(nav.builtSections, {ShellSection.home});
    expect(nav.canGoBack, isFalse);
    expect(nav.back(), isFalse);
  });

  test('בחירת מקטע בונה אותו, והבנייה נשמרת אחרי יציאה', () {
    nav.select(ShellSection.plugins);
    expect(nav.section, ShellSection.plugins);
    expect(nav.stack,
        [const HomeRoute(), const SectionRoute(ShellSection.plugins)]);
    expect(nav.isBuilt(ShellSection.plugins), isTrue);
    expect(nav.isBuilt(ShellSection.library), isFalse);

    nav.select(ShellSection.home);
    expect(nav.section, ShellSection.home);
    expect(nav.isBuilt(ShellSection.plugins), isTrue);
    expect(notified, 2);
  });

  test('בחירה חוזרת של אותו מקטע אינה מודיעה', () {
    nav.select(ShellSection.home);
    nav.select(ShellSection.settings);
    nav.select(ShellSection.settings);
    expect(notified, 1);
  });

  test('בחירה מהסרגל מחליפה מקטע ואינה מערימה', () {
    nav.select(ShellSection.otzaria);
    nav.select(ShellSection.library);
    expect(nav.stack,
        [const HomeRoute(), const SectionRoute(ShellSection.library)]);
    expect(nav.back(), isTrue);
    expect(nav.section, ShellSection.home);
  });

  test('פרטי תוסף יושבים בתוך מקטע התוספים, וחזרה מובילה לרשימה', () {
    nav.push(const PluginDetailRoute('a'));
    expect(nav.section, ShellSection.plugins);
    expect(nav.isBuilt(ShellSection.plugins), isTrue);
    expect(nav.stack, [
      const HomeRoute(),
      const SectionRoute(ShellSection.plugins),
      const PluginDetailRoute('a'),
    ]);

    nav.push(const PluginDetailRoute('b'));
    expect(nav.current, const PluginDetailRoute('b'));
    expect(nav.stack, hasLength(3));

    expect(nav.back(), isTrue);
    expect(nav.current, const SectionRoute(ShellSection.plugins));
    expect(nav.back(), isTrue);
    expect(nav.current, const HomeRoute());
  });

  test('ניהול תוכנות נוספות שייך להגדרות', () {
    nav.push(const CustomAppsManageRoute());
    expect(nav.section, ShellSection.settings);
    expect(nav.stack[1], const SectionRoute(ShellSection.settings));

    nav.push(const CustomAppDetailRoute('x'));
    expect(nav.section, ShellSection.customApps);
  });

  test('שכבת משימה: אין חזרה ואין ניווט עד שהיא נסגרת', () {
    nav.select(ShellSection.library);
    nav.showTask();
    expect(nav.showsTask, isTrue);
    expect(nav.current, const TaskRoute(ShellSection.library));
    expect(nav.section, ShellSection.library);
    expect(nav.canGoBack, isFalse);
    expect(nav.back(), isFalse);

    nav.select(ShellSection.settings);
    nav.push(const PluginDetailRoute('a'));
    expect(nav.current, const TaskRoute(ShellSection.library));

    nav.endTask();
    expect(nav.current, const SectionRoute(ShellSection.library));
    expect(nav.isBuilt(ShellSection.settings), isFalse);
  });

  test('push של מקטע או בית שקול ל-select', () {
    nav.push(const SectionRoute(ShellSection.reports));
    expect(nav.section, ShellSection.reports);
    nav.push(const HomeRoute());
    expect(nav.stack, [const HomeRoute()]);
    nav.push(const TaskRoute(ShellSection.home));
    expect(nav.showsTask, isTrue);
  });

  group('שער הכניסה', () {
    late List<ShellSection> asked;
    late Completer<bool> answer;
    late ShellNavigator gated;

    setUp(() {
      asked = [];
      answer = Completer<bool>();
      gated = ShellNavigator(
        canEnter: (section) {
          asked.add(section);
          if (section == ShellSection.settings) return answer.future;
          return true;
        },
      );
    });

    tearDown(() => gated.dispose());

    test('מקטע פתוח נכנס מיד, בלי פער אסינכרוני', () {
      gated.select(ShellSection.library);
      expect(gated.section, ShellSection.library);
      gated.push(const PluginDetailRoute('a'));
      expect(gated.current, const PluginDetailRoute('a'));
      expect(asked, [ShellSection.library, ShellSection.plugins]);
    });

    test('ההגדרות ממתינות לשער, ודחייה משאירה במקום', () async {
      final entered = gated.select(ShellSection.settings);
      expect(gated.section, ShellSection.home);
      answer.complete(false);
      expect(await entered, isFalse);
      expect(gated.section, ShellSection.home);
      expect(gated.isBuilt(ShellSection.settings), isFalse);
    });

    test('ניהול התוכנות עובר באותו שער של ההגדרות', () async {
      final entered = gated.push(const CustomAppsManageRoute());
      expect(asked, [ShellSection.settings]);
      expect(gated.current, const HomeRoute());
      answer.complete(true);
      expect(await entered, isTrue);
      expect(gated.current, const CustomAppsManageRoute());
    });

    test('משימה שנפתחה בזמן ההמתנה גוברת על הכניסה', () async {
      final entered = gated.select(ShellSection.settings);
      gated.showTask();
      answer.complete(true);
      expect(await entered, isFalse);
      expect(gated.current, const TaskRoute(ShellSection.home));
    });
  });

  test('כל מסך בסרגל הקיים הוא מקטע בשם זהה', () {
    final sections = ShellSection.values.map((s) => s.name).toSet();
    for (final screen in LauncherScreen.values) {
      expect(sections, contains(screen.name), reason: screen.name);
    }
  });
}
