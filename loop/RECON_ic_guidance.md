# RECON_ic_guidance — IC/출구 TTS 조기안내 훅 지점

작성: 2026-06-30 | 상태: 읽기전용 recon 완료

---

## 앵커 1 — Valhalla maneuver `type` → Dart ManeuverStep 파싱

**파일:** `lib/services/routing_service.dart:417–436`

`_collectManeuvers()` 내부에서 `m['type']`을 그대로 `ManeuverStep.type`(int)에 저장.
필터 없음 — type=19, 20 모두 손실 없이 모델까지 도달한다.

```dart
// L425
type: (m['type'] as num?)?.toInt() ?? 0,   // pass-through
```

ManeuverStep 클래스 정의: `lib/services/routing_service.dart:31–46`
- 필드 5개만 보존: `type`, `instruction`, `distanceKm`, `beginShapeIdx`, `endShapeIdx`

---

## 앵커 2 — `eventForType` 전체 분기

**파일:** `lib/features/navigation/voice_engine.dart:10–23`

```dart
String? eventForType(int type) {
  switch (type) {
    case 14: case 15: case 16: return 'turn_left';
    case 9:  case 10: case 11: return 'turn_right';
    case 12: case 13:          return 'uturn';
    case 17: case 18: case 19: return 'ramp';    // ← type=19 RampLeft 여기로
    case 20: case 21:          return 'exit';    // ← type=20 ExitRight 여기로
    case 22: case 23: case 24: return 'keep';
    case 25: case 37: case 38: return 'merge';   // 고속본선 합류
    case 26: case 27:          return 'roundabout';
    case 4:  case 5:  case 6:  return 'destination';
    default:                   return null;      // silent drop 없음
  }
}
```

type=19 → `'ramp'`, type=20 → `'exit'`. default는 null 반환(안내 건너뜀)으로 삼킴 아님.

---

## 앵커 3 — `guidance_profile.json` events 목록

**파일:** `assets/config/guidance_profile.json`

```json
"events": {
  "turn_left":   { "enabled": true },
  "turn_right":  { "enabled": true },
  "uturn":       { "enabled": true },
  "ramp":        { "enabled": true },   // ← type=19 활성
  "exit":        { "enabled": true },   // ← type=20 활성
  "keep":        { "enabled": true },
  "merge":       { "enabled": true },   // ← type=25/37/38 활성
  "roundabout":  { "enabled": true },
  "continue":    { "enabled": false },  // 유일하게 비활성
  "destination": { "enabled": true }
}
```

tier 정의:

| minEntryM | 안내 거리(pointsM) |
|-----------|-----------------|
| ≥500m     | 500, 300, 50    |
| ≥150m     | 300, 50         |
| ≥30m      | 100, 50         |
| <30m      | (없음, imminent만) |

`imminent_m: 5`

---

## 앵커 4 — `default_ko.json` 발화 템플릿 구조

**파일:** `assets/voice_packs/default_ko.json`

```json
"ramp_approach":  "{dist}미터 앞 진입",
"ramp_imminent":  "진입입니다",
"exit_approach":  "{dist}미터 앞 진출",
"exit_imminent":  "진출입니다",
"merge_approach": "{dist}미터 앞 합류",
"merge_imminent": "합류 구간",
```

- 변수 자리표는 `{dist}` 하나뿐. 치환은 speak time에 수행(voice_engine.dart L54 부근).
- `exit_name`, `exit_number`, `sign` 변수 주입 메커니즘 **없음**.
- 출구명 발화를 원하면 템플릿에 `{exit_name}` 자리표를 추가하고, speak 호출부에서 치환 로직도 함께 확장해야 한다.

---

## 앵커 5 — `voice_engine.dart` 적응형 티어 로직 및 1km 분기 위치

**티어 정의:** `lib/features/navigation/guidance_profile.dart:30–33`

```dart
GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
GuidanceTier(minEntryM: 30,  pointsM: [100, 50]),
GuidanceTier(minEntryM: 0,   pointsM: []),
```

