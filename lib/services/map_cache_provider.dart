import 'package:flutter_map/flutter_map.dart';

/// Returns a [NetworkTileProvider] with aggressive disk caching enabled.
///
/// Uses flutter_map's built-in [BuiltInMapCachingProvider] (background
/// isolate + path_provider cache directory, 500 MB cap, 30-day freshness).
///
/// Behaviour during an offline ride:
/// - Tiles cached within the last 30 days are served directly from disk
///   without any network request.
/// - Tiles in uncached areas return transparent 1×1 images
///   ([silenceExceptions]: true) instead of crashing the tile layer.
/// - The existing route polyline rendered by flutter_map is unaffected
///   by tile-load failures — it renders on a separate layer.
NetworkTileProvider buildCachedTileProvider() {
  return NetworkTileProvider(
    // Silence failed loads so the UI never freezes during an offline ride.
    silenceExceptions: true,
    // Keep tiles fresh for 30 days regardless of server cache-control headers.
    cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
      overrideFreshAge: const Duration(days: 30),
      maxCacheSize: 500 * 1024 * 1024, // 500 MB
    ),
  );
}
