// צילומי סקירה (לא goldens): רק ב-Windows עם OTZ_VISUAL=1; השלב ב-OTZ_VISUAL_PHASE.
// פלט: build/visual_review/<phase>/<state>.png, ו-<state>_narrow.png ב-760x560.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/app_shell.dart';
import 'package:launcher_app/src/screens/home/home_page.dart';
import 'package:launcher_app/src/screens/reports/reports_page.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_navigator.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../home_fixtures.dart';
import '../page_fixtures.dart';
import '../task_fixtures.dart';
import '../test_harness.dart';
import '../test_support.dart';
import 'visual_fonts.dart';

final _enabled =
    Platform.isWindows && Platform.environment['OTZ_VISUAL'] == '1';
final _phase = Platform.environment['OTZ_VISUAL_PHASE'] ?? 'phase0';

const _sizes = {'': Size(1000, 720), '_narrow': Size(760, 560)};

/// מצב לצילום: שם הקובץ, ומה עושים אחרי שהמסגרת עלתה.
typedef VisualState = ({
  String name,
  Future<void> Function(WidgetTester tester) open,
});

/// מאז שלב 2 אין סרגל: המקטעים נפתחים מהאריחים שבבית.
Future<void> _tapTile(WidgetTester tester, ShellSection section) async {
  await tester.tap(find.byKey(ShellKeys.tile(section)));
  await tester.pump();
}

final List<VisualState> _phase0States = [
  (name: 'home', open: (_) async {}),
  (name: 'otzaria', open: (t) => _tapTile(t, ShellSection.otzaria)),
  (name: 'library', open: (t) => _tapTile(t, ShellSection.library)),
  (name: 'plugins', open: (t) => _tapTile(t, ShellSection.plugins)),
  (
    name: 'settings',
    open: (t) => _tapTooltip(t, stringsOf().shell.settingsTooltip),
  ),
];

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pump();
}

final List<VisualState> _phase1States = [
  ..._phase0States,
  (name: 'help', open: (t) => _tapTooltip(t, stringsOf().shell.helpTooltip)),
];

Future<void> _tab(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  }
  await tester.pump();
}

final List<VisualState> _phase1bStates = [
  ..._phase1States,
  // שורת הכותרת מעל השכבה של הדו-שיח, והכפתור הממוקד בצבע הרגיל.
  (
    name: 'dialog_hover_close',
    open: (t) async {
      await _tapTooltip(t, stringsOf().shell.helpTooltip);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: t.getCenter(
          find.bySemanticsLabel(stringsOf().shell.windowClose),
        ),
      );
      await t.pump();
    },
  ),
  (name: 'focus_keyboard', open: (t) => _tab(t, 3)),
];

/// שלב 2a: המסגרת האמיתית (הבית ודפי המשנה). מצבי הבית של המוקאפ מצולמים
/// בנפרד, מהמודל — ראו `home_<scenario>`.
final List<VisualState> _phase2aStates = [
  (name: 'shell_home', open: (_) async {}),
  (name: 'shell_library', open: (t) => _tapTile(t, ShellSection.library)),
  (name: 'shell_plugins', open: (t) => _tapTile(t, ShellSection.plugins)),
  (
    name: 'shell_settings',
    open: (t) => _tapTooltip(t, stringsOf().shell.settingsTooltip),
  ),
];

/// שלב חדש מוסיף כאן את רשימת המצבים שלו.
final Map<String, List<VisualState>> _statesByPhase = {
  'phase0': _phase0States,
  'phase1': _phase1States,
  'phase1b': _phase1bStates,
  'phase2a': _phase2aStates,
  // תיקוני הסקירה של 2a — אותם מצבים, ומצבי הבית החדשים מ-home_fixtures.
  'phase2a2': _phase2aStates,
  // סבב 3: הגילוי שבדף הדיווחים — ראו `reports_<variant>`.
  'phase2a3': _phase2aStates,
  // מסכי המשימה מצולמים מהמודל — ראו `task_<scenario>`.
  'phase2b': _phase2aStates,
  // הדפים מצולמים מהקונטרולרים — ראו `page_<scenario>`.
  'phase3': _phase2aStates,
  // תיקוני 2b: מסכי המשימה שוב, והבית (היחידות הלטיניות).
  'phase2b2': const [],
};

