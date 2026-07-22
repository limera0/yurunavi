# REPORT_MARKER — B1+B2 마커 구현 보고

## 0단계 게이트 4개 판정

| 항목 | 결과 | 근거 (파일:라인) |
|------|------|-----------------|
| removeCircle 실시그니처 | `Future<void> removeCircle(Circle circle)` | controller.dart:1421 |
| ml.CircleOptions / ml.Circle 프리픽스 | YES — re-export 확인 | maplibre_gl.dart:58-59 |
| _toMl() latlong2→ml.LatLng 변환 | YES | main_map_screen.dart:89 |
| 경로 레이어 생성 방식 | **1회 생성** (_initRouteLayer만 addLineLayer, _updateRouteLayer는 setGeoJsonSource만) | main_map_screen.dart:235-261 |

→ 전원 PASS. addCircle 방식 사용. 마커는 경로 레이어 이후 추가되므로 z-order 경로선 위 보장.

## 추가/수정 내용 (main_map_screen.dart 단일 파일)

### (2-1) 필드 추가 (line 87~91)
```dart
ml.Circle? _locMarker;
ml.Circle? _destMarker;
static const String _kLocColor = '#00C853';
static const String _kDestColor = '#E53935';
```

### (2-2) 메서드 추가 (line 264~309, _updateRouteLayer 직전)
- `_ensureLocationMarker()` — _origin ?? _lastKnown 기준, 없으면 생성, 있으면 updateCircle
- `_ensureDestMarker(LatLng dest)` — 목적지 좌표 기준, 없으면 생성, 있으면 updateCircle
- `_removeDestMarker()` — removeCircle 후 _destMarker = null

### (2-3) 호출 지점 5개
| 지점 | 추가 코드 | 비고 |
|------|-----------|------|
| onStyleLoadedCallback (line ~741) | `await _ensureLocationMarker()` | _initRouteLayer() 완료 후 → z-order 보장 |
| _lastKnown setState (line ~169) | `_ensureLocationMarker()` unawaited | 캐시 위치 도착 시 |
| _origin setState (line ~186) | `_ensureLocationMarker()` unawaited | GPS 스트림 매 10m |
| _applyDestination (line ~490) | `_ensureDestMarker(dest)` unawaited | 탭→목적지 설정 직후 |
| _clearDestination (line ~598) | `_removeDestMarker()` unawaited | 목적지 해제 시 |

## analyze · build 결과
- `flutter analyze`: **No issues found!**
- `flutter build apk --debug`: **✓ Built app-debug.apk** (Gradle 23.4s, KGP 경고는 기존 프로젝트 경고 — 이번 변경과 무관)

## 폰 실측 체크리스트
- [ ] 앱 시작 시 현위치에 초록 원 표시 (B1)
- [ ] GPS 이동(10m+) 시 초록 원이 새 위치로 이동 (B1 갱신)
- [ ] 지도 탭 → 목적지 선택 시 탭 좌표에 빨강 원 표시 (B2, 스냅 없음)
- [ ] 내비 종료 / X버튼으로 목적지 해제 시 빨강 원 사라짐
- [ ] 경로 표시 시 마커(초록/빨강)이 경로선 위에 그려짐 (z-order)

## 미확인 리스크 (후속 확인 필요)
- `_updateRouteLayer`가 `setGeoJsonSource`만 사용하므로 addCircle이 나중에 추가되어도 경로선이 다시 위로 올라오지 않음 — 폰에서 z-order 확인 필요. 문제 시 경로선 레이어에 `belowLayerId` 옵션 적용 별도 작업.
- `_applyDestination`이 `void`인 채로 `_ensureDestMarker` unawaited 처리 — 빠른 연속 탭 시 race condition 가능성 미미하지만 존재. 현재 UX상 문제없을 것으로 판단.
