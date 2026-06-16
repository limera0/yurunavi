# RECON: 지도 라벨 언어 단일 선택 (한/영/일 택1)
작성일: 2026-06-13 | 상태: 읽기 전용 정찰 완료

---

## A. 스타일 JSON — text-field 레이어 전수 조사

파일: `assets/images/osm_liberty_yurunavi.json`

### A-1. text-field를 가진 레이어 총 26개

#### 패턴 ① `{ref}` — 도로 방패 번호, 언어 전환 불필요 (3개)
| layer id | text-field |
|---|---|
| highway-shield | `{ref}` |
| highway-shield-us-interstate | `{ref}` |
| highway-shield-us-other | `{ref}` |

#### 패턴 ② `{name:latin}\n{name:nonlatin}` 또는 `{name:latin} {name:nonlatin}` — **언어 전환 대상 (16개)**
| layer id | text-field |
|---|---|
| waterway-name | `{name:latin} {name:nonlatin}` (공백) |
| water-name-lakeline | `{name:latin}\n{name:nonlatin}` (줄바꿈) |
| water-name-other | `{name:latin}\n{name:nonlatin}` |
| poi-level-3 | `{name:latin}\n{name:nonlatin}` |
| poi-level-2 | `{name:latin}\n{name:nonlatin}` |
| poi-level-1 | `{name:latin}\n{name:nonlatin}` |
| poi-railway | `{name:latin}\n{name:nonlatin}` |
| highway-name-path | `{name:latin} {name:nonlatin}` |
| highway-name-minor | `{name:latin} {name:nonlatin}` |
| highway-name-major | `{name:latin} {name:nonlatin}` |
| airport-label-major | `{name:latin}\n{name:nonlatin}` |
| place-other | `{name:latin}\n{name:nonlatin}` |
| place-village | `{name:latin}\n{name:nonlatin}` |
| place-town | `{name:latin}\n{name:nonlatin}` |
| place-city | `{name:latin}\n{name:nonlatin}` |
| place-city-capital | `{name:latin}\n{name:nonlatin}` |

#### 패턴 ③ `{name:latin}` 단독 — **언어 전환 시 한/일 모드에서도 바꿔야 할 대상 (7개)**
| layer id | text-field |
|---|---|
| water-name-ocean | `{name:latin}` |
| place-state | `{name:latin}` |
| place-country-other | `{name:latin}` |
| place-country-3 | `{name:latin}` |
| place-country-2 | `{name:latin}` |
| place-country-1 | `{name:latin}` |
| place-continent | `{name:latin}` |

### A-2. 현재 스타일이 실제로 참조하는 name 필드
- `name:latin` — 로마자/영문 이름
- `name:nonlatin` — 비로마자 이름 (한국 mbtiles에서는 사실상 한국어)
- `{ref}` — 도로 번호 (언어 무관)
- **`name:ko`, `name:en`, `name:ja`, `name` (bare) 는 스타일에서 현재 사용하지 않음**

### A-3. 결론 — A
- 언어 전환 시 건드려야 할 레이어: **23개** (패턴 ② 16 + 패턴 ③ 7)
- 패턴 ① 3개(방패)는 `{ref}` 고정이므로 제외
- 한국어 모드 표현식 예시: `{name:nonlatin}` (또는 `{name}`)
- 영어 모드 표현식 예시: `{name:latin}`
- 일본어 모드: `{name:ja}` — **mbtiles에 해당 필드 존재 여부 미확인 (→ D 미확인 목록)**

---

## B. 스타일 로딩 + 컨트롤러 접근

### B-1. 스타일 참조 위치
| 파일 | 라인 | 방식 |
|---|---|---|
| `lib/features/map/presentation/main_map_screen.dart` | 765 | `styleString: 'assets/images/osm_liberty_yurunavi.json'` (asset 문자열) |
| `lib/features/navigation/presentation/nav_screen.dart` | 782 | `styleString: 'assets/images/osm_liberty_yurunavi.json'` (asset 문자열) |

두 곳 모두 `styleString`에 asset 경로를 직접 문자열 리터럴로 넘김. `styleUrl` 방식 없음.

### B-2. MapLibre 컨트롤러 변수
- `main_map_screen.dart:80` → `ml.MapLibreMapController? _mlCtrl;`
  - `onMapCreated: (c) => _mlCtrl = c` (라인 775)
- `nav_screen.dart:50` → `ml.MapLibreMapController? _mlCtrl;`
  - `onMapCreated: (c) => _mlCtrl = c` (라인 790)

### B-3. `setLayoutProperty` / `setLayerProperties` 기존 호출 여부
```
grep -rn "setLayoutProperty\|setLayerProperties\|setLayerProperty" lib/ --include=*.dart
→ 결과 없음 (0건)
```
**현재 런타임 레이어 속성 변경 코드는 전혀 없음.**

### B-4. 결론 — B
- 스타일은 asset 파일 경로 문자열 주입 방식. 런타임 변경에는 두 가지 경로:
  - **(옵션 α) `setLayoutProperty` 호출**: 스타일 재로딩 없이 레이어별 `text-field` 를 덮어씀. `_mlCtrl`이 이미 있으므로 접근 가능. 23개 레이어를 루프로 처리.
  - **(옵션 β) 스타일 JSON 재주입**: 언어별 json을 미리 생성하거나 런타임에 수정 후 `MapLibreMap` 위젯을 재빌드. 더 단순하지만 화면 깜빡임 발생 가능.
