# NIGHT_TASK (4번째 밤) — 가짜 거리 제거 + 내비 버그 2건 수정

> 너는 오케스트레이터다. CLAUDE.md 와 이 파일을 읽고, 절대 규칙을 지키며
> **모듈 1 → 2 → 3** 순서로 진행하라. 코딩은 flutter-coder/rust-coder,
> 검사는 code-auditor 에게 위임하라.
> **각 모듈 시작 전 체크포인트 커밋, PASS 후 커밋.** 막히면 멈추고 MORNING_REPORT.md 에 적어라.
> 사용자는 자리에 없다. 절대 범위를 넘지 마라. 추측으로 진행 금지. push 금지.

---

## 전제 (지난밤 조사로 확정된 사실 — 다시 진단하지 마라)
- 폰 연결은 복구됨(MagicDNS + cleartext). APK 빌드 성공 상태.
- `RoutingService`(lib/services/routing_service.dart)는 이미 Valhalla 실제 경로(폴리라인+거리)를
  정상 반환한다. **문제는 UI가 이 결과를 안 쓰고 가짜 값을 쓴다는 것.**
- 직전 커밋 `309c89e` 가 깨끗한 기준점. 시작 전 `git log --oneline -1` 로 확인하라.

---

## 모듈 1 — 카드 거리를 Valhalla 실제 거리로 교체 (최우선, 앱의 핵심)
**목표:** 경로 카드의 "직선거리 × 고정배수" 가짜 계산을 제거하고,
`RoutingService`가 반환하는 **실제 Valhalla 도로 거리/시간**을 카드에 표시한다.

확정된 문제 위치 (지난밤 조사):
- `lib/features/map/presentation/main_map_screen.dart:1167-1172, 1222`
  ```dart
  static const _routes = [
    _RouteInfo('시골길로\n느긋하게', 1.55, ...),  // haversine × 1.55  ← 가짜
    _RouteInfo('지방도로\n여유롭게', 1.22, ...),   // haversine × 1.22  ← 가짜
    _RouteInfo('국도로\n빠르게', 1.0, ...),        //                  ← 가짜
  ];
  ```

할 일:
1. 체크포인트 커밋.
2. `RoutingService.fetchRoutes()` 가 반환하는 3개 경로의 **실제 거리(km)·시간(분)·폴리라인**을
   카드가 직접 받아 표시하도록 연결하라.
   - 이미 `map_providers.dart`에 `allRoutes`(3카드 폴리라인)가 페치되어 있다(전제 참고).
     거리/시간도 함께 들어있는지 확인하고, 있으면 그걸 쓰고 없으면 RoutingService 반환값에 추가하라.
3. `haversine × 배수` 로직과 `_routes` 의 배수 상수(1.55/1.22/1.0)를 **삭제**하라.
4. 카드 3장이 RoutingService 의 시골길/지방도로/국도 거리·시간을 그대로 보여주게 하라.

완료 기준:
- [ ] 카드 거리 = Valhalla 실제 거리 (직선×배수 코드 완전 삭제)
- [ ] 카드의 시간(분)도 Valhalla time 으로 표시
- [ ] `flutter analyze` 0 issues
건드리지 말 것: RoutingService 내부 로직(이미 정상), 라우팅 주소, 지도 타일, 권한.

---

## 모듈 2 — 내비 화면 거리 하드코딩 제거
**목표:** 내비 화면 ETA 바의 하드코딩 `23.4km` 를 실제 경로 길이로 교체.

확정된 문제 위치:
- `lib/features/navigation/presentation/nav_screen.dart:409` → `Text('23.4km', ...)` 하드코딩
- `NavScreen` 은 `widget.routePolyline` 을 이미 파라미터로 받는다(main_map_screen.dart:302-309).
  단지 그 길이를 계산해 쓰지 않고 있을 뿐.

할 일:
1. 체크포인트 커밋.
2. `nav_screen.dart` 에서 `widget.routePolyline` 의 점들로 **Haversine 누적 거리**를 계산하는
   헬퍼를 추가하고, ETA 바에 그 값을 표시하라.
   - RoutingService 에 이미 폴리라인→거리 계산 유틸이 있으면 재사용하라(중복 구현 금지).
3. 하드코딩 `23.4km` 제거.
4. `DrivingScreen`(lib/screens/driving_screen.dart:469) 은 **구버전으로 보이며 현재 미사용**이라고
   조사됐다. **이번엔 건드리지 마라.** (확실치 않으므로 위험. 보고서에만 "정리 후보"로 남겨라.)

