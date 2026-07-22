# RECON_PIN (원형→물방울 핀 마커)

## 1. maplibre_gl 패키지 내 핀 에셋 실존 여부

- **패키지 lib/ 내 PNG/SVG**: **없음**
  - `find "$ML" -iname "*.png"` → 결과 없음
  - `find "$ML" -type d -iname "assets" -o -iname "images"` → 결과 없음
  - 패키지 루트에 이미지 파일 전혀 없음 (Dart/Android/iOS 소스파일만 존재)
- **example 앱 에셋**: **없음**
  - `ls "$ML/example/assets"` → 결과 없음 (example 디렉터리에 assets 폴더 자체 없음)
- **결론**: 패키지 `maplibre_gl-0.26.1`은 **물방울 핀 공식 에셋을 번들로 제공하지 않는다. NO.**
  - 패키지는 API(Dart 코드)만 제공. 아이콘 이미지는 소비자 앱이 직접 공급해야 함.

---

## 2. 심볼 아이콘의 출처 구조

- **`SymbolOptions.iconImage`가 참조하는 것**:
  - `layer_properties.dart:348` 주석: `"Name of image in sprite to use for drawing an image background."`
  - 즉 **지도 스타일의 sprite에 등록된 이름** 또는 **`addImage(name, bytes)`로 앱이 런타임에 등록한 이름** 두 가지.
  - `controller.dart:1623` 주석: "This allows you to add an image to the currently displayed style once, and from there on refer to it e.g. in the `Symbol.iconImage`"
- **'공식 아이콘'은 패키지 소관인가 지도 스타일 소관인가**:
  - **지도 스타일 소관**(sprite URL) 또는 **앱 소관**(`addImage`로 직접 등록).
  - 패키지 자체는 아이콘 이미지를 전혀 소유하지 않는다.

---

## 3. 현재 지도 스타일의 sprite

- **스타일 파일/URL 위치**:
  - `main_map_screen.dart:734`: `styleString: 'assets/images/osm_liberty_yurunavi.json'`
  - 로컬 asset 파일: `/data/projects/yurunavi/assets/images/osm_liberty_yurunavi.json`
- **sprite 항목**:
  ```json
  "sprite": "https://maputnik.github.io/osm-liberty/sprites/osm-liberty"
  ```
  - **원격 URL** — 로컬 사본 없음. 런타임에 네트워크로 로드.
- **sprite 내 핀/마커류 아이콘 이름**:
  - sprite JSON 파일이 로컬에 없어 키 목록 직접 확인 불가.
  - 스타일 파일 내 `icon-image` 사용 이름들: `"arrow"`, `"{class}"`, `"default_{ref_length}"`, match 식 등 — **"marker"/"pin"/"location"/"teardrop" 류 이름 없음**.
  - osm-liberty sprite는 도로 화살표·POI 분류 아이콘 위주. 물방울 핀은 **포함 가능성 낮음** (미확인, 네트워크 접근 필요).
- **타일서버 sprite**: `/data/tiles/data/config.json`에 sprite 항목 없음. tileserver-gl은 fonts만 서브.

---

## 4. 현재 마커 코드 구조 (전환 시 수정 지점)

### 관련 필드/상수 (line)
| 항목 | 라인 | 내용 |
|------|------|------|
| `ml.Circle? _locMarker` | 88 | 현위치 마커 핸들 |
| `ml.Circle? _destMarker` | 89 | 목적지 마커 핸들 |
| `_kLocColor = '#00C853'` | 90 | 현위치 색상 (녹색) |
| `_kDestColor = '#E53935'` | 91 | 목적지 색상 (적색) |

### 생성 (addCircle)
| 메서드 | 라인 | 호출처 |
|--------|------|--------|
| `_ensureLocationMarker()` | 275-293 | onStyleLoadedCallback:753, _lastKnown setState:168, _origin setState:188 |
| `_ensureDestMarker(dest)` | 294-309 | `_applyDestination`:495 |

**addCircle 파라미터 현황** (두 마커 공통):
```dart
circleRadius: 8, circleColor: _kLocColor/_kDestColor,
circleStrokeWidth: 3, circleStrokeColor: '#FFFFFF'
```
- `updateCircle` 호출 시: `CircleOptions(geometry: geo)` 만 전달 (위치 갱신 전용)

