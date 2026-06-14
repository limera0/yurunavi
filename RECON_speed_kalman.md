# RECON — 칼만 속도융합 도입을 위한 현 속도코드 정찰

읽기전용 정찰. 코드 미수정. 날짜 2026-06-12 / 브랜치 feat/maplibre-migration
대상 파일: `lib/features/navigation/presentation/nav_screen.dart` (활성 내비 화면)

---

## 1. 요약

- **보간 "또 죽은" 원인 1줄 판정: 유력(코드 regression 아님 / 환경적 — GPS 5초 throttle)**
  `_speedTicker`는 initState 경로(`_startLocation`)에서 기동되고 dispose에서만 cancel되며,
  중간 조기 cancel/재할당 지점은 **없음**(아래 B 근거). 따라서 ticker 자체는 살아있음.
  "멈춰도 11~13km 5초 유지" 증상은 **GPS fix 간격이 5초로 벌어졌을 때**
  `_vCur`(직전 도플러 값)가 다음 fix 또는 8초 staleness 까지 고착되고,
  `slope≈0`이라 ticker가 200ms마다 같은 값을 재출력하기 때문(유력, 아래 B-6).
- **DESIGN_speed_kalman.md: 리포에 없음**(`find -iname "*kalman*"` → NO KALMAN DOC).
  설계 의도 문서 부재 → 필터 구조는 구현 턴에서 결정 필요.
- **sensors_plus: 없음.** `pubspec.yaml`에 `geolocator: ^14.0.2`만 존재(pubspec.yaml:20).
  IMU/가속도계 의존성·import·사용처 **전무**(아래 C-7,8).
- 활성 속도 경로는 **NavScreen 단일**. `driving_screen.dart`는 미사용 레거시(아래 D 주).

---

## 2. 현 속도코드 구조도 (필드·타이머·흐름)

### A-2. 속도 관련 필드 (선언 라인 + 용도)

| 필드 | 라인 | 용도 |
|---|---|---|
| `double _speedKmh = 0` | 59 | 화면 표시 속도(소스 오브 트루스). `_Speedometer`로 전달 |
| `final _posBuffer` | 65 | 최근 12초 GPS fix 링버퍼 `{lat,lon,t,acc}`. ZUPT 군집 앵커용 |
| `DateTime? _lastSpeedAt` | 66 | 적응 갱신 throttle 타이밍 기준 |
| `bool _moving` | 67 | 도플러+히스테리시스 이동상태. 0 게이트 |
| `bool _firstFixReceived` | 68 | 첫 fix 전 "GPS 검색 중" 표시 |
| `Timer? _speedTicker` | 72 | 200ms 외삽 ticker 핸들 |
| `double? _vPrev, _vCur` | 73 | 직전/최근 fix 도플러 속도(m/s) — ticker 입력 |
| `DateTime? _vPrevAt, _vCurAt` | 74 | 직전/최근 fix 수신시각(pos.timestamp 불신) |
| `LatLng? _vPrevPos, _vCurPos` | 75 | 직전/최근 fix 위치 — 점프 가드용 |

> 주: 정찰 요청의 `_spdTicker / _staleTimer / _fix1 / _fix2`는 **현 코드에 없음**.
> 실제 명칭은 `_speedTicker`(72)이며 staleness는 별도 타이머가 아니라
> `_tickSpeed` 내부 `sinceFix > 8000` 분기(239)로 구현됨. `_fix1/_fix2`는 `_vPrev/_vCur`에 해당.

### 흐름도

```
Geolocator.getPositionStream (210-221, 1Hz·bestForNavigation)
   └─> _onPosition(pos)  [277]
         ├─ _posBuffer.add / 12초 윈도 정리           (285-286)
         ├─ 적응 throttle: ≤10km/h→500ms / else 1000ms (289-300, 미달 시 early-return)
         ├─ 도플러 d = pos.speed (NaN/음수→0)          (304)
         ├─ _posBuffer 군집반경 parked 판정            (306-321)
         ├─ _moving 갱신(parked/d≥2/d<1.5 히스테리시스) (323-330)
         ├─ _vPrev←_vCur 시프트, _vCur←d 보관           (333-334)
         └─ setState(_speedKmh = _moving ? d*3.6 : 0)  (336-341)

Timer.periodic 200ms → _tickSpeed()  [225 기동, 230 정의]
         ├─ sinceFix>8000 → 0 (staleness)             (239-244)
         ├─ !_moving → 0 (ZUPT 존중)                   (246-249)
         ├─ vPrev/prevAt 없음 → 마지막 실측             (255-258)
         ├─ 가드(dtFix>6500/jump>150/avg>75) → 실측     (265-268)
         └─ 선형 외삽 v=vCur+slope*sinceFix → setState  (271-274)

_speedKmh → _Speedometer(speedKmh:..) [937] → Text(toStringAsFixed(0)) [1110-1112]
```

