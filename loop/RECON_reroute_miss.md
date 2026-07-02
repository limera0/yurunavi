# RECON — YNAV_REROUTE 로그 0줄 원인 규명

날짜: 2026-06-30  
브랜치: feat/ic-early-guidance  
커밋 기준: offset 커밋 fdb2414 포함 확정

---

## 앵커 5개

### 1. 'YNAV_GUIDE reroute' 로그 위치 및 호출 경로

`lib/features/navigation/presentation/nav_screen.dart:310`

```dart
debugPrint('YNAV_GUIDE reroute steps=${_steps.length} first=...');
```

호출 경로:  
`prog.offRoute` (line 230) → `_triggerReroute()` (line 231) → 3s debounce Timer (line 279) → `_reroute(current)` (line 282) → **line 310**

---

### 2. nav_screen.dart:291-298 전체 인용 및 래퍼 함수

`lib/features/navigation/presentation/nav_screen.dart:286-298`  
래퍼: `Future<void> _reroute(LatLng origin)` (line 286)

```dart
286  Future<void> _reroute(LatLng origin) async {
287    if (_isRerouting || !mounted) return;
288    final dest = widget.destination;
289    if (dest == null) return;
290    setState(() => _isRerouting = true);
291    final navState = ref.read(navStateProvider);
292    final heading = (navState != null && navState.speedKmh > 2) ? navState.headingDeg : null;
293    final off = offsetOrigin(origin.latitude, origin.longitude, heading, 40);
294    final routeOrigin = LatLng(off.lat, off.lng);
295    developer.log('YNAV_REROUTE off origin hdg=$heading d=40', name: 'NavScreen');
```

1번(YNAV_GUIDE reroute)과 **동일한** 함수 `_reroute()` 내부. 같은 경로.

---

### 3. 'YNAV_REROUTE off origin' 로그는 게이트 **밖**

`lib/features/navigation/presentation/nav_screen.dart:292,295`

```dart
292    final heading = (navState != null && navState.speedKmh > 2) ? navState.headingDeg : null;  // 게이트: heading 값 결정
295    developer.log('YNAV_REROUTE off origin hdg=$heading d=40', name: 'NavScreen');             // 무조건 실행
```

line 292 게이트는 `heading`의 **값**만 결정(null vs 실제값). line 295 로그는 조건문 없이 항상 실행.  
즉 `_reroute()`가 line 289를 통과하면 line 295는 **반드시** 실행된다.  
→ 로그가 0줄이라면 `_reroute()`가 아예 진입하지 못했거나, 출력이 다른 채널로 사라진 것.

---

### 4. 오프루트 자동 재탐색 트리거와 offset 적용 경로 — **동일 함수, 그러나 이중 guard 존재**

`lib/features/navigation/presentation/nav_screen.dart:277-284`

```dart
277  void _triggerReroute() {
278    if (_isRerouting) return;                     // guard 1: 진행 중이면 타이머도 안 만듦
279    _offRouteDebounce ??= Timer(..., () {
280      _offRouteDebounce = null;
281      final current = ref.read(navStateProvider)?.pos;
282      if (current != null) _reroute(current);     // guard 2: pos null이면 호출 안 함
283    });
284  }
```

- offset 코드와 트리거가 동일 함수(`_reroute`)를 씀 → 배선 이중화 문제는 없음
- **그러나** line 278: `_isRerouting = true` 상태에서 오면 debounce timer 자체가 생성 안 됨
- line 282: `navState.pos` null이면 `_reroute()` 호출 자체가 생략됨

---

### 5. navState.heading 출처 및 null 가능성

출처: `lib/features/navigation/providers/nav_state_provider.dart` (agent 탐색 기준 line 144)

```dart
_headingDeg = pos.heading >= 0 ? pos.heading : null;
```

재탐색 시점 null 가능 경로 두 가지:
1. GPS `pos.heading < 0` (무효값) → `headingDeg = null`
2. `speedKmh ≤ 2` (line 292 gate) → heading이 있어도 코드 내에서 null로 취급

heading null = offset 미적용(raw origin 그대로). 하지만 이건 offset 효과 없음이지 **로그가 0줄인 이유가 아님**.

---

## 원인 단정

> **`developer.log('...', name: 'NavScreen')` (line 295)는 Android logcat에서 태그 `NavScreen`으로 출력되며, `debugPrint` 기반 `flutter` 태그 스트림에 나타나지 않는다. `adb logcat -s flutter` 또는 `flutter run` 표준 출력 필터링 시 이 로그는 완전히 누락되므로 코드는 실행됐지만 0줄로 보인다.**

보조 후보 (배제 불가): `_triggerReroute` line 278 guard — 첫 번째 재탐색이 진행 중(`_isRerouting=true`)일 때 오프루트가 다시 발생하면 debounce timer 자체가 생성되지 않아 `_reroute()` 미호출. finally block(line 322)이 `!mounted`로 실행 안 될 경우 `_isRerouting`이 true로 고착.

---

## 수정 슬라이스 제안

**Option A (확인 우선):** line 295를 `debugPrint`로 교체 또는 복제 — 동일 flutter 태그 스트림으로 합류시켜 다음 라이딩에서 로그 수집 확인.

```dart
// before
developer.log('YNAV_REROUTE off origin hdg=$heading d=40', name: 'NavScreen');
// after
debugPrint('YNAV_REROUTE off origin hdg=$heading d=40');
```

**Option B (guard 안정화):** `_isRerouting` 고착 방지 — finally를 `WidgetsBinding.addPostFrameCallback` 래핑으로 unmounted 시에도 flag 리셋 보장.

Option A 먼저 적용 후 로그 재수집 → 여전히 0줄이면 Option B로 이동.
