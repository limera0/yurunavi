# REPORT: nav_screen ETA 실계산

커밋: fea7f99  
날짜: 2026-06-09  
브랜치: feat/maplibre-migration

---

## 0단계 사전검증 결과

### Valhalla time 파싱 현황 (routing_service.dart)
- `summary.time` (초)는 추출하지 않음
- 대신 `RouteResult.durationMin` 에 **실효속도 기반 재계산값** 보존
  - 근거 주석: "Valhalla time은 ~57-88km/h 낙관치이므로 거리 기반으로 재계산"
  - `_courseSpeeds` 배열로 코스별 km/h 지정 → `(km / speed * 60).round()`
- `ManeuverStep`에는 시간 필드 없음 (`distanceKm`만 존재)

### nav_screen으로의 데이터 흐름
- `main_map_screen.dart`에서 NavScreen 호출 시 `maneuvers`만 전달, `durationMin` 미전달
- 하드코딩 위치: nav_screen.dart line 779 (`'14:32 도착'`), line 788 (`'38분'`)
- `_reroute()`: 새 경로의 `points`만 setState, `durationMin` 미갱신

### 스코프 결정
**2파일** 수정 (routing_service.dart 모델 변경 불필요):
- `lib/features/navigation/presentation/nav_screen.dart`
- `lib/features/map/presentation/main_map_screen.dart`

---

## 구현 내용

### nav_screen.dart (+32줄)

1. `NavScreen` 생성자에 `final int durationMin` 파라미터 추가 (기본값 0)
2. State에 `int _durationMin = 0` 뮤터블 필드 추가
3. `initState()`에서 `_durationMin = widget.durationMin` 초기화
4. `_reroute()` 성공 시 `_durationMin = routes[selIdx].durationMin` 함께 갱신
5. ETA 헬퍼 2개 추가:
   - `_etaText(int min)` → `"HH:mm 도착"` (DateTime.now() + Duration(minutes))
   - `_remainingText(int min)` → `"X시간 Y분"` / `"Y분"` / `"--"` (0이면)
6. 하드코딩 교체:
   - `'14:32 도착'` → `_etaText(_durationMin)`
   - `'38분'` → `_remainingText(_durationMin)`
7. TODO 주석: Valhalla time 낙관적 추정치, 실효속도 보정 TODO 명시

### main_map_screen.dart (+4줄)

`_startNavigation()` 내 NavScreen 생성 시점에:
```dart
final selIdx = ref.read(mapInteractionProvider).selectedRouteIdx
    .clamp(0, _fetchedRoutes.length - 1);
final durationMin = selIdx < _fetchedRoutes.length
    ? _fetchedRoutes[selIdx].durationMin
    : 0;
// NavScreen(... durationMin: durationMin)
```

---

## 검증 결과

```
flutter analyze (2 files)
→ No issues found!

flutter build apk --debug
→ ✓ Built build/app/outputs/flutter-apk/app-debug.apk  (11.3s)
```

---

## 폰 실측 가이드 (마스터 직접)

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

확인 항목:
1. 경로 탐색 후 내비 진입 → 하단 바에 실제 도착 시각 / 남은 시간 표시 확인
2. 경로 이탈 → 재탐색 후 ETA가 새 경로 시간으로 갱신되는지 확인
3. 1시간 이상 경로: "X시간 Y분" 형식 확인
4. `durationMin = 0`인 경우(경로 없이 진입): "--" 표시 확인
