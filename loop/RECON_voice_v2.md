# RECON_voice_v2 — 음성 요구 5건 훅 지점 확정

작성일: 2026-06-30  
브랜치: feat/ic-early-guidance  
상태: 읽기전용 조사. 코드 변경 없음.

---

## R1. 근접 회전 문구 속도연동 (≥20 km/h)

### 훅 지점

| 파일 | 라인 | 현황 |
|------|------|------|
| `lib/features/navigation/voice_engine.dart` | 32 | `onProgress(int step, double d, List<ManeuverStep> steps)` — speedKmh 파라미터 없음 |
| `lib/features/navigation/voice_engine.dart` | 54–58 | imminent key 생성: `'${event}_imminent'` 단일 분기, 속도 조건 없음 |
| `lib/features/navigation/presentation/nav_screen.dart` | 241–242 | `_voiceEngine!.onProgress(prog.activeStepIdx, prog.distToNextTurnM, _maneuvers)` — speed 미전달 |
| `assets/voice_packs/default_ko.json` | 13, 15 | `turn_left_imminent: "좌회전입니다"`, `turn_right_imminent: "우회전입니다"` — 고속 변형 키 없음 |

### 현황 요약
- `_handleVoice` (`nav_screen.dart:239`)는 `ConsumerState` 내부 메서드이므로 `ref.read(navStateProvider)?.speedKmh`를 추가 주입 없이 바로 읽을 수 있다.  
- `VoiceEngine`에는 속도 개념이 없으며 `onProgress` 시그니처를 확장해야 한다.  
- 새 템플릿 키 (`turn_left_imminent_fast`, `turn_right_imminent_fast`)를 JSON에 추가하고, `onProgress` 내부에서 `speedKmh ≥ 20 ? '_fast' : ''` suffix로 분기.

### 분류 → **순수로직·책상검사 가능**

### 구현 슬라이스
1. `VoiceEngine.onProgress`에 `double speedKmh = 0` 추가 (순수 함수 유지, 테스트 가능).  
2. `nav_screen.dart:241` 에서 `ref.read(navStateProvider)?.speedKmh ?? 0` 전달.  
3. `default_ko.json` 에 `turn_left_imminent_fast: "곧 좌회전입니다"`, `turn_right_imminent_fast: "곧 우회전입니다"` 추가.  
테스트 경계: `onProgress(step, d, steps, speedKmh)` 단위 테스트로 key 출력 검증.

---

## R2. 도착 문구 ("목적지 도착" → "목적지에 도착했습니다")

### 훅 지점

| 파일 | 라인 | 현황 |
|------|------|------|
| `assets/voice_packs/default_ko.json` | 10 | `"arrival": "목적지에 도착했습니다"` — 이미 올바른 값 (prog.arrived 경로) |
| `assets/voice_packs/default_ko.json` | 28 | `"destination_imminent": "목적지 도착"` ← **구 문구 잔존** |
| `lib/features/navigation/presentation/nav_screen.dart` | 224 | `_vps?.speak('arrival')` — `prog.arrived` (25m) 도달 시 발화 |
| `lib/features/navigation/voice_engine.dart` | 20 | `case 4: case 5: case 6: return 'destination';` → VoiceEngine이 imminentM(5m) 도달 시 `destination_imminent` 발화 |

### 현황 요약
- `arrival` 키(`"목적지에 도착했습니다"`)는 `nav_screen.dart:224`에서 `prog.arrived`(잔여 25m 이하) 조건에 발화된다.  
- `destination_imminent`(`"목적지 도착"`)는 VoiceEngine이 imminentM(현재 5m) 도달 시 발화한다.  
- R2 타깃은 `default_ko.json:28` `destination_imminent` 문구이며, R3과 동일 키를 수정한다 → 두 요구사항 동시 결정 필요.

### 분류 → **순수로직·책상검사 가능**

---

## R3. 근접 큐 (5m "도착했습니다" → "목적지 부근입니다", 임계 5m → 10m)

### 훅 지점

| 파일 | 라인 | 현황 |
|------|------|------|
| `assets/config/guidance_profile.json` | 4 | `"imminent_m": 5` ← 변경 대상 (5 → 10) |
| `lib/features/navigation/guidance_profile.dart` | 30 | fallback `imminentM: 5` 하드코딩 — JSON 변경 시 함께 수정 |
| `assets/voice_packs/default_ko.json` | 28 | `"destination_imminent": "목적지 도착"` → `"목적지 부근입니다"` (R2와 동일 라인) |

