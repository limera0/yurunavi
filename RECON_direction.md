# RECON #2: 안내 방향 오류 추적 결과

---

## E. _steps 인덱스 의미 (off-by-one 판정)

### E-1. Valhalla maneuver 파싱 — routing_service.dart:319-325

```dart
for (final m in (leg['maneuvers'] as List? ?? [])) {
  maneuvers.add(ManeuverStep(
    type:        (m['type'] as num?)?.toInt() ?? 0,
    instruction: (m['instruction'] as String?) ?? '',
    distanceKm:  (m['length'] as num?)?.toDouble() ?? 0.0,
  ));
}
```

- 인덱스 오프셋 없음. Valhalla 응답 순서 그대로 1:1 변환.
- `distanceKm = m['length']` = Valhalla semantics 기준 "이 행동을 수행한 후 다음 maneuver까지 이동할 거리."
- `begin_shape_index` / `end_shape_index` 파싱 없음 (G-1 참조).
- `instruction`(영문 안내 문장)은 ManeuverStep에 저장되나, `_TurnStep.fromManeuver()` (:1213)에서 사용 안 됨 (F-3 참조).

---

### E-2. 카드가 보여주는 것: "현재 행동" vs "다음 회전"

**카드 렌더링 경로 (nav_screen.dart):**
```
:783   final step = _steps[_stepIdx];
:950   Text(step.dist, ...)    // "742m"  (현재 step의 구간 거리)
:959   Text(step.label, ...)   // "우회전" (현재 step의 행동)
```

**Valhalla maneuver semantics:**
- `maneuver[i].type` = 이 지점에서 수행할 행동 (e.g., 우회전)
- `maneuver[i].length` = 이 행동 후 다음 maneuver까지 이동 거리

**결과:** `_steps[_stepIdx]`는 "지금 이 지점에서 할 행동 + 그 다음까지의 거리."
레이아웃상 dist가 먼저, label이 나중 → "742m 우회전"으로 읽히지만,
이것은 **"742m 앞에서 우회전"이 아니라 "우회전 구간, 총 742m"** 를 표시한다.

**type=1 depart step 포함 여부:**
- `_applyRouteGuidance(:373-375)` = `maneuvers.map(_TurnStep.fromManeuver)` → ALL maneuvers 포함.
- Valhalla가 type=1 depart를 반환하면 **`_steps[0]` = 출발(type=1)**, 초기 카드는 "742m 출발."
- Valhalla가 depart를 생략하면 `_steps[0]` = 첫 번째 실질 회전 → "742m 우회전."

**off-by-one 여부 판정:**
표준 내비 관례("Xm 앞에서 [다음 행동]")와 비교하면:
- 관례: 카드 = `_steps[_stepIdx+1].label` + 현재 `remaining` 거리
- 실제 코드: 카드 = `_steps[_stepIdx].label` + `_steps[_stepIdx].dist` (정적, 비갱신)

→ **구조적 off-by-one 존재.** 카드가 "다가오는 회전"이 아닌 "현재 maneuver"를 표시하면서,
  거리 먼저/레이블 나중 레이아웃 때문에 마치 "Xm 앞 [행동]"처럼 읽힌다.
  이 인덱스 오차는 depart(type=1) step 유무에 따라 1칸 더 어긋날 수 있다.

---

### E-3. TTS(`_announceStep`)와 카드의 step 일치 여부

**일반 TTS:** `_announceStep(idx)` — nav_screen.dart:503-512
```dart
final step = _steps[idx];               // 카드와 동일 인덱스
final text = step.dist.isNotEmpty
    ? '${step.dist} 앞 ${step.label}'
    : step.label;
_tts?.speak(text);
```
→ 카드와 TTS 동일 step, 동일 데이터. **카드와 TTS는 항상 같은 인덱스.**

**400m 예비 발화 (유일한 예외):** nav_screen.dart:412-416
```dart
final next = _steps[_stepIdx + 1];      // ← 현재 인덱스 + 1 (NEXT step)
final distStr = '${remaining.toStringAsFixed(0)}미터 앞';
_tts?.speak('$distStr ${next.label}');
```
→ 예비 발화만 **`_stepIdx + 1`을 참조.** 이 음성은 실제 "Xm 앞 [다음 행동]"을 올바르게 말한다.

**결론:** 일반 TTS와 카드는 같은 step을 보이므로, TTS가 맞게 들렸다면 방향 오류는
인덱스 차이가 아닌 매핑 오류 또는 off-by-one 의미 불일치에서 온다.

---

## F. type → 한글 방향 매핑

### F-1. 매핑 함수 위치

- `_iconForType(int type)`: nav_screen.dart:1222-1235
- `_labelForType(int type)`: nav_screen.dart:1238-1257

### F-2. 매핑 오류 및 누락

Valhalla maneuver type 정의(공식 proto):

