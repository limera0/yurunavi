# REPORT: 지도 언어 전환 플랜 B (스타일 JSON 재주입)
작성일: 2026-06-13 | 브랜치: feat/map-language

---

## [0] 게이트 결과

### 0-1. styleString raw JSON 지원 여부
`MapLibreMapController.java:301`:
```java
} else if (styleString.startsWith("{") || styleString.startsWith("[")) {
  mapLibreMap.setStyle(new Style.Builder().fromJson(styleString), onStyleLoadedCallback);
}
```
**YES** — `{` 로 시작하는 문자열을 raw JSON으로 분기 처리. asset 경로와 완전히 구분됨.

### 0-2. didUpdateWidget → styleString 변경 시 스타일 재로딩 여부
흐름:
1. `maplibre_map.dart:370` `didUpdateWidget` → `_maplibreMapOptions.updatesMap(newOptions)`
2. styleString이 변경되면 updates map에 포함 → `_updateOptions(updates)`
3. `controller._updateMapOptions(updates)` → platform channel `map#update`
4. Android `Convert.interpretMapLibreMapOptions` → `sink.setStyleString()`
5. `MapLibreMapController.java:286` `setStyleString()` → `mapLibreMap.setStyle(fromJson(...), onStyleLoadedCallback)`

**YES** — `setState(() => _styleJson = ...)` 호출 시 MapLibreMap 위젯 재생성 없이 네이티브 스타일만 교체. `onStyleLoadedCallback` 재실행, 카메라 위치 유지.

### 0-3. 스타일 JSON URL 절대경로 확인
| 필드 | 값 |
|---|---|
| `glyphs` | `https://tiles.westinx.com/fonts/{fontstack}/{range}.pbf` |
| `sprite` | `https://tiles.westinx.com/styles/osm-bright/sprite` |
| `sources.openmaptiles.url` | `https://tiles.westinx.com/data/v3.json` |

**전부 절대 HTTPS URL** — 인라인 JSON에서 정상 동작. PASS.

### 0-4. 전환 메커니즘 결정
0-2가 YES → **`setState`로 `_styleJson` 갱신. `ValueKey` 불필요. 카메라 유지.**

---

## 실제 사용 API

α와 달리 `setLayerProperties` 미사용. 대신:
```dart
// initState에서 1회 로드
final raw = await rootBundle.loadString('assets/images/osm_liberty_yurunavi.json');
setState(() {
  _rawStyle = raw;
  _styleJson = applyMapLanguageToStyle(raw, _debugLang);
});

// 언어 전환 시
void _applyMapLanguage(MapLanguage l) {
  setState(() {
    _debugLang = l;
    _styleJson = applyMapLanguageToStyle(_rawStyle!, l);
  });
}

// MapLibreMap에 주입
ml.MapLibreMap(styleString: _styleJson!, ...)
```

`applyMapLanguageToStyle`은 23개 레이어의 `layout.text-field`만 교체.
`text-color`, `text-size`, `text-halo-*`, `symbol-placement` 등 나머지는 JSON 원본 그대로.

---

## 커밋 해시

| 단계 | 해시 | 메시지 |
|---|---|---|
| 체크포인트 | `e005079` | checkpoint: before plan-B style re-injection |
| 커밋 1 | `e4bfbba` | feat(map): add applyMapLanguageToStyle |
| 커밋 2 | `50a619c` | refactor(map): switch language mechanism to style re-injection |

---

## 빌드 결과

```
flutter analyze → No issues found! (ran in 1.5s)
flutter build apk --debug → ✓ Built build/app/outputs/flutter-apk/app-debug.apk (215M)
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`

---

## 폰 검증 절차

```
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### ① 앱 실행 직후 (한국어 모드 기본값)
- 지도 라벨이 **한글 단일 표기** (영어 병기 없음)
- 텍스트 색상, halo, 도로명 정렬(symbol-placement), 크기 **모두 정상**
- 좌하단 `라벨: 한국어` 버튼 표시 확인

### ② 버튼 탭 → English 전환
- 짧은 재로딩 깜빡임 발생 (정상 — α와 달리 속성 깨짐이 아님)
- 라벨이 **로마자 단일 표기**로 변경
- 텍스트 색상·halo·크기 **α와 달리 정상 유지** ← 핵심 검증 포인트
- 버튼 라벨 `라벨: English` 로 업데이트

### ③ 다시 탭 → 한국어 복귀
- 라벨이 **한글 단일 표기**로 복귀
- 스타일 속성 여전히 정상

### ④ 깜빡임 허용 기준
- 전환 시 짧은 흰 화면/재로딩 — **정상 (버그 아님)**
- 전환 후 카메라 위치 이동 없음 확인

### ⑤ logcat 확인
```powershell
adb logcat -d | Select-String -Pattern "MapLibre|style|exception|Error"
```
→ style 로딩 성공 로그 확인, exception 없어야 통과.