### 현황 요약
- `route_progress_provider.dart:47`: 도착 반경 `_kArrivalM = 25m`. imminentM(5m)과 도착 감지(25m)는 별개이므로 10m로 올려도 대역 충돌 없음.  
- R2·R3 모두 `destination_imminent` 키를 수정한다 — 문구를 "목적지 부근입니다"로 통일하고, 도착 확정은 `arrival` 키("목적지에 도착했습니다")로만 처리하면 두 요구사항 동시 충족.  
- `guidance_profile.dart:30` fallback은 JSON 로드 실패 시에만 사용되지만 일관성 차원에서 동기화.

### 분류 → **순수로직·책상검사 가능**

### 구현 슬라이스 (R2 + R3 묶음 1 커밋)
1. `guidance_profile.json:4` → `"imminent_m": 10`  
2. `guidance_profile.dart:30` → `imminentM: 10`  
3. `default_ko.json:28` → `"destination_imminent": "목적지 부근입니다"`  
   (`arrival` 키는 현행 유지: "목적지에 도착했습니다")

---

## R4. 사거리 직진 안내 ("직진입니다" 동일 임계 발화)

### 훅 지점

| 파일 | 라인 | 현황 |
|------|------|------|
| `lib/features/navigation/voice_engine.dart` | 10–23 | `eventForType`: type 8 누락 → `null` 반환 (발화 없음) |
| `assets/config/guidance_profile.json` | 36 | `"continue": { "enabled": false }` — 프로필에 존재하나 disabled + eventForType 매핑 없음 |
| `assets/voice_packs/default_ko.json` | (없음) | `continue_approach`, `continue_imminent` 키 미존재 |
| `lib/features/navigation/presentation/nav_screen.dart` | 1061–1085 | `_labelForType`: type 8 → '직진', type 22 → '직진' (카드 표시 전용) |

### Valhalla type 매핑 현황
- type 8 = Continue (직진/계속 진행) → `eventForType`에서 **null** (현재 무음)  
- type 7 = Becomes (도로명 변경) → **null** (무음, 의도적)  
- type 22, 23, 24 → `'keep'` (차선유지) — `_labelForType`에서 22='직진'과 불일치(카드 표기 오류 별개)

### 교차로 구분 가능 여부
`ManeuverStep`(`routing_service.dart:31–46`) 필드: `type`, `instruction`, `distanceKm`, `beginShapeIdx`, `endShapeIdx` — 교차로 여부 플래그 없음.  
type 8을 'continue'에 매핑하면 **비교차로 직진(도로 계속) 포함 전부 발화 → 과다 위험**.  
Valhalla `/route` 응답의 maneuver에는 `verbal_pre_transition_instruction`에 힌트가 있으나 현재 파싱하지 않음.

### 분류 → ~~라우팅/엣지 데이터 필요·보류~~ → **실증 완료, 구현 가능 (2026-07-06 갱신)**

**curl 계측 (2026-07-06, 폰 없이 desk에서 진행):** `localhost:8002`에 8개 실경로 태움 —
국도44(홍천-인제 54km), 부산시내(서면-해운대 14km), 국도19(구례-하동 37km), 국도42(여주-원주
32km), 김제 평야 그리드(38km, T자/사거리 밀집 지역), 대전 시내 그리드(7km), 정선 오지도로(59km),
가평 국도(남양주-가평 43km). **합계 285km, maneuver 118개 중 type 8 발생 0건.**

**원인(Valhalla 소스 확인, `maneuversbuilder.cc:1880-1996`):** `kContinue`(type 8)는 turn_degree가
`kStraight`일 때의 fallback 분류일 뿐이며, 실제로 최종 trip leg에 "별도 maneuver"로 살아남으려면
`internal_intersection`이거나 `HasSimilarStraightSignificantRoadClassXEdge`(비슷한 각도의 경쟁
도로가 교차점에 있어 직진 여부가 애매한 경우) 조건을 통과해야 한다 — 그 외 평범한 직진 구간은
애초에 별도 maneuver로 분리되지 않고 이전 maneuver에 흡수된다. 즉 **Valhalla 엔진 자체가 이미
"애매한 분기점"으로 필터링해서 내보내므로, RECON 작성 당시 우려했던 "비교차로 직진 포함 전부
발화 → 과다 위험"은 이 타일셋/costing(motorcycle) 기준 근거 없음.**

**결론:** 실주행 없이도 진행 가능. `case 8: return 'continue';` 매핑 + `continue_approach`/
`continue_imminent` 템플릿 추가 + profile enable=true (tier는 공통 폴백, sharp-curve와 동일 원칙
— 실주행 근거 없이 타이밍까지 새로 만들지 않음). 단, **표본 8개 모두 type 8이 0건이라 "발화가
드물게라도 정상 동작하는지"는 이번 라이딩에서 직접 들어봐야 확인됨** — 애초에 흔치 않은
이벤트이므로 이번 세션 구현 후에도 "탑승 중 못 들을 가능성 높음"은 별개로 기록.

