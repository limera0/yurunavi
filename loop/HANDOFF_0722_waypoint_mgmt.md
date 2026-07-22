# HANDOFF — 17번 경유지 관리 UI (2026-07-22)

이 파일을 읽는 Claude는 아래 계획을 순서대로 실행한다.
**코딩 전에 반드시 이 파일 전체를 읽어라.**

---

## 배경 및 목적

투어링 라이더는 목적지보다 달리는 경로 자체가 중요하다.
경유지를 자유롭게 추가·삭제·순서변경하고, 출발지도 현위치가 아닌
임의 장소로 설정할 수 있어야 한다.

참조 UI: 네이버지도 경유지 편집 화면 (드래그핸들 + 즉시 경로 반영)

**브랜치**: `verify/ride-0711` (현재 브랜치 그대로 작업)

---

## 정찰 결과 (2026-07-22 확인)

### 이미 구현된 것 (건드리지 않아도 됨)
- `MapInteractionState.waypoints: List<LatLng>` + Valhalla 전달 완성
- `addWaypoint()` / `removeWaypoint()` in `map_providers.dart`
- `_syncWaypointMarkers()` — 노란 포인터(`pointer_yellow`) 지도 렌더링
- `RoutingService.fetchRoutes(waypoints:)` — locations 배열 전달 완성
- 내비 경유지 통과 판정 (`nav_screen.dart`, 지오펜스 40m)

### 없는 것 (이번 과제 대상)
- 포인터 위 숫자(1, 2, 3) 표시
- `reorderStop()` notifier 메서드
- `RouteStop` / `stops` 통합 리스트 구조
- 경유지 관리 시트 UI
- 검색창에서 경유지/출발지 추가

### 핵심 파일 위치
| 파일 | 역할 |
|------|------|
| `lib/features/map/providers/map_providers.dart` | `MapInteractionState`, `MapInteractionNotifier` |
| `lib/features/map/presentation/main_map_screen.dart` | `_syncWaypointMarkers()` L777, `_TapAction` L43, `_fetchAndStoreAllRoutes()` L1188 |
| `lib/services/routing_service.dart` | `fetchRoutes(waypoints:)` L257 |
| `lib/features/navigation/presentation/nav_screen.dart` | `widget.waypoints` 전달, 통과 판정 |

---

## 아키텍처 변경: stops 통합

### 현재
```
_origin (local GPS, main_map_screen 로컬 변수)
state.destination: LatLng?
state.waypoints: List<LatLng>
state.waypointNames: List<String?>
```

### 변경 후
```dart
// lib/features/map/models/route_stop.dart (신규)
class RouteStop {
  final LatLng latLng;
  final String? name;
  final bool isCurrentLocation; // true → GPS 추적으로 자동 갱신
  const RouteStop({required this.latLng, this.name, this.isCurrentLocation = false});
  RouteStop copyWith({LatLng? latLng, String? name, bool? isCurrentLocation}) => ...
}

// MapInteractionState 필드
final List<RouteStop> stops; // [출발지, 경유지..., 도착지] 통합

// 편의 getter (기존 호출부 호환 유지)
LatLng? get origin      => stops.isEmpty ? null : stops.first.latLng;
LatLng? get destination => stops.length < 2 ? null : stops.last.latLng;
List<LatLng> get waypoints =>
    stops.length < 3 ? [] : stops.sublist(1, stops.length - 1).map((s) => s.latLng).toList();
List<String?> get waypointNames =>
    stops.length < 3 ? [] : stops.sublist(1, stops.length - 1).map((s) => s.name).toList();
```

**기존 `state.destination`, `state.waypoints`, `state.waypointNames` getter를 유지**하므로
라우팅 서비스 / 내비 화면 호출부 수정 최소화.

---

## Phase별 세부 명세

### Phase 0 — RouteStop 모델 + stops 필드 마이그레이션

**신규 파일**: `lib/features/map/models/route_stop.dart`
- `RouteStop` 클래스 (위 설계 그대로)

**`map_providers.dart` 수정**:
1. `MapInteractionState`에 `stops: List<RouteStop>` 추가
2. 기존 `destination`, `waypoints`, `waypointNames` 필드를 getter로 전환
3. `copyWith`에 `stops` 반영
4. `MapInteractionNotifier` 메서드 업데이트:
   - `setDestination(LatLng dest, {String? name})` → `stops`의 마지막 항목 설정/교체
   - `addWaypoint(LatLng wp, {String? name})` → `stops`의 마지막-1 위치에 삽입
   - `removeWaypoint(int idx)` → `stops[idx+1]` 제거 (출발지 오프셋 고려)
   - `reorderStop(int oldIdx, int newIdx)` **신규** — stops 전체 재배치

**`main_map_screen.dart` 수정**:
- GPS 확보 시 `_origin` 로컬 변수 대신 `stops[0] = RouteStop(isCurrentLocation: true)` 설정
- GPS 업데이트 시 `stops[0].isCurrentLocation == true`면 `stops[0].latLng` 갱신
- `_fetchAndStoreAllRoutes()`에서 `origin` / `destination` / `waypoints` getter 그대로 사용

**완료 기준**: `flutter analyze` PASS, 기존 경로 계산 동작 동일

---

### Phase 1 — 포인터 숫자 표시

**`main_map_screen.dart` `_syncWaypointMarkers()` 수정**:

