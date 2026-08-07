GOAL: 터널 구간에서 GPS 신호가 끊겨도 직전 1분 평균속도×1.05로 경로 shape를 따라 위치를 시간적분 전진시켜, 안내 타이밍과 재탐색 판정이 GPS 공백 동안에도 안정적으로 유지되게 한다.

- 작성 2026-08-07 · 근거: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S7 (368~374행)
- 이 항목은 원인 조사가 아니라 **신규 기능 설계** — 마스터가 알고리즘 골자(1분 평균속도×1.05)를
  이미 제시했다. 아래는 그걸 현재 아키텍처에 꽂아 넣는 구체 설계.
- ⚠️ **S5(정차 모드)가 건드린 것과 같은 파일(`nav_screen.dart`의 `_triggerReroute()` 게이트,
  `nav_state_provider.dart`)을 다시 건드린다.** S5가 이미 커밋(`fd667f1`)돼 있는 최신 HEAD
  기준으로 작업할 것 — S5의 `isStationary` 게이트 옆에 이번 게이트를 추가하는 형태.

## 현재 코드 구조 (2026-08-07 확인)

- `lib/features/navigation/providers/nav_state_provider.dart` — `NavStateNotifier`.
  `_kStaleMs = 8000`(8초) — `_tickSpeed()`가 마지막 fix로부터 8초 넘게 지나면 `_speedKmh`를
  0으로 강제하는 **이미 존재하는 "GPS 상실" 판정 기준선**. 단, 이건 속도 표시만 죽이고
  **`_pos`는 건드리지 않는다** — 지금은 GPS가 끊기면 (터널이든 뭐든) 위치가 그냥 마지막 fix에
  얼어붙는다. 이번 작업이 정확히 이 얼어붙음을 터널 한정으로 개선한다.
- `lib/features/navigation/providers/route_progress_provider.dart` — `RouteProgressNotifier`.
  `_pts`/`_segLenM`/`_cumFromStartM`/`_totalM`(경로 shape + 누적거리, `setRoute()`에서 사전계산)와
  `_zones`(`List<StructureZone>`, tunnel 포함), `_snapIdx`/`_traveledM`(현재 진행 상태)를
  이미 갖고 있다 — **경로 shape·구조물 zone·진행거리를 다 아는 유일한 provider**라 dead
  reckoning은 여기 붙이는 게 맞다(`NavStateNotifier`는 경로를 모르는 순수 GPS 계층이라 여기
  붙이면 관심사 경계가 무너진다).
  - `ref.listen<NavigationState?>(navStateProvider, (_, next) { ... _advance(p, heading) })`
    (`:119-122`)가 매 GPS fix(또는 재-emit)마다 `_advance()`를 호출.
  - `_advance()`(`:243~`)는 `[_snapIdx, _snapIdx+_kSnapWindow]` 범위에서만 최근접 세그먼트를
    찾는 **단조 전진** 스냅이다 — `_snapIdx`는 절대 뒤로 안 간다. 이 제약이 아래 §5 리스크의
    원인.
  - `_cumFromStartM[i]` → `_pts[i]` 방향의 "누적거리→좌표" **역변환 헬퍼가 아직 없다**
    (지금까지는 좌표→누적거리 방향만 필요했음). 신규 작성 필요.

## 작업 항목

### 1. `NavigationState`에 `stale` 필드 추가

- `nav_state_provider.dart`의 `NavigationState`에 `final bool stale;` 추가.
  `_tickSpeed()`가 `sinceFix > _kStaleMs`(기존 8초 상수, 새로 만들지 말고 재사용)일 때 `true`.
  이 필드 하나로 "GPS 상실"의 단일 기준선을 앱 전체가 공유한다(RouteProgressNotifier가
  독자적으로 staleness를 다시 계산하지 않게).
  ⚠️ `NavigationState`는 파일 상단 주석에 **"copyWith 금지, 매번 전체 필드 명시 생성"**
  이라고 못박혀 있다 — 새 필드 추가 시 `state = NavigationState(...)`로 생성하는 모든 자리
  (`_onFix`, `_tickSpeed`, `_emitState`, 초기 seed 등)에 `stale:` 인자를 빠짐없이 채울 것.

