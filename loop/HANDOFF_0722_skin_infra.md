# HANDOFF — 스킨 시스템 + 인프라 추상화 (2026-07-22)

이 파일을 읽는 Claude는 아래 계획을 순서대로 실행한다.
**코딩 전에 반드시 이 파일 전체를 읽어라.**

---

## 배경 및 목적

마스터가 8번(브랜드 방향성 확정)을 기다리는 동안 11번(하드코딩 스타일 리팩터)을
선행하기 위해, 게임의 스킨 구조를 도입한다.

```
기능(Flutter)
      │
      ├── ThemeData / Color / Typography / Icons / Animation / Widget Style
      │
      ▼
Skin Package (번들 or 다운로드)
      │
      ▼
사용자가 적용 → 추후 유료 스킨 수익화
```

**동시 목적**: AWS 등 인프라 이전 시 코드 변경이 최소화되도록
서버 URL 등 모든 하드코딩 값을 추상화한다.

**브랜치**: `verify/ride-0711` (현재 브랜치 그대로 작업)

---

## 현황 (정찰 완료, 2026-07-22)

### 하드코딩 핫스팟
| 파일 | 건수 |
|------|------|
| `main_map_screen.dart` | ~117건 Color+TextStyle |
| `profile_screen.dart` | ~44건 |
| `nav_screen.dart` | ~43건 |
| `daylight_bar.dart` | ~10건 |

- 브랜드 틸 `Color(0xFF008080)`: **27곳** 직접 박힘
- `TextStyle(...)` 인라인: 116건 / 15파일
- 애니메이션 ms 하드코딩: `600ms`, `700ms` 등 5파일

### 서버 URL 하드코딩 (5파일)
| URL | 파일 |
|-----|------|
| `https://valhalla.westinx.com` | `routing_service.dart` (4곳) |
| `https://navi.westinx.com` | `native_engine.dart` |
| POI 백엔드 | `poi_service.dart` |
| 주소검색 백엔드 | `address_search_service.dart` |
| 타일서버(주석) | `poi_icon_renderer.dart` |

### 기존 구조 (활용 가능)
- `lib/core/theme/app_theme.dart`: `AppColors`, `AppTextStyles`, `NightModeColors`, `RiderModeColors` 이미 정의됨
- `lib/core/theme/palette.dart` / `typography.dart` / `spacing.dart`: 스켈레톤 인터페이스 있음(미연결)
- `lib/core/theme/app_theme_selector.dart`: 준비됨(미적용)
- `MaterialApp`에서 `AppTheme.light/night/rider` 3종 이미 전환 중

---

## 목표 디렉터리 구조

```
lib/core/
  ├── config/
  │     └── app_config.dart          ← 서버 URL 전부 집결
  └── skin/
        ├── skin.dart                ← 스킨 계약 (abstract interface)
        ├── skin_provider.dart       ← Riverpod, 런타임 스킨 전환 + 영속
        ├── skins/
        │     ├── default_skin.dart  ← 현재 디자인값 그대로 이식
        │     └── (추후 paid skins)
        └── loader/
              └── skin_loader.dart  ← JSON manifest 파싱 → AppSkin 인스턴스
```

---

## Phase별 세부 명세

### Phase 0 — 인프라 Config 추상화

**파일**: `lib/core/config/app_config.dart`

```dart
abstract class AppConfig {
  static AppConfig get instance => _instance;
  static late AppConfig _instance;
  static void init(AppConfig cfg) => _instance = cfg;

  String get valhallaBaseUrl;
  String get tileBaseUrl;
  String get naviBaseUrl;
  String get poiBaseUrl;
  String get addressBaseUrl;
}

class ProdConfig implements AppConfig {
  const ProdConfig();
  @override String get valhallaBaseUrl => 'https://valhalla.westinx.com';
  @override String get tileBaseUrl     => 'https://tiles.westinx.com';
  @override String get naviBaseUrl     => 'https://navi.westinx.com';
  @override String get poiBaseUrl      => 'https://poi.westinx.com';   // poi_service.dart에서 실제 URL 확인할 것
  @override String get addressBaseUrl  => 'https://api.vworld.kr';     // address_search_service.dart에서 실제 URL 확인할 것
}

// 추후 추가
// class AwsConfig implements AppConfig { ... }
// class DevConfig implements AppConfig { ... }
```

