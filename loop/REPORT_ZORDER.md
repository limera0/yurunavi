# REPORT_ZORDER — 마커 z-order 가림 해결 보고

## 0단계 게이트 3개 판정

| 항목 | 결과 |
|------|------|
| addLineLayer `belowLayerId` named param | YES (controller.dart:654) |
| _initRouteLayer 내 addLineLayer 2개 | YES (route-bg, route-selected) |
| ctrl 지역변수명 | `ctrl` (`final ctrl = _mlCtrl;`) |

→ 전원 PASS.

## 변경 전/후 핵심 diff

### Before (_initRouteLayer 상단)
```dart
Future<void> _initRouteLayer() async {
  final ctrl = _mlCtrl;
  if (ctrl == null) return;
  // bg layer (below selected route)
  await ctrl.addGeoJsonSource(_routeBgSourceId, _buildBgGeoJson([]));
  await ctrl.addLineLayer(
    _routeBgSourceId,
    _routeBgLayerId,
    const ml.LineLayerProperties(...),
  );                                   // ← belowLayerId 없음
  ...
  await ctrl.addLineLayer(
    _routeSourceId,
    _routeLayerId,
    const ml.LineLayerProperties(...),
  );                                   // ← belowLayerId 없음
}
```

### After
```dart
Future<void> _initRouteLayer() async {
  final ctrl = _mlCtrl;
  if (ctrl == null) return;
  // 경로선을 circle 마커 레이어 아래에 삽입하기 위해 circle layer id 산출
  final circleLyr = ctrl.circleManager?.layerIds.isNotEmpty == true
      ? ctrl.circleManager!.layerIds.first
      : null;
  debugPrint('[zorder] circleLyr=$circleLyr');  // ★진단용 로그

  await ctrl.addGeoJsonSource(_routeBgSourceId, _buildBgGeoJson([]));
  await ctrl.addLineLayer(
    _routeBgSourceId,
    _routeBgLayerId,
    const ml.LineLayerProperties(...),
    belowLayerId: circleLyr,           // ← 추가
  );
  await ctrl.addGeoJsonSource(_routeSourceId, _buildRouteGeoJson([]));
  await ctrl.addLineLayer(
    _routeSourceId,
    _routeLayerId,
    const ml.LineLayerProperties(...),
    belowLayerId: circleLyr,           // ← 추가
  );
}
```

변경 범위: `_initRouteLayer` 단 1개 메서드, 추가 7줄(circleLyr 산출 3줄 + debugPrint 1줄 + belowLayerId 2줄 + 공백 1줄).

## analyze · build 결과
- `flutter analyze`: **No issues found!**
- `flutter build apk --debug`: **✓ Built app-debug.apk** (Gradle 10.8s)

## 폰 실측 + 로그 확인 항목

- [ ] logcat에서 `[zorder] circleLyr=...` 값 확인 (null 아닌지)
      ```
      adb logcat | grep zorder
      ```
      기대값: `[zorder] circleLyr=<랜덤문자열>_0` (null이면 타이밍 문제)

- [ ] 경로 표시 시 초록/빨강 마커가 경로선 위에 보임 (z-order 해결)

- [ ] 경로 미표시 상태(마커만)에서도 마커 정상 표시 (회귀 없음)

- [ ] 대안경로(회색, route-bg-layer) 표시 시에도 마커가 위 (bg/selected 둘 다 belowLayerId 적용)

## 폰에서 여전히 가림 시 진단 분기

| 증상 | 원인 | 대응 |
|------|------|------|
| `circleLyr=null` | circleManager 미초기화 (annotationOrder에 circle 미포함 등) | annotationOrder 명시 또는 B안(GeoJsonSource+CircleLayer) 전환 |
| `circleLyr=값 있음` 인데도 가림 | Android GL 렌더러가 belowLayerId 무시 (드문 케이스) | B안 전환: addCircle → addGeoJsonSource+addCircleLayer, 경로 이후 추가 |
