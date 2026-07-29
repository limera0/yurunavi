GOAL: 브랜드 방향 3안(A/B/C)을 무료 스킨 3종으로 구현 — 기본 스킨을 A로 교체, 설정
화면에서 A/B/C를 선택할 수 있게, 향후 유료 스킨 확장을 위한 스캐폴딩(isPremium)은
이미 있는 필드를 그대로 재사용

이 파일을 읽는 Claude(혹은 flutter-coder)는 아래 내용을 순서대로 실행한다.
**코딩 전에 반드시 이 파일 전체를 읽어라.**

---

## 배경 및 목적

**마스터 결정 (2026-07-29, 대화 내 확정)**:
1. 로드맵 8번(브랜드 방향성 확정) 관련, Claude가 질문지 답변을 바탕으로 3가지 방향
   (A/B/C)을 제안했고 마스터가 검토함.
2. "기본은 A안. B안과 C안도 버리지 말고, 설정 페이지의 스킨 항목에서 고를 수 있게
   하자. 이 3가지가 무료 스킨, 그리고 앞으로 특색을 더 살려서 만드는 스킨은 유료로
   제공하자."
3. "한국적 감성" 해석 확인: 한국 전통 문양/색이 아니라 **"유럽/미국(서양) 특유의
   디자인 감각 대신 한국·일본의 디자인 감각"**이라는 뜻으로 확정. (3안 모두 이미
   일본 서브컬처·MUJI·베스파/피가로 등 비서구 지향이라 재작업 불필요 — 향후 스킨
   추가/9번 앱 아이콘 작업 시 참고할 것.)

**출처**: 사용자가 채팅에 직접 붙여넣은 브랜드 아이덴티티 질문지 답변
(업로드된 원본 `260729_brandIdentity_Yurunavi.md`는 인코딩이 깨져 못 읽었음 —
재입력받은 텍스트가 유일한 원본, 이 문서에 필요한 부분은 아래 옮겨 적음).

**관련 과거 문서**: `loop/STITCH_DESIGN_PROMPTS.md`(2026-07-14, 보류된 대안 경로),
`RELEASE_ROADMAP.md` 8번/11번(Phase 5)/9번.

---

## ⚠️ 아키텍처 주의 — 두 개의 팔레트 시스템 중 어느 쪽을 쓸지

이 저장소에는 "미래 팔레트 교체"를 위한 스켈레톤이 **두 벌** 있다. 반드시
`lib/core/skin/`(2번) 쪽에 구현할 것 — 1번 쪽은 건드리지 마라.

1. `lib/core/theme/palette.dart` + `app_theme_selector.dart`
   (`YuruNaviPalette`, `AppThemeSelector`) — 파일 자체 doc comment에 "Skeleton
   only: nothing consumes this yet"라고 적혀 있음. 정적 단일 스왑용(구매한 리디자인
   하나를 통째로 바꿔 끼우는 용도)이고 런타임 선택/프리미엄 개념이 없음.
   **이번 작업과 무관 — 손대지 말 것.**
2. `lib/core/skin/`(`AppSkin`/`SkinColors`/`SkinProvider`/`SkinLoader`) — Riverpod
   `NotifierProvider`로 런타임에 `.apply()`로 스킨을 바꿀 수 있고, `AppSkin`에
   `isPremium` 필드가 이미 있음. **이번 작업은 전부 이 디렉터리 기준.**

---

## Phase 1 — `SkinColors`에 3-way 경로 컬러 필드 추가

**파일**: `lib/core/skin/skin.dart`

기존 `SkinColors`에는 단일 `routeLine` 색만 있고, 실제 앱의 핵심 UX인 "시골길/
지방도/국도" 3가지 경로 동시 비교(코스 선택 화면·내비 화면·지도 폴리라인)는 아직
`lib/core/theme/app_theme.dart`의 전역 상수 `courseLineColor`(`Map<int, Color>`,
key 0=시골길, 1=지방도, 2=국도)를 직접 참조하고 있어 스킨을 바꿔도 경로선 색이
안 바뀐다. 이러면 스킨 기능의 절반이 죽은 셈이니 반드시 같이 고칠 것.

`SkinColors`에 추가:
```dart
/// 코스 인덱스별 경로선 색 (0: 시골길/scenic, 1: 지방도/regional, 2: 국도/fast).
/// 레거시 최상위 courseLineColor map과 동일한 키 규약.
Map<int, Color> get courseLineColor;
```
`_DefaultColors`(`default_skin.dart`)와 `_JsonColors`(`skin_loader.dart`)에도
구현 추가:
- `_DefaultColors`: 레거시 `legacy.courseLineColor`를 그대로 반환(기존 동작 유지,
  이 스킨은 색 안 바뀜 — 문제없음, 아래 Phase 2에서 새 기본 스킨으로 교체됨).