### A-3. 200ms 보간 ticker 전문 (`_tickSpeed`, 230-275 인용)

```dart
void _tickSpeed() {
  if (!mounted) return;
  final curAt = _vCurAt;
  final vCur = _vCur;
  if (curAt == null || vCur == null) return;
  final sinceFix = DateTime.now().difference(curAt).inMilliseconds;
  // staleness: 8초간 새 fix 없으면 정차로 간주 → 0 (고착 차단)
  if (sinceFix > 8000) {
    if (_speedKmh != 0.0 || _moving) {
      setState(() { _speedKmh = 0.0; _moving = false; });
    }
    return;
  }
  // ZUPT 존중: 히스테리시스 정차 판정이면 0 유지
  if (!_moving) {
    if (_speedKmh != 0.0) setState(() => _speedKmh = 0.0);
    return;
  }
  final measured = (vCur * 3.6).clamp(0.0, 270.0);
  final vPrev = _vPrev;
  final prevAt = _vPrevAt;
  if (vPrev == null || prevAt == null) {
    if ((_speedKmh - measured).abs() > 0.05) setState(() => _speedKmh = measured);
    return;
  }
  final dtFix = curAt.difference(prevAt).inMilliseconds;
  final jumpM = (_vPrevPos != null && _vCurPos != null)
      ? _distanceM(_vPrevPos!, _vCurPos!) : 0.0;
  final avgMs = dtFix > 0 ? jumpM / (dtFix / 1000.0) : double.maxFinite;
  if (dtFix <= 0 || dtFix > 6500 || jumpM > 150.0 || avgMs > 75.0) {
    if ((_speedKmh - measured).abs() > 0.05) setState(() => _speedKmh = measured);
    return;
  }
  final slope = (vCur - vPrev) / dtFix; // m/s per ms
  final v = (vCur + slope * sinceFix).clamp(0.0, 75.0);
  final kmh = v * 3.6;
  if ((_speedKmh - kmh).abs() > 0.05) setState(() => _speedKmh = kmh);
}
```

외삽식: `v = vCur + ((vCur - vPrev)/dtFix) * sinceFix`, `[0,75] m/s` clamp (271-272).
즉 직전 2개 fix의 도플러 기울기를 fix 이후 경과시간만큼 1차 외삽.

### A-4. staleness 워치독
별도 `_staleTimer` 없음. `_tickSpeed` 내부 `sinceFix > 8000`(239) 임계값으로
`_speedKmh=0; _moving=false` 강제(241). 200ms 주기로 평가됨.

---

## 3. 보간 죽은 원인 근거 (B)

### B-5. ticker setState 경로 생존 추적 (grep + 읽기)
`_speedTicker` 전체 출현 위치: **선언 72 / dispose cancel 171 / `_startLocation` 내 cancel→재기동 224-225** 뿐.
중간 조기 cancel·재할당 지점 **없음**.

```dart
// 224-225 (_startLocation 말미, GPS 스트림 listen 직후)
_speedTicker?.cancel();
_speedTicker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tickSpeed());
// 171 (dispose)
_speedTicker?.cancel();
```

`_tickSpeed` 내 `setState(_speedKmh)` 호출 경로 5개 모두 존재: 241, 247, 256, 266, 274.
→ **ticker는 _startLocation~dispose 동안 정상 가동. 코드 수준 보간 단절 없음(확정).**

### B-6. "멈춰도 11~13km 5초 유지" 증상 부합 경로 (가설 검증)
원인은 **`_moving`이 즉시 false로 안 떨어지고 + ticker가 마지막 도플러를 고착**하는 구조:
- 정차 판정 두 경로: (a) `_posBuffer` 군집반경 `parked`(320) → `_moving=false`(324),
  (b) 도플러 `d < 1.5`(327) → `_moving=false`(329).
  GPS가 5초 간격이면 12초 윈도(286)에 샘플 2~3개뿐 → 군집 parked 판정이 **지연**.
  도플러 `d`도 5초마다만 갱신되므로 d<1.5 판정도 다음 fix까지 **지연**.
- 그 사이 `_moving==true`가 유지되고, `_vCur`는 정차 직전 도플러(≈11~13km/h)로 고착.
  `_vPrev≈_vCur`(등속이었으므로)이라 `slope≈0`(271) → ticker가 200ms마다 **같은 값 재출력**(274).
- 해소는 둘 중 빠른 쪽: 다음 fix(최대 ~5초)에서 `_moving=false`, 또는 `sinceFix>8000`(239) staleness.
  → **약 5초간 11~13km/h 고착**과 정확히 부합. **유력**.

> REPORT_speed_polish.md(12-15행)도 동일 결론: 알림권한 미부여 → foreground service 미기동 →
> GPS 배경 throttle(5초+) → 등속 시 slope≈0 → "안 바뀌는" 느낌. 코드 regression 아님.

