# RECON — 회전교차로 안내 무음 (p2/p3)

## 1. eventForType 매핑 — voice_engine.dart:10-23 → **가설 기각**
```dart
case 26: case 27:          return 'roundabout';   // voice_engine.dart:19
```
type 26(kRoundaboutEnter)/27(kRoundaboutExit) 모두 `'roundabout'`로 이미 매핑되어 있음.
"미매핑이 원인"이라는 앵커 가설은 **사실이 아님**.

## 2. 템플릿 키 — assets/voice_packs/default_ko.json:27-28 → 존재
```json
"roundabout_approach": "{dist}미터 앞 회전교차로",
"roundabout_imminent": "회전교차로",
```
enter/exit 구분 없이 동일 키 재사용(내용 이슈는 있으나 "문구 없음"은 아님).

## 3. guidance_profile.json roundabout tier — :35 → **전용 tier 없음, 전역 폴백**
```json
"roundabout":  { "enabled": true },
```
`ramp`/`exit`는 각각 전용 tier(1000/400/120/0, points 최대 1000m)를 갖지만 `roundabout`은 오버라이드가 없어 전역 폴백을 그대로 씀:
```json
"tiers": [
  { "min_entry_m": 500, "points_m": [500, 300, 50] },
  { "min_entry_m": 150, "points_m": [300, 50] },
  { "min_entry_m": 30,  "points_m": [100, 50] },
  { "min_entry_m": 0,   "points_m": [] }
]
```
`min_entry_m:0` tier는 `points_m: []` — entryD<30m일 때 발화 후보가 `imminentM(10)` 하나뿐이며, entryD≤10이면 그마저 필터링되어 **pending 포인트가 완전히 빈다** (voice_engine.dart:42-48, `pts.where((p) => p < entryD)`).

## 4. Valhalla 계약 실측 (curl, 검단회전교차로 인천 37.5988,126.6506 통과 경로)
```
0 type=2  len=232m  Drive east on 단봉로
1 type=15 len=46m   Turn left onto 검단로/54          ← 회전교차로 직전 진입로, 매우 짧음
2 type=26 len=53m   Enter 검단회전교차로 and take the 2nd exit
3 type=27 len=543m  Exit the roundabout onto 검단로/54
```
- **type 26/27 실제로 나옴** — fork가 roundabout을 다른 type으로 뭉개지 않음.
- **`roundabout_exit_count` 필드 존재**: type26 maneuver JSON에 `"roundabout_exit_count": 2` 포함 (curl 원본 확인, `/tmp/route1.json`). "N번째 출구" 발화용 데이터는 Valhalla가 이미 제공.
- 핵심 관찰: 회전교차로 **직전 진입 세그먼트가 46m, 로터리 내부 세그먼트가 53m**로 둘 다 전역 tier의 `min_entry_m:30~0` 구간에 들어가는 극단적으로 짧은 구간.

## 5. routing_service.dart 파싱 — :30-47, :417-436
```dart
class ManeuverStep {
  final int type;            // 보존됨 (line 425: (m['type'] as num?)?.toInt() ?? 0)
  final String instruction;
  final double distanceKm;
  final int beginShapeIdx;
  final int endShapeIdx;
  // roundabout_exit_count 필드 없음 — 파싱 안 함
}
```
type/거리/shape index는 정상 보존. 단 **`roundabout_exit_count`는 아예 캡처하지 않음** → Valhalla가 주는데도 앱단에서 즉시 버려짐.

## 추가 조사 (앵커 밖, 무음의 실제 메커니즘)
`route_progress_provider.dart:104-121` — `_advance()`는 GPS fix마다 `_snapIdx`부터 최대 `_kSnapWindow=50`개 세그먼트를 스캔해 최근접 perpendicular 지점으로 스냅한다. 로터리 형상은 지름 ~35-40m의 작은 원이라, 폴리라인 점 간격이 넓으면 원 반대편 세그먼트까지의 수직거리가 GPS 오차(5-15m)와 비슷해질 수 있어 `bestSeg`가 앞으로 널뛸 위험이 있다. `activeStepIdx`가 46m 진입 세그먼트(idx=1)나 53m 로터리 세그먼트(idx=2)를 한 fix에 건너뛰면, `voice_engine.dart:38 if (step != _voiceStepIdx)`가 그 스텝을 아예 거치지 않아 pending 계산 자체가 발생하지 않는다.

## 원인 단정 (1줄)
eventForType 미매핑이 아니라, **회전교차로 진입 직전(46m)·로터리 내부(53m) 세그먼트가 전역 폴백 tier(min_entry 30/0, points 최대 100m)에 비해 지나치게 짧아 entryD가 이미 임계치 아래로 들어온 채 스텝이 전환되고, 그 결과 pending 포인트가 비거나(3) GPS 스냅이 짧은 세그먼트를 건너뛰어(추가 조사) 발화가 통째로 스킵되는 것**이 가장 유력한 원인.

## 수정 슬라이스 제안
1. `guidance_profile.json`에 `roundabout` 전용 tier 추가(ramp/exit처럼) — 예: `{500,[500,300,100]}, {150,[150,50]}, {0,[50,10]}` 등 짧은 진입 구간에서도 최소 1개 포인트가 살아남게.
2. `voice_engine.dart` — type 26/27을 `roundabout_enter`/`roundabout_exit`로 분리 매핑(현재는 둘 다 `'roundabout'`로 뭉개져 있어 "진입"과 "탈출" 안내가 같은 문구로 나감). `default_ko.json`에 `roundabout_enter_*`/`roundabout_exit_*` 키 분리 추가.
3. `routing_service.dart:424-430` — `roundabout_exit_count`를 `ManeuverStep`에 필드로 추가 파싱하면, 문구를 `"{dist}미터 앞 회전교차로, {exit}번째 출구"`처럼 출구 번호까지 발화 가능 (Valhalla가 이미 제공 확인됨, 3항).
4. `route_progress_provider.dart` — 짧은 세그먼트 연속 구간(로터리)에서 GPS 스냅이 건너뛰지 않도록, roundabout류 maneuver 진입 시 `_kSnapWindow` 축소 또는 별도 최소-체류 로직 검토(코드 변경 전 재현 테스트 필요).
