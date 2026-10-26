import 'package:seforim_library_updater/seforim_library_updater.dart';

/// קשת לפי שם ה-manifest: הנכסים שלה (ה-manifest וקובצי ה-patch) וגודלם.
typedef _Edge = ({int from, int to, List<ReleaseAsset> assets, int bytes});

final RegExp _edgeName = RegExp(
  r'^patch-v(\d+)-v(\d+)\.db\.zst\.manifest\.json$',
);

/// חסם עליון לבייטים ש-`LibraryMirrorExporter.export` (לא אישי) יוריד, משמות
/// וגדלים בלבד — בלי לשלוף אף manifest. `null` = אין חסם אמין.
///
/// מחיל מכללי המייצא את מה שאינו דורש manifest: פסילת קשת שה-manifest שלה כבר
/// בכונן ואינו בר-החלה ([heldManifest]), הקשת האיטית ([ApplyTimeEstimate], בלי
/// זיכוי — הנשא הוא החדש), ומבוי סתום. קשת שאיננו יודעים עליה נחשבת תקפה,
/// ולכן הקשתות כאן הן על-קבוצה של האמיתיות והחסם אינו יורד מתחת להורדה.
int? mirrorDownloadBytesBound({
  required List<LibraryRelease> relevant,
  required int supportedDbSchemaVersion,
  required ApplyTimeEstimate applyTime,
  required bool Function(LibraryRelease release, ReleaseAsset asset) complete,
  required DeltaManifest? Function(LibraryRelease release, ReleaseAsset asset)
  heldManifest,
}) {
  ReleaseAsset? fullOf(LibraryRelease release) =>
      release.fullDbAssetFor(maxSchemaVersion: supportedDbSchemaVersion);
  final carriers = relevant.where((r) => fullOf(r) != null).toList()
    ..sort(
      (a, b) => LibraryUpdateDiscovery.releaseVersionOf(
        b,
      ).compareTo(LibraryUpdateDiscovery.releaseVersionOf(a)),
    );
  final newest = carriers.firstOrNull;
  final newestFull = newest == null ? null : fullOf(newest)!;
  if (newestFull?.isSplitFullDbManifest ?? false) return null;
  final newestVersion = newest == null
      ? 0
      : LibraryUpdateDiscovery.releaseVersionOf(newest);

  final always = <(LibraryRelease, ReleaseAsset)>[];
  final edges = <(LibraryRelease, _Edge)>[];
  for (final release in relevant) {
    final claimed = <String>{};
    for (final manifestAsset in release.deltaManifestAssets) {
      always.add((release, manifestAsset));
      claimed.add(manifestAsset.name);
      final manifest = heldManifest(release, manifestAsset);
      final int from;
      final int to;
      final List<ReleaseAsset> files;
      if (manifest != null) {
        final names = {for (final f in manifest.patchFiles) f.file};
        claimed.addAll(names);
        if (!_appliable(manifest)) continue;
        files = release.assets.where((a) => names.contains(a.name)).toList();
        // קשת חסרה אינה נבנית, אבל מה שיש ממנה יורד.
        if (files.length < names.length) {
          always.addAll(files.map((f) => (release, f)));
          continue;
        }
        (from, to) = (manifest.fromVersion, manifest.toVersion);
      } else {
        final match = _edgeName.firstMatch(manifestAsset.name);
        if (match == null) continue;
        final base = manifestAsset.name.substring(
          0,
          manifestAsset.name.length - '.manifest.json'.length,
        );
        files = release.assets
            .where(
              (a) =>
                  !a.isDeltaManifest &&
                  (a.name == base || a.name.startsWith('$base.')),
            )
            .toList();
        claimed.addAll(files.map((f) => f.name));
        (from, to) = (int.parse(match.group(1)!), int.parse(match.group(2)!));
      }
      edges.add((
        release,
        (
          from: from,
          to: to,
          assets: [manifestAsset, ...files],
          bytes: [
            manifestAsset,
            ...files,
          ].fold(0, (sum, a) => sum + (a.size > 0 ? a.size : 0)),
        ),
      ));
    }
    for (final asset in release.assets) {
      if (asset.name.startsWith('patch-') && !claimed.contains(asset.name)) {
        always.add((release, asset));
      }
    }
  }

  // שני המעברים של המייצא: עם זיכוי ההורדה לפני בחירת הנשא, ובלעדיו אחריה.
  List<(LibraryRelease, _Edge)> fast({required bool credit}) {
    if (newestFull == null || newestFull.size <= 0) return edges;
    final fullSeconds = applyTime.fullRouteSeconds(newestFull.size);
    return [
      for (final entry in edges)
        if (entry.$2.to > newestVersion ||
            !applyTime.isOutOfRange(
              applyTime.deltaRouteSeconds([entry.$2.bytes]),
              fullSeconds,
              savedDownloadBytes: credit ? newestFull.size - entry.$2.bytes : 0,
            ))
          entry,
    ];
  }

  var kept = fast(credit: false);
  if (newest != null) {
    if (!complete(newest, newestFull!)) {
      final reach = _maxReach([for (final e in fast(credit: true)) e.$2]);
      for (final candidate in carriers.skip(1)) {
        if (!complete(candidate, fullOf(candidate)!)) continue;
        final version = LibraryUpdateDiscovery.releaseVersionOf(candidate);
        final reached = reach[version] ?? version;
        // מסד ישן שהמייצא עשוי לבחור: ההורדה בין ~0.1GB לכל המסד — אין חסם.
        if (version < newestVersion
            ? reached >= newestVersion
            : reached > version) {
          return null;
        }
      }
    }
    final reach = _maxReach([for (final e in kept) e.$2]);
    kept = [
      for (final entry in kept)
        if ((reach[entry.$2.to] ?? entry.$2.to) >= newestVersion) entry,
    ];
  }

  final counted = <(String, String)>{};
  var bytes = 0;
  void count(LibraryRelease release, ReleaseAsset asset) {
    if (!counted.add((release.tag, asset.name))) return;
    if (complete(release, asset)) return;
    if (asset.size > 0) bytes += asset.size;
  }

  if (newest != null) count(newest, newestFull!);
  for (final (release, asset) in always) {
    count(release, asset);
  }
  for (final (release, edge) in kept) {
    for (final asset in edge.assets) {
      count(release, asset);
    }
  }
  return bytes;
}

bool _appliable(DeltaManifest manifest) {
  final format = manifest.patchFormatVersion;
  return !manifest.fullRebase &&
      isSupportedSchemaVersion(manifest.fromSchemaVersion) &&
      isSupportedSchemaVersion(manifest.toSchemaVersion) &&
      (format == null || isSupportedPatchFormatVersion(format)) &&
      manifest.hasSupportedCompression;
}

/// לכל גרסה — הגבוהה ביותר שאפשר להגיע אליה ממנה בקשתות קדימה.
Map<int, int> _maxReach(List<_Edge> edges) {
  final reach = <int, int>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final edge in edges) {
      if (edge.to <= edge.from) continue;
      final candidate = reach[edge.to] ?? edge.to;
      if (candidate > (reach[edge.from] ?? edge.from)) {
        reach[edge.from] = candidate;
        changed = true;
      }
    }
  }
  return reach;
}
