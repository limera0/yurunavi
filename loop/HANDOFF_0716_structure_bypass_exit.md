# HANDOFF — YuruNavi (2026-07-16, 언더패스/고가도로 "옆길" 구조물 인지 기능)

이 문서는 커밋 `ec1044f`(터널/교량 구조물 인접 출구 안내, 아래 §1) 다음 세션이 이어받을
작업이다. **다음 세션은 이 문서부터 읽을 것.**

---

## 0. 왜 이 기능이 필요한가 (반드시 먼저 읽을 것 — 사용자 원문 근거)

이건 편의 기능이 아니라 **안전 기능**이다. 사용자가 직접 준 근거를 그대로 남긴다:

> 고가도로나 언더패스가 있는 길은 통상 1차선이 아니라 3차선, 4차선, 혹은 5차선일수도
> 있어. 그런데 고가도로나 언더패스 진입인지 옆길인지를 미리 말해주지 않으면 미리
> 차선을 바꿀 타이밍을 놓치게 되고, 운이 없게 1차선이나 2차선을 달리고 있었는데
> 고가도로 옆길로 가야 하는 상황이라면 갑작스레 맨 우측 차선까지 차선 이동을 해야
> 하고, 자칫 잘못하면 사고로 이어질 수 있어.

즉: "우측 출구"라는 일반 안내만으로는 라이더가 그게 "고가/지하차도 옆길로 빠지는
분기"라는 걸 미리 인지 못 하고, 다차선 도로에서 차선 변경 타이밍을 놓쳐 마지막
순간에 급하게 여러 차선을 가로질러야 하는 상황이 생길 수 있다 — 오토바이 라이더에게는
실제 사고 위험. **이 판단 기준(임계값, 반경 등)을 정할 때 "조금 덜 정확해도 되니
UX를 해치지 말자"보다 "안전을 위해 조금 과감하게 잡아도 된다"는 쪽으로 판단할 것.**

---

## 1. 이미 완료된 것 (커밋 `ec1044f`) — 재사용 가능한 기반

경로 위에 실제로 있는 교량/터널(`StructureZone`, `trace_attributes`로 조회)에 한해,
그 근처의 우측/좌측 출구(maneuver type 20/21) 안내를 "터널/고가도로 우측/좌측
옆길"로 바꾸는 기능은 이미 구현·라이브 검증 완료됨:

- `lib/services/routing_service.dart:564` `structureNearExit()` — exit maneuver가
  구조물 zone과 겹치거나 300m 이내에서 끝나면 그 타입 반환.
- `lib/features/navigation/providers/route_progress_provider.dart:58` 부근
  `_exitStructureByManeuverIdx`(`Map<int, StructureType>`) — maneuver 인덱스 →
  인접 구조물 타입. `setRoute()`/`setStructureZones()` 호출마다 재계산.
- `lib/features/navigation/voice_engine.dart` `onProgress()` — `exitStructureByManeuverIdx`
  를 봐서 `exit_${phase}_structure` TTS 키 선택(named exitName > 구조물 > 랜드마크
  순 우선순위).
- `lib/features/navigation/presentation/nav_screen.dart` `_TurnStep._labelForType()` —
  카드 라벨도 동일 로직.
- `assets/voice_packs/default_ko.json` — `exit_approach_structure`/`exit_imminent_structure`
  템플릿.

**중요**: 카드 라벨/TTS 출력 레이어는 이미 완성돼 있고 **구조물 타입을 어떻게
알아냈는지는 신경 안 쓴다** — `_exitStructureByManeuverIdx` 맵에 항목만 채워주면
그대로 동작한다. 즉 이번 작업은 **이 맵에 항목을 추가하는 새 데이터 소스를 만드는
것**이지, 출력 로직을 다시 만드는 게 아니다.

---

## 2. 이번 세션 과제 — 경로에 없는(우회 중인) 구조물 감지

`structureNearExit()`는 **현재 경로 위에 있는** 구조물만 안다(trace_attributes가
실제로 밟는 도로만 조회하니까). 그런데 "옆길" 시나리오는 정의상 **그 구조물을
안 타는** 경로다 — 그래서 지금 로직으로는 절대 못 잡는다. 언더패스 옆길
테스트(§3 참조)에서 실제로 `exitStructureByManeuverIdx`에 해당 exit이 안 잡혀서
그냥 기존 `exit_approach_landmark` 그대로 나가는 걸 확인함.

### 이미 조사해서 확인한 것 — Valhalla `/locate`가 정확히 이 용도로 쓸 수 있다

`/locate` 액션에 좌표 + `radius` + `verbose:true`를 주면, **경로에 없어도** 반경
내 모든 엣지를 그 엣지의 `bridge`/`tunnel` 플래그, 그리고 `edge_info.names`(도로명
목록)까지 포함해서 반환한다. 실측 확인:

