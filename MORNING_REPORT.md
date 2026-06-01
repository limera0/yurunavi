# MORNING_REPORT — 4번째 밤 (2026-06-01)

오케스트레이터: Claude Sonnet 4.6

---

## 1. 완료 모듈 + 커밋 해시

| 모듈 | 내용 | 커밋 |
|------|------|------|
| 체크포인트 | 모듈 1 시작 전 | `10653dc` |
| 1 + 2 + 3 | 실제 Valhalla 거리 + 내비 초기화면 버그 수정 | `e612036` |

---

## 2. 완료 기준 체크 (모듈별)

### 모듈 1 — 카드 거리를 Valhalla 실제 거리로 교체
- [x] 카드 거리 = Valhalla 실제 도로 거리 (`haversine × 배수` 코드 완전 삭제)
- [x] 카드 시간(분)도 Valhalla 실제 time으로 표시
- [x] `1.55 / 1.22 / 1.0` 배수 상수 완전 삭제됨
- [x] 경로 미로드 시 `---` 플레이스홀더 표시 (크래시 없음)
- [x] `flutter analyze` 0 issues

변경된 파일:
- `lib/services/routing_service.dart`: `RouteResult` 클래스 추가, `fetchRoutes()` 반환 타입을 `List<RouteResult>`로 변경, Valhalla 응답에서 `time`(초) 추출 후 분으로 변환
- `lib/features/map/providers/map_providers.dart`: `allRouteMeta: List<({double km, int mins})>` 필드 추가, `setAllRouteMeta()` 메서드 추가
- `lib/features/map/presentation/main_map_screen.dart`: `_fetchAndStoreAllRoutes()` / `_onRouteCardSelect()` 모두 실제 거리·시간 저장, `_CourseSheet` 에서 `haversine × 배수` 로직 제거 및 `routeMeta` 파라미터로 교체

### 모듈 2 — 내비 화면 거리 하드코딩 제거
- [x] `nav_screen.dart`의 `23.4km` 하드코딩 제거됨
- [x] `_polylineKm()` Haversine 헬퍼 추가, 폴리라인 실제 길이 계산
- [x] 폴리라인 비어 있을 때 `--` 표시 (크래시 없음)
- [x] `flutter analyze` 0 issues

### 모듈 3 — 내비 초기화면 / 현위치 버튼 버그 2건
- [x] 버그 A 수정: `initialCenter`에서 `widget.destination` 제거 → `_currentPos ?? _kInitialMapView`
- [x] 버그 B 확인: `nav_screen.dart:174`의 `onMapEvent` 핸들러에 이미 `event.source != MapEventSource.mapController` 체크 존재 → 수정 불요, 정상 동작 확인
- [x] `flutter analyze` 0 issues

### 빌드 검증
- [x] `flutter analyze` → No issues found
- [x] `flutter build apk --debug` → **빌드 성공**
  - APK: `build/app/outputs/flutter-apk/app-debug.apk`

---

## 3. 막힌 것 / 건너뛴 것

없음. 모듈 1·2·3 모두 정상 완료.

`driving_screen.dart`는 NIGHT_TASK 지시에 따라 전혀 건드리지 않음.

---

## 4. 사용자가 폰에서 확인할 것

폰에 Tailscale 켠 상태로 APK 설치 후:

1. **카드 거리가 달라졌는지 확인**
   - 목적지를 찍으면 하단에 시골길·지방도로·국도 카드 3장이 나옵니다.
   - 이전에는 카드 거리가 직선거리에 고정 배수를 곱한 가짜 숫자였습니다.
   - 이제는 Valhalla 서버가 실제 도로를 따라 계산한 거리와 시간이 표시됩니다.
   - 3장의 거리가 이전과 다르고, 서로 다른 실제 거리(시골길이 제일 길고 국도가 제일 짧음)인지 확인해주세요.

2. **카드 거리 ≈ 내비 거리인지 확인**
   - "Start your Engine" 슬라이더를 밀어 내비 화면 진입 후 하단 ETA 바의 거리를 확인합니다.
   - 이제 카드에서 선택한 경로의 실제 폴리라인 길이가 표시됩니다.
   - 카드 거리와 내비 거리가 대략 일치해야 합니다(완전 동일하지 않을 수 있지만 크게 차이 나면 안 됩니다).

3. **내비 켤 때 현위치 중심으로 뜨는지 확인**
   - 이전에는 내비 화면이 열릴 때 목적지가 화면 중앙으로 왔습니다.
   - 이제는 내 현재 위치(GPS) 중심으로 지도가 뜹니다.
   - GPS 신호를 받자마자 자동으로 내 위치로 이동합니다.

---

## 5. driving_screen.dart 정리 건

`lib/screens/driving_screen.dart`는 구버전 내비 화면으로 보입니다. 현재 `_startNavigation()`은 `NavScreen`(`lib/features/navigation/presentation/nav_screen.dart`)을 사용하며 `DrivingScreen`은 호출하지 않습니다.

이 파일은 **다음 밤 정리 후보**입니다. 삭제 전 `main.dart` 등 다른 파일에서 import하는지 최종 확인 필요.

---

## 6. 토큰/한도 메모

모듈 1·2·3 + 빌드 검증 모두 단일 세션에서 완료됨. 한도 초과 없음.

---

## 7. 용어 설명

- **Valhalla 실제 도로 거리**: 서버가 도로 지도를 따라 실제 경로를 계산한 거리. 이전의 "직선거리 × 배수" 와 달리 실제로 달려야 하는 거리입니다.
- **Haversine**: 좌표 두 개 사이의 직선 거리를 구하는 공식. 내비 화면에서 경로 점들 사이의 거리를 모두 더해 전체 경로 길이를 계산하는 데 사용합니다.
- **폴리라인**: 지도에 그려지는 경로 선. 수백~수천 개의 좌표 점들을 연결한 것입니다.
- **ETA 바**: 내비 화면 하단의 "도착 예정 시각·거리·시간" 표시 영역.