### 업데이트 (updateCircle)
- `_ensureLocationMarker:290`: `c.updateCircle(_locMarker!, CircleOptions(geometry: geo))`
- `_ensureDestMarker:307`: `c.updateCircle(_destMarker!, CircleOptions(geometry: geo))`

### 제거 (removeCircle)
- `_removeDestMarker()` line 311-316: `c.removeCircle(_destMarker!)` → `_destMarker = null`
- `_locMarker`는 명시적 제거 없음 (앱 생존기간 동안 유지)

---

## 5. addSymbol/addImage/SymbolOptions 실시그니처

### `addImage` (controller.dart:1656)
```dart
Future<void> addImage(String name, Uint8List bytes, [bool sdf = false])
```
- `name`: 이후 `SymbolOptions.iconImage`에서 참조할 문자열 키
- `bytes`: PNG 바이트 (`Uint8List`)
- `sdf`: true면 SDF 이미지 (런타임 색상 변경 가능)
- **호출 시점 제약**: `onStyleLoadedCallback` 이후에만 가능. 스타일 재로드 시 재등록 필요.

### `addSymbol` (controller.dart:1123)
```dart
Future<Symbol> addSymbol(SymbolOptions options, [Map<String, dynamic>? data])
```

### `updateSymbol` (controller.dart:1172)
```dart
Future<void> updateSymbol(Symbol symbol, SymbolOptions changes)
```

### `removeSymbol` (controller.dart:1200)
```dart
Future<void> removeSymbol(Symbol symbol)
```

### `SymbolOptions` (maplibre_gl_platform_interface-0.26.1/lib/src/symbol.dart)
```dart
const SymbolOptions({
  double? iconSize,
  String? iconImage,    // ★ addImage로 등록한 name 또는 sprite 키
  double? iconRotate,
  Offset? iconOffset,
  String? iconAnchor,  // "bottom","top","center" 등
  List<String>? fontNames,
  String? textField,
  double? textSize,
  // ... 텍스트 관련 다수
  double? iconOpacity,
  String? iconColor,   // SDF일 때만 유효
  // ...
  LatLng? geometry,
  int? zIndex,
  bool? draggable,
})
static const SymbolOptions defaultOptions = SymbolOptions();
```
**중요**: `iconColor`는 **SDF 이미지에만 유효**. 일반 PNG는 `addImage`에서 `sdf=false`이므로 색상 변경 불가 — 색상별(녹색/적색) 핀이 필요하면 **PNG 2개** 별도 준비 또는 **SDF 1개**로 처리.

### `addSymbolLayer` (controller.dart:611)
```dart
Future<void> addSymbolLayer(String sourceId, String layerId,
    SymbolLayerProperties properties, {
  String? belowLayerId, String? sourceLayer,
  double? minzoom, double? maxzoom,
  dynamic filter, bool enableInteraction = true,
})
```

---

## 6. 결론 — '공식 에셋' 현실 판정 + 구현 경로 옵션

### maplibre_gl 공식 에셋만으로 물방울 핀이 실제 가능한가?
**NO.** 패키지에 번들 에셋 없음. osm-liberty sprite에 핀 아이콘 있는지 미확인(원격). 어느 경우도 "패키지가 제공하는 공식 물방울 핀"은 **존재하지 않는다.**

### 가능한 경로들 (실제로 존재하는 API 기반)

**경로1: `addCircle` 유지 + CircleOptions 시각 개선 (현상유지 변형)**
- 현재 원형 마커를 그대로 두되, radius/stroke/color만 조정 → "물방울"은 아니지만 핀처럼 보이는 원 마커
- 작업량: 매우 적음 (3줄 파라미터 변경)
- 회귀위험: 없음
- 에셋: 불필요
- 한계: 물방울 모양 불가능 (원만 지원)

**경로2: 앱 자체 PNG를 `assets/images/`에 추가 → `addImage` + `addSymbol`로 전환**
- `assets/images/pin_green.png`, `assets/images/pin_red.png` 작성 (자체 제작)
- `pubspec.yaml`에 이미 `assets/images/` 등록됨 → 추가 파일만 넣으면 됨
- `onStyleLoadedCallback`에서:
  ```dart
  final bytes = await rootBundle.load('assets/images/pin_green.png');
  await c.addImage('pin_green', bytes.buffer.asUint8List());
  ```