### 2. `RouteProgressNotifier`에 1분 속도 이력 버퍼

- 실측 fix(= `!next.stale`)에서만 `(DateTime, speedKmh)`를 버퍼에 쌓고 60초 넘은 항목은 버림.
  dead reckoning 중 스스로 만든 합성 tick은 이 버퍼에 넣지 않는다(자기 추정치로 자기 평균을
  오염시키지 않게).
- 평균 계산은 단순 산술평균으로 충분(체크리스트가 정밀한 가중 평균을 요구하지 않음).

### 3. 터널 zone 판정 + dead reckoning 진입/유지/종료

- 진입 조건: `next.stale == true` **그리고** 현재 `_snapIdx`(또는 직전 실측 스냅 위치)가
  `_zones`의 `StructureType.tunnel` 항목 중 하나의 `[beginShapeIdx, endShapeIdx]` 범위 안.
  (다리/고가/지하차도는 이번 스코프 아님 — 체크리스트가 터널로 명시 한정)
- 진입 시 `Timer.periodic`(예: 500ms 간격 — `NavStateNotifier`의 200ms 틱보다는 성기게,
  부드러움과 배터리의 절충) 시작:
  - `avgSpeedMps = (§2 버퍼 평균 speedKmh) / 3.6 * 1.05`
  - `_traveledM = min(_traveledM + avgSpeedMps * intervalSec, tunnelZone의 endShapeIdx에
    해당하는 _cumFromStartM 값)` — **터널 끝을 넘어서까지 계속 추정하지 않는다.** 끝에
    도달하면 그 자리에서 멈춘 채(`_traveledM` 고정) 실측 fix를 기다린다(더 못 미룰 근거가
    없는 억지 추정보다 "모른다"가 낫다는 원칙, memory `feedback_accurate_maneuver_wording`과
    같은 결의 판단).
  - `_snapIdx`도 이 추정 누적거리에 맞는 세그먼트 인덱스로 함께 전진(단, `_advance()`의
    실측 스냅 로직과는 별도 경로 — 아래 §4 참고).
  - 매 tick마다 `_structureFieldsFor`/`_curveFieldsFor` 등 **기존 파생 계산 헬퍼를 그대로
    재사용**해 `RouteProgress`를 재계산·emit(새 로직을 따로 만들지 말 것 — `setRoute`/
    `setStructureZones`가 이미 이 헬�들를 쓰는 패턴을 그대로 따른다).
- 종료 조건 A: 실측 fix 도착(`!next.stale`) → 타이머 취소, 이후 `_advance(realPos, heading)`가
  정상적으로 실측 위치로 이어받는다.
- 종료 조건 B: 추정 누적거리가 터널 끝에 도달 → 타이머는 유지하되(다음 실측 fix를 계속
  기다리는 상태) 더 이상 전진하지 않고 대기.

### 4. 누적거리 → 좌표 역변환 헬퍼 신설

- `LatLng _pointAtCumulativeM(double targetM)` — `_cumFromStartM`에서 `targetM`을 감싸는
  세그먼트 `i`를 찾아(이분탐색 또는 순차탐색, 리스트가 경로당 한 번만 순회되면 되므로 성능
  민감 아님) `_pts[i]`~`_pts[i+1]` 사이를 `(targetM - _cumFromStartM[i]) / _segLenM[i]`
  비율로 선형보간.

### 5. `RouteProgress`에 상태 노출 + nav_screen.dart 배선

- `RouteProgress`에 `final bool deadReckoning;`과 `final LatLng? estimatedPos;`(dead
  reckoning 중이 아니면 `null`) 추가. 다른 필드처럼 `RouteProgress`를 생성하는 모든 자리
  (`setRoute`, `setStructureZones`, `_advance`, 신규 dead-reckoning tick)에 값 채울 것.
