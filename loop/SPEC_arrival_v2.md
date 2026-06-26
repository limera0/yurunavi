# SPEC_arrival_v2.md — 종료 모델 교체 (카운트다운 폐기 → 지오펜스 수동종료)

작성일: 2026-06-26
근거: loop/RECON_arrival_v2.md
대상: `lib/features/navigation/presentation/nav_screen.dart` (단일 파일)
브랜치: feat/arrival-fix (이미 C1~C4 적재됨)
분류: **T3 (라이딩 검증 필요)** → 검증 통과 전 main 머지 금지.

---

## 1. 목표

라이딩 실측에서 `_speedKmh < 1.0` 정차 게이트가 실 GPS에서 안 걸려 종료 불가.
정차 게이트 + 10초 카운트다운(C3)을 **지오펜스 기반 수동 종료버튼**으로 교체.

- 종료버튼 노출 = `목적지 직선거리 ≤ 30m` **AND** `_speedKmh ≤ 30km/h`
- 종료 = **버튼 수동 탭만**. 자동 종료(타이머) 완전 폐기.
- 목적지 30m 밖 이탈 시 = 버튼 숨김 + 안내(guiding) 복귀 + 재탐색.

C1(도착감지 잔여20m)/C2(상단 도착카드)/C4(TTS·POI)는 손대지 않음.
**실질적으로 C3만 교체.**

---

## 2. 상수 (신규)

```dart
static const _kGeofenceM   = 30.0;  // 종료버튼 지오펜스 반경(직선, m)
static const _kExitSpeedKmh = 30.0; // 종료버튼 노출 속도 상한(km/h)
```

- 위치: 기존 `_kArrivalM`(:100) 인접에 선언.

## 3. 상태 단순화

`enum _ArrivalPhase { guiding, arrivedHold }` — **`stopReady` 제거**(:31).
종료버튼 노출은 페이즈가 아니라 **라이브 불리언**으로 제어:

```dart
bool _canExit = false; // 지오펜스+속도 게이트 통과 시 종료버튼 노출
```

## 4. 제거 항목 (C3 잔재)

| 대상                                  | file:line | 처리                               |
| ----------------------------------- | --------- | -------------------------------- |
| `int _countdownSec`                 | :101      | 삭제                               |
| `Timer? _countdownTimer`            | :102      | 삭제                               |
| `DateTime? _parkGateAt`             | :103      | 삭제                               |
| dispose `_countdownTimer?.cancel()` | :206      | 삭제                               |
| `_ArrivalPhase.stopReady` 값         | :31       | enum에서 제거                        |
| `_checkStopGate` 함수 전체              | :584–616  | **§5 함수로 교체**                    |
| 호출부 `_checkStopGate(parked)`        | :377      | `_checkArrivedGeofence(loc)`로 교체 |

## 5. 신규 함수 `_checkArrivedGeofence(LatLng loc)`

`_checkStopGate`(:584–616)를 아래로 **완전 대체**:

```dart
void _checkArrivedGeofence(LatLng loc) {
  if (_phase != _ArrivalPhase.arrivedHold) return;
  final dest = widget.destination;
  if (dest == null) return;

  final dist = _distanceM(loc, dest); // :667 재사용

  // 목적지 30m 밖 이탈(통과/오버슈트) → 안내 복귀 + 재탐색
  if (dist > _kGeofenceM) {
    setState(() {
      _phase = _ArrivalPhase.guiding;
      _canExit = false;
      _arrivalAnnounced = false; // 재도착 시 'arrival' 재발화 허용
    });
    _reroute(loc); // :502 재사용 — 현위치→목적지 신규 경로
    return;
  }

  // 30m 이내: 속도 게이트로 종료버튼 노출 토글
  final can = _speedKmh <= _kExitSpeedKmh;
  if (can != _canExit) setState(() => _canExit = can);
}
```

- 호출부(:377): `_checkStopGate(parked);` → `_checkArrivedGeofence(loc);`
  - `parked` 인자 불필요(거리+속도 즉시 판정). 단 `_calcParkState()`/`parked` 변수 자체는
    `_onPosition` 다른 곳에서 쓰므로 **삭제하지 말 것** — 호출 인자만 교체.

## 6. UI 종료버튼 (:1179–1210)

- 노출 조건: `_phase == _ArrivalPhase.stopReady` → **`_phase == _ArrivalPhase.arrivedHold && _canExit`**
- 버튼 텍스트(:1200): `'지금 종료 ($_countdownSec)'` → **`'지금 종료'`** (카운터 제거)
- onTap(:1190) `Navigator.of(context).pop()` — **유지** (수동 종료).
- 상단 도착카드(:1034) `_phase == arrivedHold` — **유지** (버튼 노출 여부와 무관하게 카드는 도착 즉시).

## 7. 커밋 (단일)

- **1커밋 = 1논리(종료모델 교체) = 1파일(nav_screen.dart)**.
  카운트다운 필드 제거와 UI 참조는 분리 시 analyze 깨짐 → **반드시 원자적 단일 커밋**.
- 게이트: `flutter analyze` No issues(상시경고 settings_screen.dart:73 무시) + code-auditor 7/7.
- 커밋메시지(예): `fix(nav): replace countdown stop-gate with geofence manual exit`

## 8. 라이딩 검증 (T3 — main 머지 전 필수)

1. **골목 서행 도착**(≤30km/h): 30m 진입 시 '지금 종료' 버튼 즉시 노출 → 탭 시 종료.
2. **속도 초과 접근**(>30km/h로 목적지 통과): 버튼 안 뜸 확인.
3. **오버슈트**: 목적지 30m 밖으로 지나침 → 도착카드 사라지고 안내 복귀 + 재탐색('reroute' 발화),
   유턴 복귀 시 재도착 카드 + 버튼 정상.
4. **자동종료 부재 회귀**: 도착 후 정차해 가만히 둬도 **절대 안 꺼짐**(타이머 폐기 확인).

## 9. 미결

없음.
