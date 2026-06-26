# RECON_arrival_v2.md — 도착/종료 v2 (카운트다운 폐기 → 지오펜스 수동종료)

작성일: 2026-06-26
대상: `lib/features/navigation/presentation/nav_screen.dart` (feat/arrival-fix, 1455줄)
방식: 읽기 전용. github.com/limera0/yurunavi `feat/arrival-fix` clone 후 grep/sed 인용.
배경: 라이딩 실측 결과 `_speedKmh < 1.0` 정차 게이트가 실 GPS에서 안 걸려 종료 불가 →
마스터 결정으로 종료 모델을 **지오펜스 게이트 수동종료**로 교체, 10초 자동 카운트다운 폐기.

---

## §A 현재 C3 구현 (들어낼 대상)

### A1. 카운트다운 필드

- `int _countdownSec = 0;` — **:101**
- `Timer? _countdownTimer;` — **:102**
- `DateTime? _parkGateAt;` — **:103** (2초 정차 게이트 누적용)
- dispose에서 cancel: `_countdownTimer?.cancel();` — **:206**

### A2. 상태 enum

- `enum _ArrivalPhase { guiding, arrivedHold, stopReady }` — **:31**
- `_ArrivalPhase _phase = _ArrivalPhase.guiding;` — **:99**
- 현재 `stopReady`는 **정차 2초 게이트 통과 시점**에 진입(타이머 구동).

### A3. `_checkStopGate(bool parked)` — **:584–616** (전체 교체 대상)

- arrivedHold 분기(**:585–609**): `parked && !_moving && _speedKmh < 1.0` 연속 2초(`_parkGateAt`) →
  `_phase = stopReady`, `_countdownSec = 10`, 1초 주기 Timer 시작.
  Timer가 0 도달 시 **`Navigator.of(context).pop()` 자동 종료**(**:601**). ← 폐기 대상.
- stopReady 분기(**:610–616**): `_moving || _speedKmh >= 3.0` → Timer cancel, arrivedHold 복귀.
- 호출부: `_onPosition` 내 **:377** `_checkStopGate(parked);`

### A4. 하단 종료버튼 UI — **:1179–1210**

- 노출 조건: `_phase == _ArrivalPhase.stopReady` (**:1179**).
- 버튼 텍스트: `'지금 종료 ($_countdownSec)'` (**:1200**) ← 카운터 표시.
- onTap: `Navigator.of(context).pop()` (**:1190**). ← 수동 종료, 이건 유지.

---

## §B 유지할 자산 (재사용)

- `_distanceM(LatLng, LatLng)` 직선거리 Haversine — **:667**. 지오펜스 거리 계산에 그대로 사용.
- `static const _kArrivalM = 20.0;` — **:100** (도착감지 임계, T1, 유지).
- C1 도착감지 `_checkArrival` — **:559–582** (경로잔여 ≤20m + 마지막step, **수정 불필요**).
- C2 도착카드(상단) `_phase == arrivedHold` 분기 — **:1034** (유지).
- C4 `_onArrivedHoldEntered` — **:620–627**: `_arrivalAnnounced` 가드 + `speak('arrival')` 1회 +
  `_fetchNearbyPois`. `bool _arrivalAnnounced` 플래그 존재(통과 복귀 시 리셋 필요).
- 재탐색 `_reroute(LatLng origin)` — **:502**. 통과 시 재탐색에 재사용.
- 이탈감지 `_checkOffRoute` — **:466**, 호출 **:379**. 단 **guiding 페이즈에서만 실행**
  (**:378** `if (_phase == guiding && ...)`). arrivedHold에선 이탈감지 OFF → v2에서 통과 처리 별도 필요.

---

## §C 핵심 차이 (v1 → v2)

| 항목          | C3 현행                            | v2                                  |
| ----------- | -------------------------------- | ----------------------------------- |
| 종료버튼 노출     | 정차 2초 게이트 → stopReady            | **목적지 직선 ≤30m AND `_speedKmh` ≤30** |
| 종료 방식       | 수동탭 OR 10초 자동                    | **수동탭만** (자동 폐기)                    |
| 통과(>30m) 처리 | stopReady→arrivedHold 복귀(버튼만 숨김) | **버튼 숨김 + guiding 복귀 + 재탐색**        |
| 정차 판정 의존    | `parked`/`_parkGateAt`/2초        | **불필요**(속도+거리 즉시 판정)                |
| 타이머         | `_countdownTimer`                | **없음**                              |

---

## §D 미결

없음. 설계 확정(지오펜스 30m / 속도 30km/h / 수동전용). SPEC_arrival_v2.md로 진행.