- `nav_screen.dart`의 `_triggerReroute()`(S5가 이미 `if (ref.read(isStationaryProvider))
  return;`를 넣어둔 그 자리) — 바로 옆에 `if (ref.read(routeProgressProvider)?.deadReckoning
  == true) return;` 추가. **체크리스트 "추측항법 중 재탐색 금지 가드"의 정확한 위치.**
- (선택, 하되 필수는 아님) `estimatedPos`가 있으면 카메라 추종/위치 마커가 실측 `pos` 대신
  이 값을 쓰게 하면 터널 안에서도 라이더가 자기 위치가 계속 전진하는 걸 볼 수 있다 — 마스터
  표현("위치... 전진")이 화면에 보이는 걸 염두에 둔 것으로 해석해 **포함을 권장**하지만,
  배선이 복잡해지면(카메라 로직이 `NavigationState.pos` 기반이라 `RouteProgress` 쪽 값을
  섞어 쓰려면 우선순위 처리 필요) 리포트에 트레이드오프를 남기고 스킵 가능 — 코더 판단.

## 알려진 리스크 (감사 시 반드시 확인)

- **`_snapIdx` 단조 전진 제약과 dead reckoning 오차의 충돌.** ×1.05로 일부러 넉넉하게
  추정하므로, 실제보다 빨리 갔다고 착각하는 쪽으로 치우친다. 터널을 빠져나와 실측 fix가
  돌아왔을 때 그 실측 위치가 dead reckoning이 밀어둔 `_snapIdx`보다 **뒤쳐진 지점**일 수
  있다. `_advance()`는 `[_snapIdx, _snapIdx+50]` 앞쪽만 훑으므로 이 경우 최근접 세그먼트를
  못 찾아 `offRoute` 오탐이나 이상한 `distToNextTurnM`이 나올 수 있다. dead reckoning
  세션 직후 첫 실측 fix에 한해 스냅 탐색 창을 뒤쪽으로도 살짝 열어주는 등 완화책을 구현하고,
  왜 그렇게 했는지(혹은 왜 불필요하다고 판단했는지) 리포트에 남길 것.

## 검증 요구

- 순수 로직 단위테스트: `_pointAtCumulativeM` 경계값(0, 끝, 세그먼트 정확히 위)
- `RouteProgressNotifier` 통합테스트: 합성 경로(tunnel zone 포함) + 가짜 clock/타이머로
  ① 정상 주행 중 stale 전환 시 터널 밖이면 dead reckoning **미진입**(이 조건 확인 필수 —
  터널 아닌 곳에서의 GPS 순단은 이번 스코프 아님) ② 터널 안에서 stale 전환 시 진입,
  `_traveledM`이 시간에 비례해 전진 ③ 터널 끝 도달 시 더 전진하지 않고 유지
  ④ 실측 fix 복귀 시 정상 `_advance()`로 복귀
- `nav_screen.dart` 게이트: `deadReckoning=true`일 때 `_triggerReroute()`가 스킵되는지
  (S5의 `nav_screen_stationary_gates_test.dart`와 같은 정적 검사 패턴 재사용 가능)
- 실기기 검증(가상GPS): 터널 구간 GPS 드롭 시나리오 재생 — memory `project_vgps_testing`
  (3-provider 모킹) 활용. 이 항목은 헤드리스 서버에서도 가능할 수 있으니, 기존 가상GPS
  하네스가 GPS provider를 완전히 끊는(fix 자체를 중단하는) 시나리오를 지원하는지 먼저 확인.
  지원하면 이번 세션에서 직접 재생해볼 것 — 안 되면 마스터 실기기 대기로 남긴다.
- `flutter analyze` 이슈 0, `flutter test` 전건 통과

## 완료 후

- `code-auditor` PASS 후 커밋, `CHECKLIST_0805_testride0802.md` §S7 `[x]`로 갱신
- `loop/MORNING_REPORT_0807_S7_tunnel_dead_reckoning.md`에 기록
