# REPORT: 내비 화면 현위치 초록점 이식

날짜: 2026-06-12

---

## 홈 화면(main_map_screen) 방식

`ml.Circle` 기반 addCircle/updateCircle 패턴.
- `ml.Circle? _locMarker` 필드로 인스턴스 보유
- `_ensureLocationMarker()`: styleLoaded 가드 → null이면 addCircle(create), 아니면 updateCircle(위치만 갱신)
- CircleOptions: radius=8, color='#00C853', strokeWidth=3, strokeColor='#FFFFFF'
- 호출 시점: GPS 스트림 fix 수신 + onStyleLoaded 완료 시

---

## 이식 내용 (nav_screen.dart)

### 추가 필드
```dart
ml.Circle? _locMarker;
static const String _kLocColor = '#00C853';
```

### 추가 메서드
`_ensureLocationMarker()` — 홈 화면과 완전 동일한 구조:
- styleLoaded 가드 + `_currentPos` null 가드
- `_locMarker == null` → addCircle, 아니면 updateCircle(geometry only)

### _onStyleLoaded 수정
`_initRouteLayer().whenComplete()` 블록 내에 `_ensureLocationMarker()` 호출 추가.
(기존 주석 "③ Circle/Symbol 마커 초기화는 커밋 ③에서 추가" 제거)

### _onPosition 수정
두 setState 경로 모두에 `_ensureLocationMarker()` 호출 추가:
- 적응 throttle 조기 반환 경로 (elapsedMs < intervalMs → return 직전)
- 전체 처리 경로 (setState 후)

---

## 갱신 방식

GPS fix 마다 `_onPosition` → `setState(_currentPos = loc)` → `_ensureLocationMarker()`(unawaited)
→ `updateCircle(geometry: _toMl(loc))` 호출. 레이어 재생성 없음.

---

## 제거한 잔재

FlutterMap 오버레이(임시 ②③ 주석 블록)의 MarkerLayer에서 현위치 원 제거:

```dart
// 제거됨:
if (_currentPos != null)
  Marker(
    point: _currentPos!,
    width: 24, height: 24,
    child: Container(
      decoration: BoxDecoration(
        color: cs.tertiary,      // ← 홈 화면과 다른 색
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        ...
      ),
    ),
  ),
```

FlutterMap 오버레이의 경유지(waypoints) / 목적지 마커는 유지.
(해당 마커들은 이번 범위 아님 — ③ 커밋에서 MapLibre Symbol로 교체 예정)

---

## 빌드 결과

```
flutter analyze: warning 1건 (기존 unused_shown_name — 변화 없음)
flutter build apk --debug: ✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

---

## 사용자 확인 체크리스트

- [ ] 내비 화면에 현위치 초록점(#00C853)이 홈 화면처럼 보이는가
- [ ] GPS 갱신 시 점이 따라 움직이는가
- [ ] 기존 경로선/카메라/속도계/새 지도스타일 회귀 없는가
