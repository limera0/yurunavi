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

### 분류 → **라우팅/엣지 데이터 필요·보류**

실제 국도/시내 경로에서 type 8 발생 빈도 확인(curl 또는 폰 주행) 없이는 과다 우려를 해소할 수 없다.  
`verbal_pre_transition_instruction`에 "교차로" 문자열 포함 여부로 필터링하는 경량 방안도 가능하나, 실증 선행 필요.

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

### 분류 → **라우팅/엣지 데이터 필요·보류 (trace 레이어 선행)**

type 매핑(`voice_engine.dart:20`)이나 템플릿(`default_ko.json:19–20`) 변경만으로는 근본 해결 불가.  
해결 경로: ① trace_attributes 별도 조회 레이어 구현 → ② ManeuverStep에 `isTunnel`/`isBridge` 주입 → ③ eventForType 또는 템플릿 key 분기.

---

## 분류표 요약

| 요구사항 | 분류 | 이유 |
|----------|------|------|
| R1 속도연동 imminent | 순수로직·책상검사 가능 | speed 값 이미 NavState에 있음. onProgress 시그니처 확장 + JSON 키 추가만 |
| R2 도착 문구 | 순수로직·책상검사 가능 | default_ko.json:28 문구 편집만 |
| R3 근접 큐 임계 | 순수로직·책상검사 가능 | guidance_profile.json + fallback 상수 + JSON 문구 변경만 |
| R4 사거리 직진 | 라우팅/엣지 데이터 필요·보류 | type 8 과다발화 위험 — 실 경로 curl/폰 검증 필요 |
| R5 지하차도 진출 | 라우팅/엣지 데이터 필요·보류 | tunnel/bridge 판별 불가 — trace_attributes 레이어 선행 필수 |

---

## 구현 슬라이스 제안

### 슬라이스 A — 순수로직 3건 (1 PR, 책상 테스트 완결)
- **A-1** R2+R3 JSON 편집 (1 커밋): `guidance_profile.json` imminentM 5→10, fallback 동기화, `destination_imminent` 문구 변경.
- **A-2** R1 VoiceEngine 확장 (1 커밋): `onProgress` speedKmh 파라미터, 'fast' suffix 분기, JSON 키 추가.
  - 단위 테스트 파일: `test/voice_engine_speed_test.dart` — 순수함수 검증.

### 슬라이스 B — R4 사거리 직진 (보류, 조사 선행)
- curl `https://<valhalla>/route` 로 국도 직선 구간 포함 경로 조회 → type 8 발생 비율 계측.
- 허용 가능하면 `eventForType`에 `case 8: return 'continue';` + JSON 키 추가 + profile enable.

### 슬라이스 C — R5 지하차도 (보류, trace 선행)
- trace_attributes 레이어(별도 M 슬롯) 완료 후 ManeuverStep 확장 → 이후 진행.
