# AUDIT_architecture.md — 기초 재설계 감사 (OsmAnd/Organic Maps 정렬)

작성일: 2026-06-27
방식: 읽기 전용. yurunavi(feat/arrival-fix) 전수 grep + 레퍼런스 소스 대조.
계기: arrival 증상 추적 중, 근본은 "Cursor 보여주기식 임시코드 + 단일소스 위반 + Valhalla
데이터 폐기"임이 드러남. 땜질 중단, 레퍼런스 기준 기초 재설계.

---

## §0 레퍼런스 뼈대 (두 곳 동일)

OsmAnd `RoutingHelper` / Organic Maps `FollowedPolyline` 모두 같은 구조:
1. **단일 위치 소스**: OsmAnd `OsmAndLocationProvider.setLocation()` → `RoutingHelper.setCurrentLocation()`.
   하나의 provider가 라우터·UI 전부에 공급.
2. **전방전용 진행 포인터**: OsmAnd `route.currentRoute`(세그먼트 인덱스), OM `FollowedPolyline.m_current`
   (전방 이터레이터). `calculateCurrentRoute()`로 **전진만**. 역행은 이탈로 간주.
3. **이탈/재탐색**: `getOrthogonalDistance`(현 세그먼트 직교거리) + `checkWrongMovementDirection`
   (bearing 비교) → 잘못된 진행방향이면 재탐색. device bearing 우선.
4. **턴 정보**: 라우터가 준 구조(노드 인덱스·instruction)를 **그대로** 사용. 재구성 안 함.

핵심 교훈: 실세계 데이터는 **단일 소스 → 전방전용 매처 → 그 매처에서 모든 파생값**.
거리·턴·도착을 서로 다른 계산으로 따로 구하지 않는다.

---

## §1 감사 결과 (file:line)

### A. 단일 소스 위반 — 실세계 데이터
- 단일 `locationStreamProvider` 존재(map_providers.dart:63, `ref.keepAlive()`), nav/map은 사용
  (nav:246, main_map:194). **LOC-UNIFY 부분 완료.**
- **위반**: `lib/screens/driving_screen.dart:97` 자체 `Geolocator.getPositionStream` 별도 생성.
- 권한/init 로직 **4곳 복붙**: map_providers:64, nav:215, main_map:170, driving:89.
- 속도 `_speedKmh`는 nav_screen 내부에서 raw GPS로 별도 산출 — 위치는 통합됐으나 **진행상태
  (스냅·속도·heading)는 미통합**. 도착/카드/속도가 각자 계산 → desync 토양.

### B. 죽은/중복 코드 (반쯤 이주)
- 이중 화면트리: `lib/screens/`(구 Cursor: driving/intro/main_map/profile/route_options/settings)
  vs `lib/features/`(신: auth/map/navigation). `main_map_screen.dart` **양쪽 중복**.
- `lib/services/native_engine.dart.bak` — 백업파일을 소스관리에 커밋.
- `lib/services/route_service.dart`(2KB) vs `routing_service.dart`(17KB) 중복 서비스.

### C. 하드코딩/매직넘버 — 중앙 config 부재
- 초기뷰 좌표 **3곳 불일치**: nav:28 `LatLng(37.5665,126.9780)`(서울), main_map:35 `(36.5,127.5)`,
  driving:16 서울. ("서울 flicker" 원인 계열.)
- `route_options_screen.dart:159–160` **랜덤 좌표로 가짜 코스 생성**(`37.5665+random*0.3`).
  순수 보여주기 더미데이터.
- routing_service:91 class-factor 매직(`'2':3.0`), nav 거리 임계 산재(20/50/300/500/30/8 등 분산).

### D. Valhalla 데이터 폐기 — 이미 주는 걸 버리고 재구성
- `ManeuverStep` = `type`/`instruction`/`distanceKm`뿐(routing_service:31).
- **0건 파싱**: `begin/end_shape_index`(진행추적), `bearing_after`(heading), `street_names`(라벨),
  `verbal_*`(TTS 안내문), `lanes`(차선). grep 전부 0.
- 결과: 진행 desync(지적1·2·3·도착), type→라벨 오역 "약간 우회전"(지적5), 차선/언더패스 부재(지적6),
  TTS 자체 생성. duration도 "낙관적 추정"(nav:37 TODO).

---

## §2 6개 라이딩 지적 → 감사 매핑

| 지적 | 뿌리(§1) |
|---|---|
| 1·2·3 카드 freeze/desync + 도착미발화 | D(shape_index 폐기) + A(진행상태 미통합) |
| 4 유턴 후 재탐색 안 함 | D(bearing_after 폐기) + 이탈로직 bearing 미반영 |
| 5 거리오류 | D + A | 
| 5 라벨오역("약간 우회전") | D(verbal_*/street_names 폐기, type 매핑) |
| 6 차선/언더패스 안내 부재 | D(lanes 폐기) |

---

## §3 기초 재설계 (레퍼런스 정렬, 층위)

- **Cleanup(선행)**: 죽은 트리/.bak/중복서비스/랜덤더미 제거. 매직넘버 `lib/core/nav_config.dart`로 중앙화.
  ※ 삭제 전 main.dart 라우팅으로 **실제 마운트 화면 확인** 필수(죽은 줄 알았는데 참조 위험).
- **Layer 0 — 단일 실세계 SoT**: 위치+속도+heading을 단일 `NavigationState`(Riverpod)로 통합.
  권한/init 단일화. driving_screen 자체 스트림 제거. (OsmAnd setCurrentLocation 대응)
- **Layer 1 — RouteSession(전방전용 매처)**: shape_index 앵커 단조스냅. 진행·카드거리·도착.
  = 기존 SPEC_guidance_p1. (OsmAnd currentRoute / OM FollowedPolyline 대응)
- **Layer 2 — 턴 정보**: `verbal_*`/`street_names`/`bearing_after`/`lanes` 파싱 → 라벨·TTS·차선(지적5라벨·6).
- **Layer 3 — 재탐색**: orthogonal dist + wrong-movement-direction(bearing) (지적4, phase2/heading-fix 통합).

**권장 순서**: Cleanup → Layer 0 → Layer 1 → Layer 2 → Layer 3.
(Cleanup가 노이즈/죽은코드를 먼저 걷어내야 이후 층이 깨끗한 기반 위에 올라감.)

## §4 기존 작업 정리
- arrival-fix v1~v3·v2b: Layer 1에 흡수(도착 트리거 재작성). C2/C4·지오펜스 종료 UI는 보존.
  main 머지 보류.
- SPEC_guidance_p1: Layer 1로 유효. 단 Cleanup·Layer 0 이후 실행 권장(편집 대상이 live 코드임 확정 후).

## §5 미결 / 검증 선행
- main.dart 라우팅 RECON: lib/screens/* 중 실제 마운트되는 화면 식별(Cleanup 안전 삭제 목록 확정).
- route_service vs routing_service 호출처 grep(어느 게 live인지).
- Layer 0 통합 시 기존 LOC-UNIFY provider를 확장할지 새 NavigationState로 감쌀지 결정.