| type | Valhalla 의미       | _iconForType 결과         | _labelForType 결과 | 판정 |
|------|---------------------|--------------------------|---------------------|------|
| 9    | kSlightRight        | turn_slight_right        | '약간 우회전'       | 정상 |
| 10   | kRight              | turn_right_rounded       | '우회전'            | 정상 |
| 11   | kSharpRight         | turn_right_rounded       | '급우회전'          | 정상 |
| 14   | kSharpLeft          | turn_left_rounded        | '급좌회전'          | 정상 |
| 15   | kLeft               | turn_left_rounded        | '좌회전'            | 정상 |
| 16   | kSlightLeft         | turn_slight_left         | '약간 좌회전'       | 정상 |
| **17** | **kRampStraight** | **turn_slight_right** ❌ | '진출로 직진' ✓     | **아이콘↔레이블 불일치** |
| **18** | **kRampRight**    | **turn_slight_left** ❌  | default → '직진' ❌ | **좌우 반전 + 레이블 오류** |
| 19   | kRampLeft           | default → straight ❌    | default → '직진' ❌ | 미매핑 |
| 20   | kExitRight          | default → straight ❌    | default → '직진' ❌ | 미매핑 |
| 21   | kExitLeft           | default → straight ❌    | default → '직진' ❌ | 미매핑 |
| 22-24| kStay계열           | default → straight ❌    | default → '직진' ❌ | 미매핑 |
| 25   | kMerge              | turn_right_rounded       | '진출로 우측'       | 합류를 우회전으로 표시 |
| 26   | kRoundaboutEnter    | turn_left_rounded        | '진출로 좌측'       | 로터리를 좌회전으로 표시 |

**핵심 오류 2건:**

**① nav_screen.dart:1233** (아이콘 left/right 반전)
```dart
case 16: case 18: return Icons.turn_slight_left;
//        ↑ type 18 = kRampRight (우측 램프진입)
//        → Icons.turn_slight_LEFT 표시: 좌우 반전
```
→ 우측 램프 진입 시 왼쪽 화살표가 카드에 표시됨.

**② nav_screen.dart:1227** (아이콘↔레이블 불일치)
```dart
case 9: case 17: return Icons.turn_slight_right;
//       ↑ type 17 = kRampStraight (직진 램프)
//       → 아이콘은 우측화살표, 레이블(:1251)은 '진출로 직진'
```
→ 같은 maneuver를 아이콘은 우회전, 글자는 직진으로 표시.

**미매핑 default 처리 (nav_screen.dart:1234, :1256):**
- type 18-24 모두 `default`로 낙하 → 아이콘=직진(straight), 레이블='직진'.
- 실제로는 우측 램프, 좌측 램프, 우측 출구, 좌측 출구 등 방향성 있는 maneuver.

---

### F-3. 카드 텍스트: type 매핑 사용, instruction 미사용

`_TurnStep.fromManeuver()` — nav_screen.dart:1213-1219:
```dart
return _TurnStep(
  _iconForType(m.type),       // ← type 기반 아이콘
  _labelForType(m.type),      // ← type 기반 한글 레이블
  _formatDist(m.distanceKm),
  m.distanceKm,
);
```

`ManeuverStep.instruction`(Valhalla 영문 안내문)은 routing_service.dart:322에서 파싱하나,
`_TurnStep.fromManeuver()`에 전달되지 않아 **카드/TTS 어디에도 표시되지 않음.** 완전 폐기.

---

## G. begin_shape_index 미파싱 영향

### G-1. 파싱부 확인

routing_service.dart:319-325: `type`, `instruction`, `distanceKm(=m['length'])` 만 추출.
`begin_shape_index` / `end_shape_index` **파싱 없음.**

**`_stepEndDistM` 구성** — nav_screen.dart:364-370:
```dart
void _computeStepEndDistances() {
  double cum = 0.0;
  for (final step in _steps) {
    cum += step.rawDistKm * 1000.0;   // Valhalla m['length'] 누적
    _stepEndDistM.add(cum);
  }
}
```

**`_traveledDistM`** — nav_screen.dart:388-401:
GPS 위치를 `_routePoints`(decoded polyline) 전체 세그먼트에 투영,
가장 가까운 세그먼트 직전까지 haversine 누적합.

**어긋날 여지:**
- `_stepEndDistM[i]`는 Valhalla `maneuver.length` 누적값 (Valhalla 내부 계산).
- `_traveledDistM`는 decoded polyline haversine 합산.
- 두 값 모두 동일 Valhalla 라우트 기반이므로 총합은 거의 일치.
- 단, GPS 투영이 **가장 가까운 세그먼트**를 찾는 방식이라, 경로가 역방향으로 겹치거나
  U자형 구간이 있으면 엉뚱한 세그먼트에 투영 → `_traveledDistM` 과대/과소 계산 가능.
- `begin_shape_index` 없으므로 "어느 polyline 구간이 몇 번째 maneuver인지" 정보 없음.
  step 경계 판정이 전적으로 거리 누적값 일치에 의존.

---

## 최종 판정 1줄

**(d) 복합** — ① off-by-one semantic (E-2): 카드가 "다가오는 회전"이 아닌 "현재 maneuver 행동"을
표시하면서 `dist-먼저/label-나중` 레이아웃이 "Xm 앞 [행동]"처럼 읽혀 방향 타이밍이 1 step 어긋남;
② type 18(kRampRight) 아이콘이 `Icons.turn_slight_left`(좌우 반전, nav_screen.dart:1233)으로
실제 우측 램프 진입 시 왼쪽 화살표를 표시하는 명백한 방향 오류가 공존.
