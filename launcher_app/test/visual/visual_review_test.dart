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
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

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

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(NavRailItem, label),
      matching: find.byType(IconButton),
    ),
  );
  await tester.pump();
}

final List<VisualState> _phase0States = [
  (name: 'home', open: (_) async {}),
  (name: 'otzaria', open: (t) => _tapNav(t, stringsOf().shell.navApp)),
  (name: 'library', open: (t) => _tapNav(t, stringsOf().shell.navLibrary)),
  (name: 'plugins', open: (t) => _tapNav(t, stringsOf().shell.navPlugins)),
  (name: 'settings', open: (t) => _tapNav(t, stringsOf().shell.navSettings)),
];

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pump();
}

final List<VisualState> _phase1States = [
  ..._phase0States.where((s) => s.name != 'settings'),
  (
    name: 'settings',
    open: (t) => _tapTooltip(t, stringsOf().shell.settingsTooltip),
  ),
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

/// שלב חדש מוסיף כאן את רשימת המצבים שלו.
final Map<String, List<VisualState>> _statesByPhase = {
  'phase0': _phase0States,
  'phase1': _phase1States,
  'phase1b': _phase1bStates,
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
                (label: s.shell.navSettings, onTap: () {}),
                (label: s.shell.navPlugins, onTap: null),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: RtlTextField(
                    decoration: InputDecoration(
                      labelText: s.shell.navApp,
                      helperText: s.shell.navLibrary,
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
                    SegmentOption(value: 0, label: s.shell.navHome),
                    SegmentOption(value: 1, label: s.shell.navApp),
                    SegmentOption(value: 2, label: s.shell.navLibrary),
                  ],
                  currentValue: 1,
                  onChanged: (_) {},
                ),
                AppDropdownField<int>(
                  value: 0,
                  entries: [
                    AppMenuEntry(value: 0, label: s.shell.navHome),
                    AppMenuEntry(value: 1, label: s.shell.navApp),
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
                ListTile(title: Text(s.shell.navHome)),
                ListTile(title: Text(s.shell.navApp)),
              ],
            ),
            const SizedBox(height: 16),
            OptionCard(
              icon: FluentIcons.arrow_download_24_regular,
              title: s.shell.navLibrary,
              description: s.shell.navPlugins,
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
