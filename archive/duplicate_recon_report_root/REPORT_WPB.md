# REPORT_WPB — 경로B 비활성 (경유지 버튼 제거) 보고

## 0단계 판정

| 항목 | 결과 |
|------|------|
| 제거 대상 라인 | `if (!_waypointAddedAtTouch) _FloatingActionLabel('경유지 추가', ...)` (line 877-890) + `if (!_waypointAddedAtTouch) SizedBox(width: 10)` (line 891-892) |
| `_waypointAddedAtTouch` dead 여부 | **완전 dead** — 버튼 제거 후 line 119(선언), 887(onTap), 877/891(조건) 모두 소멸 |
| line 410 setState | `_waypointAddedAtTouch = false;` 한 줄만 dead — setState 블록 자체는 `_touchPoint`·`_touchDistKm` 갱신용으로 보존 |
| 보존한 목적지 버튼 | `_FloatingActionLabel(label: '목적지', ...)` (LAYER 6 내) — 정상 보존 |
| 경로A 경계 | line 385-413 (addWaypoint, _fetchAndStoreAllRoutes) — 완전 무변경 |

---

## 제거 diff

### [제거 1+2] 경유지 버튼 + SizedBox 블록

```dart
// BEFORE (line 875-892):
children: [
  // 같은 지점에 경유지가 이미 추가됐으면 버튼 숨김 (버그 수정)
  if (!_waypointAddedAtTouch)
  _FloatingActionLabel(
    label: '경유지 추가',
    color: const Color(0xFFFFB300),
    onTap: () {
      if (_touchPoint != null) {
        ref.read(mapInteractionProvider.notifier).setWaypoint(_touchPoint!);
        setState(() => _waypointAddedAtTouch = true);
      }
    },
  ),
  if (!_waypointAddedAtTouch)
  const SizedBox(width: 10),
  _FloatingActionLabel(   // ← 목적지 버튼 시작

// AFTER:
children: [
  _FloatingActionLabel(   // ← 목적지 버튼만 남음
```

### [dead code 정리 1] 필드 선언 제거
```dart
// BEFORE (line 119):
bool _waypointAddedAtTouch = false; // 같은 터치 지점에 경유지 추가됐으면 true

// AFTER: 해당 줄 제거
```

### [dead code 정리 2] setState 내 한 줄 제거
```dart
// BEFORE (line 406-410):
setState(() {
  _touchPoint = tapped;
  _touchDistKm = _haversineKm(origin, tapped);
  _waypointAddedAtTouch = false; // 새 탭 → 경유지 버튼 다시 표시  ← 제거
});

// AFTER:
setState(() {
  _touchPoint = tapped;
  _touchDistKm = _haversineKm(origin, tapped);
});
```

### 보존 확인
- `경유지 추가` 시트 ListTile (line 443): 경로A, **보존**
- `addWaypoint(tapped)` (line 390): 경로A, **보존**
- provider `setWaypoint`/`addWaypoint`/`removeWaypoint` 정의: **보존**
- LAYER 6 `_FloatingActionLabel(label: '목적지')`: **보존**

---

## analyze · build 결과
- `flutter analyze`: **No issues found!**
- `flutter build apk --debug`: **✓ Built app-debug.apk** (Gradle 10.2s)

---

## 폰 실측 체크리스트

- [ ] 목적지 미확정(빈 지도) 상태에서 탭 → '경유지 추가' 버튼 더 이상 안 뜸
- [ ] 같은 상태에서 '목적지' 버튼만 표시, 탭 시 목적지 확정 정상 (회귀 없음)
- [ ] 목적지 확정 후 경로 표시 중 탭 → 시트에 '경유지 추가' 항목 여전히 표시 (경로A 보존)
- [ ] 경로A로 경유지 추가 후 경로 재탐색 정상 (Valhalla waypoints 포함 재요청)
