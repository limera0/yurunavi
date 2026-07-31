import 'package:flutter_riverpod/flutter_riverpod.dart';

// Re-export from new feature-based structure.
// Kept for backward compatibility with screens not yet migrated.
export '../features/map/providers/map_providers.dart';

/// Whether the splash screen has already handed off to [MainMapScreen].
/// Used by `main.dart` to decide when it's safe to apply the app-wide
/// system status/navigation bar color (splash itself is excluded —
/// loop/layout_fixes/PROGRESS.md 라운드2). Flipped to `true` exactly once,
/// right before `SplashScreen._goToMain()` navigates away.
final pastSplashProvider =
    NotifierProvider<PastSplashNotifier, bool>(PastSplashNotifier.new);

class PastSplashNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markPastSplash() => state = true;
}
