# SPEC_guidance_config — 적응형 안내 티어 + config 외부화 (설계)

작성: 2026-06-28
브랜치: TBD (구현은 버그픽스 머지 후 별 브랜치)
성격: **설계 SPEC.** 구현 전 VoicePackService 내부 RECON 선행 필요(§9).
목적: 하드코딩 500/300/50 발화를 **config 구동 적응형 티어 엔진**으로 교체.
"174m 앞" 류 소음 제거 + 안내 프로파일을 다운로드·교체 가능한 모듈로(마켓 연결).

---

## 1. 설계 원칙
- 타이밍 로직 **하드코딩 금지** → `guidance_profile.json` 외부화.
- **2층 분리**: 안내 프로파일(타이밍, 언어무관) ⊥ 음성 팩(문구/오디오, 언어별). 둘 다 다운로드 교체.
- 발화 거리는 항상 **깔끔한 점**(500/300/100/50/직전)에서만 — 임의 실거리 미발화.
- 진입 거리에 따라 **티어 선택** → 런웨이에 안 맞는 상위 점은 자동 스킵.
- 메모리 원칙 계승: 모든 조정값 설정 변수화. 이 파일이 앱 튜닝값 중심 파일의 첫 인스턴스.

---

## 2. 적응형 티어 엔진 (핵심 알고리즘)

### 티어 표 (네 사양 그대로, config화)
| 진입 거리 band | 안내점(직전 제외) |
|---|---|
| ≥ 500m | 500, 300, 50 |
| 150–500m | 300, 50 |
| 30–150m | 100, 50 |
| < 30m | (없음) |

직전(기본 5m)은 **모든 티어 공통**으로 항상 마지막에.

### 선택·발화 로직 (의사코드 아님 — 구현 명세)
```
// step이 active로 바뀌는 순간 (진입)
entryD = prog.distToNextTurnM
tier   = profile.tiers.firstWhere(t => entryD >= t.minEntryM)   // desc 정렬
points = [...tier.pointsM, profile.imminentM]                    // 직전 합류
// seed: 이미 지난 점 제거 (진입 시 entryD보다 큰/같은 점은 안 읽음)
pending = points.where(p => p < entryD).toList()..sort(desc)

// 매 tick (distToNextTurnM 단조 감소 보장됨)
d = prog.distToNextTurnM
while (pending.isNotEmpty && d <= pending.first) {
  point = pending.removeAt(0)
  final isImminent = (point == profile.imminentM)
  _vps?.speak(phraseKey(event, isImminent), vars: {'dist': point, 'direction': eventLabel})
  debugPrint('YNAV_TTS point=$point d=${d.toStringAsFixed(1)} step=$step event=$eventId')
}
```
- `p < entryD` 필터 = 버그픽스 seed의 일반화. 진입-다발·과대거리 라벨 **설계상 불가**.
- step 단조 감소 → while 1회 통과 = 정확히 1회 발화(중복 없음).
- 정지/저속 재진입에도 pending 소비분은 재발화 안 됨(이미 제거).

---

## 3. config 스키마 — `assets/config/guidance_profile.json` (전체 예시)
```json
{
  "schema_version": 1,
  "profile_id": "default_ko",
  "profile_name": "기본 안내",
  "units": "metric",
  "imminent_m": 5,
  "tiers": [
    { "min_entry_m": 500, "points_m": [500, 300, 50] },
    { "min_entry_m": 150, "points_m": [300, 50] },
    { "min_entry_m": 30,  "points_m": [100, 50] },
    { "min_entry_m": 0,   "points_m": [] }
  ],
  "events": {
    "depart":       { "valhalla_types": [1,2,3],   "phrase": "depart",       "enabled": true,  "tiers": "none" },
    "turn_left":    { "valhalla_types": [14,15,16], "phrase": "turn_left",    "enabled": true },
    "turn_right":   { "valhalla_types": [9,10,11],  "phrase": "turn_right",   "enabled": true },
    "uturn":        { "valhalla_types": [12,13],    "phrase": "uturn",        "enabled": true },
    "continue":     { "valhalla_types": [7,8],      "phrase": "continue",     "enabled": false },
    "ramp":         { "valhalla_types": [17,18,19], "phrase": "ramp",         "enabled": true },
    "exit":         { "valhalla_types": [20,21],    "phrase": "exit",         "enabled": true },
    "keep":         { "valhalla_types": [22,23,24], "phrase": "keep",         "enabled": true },
    "merge":        { "valhalla_types": [25,37,38], "phrase": "merge",        "enabled": true },
    "roundabout":   { "valhalla_types": [26,27],    "phrase": "roundabout",   "enabled": true },
    "waypoint":     { "valhalla_types": [],         "phrase": "waypoint",     "enabled": true,  "source": "leg_boundary" },
    "destination":  { "valhalla_types": [4,5,6],    "phrase": "destination",  "enabled": true,  "tiers": "near_only" },

    "_deferred_v2": "아래는 maneuver type으로 불가 — edge 속성/verbal_* 필요, 현재 비활성",
    "tunnel":       { "valhalla_types": [], "phrase": "tunnel",   "enabled": false, "needs": "edge use=tunnel" },
    "bridge":       { "valhalla_types": [], "phrase": "bridge",   "enabled": false, "needs": "edge use=bridge" },
    "overpass":     { "valhalla_types": [], "phrase": "overpass", "enabled": false, "needs": "edge grade/structure" },
    "underpass":    { "valhalla_types": [], "phrase": "underpass","enabled": false, "needs": "edge structure" },
    "consecutive":  { "valhalla_types": [], "phrase": "consecutive","enabled": false, "needs": "verbal_multi_cue" },
    "clock_turn":   { "valhalla_types": [], "phrase": "clock_turn","enabled": false, "needs": "roundabout exit bearing 계산" },
    "lane":         { "valhalla_types": [], "phrase": "lane",     "enabled": false, "needs": "lanes — 한국 농촌 OSM 0%, 영구 제외" }
  }
}
```
- `valhalla_types` 정수는 **RECON에서 fork enum과 대조 확정**(추측 금지 — 로그상 depart=2 일치만 확인됨).
- `tiers:"none"` = 출발처럼 거리 안내 없이 단발. `tiers:"near_only"` = 목적지 부근만.
- `enabled:false`는 스키마엔 있되 런타임 무시 → 미래 데이터 확보 시 켜기만.

