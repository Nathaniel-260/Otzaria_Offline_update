import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:plugins_manager/src/services/plugin_mirror_sync.dart';
import 'package:test/test.dart';

import 'support.dart';

class _StopBeforeLaunch implements Exception {
  const _StopBeforeLaunch();
}

void main() {
  late Directory temp;
  late PluginMirrorStore store;
  final strings = AppL10n.strings.pluginsDomain;

  setUp(() {
    temp = createTempDir();
    store = PluginMirrorStore(temp.path);
  });
  tearDown(() => deleteTempDir(temp));

  Map<String, dynamic> apiPlugin({
    String version = '1.1.0',
    String? pluginUid = 'uid-a',
    Map<String, String?>? hashes,
  }) =>
      {
        'id': 'a',
        'name': 'אלף',
        'version': version,
        'status': 'stable',
        'pluginUid': pluginUid,
        'downloadUrl': '/api/plugins/a/download',
        if (hashes != null) 'sha256': hashes[version],
        'versions': [
          for (final v in [version, '1.0.0'])
            {
              'version': v,
              'status': 'stable',
              'downloadUrl': v == version
                  ? '/api/plugins/a/download'
                  : '/api/plugins/a@$v/download',
              'isLatest': v == version,
              if (hashes != null) 'sha256': hashes[v],
            },
        ],
      };

  PluginsManager manager(
    Map<String, dynamic> raw,
    List<int> Function(Uri url) file, {
    List<Uri>? requests,
  }) =>
      PluginsManager(
        resolveMirrorDir: () async => temp.path,
        resolvePluginsDir: () async => p.join(temp.path, 'otzaria', 'plugins'),
        baseUrl: 'https://otzaria.test',
        httpClient: MockClient((request) async {
          requests?.add(request.url);
          if (request.url.path == '/api/plugins') return jsonResponse([raw]);
          if (request.url.path.endsWith('/download')) {
            return http.Response.bytes(file(request.url), 200);
          }
          return http.Response('', 404);
        }),
        otzariaLaunchPath: () async => throw const _StopBeforeLaunch(),
      );

  group('זהות הבילד', () {
    test('pluginUid מהאתר הוא ה-manifestId עוד לפני שהקובץ ירד', () {
      final plugin = StorePlugin.fromApi(apiPlugin(), 'https://otzaria.test');

      expect(plugin.manifestId, 'uid-a');
      expect(
        plugin.statusAgainst({'uid-a': '1.1.0'}),
        PluginInstallStatus.upToDate,
      );
    });

    test('הכתובת החיה שהחזירה גרסה אחרת — הקובץ נדחה ואינו נשמר', () async {
      final raw = apiPlugin();
      final outcome = await manager(
        raw,
        (_) => pluginBytes('{"id":"uid-a","version":"1.2.0"}'),
      ).sync();

      expect(outcome.failed, ['אלף']);
      final saved = outcome.catalog.plugins.single;
      expect(saved.localFiles, isEmpty);
      expect(
        File(p.join(store.pluginDir('a'), 'plugin-1.1.0.otzplugin'))
            .existsSync(),
        isFalse,
      );
    });

    test('מזהה מניפסט שאינו ה-pluginUid של האתר — נדחה', () async {
      final outcome = await manager(
        apiPlugin(),
        (_) => pluginBytes('{"id":"other","version":"1.1.0"}'),
      ).sync();

      expect(outcome.failed, ['אלף']);
      expect(outcome.catalog.plugins.single.localFiles, isEmpty);
    });

    test('מזהה וגרסה תואמים — הבילד נשמר', () async {
      final outcome = await manager(
        apiPlugin(),
        (_) => pluginBytes('{"id":"uid-a","version":"1.1.0"}'),
      ).sync();

      expect(outcome.failed, isEmpty);
      expect(outcome.catalog.plugins.single.localFiles.keys, ['1.1.0']);
    });
  });

  group('sha256 מהאתר', () {
    final good = pluginBytes('{"id":"uid-a","version":"1.1.0"}');
    final goodHash = sha256.convert(good).toString();

    test('אתר שמפרסם sha256 — ההורדה בכתובת המוצמדת לגרסה', () async {
      final requests = <Uri>[];
      final outcome = await manager(
        apiPlugin(hashes: {'1.1.0': goodHash, '1.0.0': null}),
        (_) => good,
        requests: requests,
      ).sync();

      final download = requests.singleWhere(
        (url) => url.path.endsWith('/download'),
      );
      expect(download.path, '/api/plugins/a/download');
      expect(download.queryParameters, {'version': '1.1.0'});
      final file = outcome.catalog.plugins.single.localFiles['1.1.0'];
      expect(file?.sha256, goodHash);
    });

    test('אתר ישן בלי sha256 — הכתובת החיה כמו קודם', () {
      final plugin = StorePlugin.fromApi(apiPlugin(), 'https://otzaria.test');

      expect(
        plugin.versions.first.downloadUrl,
        'https://otzaria.test/api/plugins/a/download',
      );
    });

    test('קובץ שאינו תואם ל-sha256 נדחה', () async {
      final outcome = await manager(
        apiPlugin(hashes: {'1.1.0': 'f' * 64}),
        (_) => good,
      ).sync();

      expect(outcome.failed, ['אלף']);
      expect(outcome.catalog.plugins.single.localFiles, isEmpty);
    });

    test('בילד שירד מהכתובת החיה אינו יורד שוב כשהאתר עובר לכתובת המוצמדת', () {
      final pinned = PluginVersionEntry(
        version: '1.1.0',
        status: 'stable',
        compatibleWith: '',
        maxAppVersion: null,
        downloadUrl: StorePlugin.pinnedDownloadUrl(
          'https://otzaria.test',
          'a',
          '1.1.0',
        ),
      );

      expect(
        PluginMirrorSync.buildMatches(
          pinned,
          'https://otzaria.test/api/plugins/a/download',
          100,
        ),
        isTrue,
      );
      expect(
        PluginMirrorSync.buildMatches(
          pinned,
          'https://otzaria.test/api/plugins/a/download?version=1.0.0',
          100,
        ),
        isFalse,
      );
    });

    test('בהתקנה: קובץ שהשתנה בכונן אחרי ההורדה נחסם', () async {
      final m = manager(
        apiPlugin(hashes: {'1.1.0': goodHash, '1.0.0': null}),
        (_) => good,
      );
      final outcome = await m.sync();
      final plugin = outcome.catalog.plugins.single;
      final path = store.absolutePath(plugin.localFiles['1.1.0']!.relativePath);
      final tampered = List<int>.of(good)..[good.length - 1] ^= 0xFF;
      File(path).writeAsBytesSync(tampered);

      final result = await m.directInstall(plugin);

      expect(result.success, isFalse);
      expect(result.error, strings.localPluginFileCorrupt);
    });

    test('בהתקנה: קובץ תקין מגיע למסירה לאוצריא', () async {
      final m = manager(
        apiPlugin(hashes: {'1.1.0': goodHash, '1.0.0': null}),
        (_) => good,
      );
      final plugin = (await m.sync()).catalog.plugins.single;

      await expectLater(
        m.directInstall(plugin),
        throwsA(isA<_StopBeforeLaunch>()),
      );
    });

    test('בהתקנה בלי sha256: קובץ של גרסה אחרת בשם הגרסה הנבחרת נחסם',
        () async {
      final m = manager(
        apiPlugin(),
        (_) => pluginBytes('{"id":"uid-a","version":"1.1.0"}'),
      );
      final plugin = (await m.sync()).catalog.plugins.single;
      final path = store.absolutePath(plugin.localFiles['1.1.0']!.relativePath);
      final other = pluginBytes('{"id":"uid-a","version":"1.2.0"}');
      File(path).writeAsBytesSync(other);
      final resized = plugin.copyWith(
        localFiles: {
          '1.1.0': PluginLocalFile(
            relativePath: plugin.localFiles['1.1.0']!.relativePath,
            fileName: 'x.otzplugin',
            ext: '.otzplugin',
            size: other.length,
          ),
        },
      );

      final result = await m.directInstall(resized);

      expect(result.error, strings.localPluginFileCorrupt);
    });
  });
}
