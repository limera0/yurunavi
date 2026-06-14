# RECON: MapLibre 스타일 로딩 방식 (2026-06-08)

## 결론 요약

| 항목 | 값 |
|------|-----|
| 로딩 방식 | **asset 경로** (a) |
| styleString 값 | `'assets/images/osm_liberty_yurunavi.json'` |
| pubspec 등록 | `assets/images/` 디렉터리 통째로 등록 → **포함됨** |
| tiles source | `https://tiles.westinx.com/data/v3.json` (외부 URL) |
| glyphs | `https://tiles.westinx.com/fonts/{fontstack}/{range}.pbf` |
| sprite | `https://maputnik.github.io/osm-liberty/sprites/osm-liberty` |

## 근거 코드

```
lib/features/map/presentation/main_map_screen.dart:758
  ml.MapLibreMap(
    styleString: 'assets/images/osm_liberty_yurunavi.json',
```

```
pubspec.yaml:44-45
  assets:
    - assets/images/
```

```json
// assets/images/osm_liberty_yurunavi.json (일부)
"sources": {
  "openmaptiles": {
    "type": "vector",
    "url": "https://tiles.westinx.com/data/v3.json"
  },
  "natural_earth_shaded_relief": {
    "tiles": ["https://klokantech.github.io/naturalearthtiles/..."]
  }
},
"sprite": "https://maputnik.github.io/osm-liberty/sprites/osm-liberty",
"glyphs": "https://tiles.westinx.com/fonts/{fontstack}/{range}.pbf"
```

## 스타일 튜너 적용 가능성 판단

### URL 로딩 방식 사용 가능 여부
- **직접 http URL 전달도 가능** — MapLibre GL의 `styleString`은 asset 경로, http URL, 인라인 JSON 세 가지 모두 지원.
- 현재는 **asset 파일**을 사용하므로, 스타일 튜너가 파일 내용을 수정하거나 인라인 JSON으로 교체하는 방식이 가장 안전.

### 권장 방향 (판단용, 구현 아님)
1. **Asset 파일 직접 수정** — `osm_liberty_yurunavi.json`의 레이어 minzoom/filter 값만 조정. 빌드 필요, 서버 무관.
2. **인라인 JSON 주입** — `rootBundle.loadString`으로 읽어 Dart 객체로 파싱 후 수정 → `jsonEncode` → styleString에 전달. 런타임 튜닝 가능.
3. **외부 URL** — `tiles.westinx.com`이 TileJSON을 서브하므로, 스타일만 별도 URL로 호스팅하면 가능. 현재 인프라에서는 불필요.

### 현재 호스트 불일치 주의
- CLAUDE.md에는 `192.168.0.57:8080` (로컬 tileserver-gl)을 사용하라고 기재.
- 실제 style JSON에는 `tiles.westinx.com` (외부 호스트) 기재.
- **어느 쪽이 실제 운영 환경인지 다음 턴에 확인 필요.**

---
*정찰 전용. 코드 수정·빌드·커밋 없음.*