- `_JsonColors`: JSON에 `courseLineColor: {"0": "#..", "1": "#..", "2": "#.."}`
  형태로 오면 파싱, 없으면 `_def.courseLineColor` 폴백. (다른 `_get()` 헬퍼처럼
  키별 hex 파싱 재사용.)

---

## Phase 2 — 스킨 3종 신설: A(신규 기본)/B/C

**디렉터리**: `lib/core/skin/skins/` (기존 `default_skin.dart`와 나란히)

**공통 사항 (3종 전부)**:
- `typography`/`motion`/`shapes`는 전부 `_DefaultTypography()`/`_DefaultMotion()`/
  `_DefaultShapes()`(default_skin.dart에 있는 클래스, private이라 그대로 재사용은
  안 되니 동일 값으로 새로 만들거나 default_skin.dart의 클래스를 public으로 승격해
  공유 — 후자를 권장, 이름은 `DefaultSkinTypography` 등으로). 질문지에서 타이포는
  이미 "둥글고 친근 + 굵고 임팩트"로 답변됐고 3안 모두 동일 적용하기로 마스터가
  검토·승인했으므로 이번 스코프에서 폰트 자체를 바꾸지 마라(9번 앱 아이콘 확정 이후
  별도 세션 몫).
- `toThemeData()`는 `DefaultSkin`과 동일하게 `AppTheme.light` 반환(기존 스킨도
  자기 색을 반영하는 완전한 ThemeData가 아직 없음 — 이 갭을 이번에 새로 만들지
  말 것, 범위 밖).
- `structureAlert`/`curveAlert`는 **3종 모두 고정값**
  (`0xFFFF8F00`/`0xFFE64A19`, DefaultSkin과 동일) — 브랜드 무드에 맞춰 재색하지
  말 것. 후면단속카메라/커브 경고 같은 안전 경고색은 스킨과 무관하게 항상 동일해야
  한다는 게 이 프로젝트의 기존 원칙(가독성·일관성 우선).
- `isPremium => false` 3종 전부.

### A — `yurucam_skin.dart` — **새 기본 스킨**
id: `'yurucam'`, displayName: `'유루캠 무드'`
```
brand            0xFFE2896F   onBrand   0xFFFFFFFF   brandLight 0x26E2896F
background       0xFFFBF1E7   surface   0xFFFFFFFF   surfaceVariant 0xFFF2E1D2
onSurface        0xFF4A3B33   onSurfaceVariant 0xFF8A776C
danger           0xFFC94F3F   warning   0xFFE8A63D   success   0xFF6E9B6B
routeLine        0xFFE2896F
courseLineColor  {0: 0xFFE2896F, 1: 0xFF8CA283, 2: 0xFF7C8B99}
```

### B — `retro_motoring_skin.dart`
id: `'retro_motoring'`, displayName: `'레트로 모터링'`
```
brand            0xFF78B4AC   onBrand   0xFFFFFFFF   brandLight 0x2678B4AC
background       0xFFF4F0E6   surface   0xFFFFFFFF   surfaceVariant 0xFFEAE0CC
onSurface        0xFF3C3A33   onSurfaceVariant 0xFF837E70
danger           0xFFC15B4E   warning   0xFFD9A54A   success   0xFF6FA37C
routeLine        0xFF78B4AC
courseLineColor  {0: 0xFF78B4AC, 1: 0xFFC7A768, 2: 0xFFDFA79E}
```

### C — `cub_buddy_skin.dart`
id: `'cub_buddy'`, displayName: `'동네 라이딩 메이트'`
```
brand            0xFFC05F4C   onBrand   0xFFFFFFFF   brandLight 0x26C05F4C
background       0xFFF9F4E9   surface   0xFFFFFFFF   surfaceVariant 0xFFF0E3C9
onSurface        0xFF232A3B   onSurfaceVariant 0xFF5B6270
danger           0xFFB0362A   warning   0xFFD98A3D   success   0xFF4F6B58
routeLine        0xFFC05F4C
courseLineColor  {0: 0xFFC05F4C, 1: 0xFF4F6B58, 2: 0xFF232A3B}
```

`speedometerBg`는 3종 다 자기 `surface`(전부 `0xFFFFFFFF`)와 동일.

