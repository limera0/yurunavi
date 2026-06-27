# REPORT_guidance_p1.md — Layer 1: shape_index 단조 진행추적 구현 완료

작성일: 2026-06-27  
브랜치: feat/layer1-progress  
커밋: 3개 (C1 8a49122 / C2 fb28558 / C3 0bdcf7d)

---

## 작업 요약

SPEC_guidance_p1.md §1~§4 전체 구현 완료.

### C1 — feat(routing): parse maneuver shape indices with leg offset
**파일**: `lib/services/routing_service.dart`

- `ManeuverStep` 에 `beginShapeIdx`, `endShapeIdx` (전역 인덱스, default=0) 추가.
  기존 생성자 호출 모두 backward-compatible (named optional, default=0).
- `_collectManeuvers(List legs)` static 헬퍼 신설:
  leg별 `begin/end_shape_index` → leg 누적 오프셋 적용 → 전역 인덱스 변환.
  오프셋 누적은 `_extractPoints`의 `skip(1)` 병합과 정확히 대응 (leg당 pts.length-1).
- 메인 파싱(:317~326) + balanced 폴백 파싱(:383~392) 양쪽을 `_collectManeuvers` 로 교체.
- **오프셋 정합 검증 로그**: 각 파싱 후 `lastEnd=${maneuvers.last.endShapeIdx} pts=${pts.length}` dev.log 출력.
  라우트 탐색 시 실측으로 `lastEnd == pts.length-1` 확인 필요 (dev.log로만, assert 아님).

### C2 — feat(nav): add routeProgressProvider monotonic snap tracker
**파일**: `lib/features/navigation/providers/route_progress_provider.dart` (신설)

- SPEC §2 코드 verbatim 구현.
- `setRoute(points, maneuvers, destination)` — 진입/재탐색 시 주입, 사전계산 O(n).
- `_advance(LatLng pos)` — [snapIdx, +50seg] 창만 탐색(단조), 세그먼트 투영 평면근사.
- `offRoute` (>50m), `arrived` (<25m) 내장.
- **Warning 2건**: `_dest`(미사용 스텁), `_kBackToleranceM`(미사용 튜닝 상수) — SPEC verbatim,
  에러 아님. Layer 3 bearing 구현 시 활용 예정.

### C3 — refactor(nav): consume routeProgress, drop split distance tracking
**파일**: `lib/features/navigation/presentation/nav_screen.dart`

**삭제**:
- `_traveledDistM` (전체 순회 O(n) → 폐기)
- `_updateStepByDistance` (거리 기반 step 자동진행·TTS → 폐기)
- `_computeStepEndDistances` + `_stepEndDistM`
- `_checkArrival` (직선거리 판정 → progress.arrived로 대체)
- `_checkOffRoute` (직선거리 탐색 → progress.offRoute로 대체)
- `_segmentDistM`, `_distanceM`
- `_kOffRouteM`, `_kArrivalRadiusM`
- `_pre500`, `_pre300`, `_pre50`

**추가**:
- `_progressSub` — `routeProgressProvider` 별도 listen (navState 핸들러와 분리).
  navState 핸들러는 카메라/속도만 처리.
- `_applyRouteGuidance` → `setRoute` 주입 (진입·재탐색 양쪽).
- `_handleVoice(RouteProgress)` — 500/300/50m 임계 TTS 각 1회 (step 전환 시 리셋).
- `_triggerReroute()` — `offRoute` 시 3초 디바운스 후 `_reroute()` 호출.
- `_voiceStepIdx`, `_said500/300/50` 상태 필드.

---

## analyze 결과

```
전체 4 issues:
  warning×2 — route_progress_provider.dart (_dest, _kBackToleranceM 미사용 스텁)
  info×2    — settings_screen.dart (Radio deprecated, C1 이전부터 존재)
  error×0
새 에러 0 ✓
```

---

## 미완료·주의사항

1. **오프셋 정합 실측 미완**: `lastEnd==pts.length-1` dev.log 확인은 실제 Valhalla 응답이 있어야 함.
   폰 라이딩 또는 에뮬레이터 경로탐색으로 `RoutingService` 로그 확인 필요.

2. **폰 라이딩 검증 미완 (T3)**: SPEC §5 라이딩 회귀 1~7 모두 미검증.
   main 머지 금지 조건 유지.

3. **경고 2건 (SPEC verbatim 스텁)**:
   - `_dest`: `setRoute`로 저장하나 현재 도착 판정에 미사용 (거리는 `_totalM` 기반).
     Layer 3 bearing/재탐색 고도화 시 활용.
   - `_kBackToleranceM`: 선언만 있고 코드에 적용 안 됨 (뒤로 고정 클램프만 사용).
     라이딩 튜닝 시 soft clamp로 전환 가능.

4. **스모크 테스트 미실행**: 빌드 환경 headless라 APK 설치 확인 불가.
   `flutter build apk --debug` 성공 여부는 빌드 실행 필요.

---

## 다음 단계 (SPEC §6)

- 폰 라이딩으로 T3 검증 (카드 단조·step 전환·TTS 거리 정확도·도착·이탈).
- window=50 / offRoute=50m / arrival=25m 튜닝.
- Layer 2: verbal_*/multi_cue 파싱 → `_labelForType` 하드코딩 대체.
- Layer 3: bearing_after + headingDeg 재탐색.