---

## 4. 음성 팩 연계 (`default_ko.json` 개편)
거리 하드코딩 키(`approach_300`) 폐기 → **`{dist}` 변수 + 이벤트별 문구**:
```json
{
  "turn_left":  { "approach": "{dist}미터 앞 좌회전", "imminent": "좌회전입니다" },
  "turn_right": { "approach": "{dist}미터 앞 우회전", "imminent": "우회전입니다" },
  "uturn":      { "approach": "{dist}미터 앞 유턴",   "imminent": "유턴입니다" },
  "depart":     { "single":   "출발합니다" },
  "destination":{ "near":     "목적지 부근입니다" }
}
```
- 엔진이 `{dist}`에 깔끔한 티어 점(500/300/100/50) 주입 → **"항상 300m" 템플릿 문제 근본 소멸**.
- 언어 팩(en/ja)은 같은 키 구조, 문구만 교체. 타이밍은 프로파일에서 옴 → 중복 없음.

---

## 5. 이벤트 분류 — 가용성 정직 구분
| 구분 | 이벤트 | v1 가용? | 근거 |
|---|---|---|---|
| 회전 | 좌/우/유턴 | ✅ | maneuver type |
| 도로구조 | 분기/진출입/유지/합류/회전교차로 | ✅ | maneuver type |
| 경로점 | 출발/경유지/목적지 | ✅ | leg 경계 + type |
| 구조물 | 터널/교량/고가/언더패스 | ❌ v2 | **edge 속성**(use=tunnel/bridge) 필요, maneuver type 아님 |
| 고급 | 연속 회전 | ❌ v2 | Valhalla `verbal_multi_cue` 파싱 필요(Layer 2) |
| 고급 | N시 방향 회전 | ❌ v2 | roundabout exit bearing 계산 필요 |
| 차로 | 차로변경/유지 | ⛔ 제외 | `lanes` — 한국 농촌 OSM 0%(메모리 확정) |

→ **v1은 회전+도로구조+경로점.** 구조물/고급은 스키마에 자리만 두고 비활성.

---

## 6. 단계화
- **v1 (이 SPEC 구현):** 티어 엔진 + `guidance_profile.json` 로더 + 음성팩 `{dist}` 개편 +
  maneuver type→event 매핑(가용분). 하드코딩 500/300/50 완전 제거.
- **v2 (별도):** edge 속성 플러밍(터널/교량) → Valhalla fork 응답 확장(메모리: 커스텀 파라미터 전구간 구현).
  verbal_multi_cue(연속 회전)는 Layer 2와 합류.
- **마켓 (must-have 완료 후):** 프로파일/음성팩 다운로드 → `assets/` 아닌 앱 저장소 로드 경로 추가.

---

## 7. 버그픽스와의 순서 (권고)
티어 엔진이 버그픽스를 **포함**한다(seed 필터 = 일반화). 두 길:
- **(권고) 버그픽스 먼저 머지:** `SPEC_tts_edge_fix` 2커밋 → 라이딩으로 Layer 1 게이트(①②④⑤) 통과 →
  **Layer 1 main 머지**. 그 위에서 이 엔진을 깨끗이 구축. (게이트가 오래 대기 중 — 먼저 닫는다)
- **(대안) 엔진으로 직행:** 버그픽스 스킵, 엔진 구현이 곧 fix. 1회 라이딩에 묶이나 변경폭 큼 → 반복 리스크.

내 권고는 **버그픽스 먼저**: 작고 안전, Layer 1 닫고 머지된 토대 위에서 엔진을 짓는 게 롤백·검증이 쉽다.
어느 라이딩이든 ①②⑤ 검증은 어차피 필요하니 버그픽스 라이딩은 안 버려진다.

---

## 8. 다음 — 구현 전 RECON 필요
이 설계를 프로덕션 SPEC으로 떨구려면 실물 확인 선행:
- `VoicePackService` API: `load()`/`speak(key, vars:)` 시그니처, vars 치환 방식, 키 구조.
- `Step`/maneuver 모델: type 정수 노출 경로, label 출처, leg 경계(경유지) 식별 방법.
- Valhalla fork maneuver type **enum 정수 실측**(§3 valhalla_types 확정).
- `_handleVoice` 현 구조에 엔진 삽입 지점.
→ `RECON_guidance_engine.md` 별도 작성 후 → `SPEC_guidance_engine_impl.md`(프로덕션).