/// הבית במצבי המוקאפ, בתוך שורת הכותרת — בלי סשן.
Set<String> get _homeScenarioPhases =>
    const {'phase2a', 'phase2a2', 'phase2a3', 'phase2b2'};

/// מסכי המשימה מצולמים מהמודל — ראו `task_<scenario>`.
const _taskPhases = {'phase2b', 'phase2b2'};

/// דף הדיווחים עם כרטיס האיסוף — המונים מגיעים מהסשן, ולכן מצולם מהווידג'ט.
const _reportsVariants = {
  'reports_collect': (reports: 3, searchRecords: 5),
  'reports_only': (reports: 2, searchRecords: 0),
};

/// משלב 1 שורת הכותרת מצוירת כולה ב-Flutter, ולכן הכפתורים נכנסים לצילום.
bool get _showWindowButtons => _phase != 'phase0';

void main() {
  late Directory tempDir;
  late SettingsController settings;
  final boundary = GlobalKey();

  setUp(() async {
    if (!_enabled) return;
    // כפתורי החלון שואלים אם החלון מוגדל.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isMaximized' ? false : null,
    );
    tempDir = Directory.systemTemp.createTempSync('visual_review');
    await AppLogger.init(tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
    await settings.update(const AppSettings(autoCheckUpdates: false));
  });

  tearDown(() async {
    if (!_enabled) return;
    settings.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  /// נותן ל-I/O האמיתי (טעינת תוספים, פענוח תמונות) להסתיים לפני הצילום.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> capture(WidgetTester tester, String file) async {
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final out = File(file)..parent.createSync(recursive: true);
      await out.writeAsBytes(png!.buffer.asUint8List());
    });
  }

  for (final state in _statesByPhase[_phase] ?? const <VisualState>[]) {
    for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
      testWidgets('$_phase/${state.name}$suffix', skip: !_enabled, (
        tester,
      ) async {
        await tester.runAsync(loadVisualFonts);
        debugDisableShadows = false;
        // כמו `debugShowCheckedModeBanner: false` שב-main.dart.
        WidgetsApp.debugAllowBannerOverride = false;
        try {
          useViewSize(tester, size);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: wrap(
                AppShell(
                  dataDir: tempDir.path,
                  settings: settings,
                  runningLocator: const _NeverRunningLocator(),
                  noticesStore: MemoryNoticesStore(
                    seen: {NoticesSeenStore.errorReportsIntro},
                  ),
                  showWindowButtons: _showWindowButtons,
                ),
              ),
            ),
          );
          await settle(tester);
          await state.open(tester);
          await settle(tester);
          await capture(
            tester,
            p.join(
                'build', 'visual_review', _phase, '${state.name}$suffix.png'),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDisableShadows = true;
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }

  for (final scenario in homeScenarios) {
    for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
      testWidgets('$_phase/home_$scenario$suffix',
          skip: !_enabled || !_homeScenarioPhases.contains(_phase), (
        tester,
      ) async {
        await tester.runAsync(loadVisualFonts);
        WidgetsApp.debugAllowBannerOverride = false;
        try {
          useViewSize(tester, size);
          AppL10n.use(AppLanguage.hebrew);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: wrap(
                Scaffold(
                  backgroundColor: const Color(0xFFF6EDE5),
                  body: Column(
                    children: [
                      AppTitleBar(
                        onHelp: () {},
                        onSettings: () {},
                        showWindowButtons: true,
                      ),
                      Expanded(
                        child: HomePage(model: homeScenario(scenario)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await settle(tester);
          await capture(
            tester,
            p.join(
              'build',
              'visual_review',
              _phase,
              'home_$scenario$suffix.png',
            ),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }

  for (final scenario in taskScenarioNames) {
    for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
      testWidgets('$_phase/task_$scenario$suffix',
          skip: !_enabled || !_taskPhases.contains(_phase), (tester) async {
        await tester.runAsync(loadVisualFonts);
        WidgetsApp.debugAllowBannerOverride = false;
        try {
          useViewSize(tester, size);
          // `formatBytes` קורא את השפה הגלובלית — בלי זה היחידות באנגלית.
          AppL10n.use(AppLanguage.hebrew);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: wrap(
                Scaffold(
                  backgroundColor: const Color(0xFFF6EDE5),
                  body: Column(
                    children: [
                      AppTitleBar(
                        onHelp: () {},
                        onSettings: () {},
                        showWindowButtons: true,
                      ),
                      Expanded(child: taskScenario(scenario)),
                    ],
                  ),
                ),
              ),
            ),
          );
          await settle(tester);
          await capture(
            tester,
            p.join(
              'build',
              'visual_review',
              _phase,
              'task_$scenario$suffix.png',
            ),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }

  for (final MapEntry(key: name, value: counts) in _reportsVariants.entries) {
    for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
      testWidgets('$_phase/$name$suffix',
          skip: !_enabled || _phase != 'phase2a3', (tester) async {
        await tester.runAsync(loadVisualFonts);
        WidgetsApp.debugAllowBannerOverride = false;
        try {
          useViewSize(tester, size);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: wrap(
                Scaffold(
                  backgroundColor: const Color(0xFFF6EDE5),
                  body: Column(
                    children: [
                      AppTitleBar(
                        onHelp: () {},
                        onSettings: () {},
                        showWindowButtons: true,
                      ),
                      Expanded(
                        child: ReportsPage(
                          errorReports: null,
                          searchFeedback: null,
                          connection: null,
                          isUploadingAll: false,
                          busy: false,
                          reportsToCollect: counts.reports,
                          searchRecordsToCollect: counts.searchRecords,
                          onCollect: () {},
                          onUpload: null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await settle(tester);
          await capture(
            tester,
            p.join('build', 'visual_review', _phase, '$name$suffix.png'),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          WidgetsApp.debugAllowBannerOverride = true;
        }
      });
    }
  }

  for (final MapEntry(key: name, value: build) in pageScenarios.entries) {
    for (final advanced in [
      false,
      if (advancedScenarios.contains(name)) true
    ]) {
      for (final MapEntry(key: suffix, value: size) in _sizes.entries) {
        final file = '$name${advanced ? '_advanced' : ''}$suffix';
        testWidgets('$_phase/page_$file',
            skip: !_enabled || !{'phase3', 'phase2b2'}.contains(_phase),
            (tester) async {
          await tester.runAsync(loadVisualFonts);
          WidgetsApp.debugAllowBannerOverride = false;
          try {
            useViewSize(tester, size);
            // מלל התחום (otzaria_l10n) נקרא מהשפה הגלובלית, לא מה-context.
            AppL10n.use(AppLanguage.hebrew);
            final crumb = switch (name.split('_').first) {
              'otzaria' => stringsOf().guide.tileApp,
              'library' => stringsOf().guide.tileLibrary,
              'reports' => stringsOf().guide.tileReports,
              _ => stringsOf().pages.selfCrumb,
            };
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: wrap(
                  Scaffold(
                    backgroundColor: const Color(0xFFF6EDE5),
                    body: Column(
                      children: [
                        AppTitleBar(
                          onHelp: () {},
                          onSettings: () {},
                          showWindowButtons: true,
                        ),
                        Expanded(
                          child: SubPageHeaderScope(
                            header: SubPageHeader(
                              onBack: () {},
                              onHome: () {},
                              trail: [(label: crumb, onTap: null)],
                            ),
                            child: build(tempDir.path, settings),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await settle(tester);
            if (advanced) {
              await tester.drag(
                find.byType(ListView).first,
                const Offset(0, -2000),
              );
              await settle(tester);
              await tester.tap(find.text(stringsOf().pages.advancedTitle));
              await settle(tester);
              await tester.drag(
                find.byType(ListView).first,
                const Offset(0, -2000),
              );
              await settle(tester);
            }
            await capture(
              tester,
              p.join('build', 'visual_review', _phase, 'page_$file.png'),
            );
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            WidgetsApp.debugAllowBannerOverride = true;
          }
        });
      }
    }
  }

  // גלריית רכיבים: שדות, סגמנט, תפריט, מתג, פירור, אריחים וכרטיסים.
  testWidgets('$_phase/gallery', skip: !_enabled || _phase == 'phase0', (
    tester,
  ) async {
    await tester.runAsync(loadVisualFonts);
    WidgetsApp.debugAllowBannerOverride = false;
    try {
      useViewSize(tester, const Size(1000, 720));
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: wrap(const _Gallery())),
      );
      await settle(tester);
      // מיקוד מהמקלדת על השדה השני — הטבעת שלו והמסגרת ב-primary.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await capture(
        tester,
        p.join('build', 'visual_review', _phase, 'gallery.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      WidgetsApp.debugAllowBannerOverride = true;
    }
  });
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SubPageHeader(
              onBack: () {},
              onHome: () {},
              trail: [
                (label: s.guide.tileReports, onTap: () {}),
                (label: s.guide.tilePlugins, onTap: null),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: RtlTextField(
                    decoration: InputDecoration(
                      labelText: s.guide.tileApp,
                      helperText: s.guide.tileLibrary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: RtlTextField(
                    decoration: InputDecoration(hintText: 'Search'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppSegmentedControl<int>(
                  options: [
                    SegmentOption(value: 0, label: s.shell.breadcrumbHome),
                    SegmentOption(value: 1, label: s.guide.tileApp),
                    SegmentOption(value: 2, label: s.guide.tileLibrary),
                  ],
                  currentValue: 1,
                  onChanged: (_) {},
                ),
                AppDropdownField<int>(
                  value: 0,
                  entries: [
                    AppMenuEntry(value: 0, label: s.shell.breadcrumbHome),
                    AppMenuEntry(value: 1, label: s.guide.tileApp),
                  ],
                  onSelected: (_) {},
                ),
                CustomSwitch(value: true, onChanged: (_) {}),
                CustomSwitch(value: false, onChanged: (_) {}),
                const CustomSwitch(value: true, onChanged: null),
              ],
            ),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 12,
              children: [
                IconTile(icon: FluentIcons.info_24_regular),
                IconTile(
                    icon: FluentIcons.info_24_regular,
                    tone: IconTileTone.quiet),
                IconTile(
                    icon: FluentIcons.info_24_regular,
                    tone: IconTileTone.error),
                IconTile(
                    icon: FluentIcons.info_24_regular, size: IconTileSize.sm),
              ],
            ),
            const SizedBox(height: 16),
            AppCard.section(
              children: [
                ListTile(title: Text(s.shell.breadcrumbHome)),
                ListTile(title: Text(s.guide.tileApp)),
              ],
            ),
            const SizedBox(height: 16),
            OptionCard(
              icon: FluentIcons.arrow_download_24_regular,
              title: s.guide.tileLibrary,
              description: s.guide.tilePlugins,
              selected: true,
              onSelected: () {},
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                ActionButton.recommended(
                    text: s.common.install, onPressed: () {}),
                ActionButton.neutral(text: s.common.cancel, onPressed: () {}),
                ActionButton.ghost(text: s.common.cancel, onPressed: () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}
