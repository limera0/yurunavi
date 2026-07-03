# RECON_sim_harness — 합성 좌표 주입점 확보 (읽기 전용)

작성: 2026-06-29
브랜치: `feat/guidance-engine`
목적: 라이딩 없이 엔진 로직을 전수 검사하는 harness를 짜기 위해, **합성 GPS 좌표를
navState 입구에 주입하는 훅**과 progress→voice 파이프라인 실행 경로를 확정.
원칙: progress 계산(스냅/distToNextTurnM)은 **실코드 그대로** 돌리고 좌표만 가짜.
(좌표를 `_handleVoice`에 직접 주입 = progress 우회 = 동어반복 → 금지)

## ⛔ 범위·금지
- **읽기 전용.** 수정·커밋 금지. 경로·훅 보고만. `file:line` + verbatim.
- 모호하면 중단·보고.

## 조사 항목

### A. navState 좌표 입구
```bash
cd /data/projects/yurunavi
grep -rn "locationStreamProvider\|Geolocator\|Position\|onLocationChanged\|navStateProvider\|LocationSettings" lib/ | grep -vi test
```
- 실 GPS가 navState로 들어오는 **단일 입구** file:line (스트림 구독 지점).
- 그 입구가 `Position`/`LatLng` 객체를 받는지, 주입 가능한 **provider override**나 **테스트 sink**가 있는지.
- harness가 합성 `Position` 시퀀스를 흘릴 수 있는 최소 침습 지점.

### B. progress→voice 파이프라인 실행 형태
- `navState.pos` → `routeProgressProvider`(스냅/distToNextTurnM) → `_handleVoice` 호출 사슬 file:line.
- 이게 **위젯(nav_screen) 안에서만** 도는지, **provider 레벨에서 헤드리스로** 돌릴 수 있는지.
  (위젯 의존이면 harness는 Flutter widget test 형태, provider 순수면 dart 단독 실행 가능)

### C. 합성 입력 소스 (경로 polyline)
- 라우팅 응답 polyline + steps를 **파일/픽스처로 로드**할 수 있는 경로(실 Valhalla 호출 없이).
- 또는 harness가 localhost:8002에 1회 curl로 실경로 받아 좌표열 생성하는 게 현실적인지.

### D. 기존 테스트 인프라
```bash
ls -la test/ 2>/dev/null; cat pubspec.yaml | grep -A5 dev_dependencies
```
- `flutter_test`/`mocktail` 등 있는지, 기존 테스트 패턴(provider override 방식) 참고용 1개.

## FINDINGS (Claude Code가 채움)

- A navState 좌표 입구 + 주입 훅:
  - 단일 입구: `lib/features/map/providers/map_providers.dart:64`
    `final locationStreamProvider = StreamProvider<Position>((ref) async* { yield* Geolocator.getPositionStream(...); });`
  - NavStateNotifier.build()에서 `ref.listen<AsyncValue<Position>>(locationStreamProvider, (_, next) { next.whenData(_onFix); })` 으로 구독
    (`lib/features/navigation/providers/nav_state_provider.dart:62`)
  - `_onFix(Position pos)` (`nav_state_provider.dart:100`)가 Position을 받아 state 갱신
  - 주입 훅: `locationStreamProvider`는 `StreamProvider`이므로
    `ProviderContainer(overrides: [locationStreamProvider.overrideWith((ref) => Stream.fromIterable([syntheticPosition, ...]))])`
    또는 widget test의 `ProviderScope(overrides: [...])` 로 합성 `Position` 시퀀스를 교체 주입 가능.
    기존 코드에 별도의 테스트용 sink/interface는 없음.

- B progress→voice 실행 형태 (위젯 의존? provider 순수?):
  - 체인: `locationStreamProvider` → `navStateProvider._onFix()` → `routeProgressProvider._advance()` (`route_progress_provider.dart:55-57`) → `RouteProgress` state emit
  - 이 구간(locationStream → RouteProgress)은 **provider 순수** — 위젯 없이 `ProviderContainer`만으로 headless 실행 가능.
  - 그러나 `_handleVoice(RouteProgress prog)` (`nav_screen.dart:237`)는 `_NavScreenState`의 private 메서드이며,
    `_vps` (VoicePackService), `_profile` (GuidanceProfile), `_steps` (List<_TurnStep>), `_pendingPoints`, `_voiceStepIdx` 등
    위젯 State 필드에 직접 의존.
  - `routeProgressProvider` → `_handleVoice` 연결 역시 위젯 내부 `ref.listenManual` (`nav_screen.dart:211`)로만 이루어짐.
  - **결론: voice 발화 판단까지 검사하려면 위젯 의존. RouteProgress 계산만 검사한다면 provider 순수 가능.**

- C polyline 픽스처/curl 로드 경로:
  - Valhalla 호출 없이 픽스처 구성 방법:
    1. `RoutingService._decodePolyline6(String shape)` (`routing_service.dart:442`) 가 static private이므로 직접 접근 불가.
       대신 `List<LatLng>`와 `List<ManeuverStep>` 를 하드코딩/JSON파일로 직접 구성하여
       `ref.read(routeProgressProvider.notifier).setRoute(points: ..., maneuvers: ..., destination: ...)` (`route_progress_provider.dart:64`) 로 주입 가능.
    2. 혹은 localhost:8002 Valhalla에 1회 curl로 실경로를 받아 JSON을 `assets/test_fixtures/` 에 저장 후 재사용하는 방식도 현실적.
       단, `RoutingService.fetchRoutes()` 는 static + HTTP 외존이므로 fixture JSON을 직접 파싱하는 별도 유틸이 필요.
  - **최소 침습 경로**: `List<LatLng>` + `List<ManeuverStep>` 리터럴을 테스트 파일에 하드코딩 → `setRoute()` 직접 호출.

- D 테스트 인프라 (flutter_test/override 패턴):
  - pubspec.yaml dev_dependencies: `flutter_test: sdk: flutter`, `flutter_lints: ^6.0.0` — mocktail/riverpod_test 없음.
  - 기존 테스트 2개:
    - `test/widget_test.dart`: placeholder `testWidgets('placeholder test', ...)` — 실질 내용 없음.
    - `test/features/map/saved_route_type_safety_test.dart`: plain `test()` 사용. Riverpod ProviderContainer/override 패턴 없음. 순수 Dart 모델 단위 테스트.
  - **provider override 패턴의 기존 사례 없음** — 신규 작성 필요.

- **harness 형태 판정**: **Flutter widget test** 형태 필요.
  - 근거:
    - `_handleVoice` (`nav_screen.dart:237`) — voice 발화 판단 로직 전체가 `_NavScreenState` 안에 있음.
    - `routeProgressProvider` → `_handleVoice` 연결이 위젯 내부 `ref.listenManual` (`nav_screen.dart:211`)로만 이루어짐.
    - TTS 발화(`_vps?.speak(key, ...)`) 검사까지 목표로 하면 위젯 레벨 실행 필수.
  - provider 단독으로 가능한 범위: `locationStreamProvider` override → `RouteProgress` 값 검증만. voice 트리거 검사 불가.
  - harness 구현 최소 형태: `ProviderScope(overrides: [locationStreamProvider.overrideWith(...)])` + `pumpWidget(NavScreen(...))` + `VoicePackService`/`FlutterTts` mock 주입.

- (harness 구현 금지 — SPEC에서)