**`main.dart`에서 초기화**:
```dart
AppConfig.init(const ProdConfig());
```

**5개 파일에서 URL 상수 → `AppConfig.instance.xxx` 교체**:
- `routing_service.dart` → `AppConfig.instance.valhallaBaseUrl`
- `native_engine.dart` → `AppConfig.instance.naviBaseUrl`
- `poi_service.dart` → `AppConfig.instance.poiBaseUrl`
- `address_search_service.dart` → `AppConfig.instance.addressBaseUrl`
- `poi_icon_renderer.dart` → 주석/타일 URL이면 `AppConfig.instance.tileBaseUrl`

**빌드 플래그 준비** (`--dart-define=ENV=prod`): Phase 0에서 stub만, 실제 다중 환경은 AWS 이전 직전에 추가해도 됨.

---

### Phase 1 — 스킨 계약 정의

**파일**: `lib/core/skin/skin.dart`

```dart
abstract class AppSkin {
  String get id;
  String get displayName;
  bool get isPremium;

  SkinColors get colors;
  SkinTypography get typography;
  SkinMotion get motion;
  SkinShapes get shapes;

  ThemeData toThemeData();
}

abstract class SkinColors {
  // 브랜드
  Color get brand;        // 현재 0xFF008080
  Color get onBrand;      // 현재 Colors.white
  Color get brandLight;   // 연한 틸

  // 배경/표면
  Color get background;
  Color get surface;
  Color get surfaceVariant;

  // 텍스트
  Color get onSurface;
  Color get onSurfaceVariant;

  // 시맨틱
  Color get danger;
  Color get warning;
  Color get success;

  // 내비 전용
  Color get routeLine;
  Color get structureAlert;   // 16번 구조물 배지 색 (현재 amber.800)
  Color get curveAlert;       // 16번 급커브 배지 색 (현재 deepOrange.700)
  Color get speedometerBg;
}

abstract class SkinTypography {
  String get fontFamily;      // 'PlusJakartaSans' 또는 다른 폰트

  TextStyle get headlineXL;   // 38px bold (내비 거리 숫자)
  TextStyle get headlineL;    // 22px bold
  TextStyle get headlineM;    // 20px bold
  TextStyle get bodyL;        // 16px
  TextStyle get bodyM;        // 14px
  TextStyle get labelM;       // 13px
  TextStyle get labelS;       // 12px
  TextStyle get mono;         // 속도계 숫자용
}

abstract class SkinMotion {
  Duration get fast;      // 150ms
  Duration get standard;  // 300ms
  Duration get slow;      // 600ms
  Duration get pulse;     // 700ms (nav 펄스)
  Curve get defaultCurve;
  Curve get emphasizedCurve;
}

abstract class SkinShapes {
  double get radiusXS;  // 8
  double get radiusS;   // 14
  double get radiusM;   // 16
  double get radiusL;   // 20
  double get radiusXL;  // 24
}
```

---

### Phase 2 — DefaultSkin 구현

**파일**: `lib/core/skin/skins/default_skin.dart`

- `AppColors`, `AppTextStyles`의 현재 값을 `DefaultSkin`으로 이식
- `app_theme.dart`의 `AppTheme.light()` → `DefaultSkin().toThemeData()` 위임
- `NightModeColors`, `RiderModeColors`는 별도 스킨으로 분리하거나 `DefaultSkin`의 variant로 처리 (착수 시 판단)

---

### Phase 3 — Call-site 전면 교체 (11번 본체)