```dart
// 현재: textField: name, textOffset: Offset(0, 1.4), textAnchor: 'top'
// 변경: 번호를 포인터 원 위에 표시

final s = await c.addSymbol(ml.SymbolOptions(
  geometry: _toMl(waypoints[i]),
  iconImage: _kWpIcon,
  iconSize: _kWpIconSize,
  iconAnchor: 'bottom',
  zIndex: 5,
  textField: '${i + 1}',          // 번호 표시
  textSize: 11,
  textColor: '#FFFFFF',
  textOffset: const Offset(0, -2.1), // 포인터 원 중앙으로 올림
  textAnchor: 'bottom',
  textIgnorePlacement: true,
  textAllowOverlap: true,
));
```

textOffset 값은 `pointer_yellow` 아이콘의 실제 크기에 따라 조정 필요.
기기에서 확인 후 미세 조정할 것.

**완료 기준**: 코스 선택 화면 지도에서 경유지 포인터 위에 흰색 숫자 1, 2, 3 표시

---

### Phase 2 — WaypointManagementSheet

**신규 파일**: `lib/features/map/presentation/waypoint_management_sheet.dart`

**UX 설계** (네이버지도 참조):
```
┌─────────────────────────────────────┐
│  🔵 경기 평택시 고덕동          ≡  │  ← 출발지 (isCurrentLocation이면 📍)
│  ○  양지초등학교           −   ≡  │  ← 경유지 (삭제 가능)
│  ○  아시아나CC             −   ≡  │
│  🔴 엠키친앤카페                ≡  │  ← 도착지
│  ＋  경유지 추가                    │
├─────────────────────────────────────┤
│  [ 로딩 스피너 or 경로 미니맵 ]     │
└─────────────────────────────────────┘
          [ 닫기 ]
```

**구현 요점**:
- `ReorderableListView` 사용 (Flutter 내장 드래그앤드롭)
- 드래그 drop → 즉시 `reorderStop()` 호출 → 즉시 `_fetchAndStoreAllRoutes()` → 지도 갱신
- 재계산 중: 로딩 스피너 표시, 드래그 비활성화 (`IgnorePointer`)
- 재계산 완료: 경로 미니맵 표시 (기존 경로 폴리라인 그대로)
- "취소" 버튼 없음 — 변경이 즉시 반영되므로
- 닫기 = 시트 dismiss (현재 stops 상태 유지)
- stops가 2개 미만이면 삭제 버튼 비활성화
- 출발지/도착지도 드래그 가능 (reorderStop으로 위치 자유 변경)
- "＋ 경유지 추가": 지도 탭 / 검색 두 가지 진입 가능

**시트 높이**: `DraggableScrollableSheet` (초기 60%, 최대 90%)

---

### Phase 3 — 경유지 추가 방식 확장

#### 검색창에서 경유지 추가
현재 주소검색 결과 탭 → 목적지 설정만 가능.
변경: 탭 시 선택 시트:
```
어디로 추가할까요?
[ 출발지로 설정 ]  [ 경유지로 추가 ]  [ 목적지로 설정 ]
```
- "출발지로 설정": `stops[0]` 교체 (isCurrentLocation = false)
- "경유지로 추가": stops 마지막-1 위치에 삽입
- "목적지로 설정": `stops` 마지막 교체 (기존 동작)
- `state.destination == null`이면 경유지 추가 비활성화 (목적지 먼저 설정)

#### 지도 탭 확인 시트 확장
현재: "여기로 안내" (목적지)만 있음.
변경: 목적지 설정 이후라면 "경유지로 추가" 옵션 추가.

---

### Phase 4 — 진입점 UI

**코스 선택 시트 상단**:
- 경유지 있으면: "경유지 2개 · 편집" 칩 버튼 → `WaypointManagementSheet` 표시
- 경유지 없으면: "+ 경유지 추가" 텍스트 버튼

**지도 우측 컨트롤 패널** (기존 버튼들 옆):
- 경유지 있을 때 경유지 수 뱃지 아이콘 (탭 → `WaypointManagementSheet`)

---

## 실행 순서 및 의존성

```
Phase 0 (stops 마이그레이션)  → 즉시 가능, 가장 큰 리팩터
       │
Phase 1 (포인터 숫자)          → Phase 0 완료 후 (stops getter 사용)
       │
Phase 2 (관리 시트)            → Phase 0 완료 후 (reorderStop 필요)
       │
Phase 3 (검색 경유지 추가)     → Phase 2 완료 후
       │
Phase 4 (진입점 UI)            → Phase 2 완료 후
```

---

## CLAUDE.md 프로토콜 준수 사항

- 각 Phase 시작 전 체크포인트 커밋
- 각 Phase 내 파일 수정 후 code-auditor PASS 확인
- 감사 최대 3회, FAIL 지속 시 BLOCKED 기록 후 중단
- `flutter analyze` 무조건 통과 후 커밋
- `git push` 금지 (로컬 커밋만)
- 완료 후 `loop/RELEASE_ROADMAP.md`에 17번 항목 추가

---

## 완료 기준

- Phase 0: `flutter analyze` PASS, 기존 경로 계산 동작 동일 (stops getter 호환)
- Phase 1: 코스 선택 화면에서 경유지 포인터 위에 숫자(1,2,3) 표시
- Phase 2: 드래그 drop 즉시 경로 재계산 + 지도 갱신, 출발지/도착지 포함 전체 재배치
- Phase 3: 검색 결과에서 출발지/경유지/목적지 선택 가능
- Phase 4: 코스 시트에서 경유지 관리 시트 진입 가능