- `setLayoutProperty`가 Flutter MapLibre SDK에서 실제로 `text-field` 표현식을 받는지 버전 확인 필요 (→ D 미확인 목록)

---

## C. 설정 화면 + 상태관리 / 영속화

### C-1. 설정 화면 존재 여부
`lib/screens/` 내 파일 목록:
```
driving_screen.dart
intro_screen.dart
main_map_screen.dart   ← lib/screens/ 사본 (구버전일 수 있음)
profile_screen.dart    ← 사용자 설정 UI 존재
route_options_screen.dart
```
- **전용 설정 화면 없음.** `profile_screen.dart`가 현재 유일한 사용자 설정 UI (닉네임, 바이크 프로필).
- `lib/features/` 하위에도 `settings` 모듈 없음 (`lib/modules/` 디렉토리 자체 미존재).
- 언어 설정 라디오를 붙일 곳: `profile_screen.dart` 하단 추가 또는 별도 `settings_screen.dart` 신설.

### C-2. 상태관리 라이브러리
`pubspec.yaml`:
```
flutter_riverpod: ^3.3.1
riverpod_annotation: ^4.0.2
```
전체 앱이 Riverpod 기반. 기존 Provider 패턴:
- `riderModeProvider` (NotifierProvider<bool>) — `map_providers.dart`에 정의, 앱 전역 상태
- `mapInteractionProvider` (NotifierProvider<MapInteractionState>)
언어 설정도 동일하게 `NotifierProvider<MapLanguage>` 형태로 추가하면 일관성 유지됨.

### C-3. SharedPreferences 사용 패턴
```
lib/services/route_service.dart     → static const _key = 'saved_routes_v1'
lib/services/profile_service.dart   → static const _key = 'user_profile_v1'
lib/services/places_service.dart    → static const _favKey = 'favorite_places_v1'
                                       static const _recentKey = 'recent_routes_v1'
```
패턴: `서비스클래스.load()` / `서비스클래스.save()` + `static const _key = 'xxx_v1'`  
언어 설정 키 네이밍 예시: `'map_language_v1'`

현재 언어/locale 관련 SharedPreferences 키 **없음** (grep 확인).

### C-4. 결론 — C
- 설정 화면 **신설 또는 profile_screen.dart 확장** 필요
- 언어값 영속화: SharedPreferences `'map_language_v1'` 키, 기존 서비스 패턴 그대로 따르면 됨
- 상태 전파: Riverpod `NotifierProvider<MapLanguage>` → 두 맵 화면이 watch

---

## D. 종합 작업 범위

### D-1. 요약
1. **설정화면**: 신설 불필요 — `profile_screen.dart`에 언어 라디오 섹션 추가로 충분. (또는 `settings_screen.dart` 신설 — 마스터 결정)
2. **건드릴 스타일 레이어 수**: **23개** (패턴 ② 16 + 패턴 ③ 7). 방패 3개는 제외.
3. **런타임 교체 vs 재로딩**: 두 옵션 모두 기술적으로 가능. `setLayoutProperty` 루프(옵션 α)가 깜빡임 없이 선호됨. 단, SDK에서 실제 동작 검증 필요.
4. **예상 커밋 분할**:
   - C1: `MapLanguage` enum + `mapLanguageProvider` + `LanguageService` (SharedPrefs 저장)
   - C2: profile_screen.dart 언어 라디오 UI
   - C3: main_map_screen.dart + nav_screen.dart `_applyLanguage()` 메서드 (23개 레이어 루프)
   - C4: 통합 테스트 및 엣지케이스 (컨트롤러 null, 스타일 미로드 타이밍)

### D-2. 미확인 · 마스터 결정 필요 항목

| # | 항목 | 근거 |
|---|---|---|
| U1 | `korea.mbtiles`에 `name:ja` 필드 존재 여부 | 스타일에서 사용 안 함; planetiler가 `name:ja`를 포함하는지 미검증 |
| U2 | `name:ko` vs `name:nonlatin` — 한국어 모드에서 어느 필드 사용? | 두 필드가 동일 데이터일 수도 있음; 실제 mbtiles 확인 필요 |
| U3 | MapLibre Flutter SDK에서 `setLayoutProperty`로 `text-field` 표현식 변경 가능 여부 | 기존 호출 코드 없음; SDK 버전(pubspec 확인 필요)에 따라 지원 여부 다름 |
| U4 | 언어 변경 시 nav_screen.dart 컨트롤러 타이밍 — `_mlCtrl`이 null인 상태에서 언어 변경 요청이 오는 경우 처리 | 현재 _mlCtrl 초기화 타이밍 미분석 |
| U5 | 설정 진입점 위치 — profile_screen 내 섹션 추가 vs 독립 settings_screen 신설 | UX 결정 필요 |
| U6 | 일본어 선택지 포함 여부 — Korea mbtiles에서 일본어 라벨이 없다면 선택지 자체를 빼야 할 수도 있음 | U1 선결 필요 |