```bash
curl -s -X POST http://localhost:8002/locate -H "Content-Type: application/json" -d '{
  "locations": [{"lat": 37.049094, "lon": 127.043782, "radius": 100}],
  "costing": "motorcycle",
  "verbose": true
}'
```

이 좌표는 언더패스 옆길 테스트 경로(출발 37.03875,127.04904 → 도착
37.05173,127.04464)의 **실제 exit maneuver 시작점**(shape idx 30)이다. 결과에
`tunnel: true` 엣지가 99.3m 거리에서 실제로 잡힌다. 목적지 좌표(37.05173,127.04464)
근처에서 같은 조회를 하면 **`names: ["고덕지하차도"]`** — 즉 OSM way 이름 자체에
"지하차도"가 박혀있는 엣지가 76~87m 거리에서 잡힌다. **이게 핵심 발견**: 이름에
"지하차도"/"터널"/"고가"가 포함된 엣지를 찾으면 그 라벨을 그대로 쓰면 되고, 이름이
없으면 `bridge`/`tunnel` 플래그로만 판정해야 한다(폴백 필요, 아래 §4 참조).

---

## 3. 구현 방향 (제안, 강제 아님 — 다음 세션이 판단)

1. **트리거 조건**: `route_progress_provider.dart`의 `_recomputeExitStructureMap()`
   (line ~264)에서, type 20/21 maneuver 중 `structureNearExit()`(온-루트)가 이미
   `null`을 반환한 것만 대상으로 삼는다 — 온-루트 매칭은 그대로 우선.
2. **조회 시점/위치**: 해당 maneuver의 `beginShapeIdx` 좌표(필요하면 `endShapeIdx`
   부근도)에서 `/locate` 호출. 반경은 실측상 99.3m짜리도 잡아야 하니 **최소 150m**
   권장(§0의 "안전 우선" 원칙 — 안내를 놓치는 것보다 과감하게 잡는 게 낫다).
3. **비동기 처리**: `fetchStructureZones()`와 같은 패턴(HTTP 호출이라 `setRoute()`
   시점엔 없고 나중에 도착) — 이 새 조회도 별도 async 함수로 분리하고, 도착 후
   `nav_screen.dart`가 이미 하는 것처럼(`_loadStructureZones` 참조, line ~548 부근)
   카드/보이스 쪽에 갱신을 알려야 한다.
4. **라벨 판정(지하차도 vs 터널 vs 고가도로)**:
   - `edge_info.names`에 "지하차도" 포함 → 지하차도
   - "터널" 포함 → 터널
   - `bridge=true` → 고가도로
   - 이름 정보가 없고 `tunnel=true`만 있는 경우 → 폴백 필요. 후보: (a) 그냥 "터널"로
     통칭, (b) 엣지 길이 기반 임계값(짧으면 지하차도, 길면 터널) — 임계값을 뭘로
     할지는 실제 지하차도/터널 사례를 몇 개 더 조회해서 길이 분포를 보고 정할 것.
     `StructureType` enum 자체가 `bridge`/`tunnel` 두 개뿐이라 "지하차도"를 별도로
     구분하려면 enum 확장이 필요할 수 있음(예: `StructureType.underpass` 추가, 또는
     enum은 그대로 두고 라벨 문자열만 별도 함수로 분기).
5. **여러 엣지가 잡힐 때**: 가장 가까운 것 우선, 동일 이름 그룹은 하나로 취급.

---

## 4. 테스트 방법 — 기존 인프라 그대로 재사용

`android/gpsinjector/`(GPS+NETWORK+FUSED 3-provider 모킹 필수 — 안 하면 매
60~100초마다 실측 위치가 새어 들어와 데이터가 오염된다, 메모리
`project_vgps_testing.md` 참조) + 메인 앱의 디버그 전용 E2E 하네스
(`adb shell am start -n com.westinx.yurunavi/.MainActivity --es e2e_dest_lat
<lat> --es e2e_dest_lon <lon>`)가 이미 구축돼 있다. 테스트 스크립트
(`route_gen.py`/`run_all.sh`)는 `/tmp` 스크래치패드에 있었고 세션 간 유지 안 되니
필요하면 다시 만들 것 — 로직은 간단하다(Valhalla `/route` 호출 → 폴리라인
리샘플링 → CSV → gpsinjector 재생).

**테스트할 좌표는 이미 다 있음** — 사용자가 최초에 준 6개 구간 중 정확히
"옆길" 2개가 이번 기능의 타겟이다:

```
[언더패스 옆길] 출발: 37.03875, 127.04904 → 도착: 37.05173, 127.04464
[고가도로 옆길] 출발: 37.07070, 127.05753 → 도착: 37.06963, 127.05469
```

**한 속도(예: 60km/h)로 한 번씩만 돌리면 충분**하다 — 이 기능은 Valhalla가 미리
계산한 경로/maneuver에 좌표 기반 조회를 얹는 것뿐이라 실시간 속도와 무관함이
이미 이전 60회 테스트로 확정됨(`loop/feedback/VGPS_STRUCTURE_EXIT_0716.md` 참조).

