import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider는 Riverpod 3에서 legacy.dart로 분리됐다 — pendingDeepLinkRouteProvider가
// 단순 명령형 상태 플래그로 이 API를 쓴다.
import 'package:flutter_riverpod/legacy.dart';

import '../models/saved_route.dart';

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

final pendingDeepLinkRouteProvider = StateProvider<SavedRoute?>((ref) => null);