---

## 4. 칼만 대체 범위표 (D-10)

| 기존 요소 | 위치 | `_speedKmh` 기여 | 칼만 후 처리 |
|---|---|---|---|
| 도플러 `d = pos.speed` | 304, 336 | **직접(주 측정)** | **유지** — 칼만 update 측정값 z (R=도플러 노이즈) |
| 200ms 외삽 ticker `_tickSpeed` | 225, 230-275 | **직접(fix 사이 값)** | **대체** — predict 스텝(IMU 적분)이 외삽 대체. slope 외삽식(271-272) 제거 |
| `_vPrev/_vCur/_vPrevAt/_vCurAt/_vPrevPos/_vCurPos` | 73-75, 333-334 | 간접(ticker 입력) | **제거** — 칼만 상태(속도·바이어스)가 흡수 |
| 도플러+히스테리시스 `_moving` 게이트 | 323-330 | 직접(0 클램프) | **흡수** — ZUPT 의사측정(z=0)으로 전환. 트리거 로직은 유지 |
| `_posBuffer` 군집 parked 판정 | 65, 285-321 | 간접(_moving 구동) | **유지(ZUPT 트리거)** — 정차 감지해 칼만 ZUPT update 발화 |
| staleness `sinceFix>8000` | 239-244 | 직접(강제 0) | **흡수/유지** — IMU만으로 표류 방지 안 되면 안전 폴백으로 유지 검토 |
| 적응 throttle `_lastSpeedAt`/`intervalMs` | 66, 288-301 | 간접(갱신율) | **재검토** — 칼만은 매 fix update 권장. throttle 제거 또는 predict율과 분리 |

**칼만 도입 시 실제로 건드릴 라인:**
제거/재작성 — `_tickSpeed` 본문(230-275), `_vPrev~_vCurPos` 필드(73-75)·시프트(333-334),
`_onPosition`의 `_speedKmh = _moving ? d*3.6 : 0`(336-341) 산출식.
유지/연동 — `_posBuffer` 군집(306-321) → ZUPT 트리거, 도플러 `d`(304) → update 입력.

---

## 5. IMU 인입 지점 후보 (C, D)

- **예측(predict):** 현 200ms ticker 자리(`_tickSpeed`, 230 / 기동 225)를 칼만 predict로 교체,
  또는 sensors_plus 가속도 스트림 콜백에서 predict. dt는 **수신시각 기반**(코드가 pos.timestamp 불신, 74 주석) 유지.
- **보정(update, GPS):** `_onPosition` 내 도플러 `d` 산출 직후(304-334) → 칼만 update(z=d).
- **보정(update, ZUPT):** parked/`_moving=false` 판정 지점(320, 323-329) → 칼만 update(z=0).
- **표시:** `_speedKmh`에 칼만 추정 속도 대입 → 기존 `_Speedometer`(937, 1110-1112) 그대로 렌더.
  `_firstFixReceived`(68, 297·340 set)·"GPS 검색 중" blink(1085, 1106-1126) 로직 변경 불필요.

### C-9 / B-11. 칼만 후에도 유지돼야 할 `_speedKmh` 의존부 (위치만, 수정 대상 아님)
- bearing 게이트: `pos.heading >= 0 && _speedKmh > 2.0 && _styleLoaded`(349).
- 속도→줌: `_zoomForSpeed(_speedKmh)`(646-650), 호출 `_recenter`(654).
- 적응 throttle 분기: `_speedKmh <= 10.0`(289).
→ 모두 `_speedKmh` 값에만 의존하므로, 칼만이 같은 필드를 채우면 무수정 동작.

---

## 6. 미확인 항목 + 구현 턴 결정사항

- **미확인:** DESIGN_speed_kalman.md 부재 → 상태벡터 구성(속도 단일 vs 속도+가속바이어스),
  프로세스/측정 노이즈(Q,R) 값, 1D vs 헤딩투영 2D 여부 — 설계 미정.
- **미확인:** 디바이스 가속도 → 진행방향 투영 방법(센서는 디바이스 프레임, 중력제거+heading 투영 필요).
  현 코드에 관련 처리 전무.
- **결정 필요:** sensors_plus 신규 추가(버전), predict 주기(현 200ms 유지 여부),
  staleness 폴백·적응 throttle 존치 여부, ZUPT를 의사측정으로 흡수할지 게이트로 남길지.
- **주(범위 외):** `lib/screens/driving_screen.dart`(`_speedKmh` 39행, raw `pos.speed`만 사용 105-111)는
  **미사용 레거시** — 인스턴스화 지점 없음. 활성 경로는 `main_map_screen.dart:651`의 `NavScreen`.
  칼만은 NavScreen에만 적용. driving_screen은 본 RECON 대상 아님.
