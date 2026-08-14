import 'package:flutter/widgets.dart';

/// 앱 전역 이미지 캐시 압박 대응 옵저버.
///
/// 배경: 레퍼런스 앱(Organic Maps)은 `Framework::MemoryWarning()`(OS 메모리 경고)과
/// `Framework::EnterBackground()`(백그라운드 진입) 양쪽에서 무조건 캐시를 비운다.
/// 유루나비는 지금까지 이 두 훅이 전혀 없었다.
///
/// `FlutterActivityAndFragmentDelegate.onTrimMemory(level)`은
/// `isFirstFrameRendered && level >= TRIM_MEMORY_RUNNING_LOW(10)`이면(=거의 모든
/// 레벨을 포함하는 넓은 조건) `SystemChannel.sendMemoryPressureWarning()`을 보내
/// Dart `WidgetsBinding.handleMemoryPressure()` → 등록된 모든
/// `WidgetsBindingObserver.didHaveMemoryPressure()`를 호출한다. 이미 조건이 넓어서
/// Kotlin(`MainActivity`) 쪽 오버라이드는 필요 없다 — 이 클래스만으로 충분하다.
///
/// 대상은 Flutter `imageCache`뿐이다. 지도 타일/POI 아이콘은 MapLibre 네이티브
/// 텍스처 풀을 거쳐 이 캐시와 무관하고, `PoiRegionCache`(가벼운 POI 쿼리 결과,
/// TTL 5분)는 과거 POI 네트워크 요청 폭주 이슈 재발 위험이 있어 대상에서 뺐다.
///
/// [nav_screen.dart]의 기존 화면 로컬 `WidgetsBindingObserver`(안내 상태 처리)와는
/// 별개다 — Flutter는 여러 옵저버를 동시에 등록할 수 있게 설계돼 있다.
class MemoryPressureObserver extends WidgetsBindingObserver {
  MemoryPressureObserver._();

  static final MemoryPressureObserver _instance = MemoryPressureObserver._();

  /// `WidgetsFlutterBinding.ensureInitialized()` 이후 아무 때나 호출 가능.
  /// `runApp()` 이전에 호출해라.
  static void init() {
    WidgetsBinding.instance.addObserver(_instance);
  }

  @override
  void didHaveMemoryPressure() {
    _clearImageCache('onTrimMemory');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // S20 조사(2026-08-14): nav_screen 자체 옵저버는 도착 후 auto-exit로
    // dispose()되면 함께 제거돼, 그 뒤에 오는 background/foreground 전이를
    // 못 본다. 이 전역 옵저버에서 모든 state 전이를 남겨야 어느 화면이
    // 떠 있을 때 몇 번 전이가 왔는지 다음 실주행에서 재구성할 수 있다.
    debugPrint('YNAV_LIFECYCLE state=$state');
    if (state == AppLifecycleState.paused) {
      _clearImageCache('background');
    }
  }

  void _clearImageCache(String reason) {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugPrint('YNAV_MEMPRESSURE $reason imageCache cleared');
  }
}
