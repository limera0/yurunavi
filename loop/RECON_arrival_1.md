# RECON_arrival.md — 도착/종료 버그 (증상A: 30m 전 조기종료 / 증상B: 통과 시 강제종료)

생성일: 2026-06-25
범위: lib/features/navigation/presentation/nav_screen.dart (코드 변경 0 — 읽기 전용 진단)
대상 화면 확정: **NavScreen** 가 유일한 활성 내비 화면. `main_map_screen.dart:670` 에서 `NavScreen(...)` push.
  → `lib/screens/driving_screen.dart` 는 레거시(라우팅 미연결, 무시).

---

## §A 도착 판정 파이프라인 (file:line)

```
_onPosition(pos)                      // GPS 1fix마다
  → _checkArrival(loc)                // nav_screen.dart:362  (매 fix 무조건 호출)
      → _distanceM(loc, dest) ≤ 30m?  // nav_screen.dart:548
          → _arrived = true           // nav_screen.dart:549
          → _vps?.speak('arrival')    // nav_screen.dart:550
          → _showArrivalDialog(pois)  // nav_screen.dart:552
              → 확인 버튼              // nav_screen.dart:660
                  → Navigator.pop()×2  // nav_screen.dart:662–663  ★내비 화면 자체 pop = 종료
```

### A1. 도착 상태/반경 상수

- `bool _arrived = false;` — **nav_screen.dart:91**
- `static const _kArrivalRadiusM = 30.0;` — **nav_screen.dart:92**

### A2. 판정 함수 전문 (nav_screen.dart:544–555)

```dart
void _checkArrival(LatLng loc) {
  if (_arrived) return;                         // 545  ← 한번 도착하면 영구 잠금(리셋 없음)
  final dest = widget.destination;
  if (dest == null) return;
  if (_distanceM(loc, dest) <= _kArrivalRadiusM) {  // 548 ← 목적지까지 '직선거리' 단일 조건
    _arrived = true;                            // 549
    _vps?.speak('arrival');                     // 550
    _fetchNearbyPois(dest).then((pois) {
      if (mounted) _showArrivalDialog(pois);    // 552
    });
  }
}
```

- `_distanceM` = 단순 Haversine 직선거리 (**nav_screen.dart:595**). 경로상 잔여거리·잔여 maneuver·진행방향 전혀 안 봄.

### A3. 종료 트리거 (nav_screen.dart:624–668)

- `barrierDismissible: false` — **nav_screen.dart:627** (다이얼로그 회피 불가)
- 본문 텍스트: "목적지에 도착했습니다.\n**내비게이션을 종료합니다.**" — **nav_screen.dart:640**
- '확인' 버튼 onPressed — **nav_screen.dart:661–664**:
  
  ```dart
  Navigator.of(ctx).pop();            // 662  다이얼로그 닫기
  if (mounted) Navigator.of(context).pop();  // 663  ★NavScreen 자체 pop → 내비 강제 종료
  ```

---

## §B 근본 원인 (증상별 1:1 매핑)

### 증상A — "목적지 30m 전인데 도착 처리, 좌회전 남았는데 끊김"

**원인: 도착 판정이 '목적지까지 직선거리 ≤ 30m' 단일 조건 (nav_screen.dart:548).**
경로상 잔여거리나 남은 maneuver(마지막 좌회전 등)를 보지 않음. 곡선/꺾임 경로에서
마지막 회전을 남겨둔 채 목적지에 직선으로 30m 이내로 근접하면 그 즉시 `_arrived=true`.
→ 안내 도중 종료. 30m 반경은 도심/골목에서 과하게 큼.

### 증상B — "목적지 지나쳐 되돌아가야 할 때도 칼같이 종료"

**원인: 통과(pass-through) 무방비 + 영구 잠금 (nav_screen.dart:545, 548).**
판정은 "한 번이라도 30m 안에 들어왔는가"만 본다. 진입/이탈 방향, 통과 여부 무시.
목적지를 스쳐 지나며 30m 안에 잠깐 들어오기만 해도 `_arrived=true` 확정되고,
`if (_arrived) return;`(545) 때문에 두 번 다시 해제 불가 → 즉시 종료 다이얼로그.

### 공통 — 종료가 '즉시·강제·정차무관'

판정과 동시에 다이얼로그가 뜨고 확인 1탭이면 `Navigator.pop`(663)으로 화면이 사라진다.
정차 여부, 안내 잔여 여부와 무관하게 끊긴다. (마스터 요구사항과 정반대)

---

## §C 마스터 해법에 재사용 가능한 기존 자산 (이미 존재 — 새로 만들 필요 없음)

마스터 설계: ①도착 시 상단 카드만 띄우고 안내 유지 → ②완전 정차 후에야 종료버튼 노출
→ ③종료버튼 10초 카운트다운(수동 즉시종료 or 10초 자동종료).

- **정차 판정 이미 구현됨**: `_calcParkState()` → `(parked, bufRadius, parkThresh)` — **nav_screen.dart:609**.
  posBuffer 군집반경 기반. `parked` 불리언을 그대로 ②조건에 쓸 수 있음.
- **이동 히스테리시스 상태**: `bool _moving` — **nav_screen.dart:77**, 갱신 **329–334**.
  `!_moving && parked` 조합으로 "완전 정차" 판정 가능.
- **속도**: `_speedKmh` (도플러 raw, 200ms 평활) — `_speedKmh == 0.0` 보조 조건 활용 가능.
- ⚠️ `_vps?.speak('arrival')`(550)도 현재 도착 확정 시 1회 발화. 새 설계에선
  발화 타이밍 재배치 필요(도착카드 시점 vs 최종 종료 시점 분리).

→ 즉 신규 알고리즘 = "도착 감지(카드)"와 "세션 종료"를 **분리**하고, 종료는 정차 게이트 뒤로 미루는 것.
  핵심 인프라(정차판정·속도)는 이미 다 있음. 추가 구현 부담 작음.

---

## §D 미해결/추가 확인 필요 (SPEC 작성 전 결정사항)

1. **조기종료 방지 기준**: 단순 반경 축소(예 30→15m)만으로는 증상A 잔여 maneuver 문제 미해결.
   "마지막 step 도달 + 목적지 근접" 복합조건이 더 정확. SPEC에서 도착판정 기준 재정의 필요.
   (참고: `_stepEndDistM` 누적거리 배열·`_stepIdx` 이미 존재 — nav_screen.dart:97~ / _updateStepByDistance)
2. **증상B 통과 재안내**: 통과 시 종료 대신 '경로이탈→재탐색'으로 흘려보낼지,
   아니면 도착카드만 띄우고 유지할지 마스터 정책 결정 필요.
3. **10초 카운트다운 UI 위치**: 상단 카드 영역 vs 별도 하단 버튼. (스타일 튜닝 영역과 연계)
4. **POI 조회(`_fetchNearbyPois`, Overpass) 타이밍**: 현재 도착 확정 즉시 호출. 카드 전환 시점으로 이동할지.

---

## 결론 (한 줄)

도착=종료가 한 덩어리로 묶여 있고(`_checkArrival`→`_showArrivalDialog`→`Navigator.pop`),
판정이 '직선 30m 1회 진입' 단일조건이라 증상A/B가 동시에 발생. 정차판정 인프라는 이미 있음.
**다음 단계: 이 RECON을 근거로 SPEC_arrival.md 작성(도착감지/종료 분리 + 정차게이트 + 10초 카운트다운).**
코드 변경은 SPEC 확정 후 별도 실행 턴에서.
