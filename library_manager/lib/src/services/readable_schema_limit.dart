import 'package:seforim_library_updater/seforim_library_updater.dart';

class ReadableSchemaRoute {
  const ReadableSchemaRoute({
    required this.edges,
    required this.latestFullDbAsset,
    required this.fullDbReleaseTag,
    required this.latestFullDbVersion,
    this.readableSchema,
    this.excludedSchema,
  });

  factory ReadableSchemaRoute.unlimited(
    OfflineLibraryDiscoveryResult discovery,
  ) => ReadableSchemaRoute(
    edges: discovery.edges,
    latestFullDbAsset: discovery.latestFullDbAsset,
    fullDbReleaseTag: discovery.fullDbReleaseTag,
    latestFullDbVersion: discovery.latestFullDbVersion,
  );

  final List<PatchEdge> edges;
  final ReleaseAsset? latestFullDbAsset;
  final String? fullDbReleaseTag;
  final int? latestFullDbVersion;
  final int? readableSchema;
  final int? excludedSchema;

  bool get limited => excludedSchema != null;

  static ReadableSchemaRoute limit({
    required OfflineLibraryDiscoveryResult discovery,
    required List<LibraryRelease> releases,
    required bool allowPrerelease,
    required int? readableSchema,
  }) {
    if (readableSchema == null || readableSchema >= kSupportedDbSchemaVersion) {
      return ReadableSchemaRoute.unlimited(discovery);
    }
    int? excluded;
    void exclude(int schema) {
      if (excluded == null || schema < excluded!) excluded = schema;
    }

    final edges = <PatchEdge>[];
    for (final edge in discovery.edges) {
      final schema = edge.manifest.toSchemaVersion;
      if (schema <= readableSchema &&
          edge.manifest.fromSchemaVersion <= readableSchema) {
        edges.add(edge);
      } else {
        exclude(schema);
      }
    }

    LibraryRelease? fullRelease;
    ReleaseAsset? fullAsset;
    var fullVersion = -1;
    for (final release in OfflineLibraryUpdateDiscovery.eligibleReleases(
      releases,
      allowPrerelease: allowPrerelease,
    )) {
      for (final asset in release.assets) {
        final schema = ReleaseAsset.fullDbSchemaOfName(asset.name);
        if (schema != null && asset.size > 0 && schema > readableSchema) {
          exclude(schema);
        }
      }
      final asset = release.fullDbAssetFor(maxSchemaVersion: readableSchema);
      if (asset == null) continue;
      final version = OfflineLibraryUpdateDiscovery.releaseVersionOf(release);
      if (version > fullVersion ||
          (version == fullVersion && _publishedAfter(release, fullRelease))) {
        fullVersion = version;
        fullRelease = release;
        fullAsset = asset;
      }
    }

    return ReadableSchemaRoute(
      edges: edges,
      latestFullDbAsset: fullAsset,
      fullDbReleaseTag: fullRelease?.tag,
      latestFullDbVersion: fullAsset == null ? null : fullVersion,
      readableSchema: readableSchema,
      excludedSchema: excluded,
    );
  }

  static bool _publishedAfter(LibraryRelease candidate, LibraryRelease? best) {
    if (best == null) return true;
    final bestDate = best.publishedAt;
    final own = candidate.publishedAt;
    if (bestDate == null) return own != null;
    return own != null && own.isAfter(bestDate);
  }
}