---

## R5. 지하차도/고가 "진출" 오안내

### 훅 지점

| 파일 | 라인 | 현황 |
|------|------|------|
| `lib/features/navigation/voice_engine.dart` | 20 | `case 20: case 21: return 'exit';` — Valhalla type 20(우측 출구)/21(좌측 출구) → 'exit' 이벤트 |
| `assets/voice_packs/default_ko.json` | 19–20 | `"exit_approach": "{dist}미터 앞 진출"`, `"exit_imminent": "진출입니다"` |
| `lib/features/navigation/presentation/nav_screen.dart` | 1075–1076 | `_labelForType`: type 20='우측 출구', 21='좌측 출구' |

### 현황 요약
- type 20/21은 Valhalla 스키마상 고속도로·간선도로 램프 출구를 의미한다.  
- 지하차도 진입 시 Valhalla가 type 20/21 또는 type 17/18/19(ramp)을 반환할 경우 "진출" 또는 "진입" 문구가 지형 맥락과 불일치한다.  
- **tunnel/bridge 판별**: Valhalla `/route` 응답에 `edge.use=tunnel/bridge` 없음. `trace_attributes` API만 제공 → 현 슬라이스에서 판별 불가.  
- `ManeuverStep`에 `tunnel`/`bridge` 필드 없음 (`routing_service.dart:31–46` 전체 필드 확인).

### 분류 → **실증 완료(2026-07-06) — 조치 불필요로 종결**

`RECON_underpass.md` D절: 8경로/98maneuver curl 실측(exit/ramp 11건) 결과, type 20/21·17-19
분기점이 tunnel edge와 접한 사례 0건, bridge 접함은 1건뿐이고 그 1건도 실제 고속도로 출구
(지하차도 오안내 아님). 진입 edge는 11/11 모두 `use=ramp`, 도로등급도 전부 간선급 이상 —
이 타일셋 기준 Valhalla가 exit/ramp를 잘못 붙이는 사례가 없어 trace_attributes 레이어를
새로 만들 근거가 현재 없음. **R4와 같은 패턴(RECON 우려 → curl 실측으로 기각).**
실주행에서 "진출/진입인데 실제로는 그냥 지하차도였다" 류 반례가 보고되면 그때 재조사.
(표본이 도심~고속도로 접속부 위주라 순수 국도 지하차도는 덜 대표됨 — 완전한 반증은 아님.)

---

## 분류표 요약

| 요구사항 | 분류 | 이유 |
|----------|------|------|
| R1 속도연동 imminent | 순수로직·책상검사 가능 | speed 값 이미 NavState에 있음. onProgress 시그니처 확장 + JSON 키 추가만 |
| R2 도착 문구 | 순수로직·책상검사 가능 | default_ko.json:28 문구 편집만 |
| R3 근접 큐 임계 | 순수로직·책상검사 가능 | guidance_profile.json + fallback 상수 + JSON 문구 변경만 |
| R4 사거리 직진 | 실증 완료·구현됨 | curl 계측(285km/118maneuver, type8 0건) → 우려 근거 없음, `feat/continue-straight-voice`로 구현 |
| R5 지하차도 진출 | 실증 완료·조치 불필요 | curl 계측(98maneuver, exit/ramp 11건) → tunnel 접함 0건·bridge 접함 1건(실제 출구) → 우려 근거 없음, 구현 안 함 |

---

## 구현 슬라이스 제안

### 슬라이스 A — 순수로직 3건 (1 PR, 책상 테스트 완결)
- **A-1** R2+R3 JSON 편집 (1 커밋): `guidance_profile.json` imminentM 5→10, fallback 동기화, `destination_imminent` 문구 변경.
- **A-2** R1 VoiceEngine 확장 (1 커밋): `onProgress` speedKmh 파라미터, 'fast' suffix 분기, JSON 키 추가.
  - 단위 테스트 파일: `test/voice_engine_speed_test.dart` — 순수함수 검증.

### 슬라이스 B — R4 사거리 직진 (완료)
- curl 실측 후 우려 근거 없음 확인, `feat/continue-straight-voice`로 구현 완료(`verify/ride-0706`에 통합, 라이딩 대기).

### 슬라이스 C — R5 지하차도 (종결, 조치 불필요)
- curl 실측 후 우려 근거 없음 확인. trace_attributes 레이어 신설 보류 — 실주행 반례 나오면 재조사.