---

## Phase 3 — 기본 스킨 교체 + 선택 영속화

**파일**: `lib/core/skin/skin_provider.dart`

- `SkinNotifier.build()`가 `const DefaultSkin()` 대신 **저장된 선택이 있으면 그
  스킨, 없으면 `const YuruCamSkin()`**을 반환하도록 변경. (`DefaultSkin` 클래스
  자체는 지우지 말 것 — `SkinLoader`의 에러 폴백/`_JsonColors` 등 기본값 소스로
  계속 쓰인다.)
- 3개 스킨을 id로 찾을 수 있는 목록/레지스트리 추가, 예:
  ```dart
  const kAvailableSkins = <AppSkin>[YuruCamSkin(), RetroMotoringSkin(), CubBuddySkin()];
  ```
  (위치는 `skin_provider.dart` 또는 `skins/` 밑에 `registry.dart` 새로 — 판단은
  맡긴다.)
- 선택 영속화: 이 저장소는 이미 `SharedPreferences`를 이런 종류의 로컬 설정
  저장에 쓰고 있다(`lib/services/*_service.dart`, `settings_providers.dart` 참고
  — 기존 관례 그대로 따를 것, 새 패키지/DB 끌어오지 말 것). 키 이름은 기존 관례에
  맞춰 짓고, `apply()` 호출 시 저장 + `build()`에서 복원.

---

## Phase 4 — 레거시 `courseLineColor` 4곳을 스킨 참조로 교체

아래 4개 파일이 전역 상수 `courseLineColor`(from `app_theme.dart`)를 직접 참조
중 — 전부 `context.skin.colors.courseLineColor` (또는 이미 `ref`/`context`가
있는 지점에서 동일하게) 로 교체해서, 스킨을 바꾸면 실제로 경로선 색이 바뀌게
만들 것. **이 4곳 외 다른 코드는 건드리지 마라** (11번 항목의 전면 리터럴 감사는
별도 스코프).

- `lib/features/map/presentation/main_map_screen.dart:422,439`
  (`courseLineColor[initialIdx] ?? courseLineColor[2]!` 형태 — null 처리 유지)
- `lib/core/widgets/course_sheet.dart:46-48`
  (`RouteInfo(..., courseLineColor[0]!)` 등 3줄)
- `lib/features/navigation/presentation/nav_screen.dart`
  (파일 내 `courseLineColor` grep해서 전부 교체)
- `lib/features/tour_summary/presentation/tour_summary_detail_screen.dart:188`

`lib/core/theme/palette.dart`/`app_theme_selector.dart`는 **건드리지 말 것**
(위 아키텍처 주의 참고).

---

## Phase 5 — 설정 화면에 "스킨" 섹션 추가

**파일**: `lib/features/settings/presentation/settings_screen.dart`

기존 섹션 패턴(`_SectionHeader` + `ListTile`/`Divider`, 25~77번 줄 근방) 그대로
따라서 새 섹션 추가. 위치는 "지도 표기 언어" 섹션 근처(둘 다 표시 관련 설정) 권장,
정확한 순서는 자유.

- 섹션 헤더: "스킨"
- A/B/C 3개를 리스트로: 각 항목에 브랜드 컬러가 보이는 작은 원형 스와치(`brand`
  색) + `displayName` + 현재 선택된 스킨이면 체크 아이콘. 탭하면
  `ref.read(skinProvider.notifier).apply(skin)`.
- `isPremium`은 3종 다 `false`이므로 잠금 UI/구매 로직은 **만들지 마라** — 나중에
  유료 스킨이 실제로 생길 때 다시 다룰 일이고, 지금 안 쓰이는 잠금 로직을 미리
  만드는 건 스코프 밖이다.

---

## 완료 후 확인 (code-auditor 넘기기 전 자체 점검)

- `flutter analyze` 0 issues, `flutter test` 기존 스위트 그린.
- 앱 최초 실행 시 배경/브랜드 컬러가 A(유루캠 무드, 코랄/파스텔)로 보이는지.
- 설정 → 스킨에서 B/C로 바꾸면: 설정 화면 자체 색 + 지도 화면 진입 시 경로 선택
  시트의 3가지 경로 색(course_sheet.dart)이 같이 바뀌는지 실기기/에뮬레이터로
  확인.
- 앱 재시작 후에도 마지막으로 고른 스킨이 유지되는지(영속화 확인).
- 구조물/커브 경고색(주황 계열)은 스킨과 무관하게 항상 동일한지.