- `addSymbol(SymbolOptions(geometry: geo, iconImage: 'pin_green', iconAnchor: 'bottom'))`
- `_locMarker`/`_destMarker` 타입을 `ml.Circle?` → `ml.Symbol?`로 교체
- 작업량: 중간 (PNG 2개 준비 필수, 마커 타입·메서드 전면 교체)
- 회귀위험: 중간 (updateSymbol/removeSymbol 패턴 확인 필요)
- 에셋출처: **자체 제작 PNG** — 마스터 요구 "자작 PNG 금지"와 충돌할 수 있음 → **마스터 확인 필요**

**경로3: SDF PNG 1개 `addImage(name, bytes, sdf=true)` → iconColor로 색상 분기**
- SDF(Signed Distance Field) PNG 1개로 핀 모양 정의
- `addSymbol(..., iconImage: 'pin_sdf', iconColor: '#00C853')`로 녹색
- `addSymbol(..., iconImage: 'pin_sdf', iconColor: '#E53935')`로 적색
- 작업량: 경로2와 동일 + SDF PNG 제작 지식 필요
- 에셋출처: **자체 제작 SDF PNG** — 역시 마스터 "자작 PNG 금지" 충돌 가능

**경로4: osm-liberty sprite 내 기존 아이콘 이름 사용 (조건부)**
- `SymbolOptions(iconImage: '스프라이트_내_이름')` — addImage 없이 바로 사용 가능
- 단, sprite에 물방울 핀류 이름이 실제로 있는지 **미확인**
- 확인 방법: `curl https://maputnik.github.io/osm-liberty/sprites/osm-liberty.json` 키 목록 조회
- 있어도 색상/모양이 osm-liberty 스타일에 종속 → 마음대로 커스텀 불가
- 작업량: 확인 후 결정 (최소 or 불가)

### 각 경로 비교

| 경로 | 물방울 모양 | 자작 에셋 | 작업량 | 회귀위험 |
|------|------------|----------|--------|---------|
| 1: 원 개선 | NO | 불필요 | 최소 | 없음 |
| 2: PNG+Symbol | YES | PNG 2개 필요 | 중간 | 중간 |
| 3: SDF PNG | YES | SDF 1개 필요 | 중간 | 중간 |
| 4: sprite 기존 아이콘 | 조건부 | 불필요 | 최소(확인후) | 낮음 |

### 마스터 확인 필요한 결정사항

1. **"자작 PNG 금지"의 범위**: 앱 번들 assets로 넣는 자체 제작 PNG도 금지인가? 아니면 "외부 다운로드 금지"만인가?
   - 만약 앱 내 자체 PNG 허용 → 경로2(or 3) 진행 가능
   - 완전 금지 → 경로4(sprite 확인 후) 또는 경로1만 가능

2. **물방울 모양이 필수인가?** addCircle 원형 마커로 대체 가능하다면 경로1로 즉시 개선 가능.

3. **경로4 sprite 확인 필요**: 네트워크 접근 가능한 환경(폰/노트북)에서 `curl https://maputnik.github.io/osm-liberty/sprites/osm-liberty.json | python3 -m json.tool | grep -i "marker\|pin\|poi\|location"` 로 키 목록 확인 후 판단.

### 미확인/리스크

1. osm-liberty sprite에 핀 아이콘이 있는지 **미확인** (원격 JSON 접근 필요)
2. `addSymbol`로 전환 시 `_locMarker` 타입 변경 (`Circle?` → `Symbol?`) — `updateSymbol`이 `updateCircle`과 동일하게 geometry만 갱신 가능한지 API 동작 확인 필요
3. `addImage`는 스타일 재로드 시 재등록 필요 — 현재 앱에서 스타일 재로드 시나리오 있는지 확인 필요 (현재 코드에서는 1회 로드로 보임, 문제 없을 듯)
4. `symbolManager` 초기화 타이밍: `addSymbol`은 `_ensureManagerInitialized(symbolManager)` 체크 — circle처럼 `onStyleLoadedCallback` 이후에만 사용 가능 (동일)