**SkinProvider** (`lib/core/skin/skin_provider.dart`):
```dart
final skinProvider = NotifierProvider<SkinNotifier, AppSkin>(SkinNotifier.new);

class SkinNotifier extends Notifier<AppSkin> {
  @override
  AppSkin build() {
    // shared_preferences에서 저장된 skinId 로드, 없으면 DefaultSkin
    return DefaultSkin();
  }
  void apply(AppSkin skin) { state = skin; }
}
```

**call-site 교체 패턴**:
```dart
// Before
color: const Color(0xFF008080)
// After
color: ref.watch(skinProvider).colors.brand
// 또는 StatelessWidget에서
color: context.skin.colors.brand  // BuildContext extension
```

**BuildContext extension** (편의 헬퍼):
```dart
extension SkinContext on BuildContext {
  AppSkin get skin => ProviderScope.containerOf(this).read(skinProvider);
}
```

**교체 우선순위**:
1. `main_map_screen.dart` (117건, 최다)
2. `nav_screen.dart` (43건 — 구조물/급커브 배지 포함)
3. `profile_screen.dart` (44건)
4. `settings_screen.dart`
5. `daylight_bar.dart`
6. 나머지

---

### Phase 4 — 스킨 JSON 로더

**에셋 구조**:
```
assets/skins/
  default/
    manifest.json    ← id, displayName, isPremium, colors{}, motion{}, shapes{}
    preview.png
```

**manifest.json 스키마** (예시):
```json
{
  "id": "default",
  "displayName": "기본",
  "isPremium": false,
  "colors": {
    "brand": "#008080",
    "onBrand": "#FFFFFF",
    ...
  },
  "motion": {
    "fast": 150,
    "standard": 300,
    "slow": 600
  },
  "shapes": {
    "radiusM": 16
  }
}
```

- 폰트 교체는 Flutter의 `FontLoader` API 사용 (다운로드 스킨에서 필요 시)
- Phase 4는 Phase 3 이후 착수

---

### Phase 5 — 수익화 Scaffold (8번 브랜드 확정 이후)

- 스킨 목록 화면 (설정 > 스킨)
- 잠금/해제 상태 UI
- `in_app_purchase` 패키지 stub 준비
- 2번째 스킨은 8번에서 확정된 브랜드 방향으로 제작

---

## 실행 순서 및 의존성

```
Phase 0 (Config 추상화)   → 즉시 시작 가능, 독립적
        │
Phase 1 (스킨 계약)       → Phase 0 완료 후
        │
Phase 2 (DefaultSkin)     → Phase 1 완료 후
        │
Phase 3 (Call-site 교체)  → Phase 2 완료 후  ← 11번 본체, 가장 물량 많음
        │
Phase 4 (JSON 로더)       → Phase 3 완료 후
        │
Phase 5 (수익화)          → 8번 완료 후
```

**8번(브랜드 확정) 없이 Phase 0~4 전부 완료 가능.**

---

## CLAUDE.md 프로토콜 준수 사항

- 각 Phase 시작 전 체크포인트 커밋
- 각 Phase 내 파일 수정 후 code-auditor PASS 확인
- 감사 최대 3회, FAIL 지속 시 BLOCKED 기록 후 중단
- `flutter analyze` 무조건 통과 후 커밋
- `git push` 금지 (로컬 커밋만)
- 한 세션에 한 Phase만 완료를 목표로 (물량 많음)
- 완료 후 `loop/RELEASE_ROADMAP.md`의 11번 상태 갱신

---

## 완료 기준

- Phase 0: `AppConfig.instance.valhallaBaseUrl` 등으로 URL 5곳 전부 교체, `flutter analyze` PASS
- Phase 1: `AppSkin` / `SkinColors` / `SkinTypography` / `SkinMotion` / `SkinShapes` 인터페이스 파일 생성, 컴파일 통과
- Phase 2: `DefaultSkin` 구현, 기존 `AppTheme.light()` 와 동일한 ThemeData 생성 확인
- Phase 3: `Color(0xFF008080)` 0건, 인라인 `TextStyle` 대폭 감소, `flutter analyze` PASS
- Phase 4: `assets/skins/default/manifest.json` 로딩 후 DefaultSkin과 동일한 색상 반환 확인
