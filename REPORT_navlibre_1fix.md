# REPORT: nav_screen MapLibre 커밋 ① 핫픽스

커밋: 0f2672f  
날짜: 2026-06-09  
브랜치: feat/maplibre-migration

---

## 0단계 사전검증

- `IgnorePointer(FlutterMap(...))` 블록: line 581
- `MapOptions(` 시작: line 583
- `backgroundColor` 기존 미존재 ✅ (예상대로)

---

## 변경 내용 (1줄)

```dart
// lib/features/navigation/presentation/nav_screen.dart:584
options: MapOptions(
+   backgroundColor: Colors.transparent, // MapLibreMap이 보이도록
    initialCenter: _currentPos ?? _kInitialMapView,
```

**근거**: `flutter_map-8.2.2` `MapOptions.backgroundColor` 기본값 `Color(0xFFE0E0E0)`. `FlutterMap` 내부 `widget.dart:88`에서 `ColoredBox(color: backgroundColor)`를 렌더하므로, 불투명 회색 박스가 아래 MapLibreMap을 완전히 가렸다. `Colors.transparent`로 교체하면 MapLibreMap이 노출된다.

---

## 검증

```
flutter analyze  →  No issues found! (1.5s)
flutter build apk --debug  →  ✓ Built app-debug.apk  (11.1s)
```

---

## 폰 실측 가이드 (마스터 직접)

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

| 확인 항목 | 기대 결과 |
|---|---|
| ① 내비 진입 후 지도 | 회색 사라짐, osm_liberty 스타일 타일 표시 |
| ② 경로/마커 | 임시 오버레이로 보임 (위치 어긋남 허용) |
| ③ 수동 드래그 | 10초 후 현위치 복귀 배너 + 재센터링 |
| ④ 주행 시 회전 | 진행방향으로 지도 bearing 회전 (heading 부호 역전 없음) |