**티어 선택 및 포인트 조립:** `lib/features/navigation/voice_engine.dart:41–42`

```dart
final tier = profile.tierFor(entryD);
final pts = [...tier.pointsM, profile.imminentM];
```

**현황:** 1000m 티어 없음. IC 조기 안내(1km)를 추가하려면:

1. `guidance_profile.json` tiers 배열 맨 앞에 `{ "min_entry_m": 1000, "points_m": [1000, 500, 50] }` 항목 추가.
2. `eventForType` 또는 그 위 레이어에서 IC 판별(type=19/20/25) 시 별도 event key(`"ic"`)를 반환하도록 분기.
3. `guidance_profile.json` events에 `"ic": { "enabled": true }` 추가.
4. `default_ko.json`에 `"ic_approach"`, `"ic_imminent"` 템플릿 추가.

분기 삽입 지점: `voice_engine.dart:41` `tierFor(entryD)` 호출 전 — entryD와 step.type을 동시에 체크하는 조건 추가.

---

## 앵커 6 — `sign.exit_name_elements` / `exit_number_elements` 보존 여부

**파일:** `lib/services/routing_service.dart:421–430`

maneuver에서 추출하는 필드:

| Valhalla 키           | ManeuverStep 필드  | 상태    |
|-----------------------|--------------------|---------|
| `type`                | `type`             | ✅ 보존  |
| `instruction`         | `instruction`      | ✅ 보존  |
| `length`              | `distanceKm`       | ✅ 보존  |
| `begin_shape_index`   | `beginShapeIdx`    | ✅ 보존  |
| `end_shape_index`     | `endShapeIdx`      | ✅ 보존  |
| `sign`                | —                  | ❌ 누락  |
| `exit_name_elements`  | —                  | ❌ 누락  |
| `exit_number_elements`| —                  | ❌ 누락  |

ManeuverStep 클래스에 해당 필드가 없어 다운스트림에서 접근 불가.
출구명 발화를 구현하려면 ManeuverStep에 `exitName`/`exitNumber` 필드를 추가하고 파싱 시 `m['sign']` 블록을 읽어야 한다.

---

## merge(25/37/38) 응답 관련

type=25/37/38 → `eventForType`에서 `'merge'` 반환, `guidance_profile.json`에서 `enabled:true` 확인.
코드 경로 완비. **실제 고속본선 합류 경로 curl로 응답 데이터 관측은 미수행** — Valhalla 응답에서 해당 type이 실제로 내려오는지, sign 필드 내용을 확인하려면 합류 포함 경로로 추가 curl 필요.

---

## 구현 슬라이스 제안

### 슬라이스 A — IC 조기 1000m 티어 (설정 변경만)
- `guidance_profile.json` tiers 배열 앞에 1000m 항목 추가 (JSON 수정, Dart 코드 변경 없음)
- 테스트 경계: `GuidanceProfile.tierFor(1100)` 단위 테스트 → `pointsM: [1000, ...]` 반환 확인

### 슬라이스 B — IC/exit 전용 event key 분리
- `eventForType()`에서 type=19/20 → `'ic'` (현재 ramp/exit와 분리)
- `guidance_profile.json` + `default_ko.json`에 `'ic'` 키 추가
- 테스트 경계: `eventForType(19)` == `'ic'`, `eventForType(17)` == `'ramp'` 단위 테스트

### 슬라이스 C — 출구명 파싱 및 발화
- `ManeuverStep`에 `String? exitName` 필드 추가
- `_collectManeuvers()`에서 `m['sign']?['exit_name_elements']` 읽어 저장
- `default_ko.json` 템플릿에 `{exit_name}` 자리표, speak 호출부에 치환 로직
- 테스트 경계: mock Valhalla JSON → `ManeuverStep.exitName` 값 단위 테스트
  + sign 없는 경우 null 폴백 확인

**추천 순서:** A → B → C (A는 무위험, B는 순수함수 교체, C는 모델 변경)