**주의**: 이번 세션 중 가상 GPS 드라이브를 오래(17분+) 돌리다가 **폰 화면이
잠겨서** Flutter 앱이 스플래시에서 멈춰버리는 문제를 겪었다(코드 문제 아님,
환경 문제). `adb shell svc power stayon true`로 충전 중 화면 유지 설정을 이미
해뒀지만, 혹시 다시 잠겨 있으면 `adb shell wm dismiss-keyguard` +
`adb shell input keyevent KEYCODE_WAKEUP`로 풀고 시작할 것 — 스크린샷
(`adb exec-out screencap -p`)으로 먼저 확인하는 습관을 들이면 이 문제로 몇 분
낭비하는 걸 막을 수 있다.

기대 결과: 언더패스/고가도로 옆길 테스트에서 지금은 `exit_approach_landmark`/
`turn_right_*` 등 기존 일반 안내가 나오는데, 이 기능 구현 후엔 "지하차도/고가도로
우측 옆길" 계열로 바뀌어야 한다.

---

## 5. 검증 체크리스트

- `flutter analyze` 0 issues, `flutter test` 전부 통과(기존 189개 + 신규).
- 언더패스 옆길, 고가도로 옆길 각 1회 실측(가상 GPS)으로 새 라벨 확인.
- 터널 진입/옆길(기존 기능)이 이번 변경으로 회귀 안 했는지 1회씩 재확인.
- 커밋 전 `git status`/`git diff --stat`로 의도한 파일만 스테이징됐는지 확인
  (이 저장소엔 관련 없는 untracked 파일이 많음 — `loop/HANDOFF_0712_poi.md` 같은
  것들은 건드리지 말 것).
- push는 사용자가 명시적으로 지시하기 전엔 하지 말 것(`verify/ride-0711`은 계속
  로컬 전용).

---

## 6. 참고 문서

- `loop/feedback/VGPS_STRUCTURE_EXIT_0716.md` — 60회 가상 GPS 테스트 원본 결과.
- 메모리 `project_vgps_testing.md` — 가상 GPS 테스트 인프라 + FUSED_PROVIDER 함정.
- 커밋 `8f88669`(E2E 하네스), `ec1044f`(터널/교량 구조물 인접 출구 안내).

---

## 7. 완료 (2026-07-16 밤 ~ 2026-07-17)

**핵심 기능(§2~§4 과제) DONE**, 커밋 `952ef64`(옆길 구조물 감지 최초 구현) →
`a437894`(begin+end 양쪽 지점 병합으로 라벨 정확도 수정, 언더패스 옆길 테스트에서
"고덕지하차도"가 exit maneuver의 endShapeIdx 쪽에 붙어있음을 실측 확인) 순으로 진행.
가상 GPS로 §3의 두 타겟 경로(언더패스 옆길/고가도로 옆길) 모두 재검증 완료 —
`exit_approach_structure`/`exit_imminent_structure`로 정상 전환됨(스크래치패드
`verify_underpass_bypass_60.log`/`verify_overpass_bypass_60.log`, 세션 간 미보존).

**후속 하드닝(2026-07-17, 커밋 `fdc0132`)**: 사용자가 "반경 150m 하나로 크게 잡으면
옆길/뒤쪽의 무관한 구조물까지 오탐할 수 있다"고 지적 → `RoutingService.forwardSamplePoints()`
신설, exit maneuver의 `beginShapeIdx`부터 **경로를 따라 전방으로만** 150m 간격으로
500m까지 샘플링 후 각 지점을 기존 150m 반경으로 조회·병합하는 방식으로 교체
(`lib/features/navigation/presentation/nav_screen.dart` `_loadOffRouteStructures`).
분류 로직(`classifyOffRouteEdges`/`mergeOffRouteStructures`)은 변경 없음 — 어느 지점을
조회할지만 바뀜. `flutter analyze` 0 issues, 관련 테스트 전부 통과(신규
`test/routing_service_forward_sample_test.dart` 포함).

**⚠️ 남은 것**: 이 forward-sampling 교체 자체는 아직 가상 GPS로 재검증 안 함(분류
로직은 안 바꿨고 begin 지점은 forward sample 0m로 그대로 포함되니 회귀 가능성은
낮다고 판단하지만, 실측 확인 전까지는 추측). 다음 세션/실주행에서 §3의 두 타겟 경로를
한 번씩 더 돌려 라벨이 여전히 정확히 나오는지 확인 권장. `minLengthM=100`(§5 체크리스트,
`RIDE_RESULTS_0716.md` "6-잔여" 항목)은 이번 세션과 무관한 별개 이슈로 여전히 미해결.

push는 여전히 보류(`verify/ride-0711`은 origin 대비 181커밋 앞선 로컬 전용 브랜치).