완료 기준:
- [ ] 내비 ETA 거리 = 실제 폴리라인 길이 (하드코딩 제거)
- [ ] 모듈 1에서 고친 카드 거리와 내비 거리가 **대략 일치**
- [ ] `flutter analyze` 0 issues
건드리지 말 것: driving_screen.dart, 경로 로직, 카드 이외 내비 UI.

---

## 모듈 3 — 내비 초기화면/현위치 버튼 버그 2건 수정 (작고 안전)
**목표:** 지난밤 조사에서 원인+수정방향까지 확정된 2건을 그대로 적용.

### 버그 A — 내비가 목적지 중심으로 뜸 (현위치여야 함)
- 위치: `lib/features/navigation/presentation/nav_screen.dart:146`
  ```dart
  initialCenter: widget.destination ?? _currentPos ?? _kInitialMapView,
  ```
- 수정: `widget.destination` 을 초기 중심에서 빼라 →
  ```dart
  initialCenter: _currentPos ?? _kInitialMapView,
  ```
  (GPS 첫 신호 오면 `_recenter(loc)` 가 자동으로 현위치 이동함 — 조사에서 확인됨)

### 버그 B — 현위치 버튼 눌러도 복귀 안 됨
- 위치: `lib/screens/driving_screen.dart:160-162`
- **그러나** driving_screen 은 미사용 의심 화면이다.
  **현재 실제 쓰이는 nav_screen.dart 는 이미 올바르게 처리**되어 있다(조사 결론, nav_screen.dart:154).
- 따라서 **버그 B는 실제로는 현재 화면에 영향 없을 가능성이 높다.**
  → driving_screen 을 고치지 말고, nav_screen 에서 현위치 버튼이 실제로 동작하는지
    코드상으로만 재확인하라. 이미 정상이면 "수정 불요"로 보고하고 넘어가라.
  → 만약 nav_screen 에도 같은 버그가 있으면, 그때만 nav_screen 에
    `&& event.source != MapEventSource.mapController` 조건을 추가하라.

완료 기준:
- [ ] 버그 A 수정됨 (initialCenter 에서 destination 제거)
- [ ] 버그 B: nav_screen 정상 확인(수정 불요) 또는 nav_screen 에만 최소 수정
- [ ] `flutter analyze` 0 issues
건드리지 말 것: driving_screen.dart, 모듈 1·2에서 고친 거리 로직.

---

## 빌드 검증 (모듈 3까지 끝나면)
1. `flutter analyze` → 0 issues
2. `flutter build apk --debug` → 성공 확인 (APK: build/app/outputs/flutter-apk/app-debug.apk)
3. 성공 시 커밋: `feat: real valhalla distances in cards + nav, fix nav initial center`

---

## 멈춤/한도 대응
- **모듈 1이 가장 중요하다**(가짜 거리 제거 = 앱의 핵심). 무조건 끝내라.
- 한도로 멈출 것 같으면 반드시 "깨끗한 커밋 직후"에 멈춰라.
- 같은 문제 3회 실패 → 건너뛰고 보고서에 원인 상세히 적고 멈춰라.
- 모듈 1에서 RoutingService 반환 구조가 예상과 다르면(거리/시간 필드 없음 등),
  **임의로 RoutingService 를 뜯어고치지 말고** 무엇이 다른지 보고서에 적고 모듈 2로 넘어가라.

## 아침 보고서 (MORNING_REPORT.md) — 한국어, 비개발자용
1. 완료 모듈 + 각 커밋 해시.
2. 모듈별 완료 기준 체크 결과.
3. 막힌 것/건너뛴 것 + 이유.
4. **사용자가 폰에서 확인할 것**:
   - 목적지 찍고 카드 3개 거리가 **이전(가짜)과 달라졌는지**, 서로 다른 실제 거리인지.
   - 카드 거리와 내비 화면 거리가 비슷하게 맞는지.
   - 내비 켜면 **현위치 중심**으로 뜨는지(목적지 아님).
5. driving_screen.dart 정리 건 — 다음 밤 후보로 남김.
6. 토큰/한도 메모.
7. 전문용어 풀어서.

## 시작 지시 (오케스트레이터 첫 프롬프트)
> CLAUDE.md 와 이 NIGHT_TASK.md 를 읽어라. 너는 오케스트레이터다.
> 모듈 1 → 2 → 3 순서로 절대 규칙을 지키며 진행하라.
> 모듈 1(가짜 거리 제거)을 최우선으로 반드시 끝내라.
> driving_screen.dart 는 미사용 의심이니 건드리지 마라.
> 각 모듈: 체크포인트 커밋 → 위임 → 검증 → 감사 → PASS면 커밋 → 다음.
> 멈출 땐 깨끗한 커밋 직후에 멈추고 MORNING_REPORT.md 를 써라.
> 범위 밖은 건드리지 말고, push 는 하지 마라.
