# 최종 레이아웃 점검 · 브랜딩 디자인 다듬기 진행 상황 (2026-07-30 시작)

출시 직전 최종 레이아웃 점검 + 브랜딩 정합성을 다듬는 트랙. 마스터가 화면 스크린샷을
한 장씩 이야기하면, 필요한 정보를 질문 → 계획 확정 → 아래에 라운드 단위로 누적 기록한다.
로드맵 번호는 부여하지 않고 이 파일로만 추적한다. **구현은 라운드마다 하지 않고 전체
화면을 다 훑어 계획만 쌓아둔 뒤, 마스터가 명시적으로 시작하라고 할 때 배치로 진행**
(2026-07-30 확인, 이유: "하나씩 수정까지 하면 너무 오래 걸려").

참조 이미지는 전부 `loop/layout_fixes/` 폴더에 마스터가 미리 넣어둠(1~17번, 파일명이
화면 내용을 나타냄 — 예: `1_logo_loading.jpg`, `7_navigation_layout.png`). 총 17개 화면
대기 중: 1 로고/로딩, 2 상태바·내비바, 3 홈 레이아웃, 4 위치 선택, 5 코스 선택 레이아웃,
6 경유지 추가 레이아웃, 7 내비게이션 레이아웃, 8 홈 불필요 버튼, 9 PIP, 10 히스토리,
11 히스토리 상세, 12 히스토리 상세 공유, 13 설정, 14 내 장소, 15 내 계정, 16 내 오토바이,
17 종료 토스트.

---

## 라운드 1 — 2026-07-30 (스플래시 화면)

**참조 이미지**: `loop/layout_fixes/1_logo_loading.jpg` — 실기기 스플래시 화면
스크린샷. 상단 상태바(크림 배경, 검정 아이콘, 11:42), 중앙에 흰 원형 배지 안에
"YURU/NAVI" 두 줄 버블레터 로고(주황 외곽선+네이비 테두리, 연한 주황 글로우), 그
아래 "유루나비"(네이비, 자간 넓음) + "이륜차를 위한 감성 내비게이션"(회색, 작은
글씨), 하단은 검정 시스템 내비게이션 바(≡ ○ < 아이콘).

### 마스터 피드백 (원문)
1. 로고 제작 필요 — 현재 임시로 만든 YURUNAVI 로고를 브랜드 이미지에 맞춰서 새로 제작
2. 로고 아래 텍스트는 글자가 너무 작아서 안 보임 — 글꼴을 예쁘게 해서 이미지로 넣을 것
3. 상단 상태바는 좋은데, 하단 내비게이션 바가 검정색이라 안 어울림 — 배경색으로 수정

### 확인 질문 및 답변
- Q1. 원형 로고 배지 컨셉 — 앱 아이콘 모티프(코랄 핀+굽이도로) 재사용 vs 텍스트 배지 유지?
  → **A. 텍스트 배지 유지** (팔레트만 새 브랜드 컬러로 교체, 컨셉은 유지)
- Q2. 로고 아래 텍스트 이미지 범위 — 태그라인만 / 한글+태그라인 / 영문 워드마크 포함?
  → **A. 한글("유루나비") + 태그라인 둘 다 하나의 이미지로**

### 조사 결과 (코드/에셋)
- 로고 배지 원본: `assets/images/yuru_circle.jpeg` (미사용 대안 크롭
  `yuru_main.jpeg`/`yuru_2line.jpeg`도 동일한 임시 팔레트) — 주황 `#F28C28` /
  네이비 `#1A2B3C`, `lib/core/theme/app_theme.dart`의 기존 `AppColors` 팔레트.
- 렌더 위치: `lib/features/auth/presentation/splash_screen.dart` `_LogoWidget`
  (L116-186) — 160×160 원형 컨테이너(흰 배경+그림자) 안에 `Image.asset`(L142-159),
  아래 `Column`에 `Text` 2개(L164-183): "유루나비" 16sp `textSecondary` / 태그라인
  13sp `AppColors.textHint`(연회색) — 이 태그라인이 "안 보임"의 실체.
- **팔레트 불일치 발견**: 2026-07-29 확정 브랜드 아이덴티티(유루캠 무드: 코랄
  `#E2896F` / 크림 `#FBF1E7` / 모스그린 `#8CA283` / 다크브라운 `#4A3B33`, 메모리
  `project_brand_identity`)가 런처 앱 아이콘(`assets/icon/app_icon_source.svg`,
  로드맵 9번 완료)에는 이미 적용돼 있는데, 스플래시 로고는 예전 팔레트 그대로 —
  이번 작업으로 격차 해소.
- 하단 내비게이션 바 원인: `lib/main.dart`는 상태바(`statusBarColor: transparent`)만
  전역 처리(L26-32, L49-53)하고 `systemNavigationBarColor`는 어디서도 기본값을
  설정하지 않음 — `nav_screen.dart:332`만 예외적으로 로컬에서 `Color(0xFFF8F4F0)`
  지정. 결과적으로 스플래시 포함 나머지 모든 화면이 OS 기본값(검정)으로 보임 —
  스플래시만의 문제가 아니라 앱 전역 이슈.

### 확정된 수정 계획

**1. 원형 로고 배지 재도안**
- 대상: `assets/images/yuru_circle.jpeg` 교체(또는 신규 에셋 + `splash_screen.dart`
  L144 경로 변경)
- 컨셉: 텍스트 배지 유지 — "YURU"/"NAVI" 영문 레터링 그대로(한글판은 2번 항목에서
  별도 처리)
- 팔레트: 코랄 `#E2896F` / 크림 `#FBF1E7` / 모스그린 `#8CA283` / 다크브라운
  `#4A3B33` (앱 아이콘과 동일 계열로 통일)
- 스타일: 현재의 두꺼운 만화풍 코믹 버블 톤에서 유루캠 무드(시마린/논논비요리/
  보노보노 계열 — 부드럽고 따뜻한 손그림 느낌)에 맞게 굵기·외곽선 재검토. 단순
  색상 교체가 아니라 필요하면 레터폼 자체도 조정.
- 원형 컨테이너의 흰 배경+그림자 처리(`splash_screen.dart` L123-141)를 유지할지,
  배경까지 브랜드 컬러로 채울지는 시안 단계에서 확인.

**2. 로고 아래 텍스트 이미지화**
- 대상: "유루나비"(한글) + "이륜차를 위한 감성 내비게이션"(태그라인) 두 줄을 하나의
  이미지로 새로 디자인, `splash_screen.dart` L164-183의 `Text` 위젯 2개를
  `Image.asset`으로 교체
- 요구사항: 유루캠 무드에 맞는 커스텀 폰트로 제작, 태그라인 가독성(현재 13sp
  연회색보다 큰 크기·충분한 대비) 확보가 최우선
- 확인 필요: 스플래시가 나이트모드(`NightModeColors`)에서도 노출되는지 미확인 —
  구현 전 확인 후 다크 배경 대비 버전 필요 여부 결정

**3. 하단 내비게이션 바 색상**
- 근본 수정 위치: `lib/main.dart` `YuruNaviApp.build()`의 두 번째
  `SystemChrome.setSystemUIOverlayStyle` 호출(L49-53)에
  `systemNavigationBarColor: theme.scaffoldBackgroundColor`,
  `systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark`
  추가. `scaffoldBackgroundColor`는 라이트(`#F9F7F2`)/나이트/라이더 모드별로 이미
  정확히 설정돼 있어(app_theme.dart L278/380/436) 화면별 분기 없이 전역 1곳
  수정으로 스플래시 포함 전체 화면에 적용됨.
- `nav_screen.dart:332` 로컬 오버라이드는 그대로 둠(건드리지 않음).
- `main()`의 최초 `SystemChrome.setSystemUIOverlayStyle`(L27-32, 첫 프레임)에도
  라이트 테마 기준값을 선반영할지는 체감 확인 후 필요시 추가.

### 상태: 계획 확정, 구현 대기
다음 단계: 로고+텍스트 시안 제작 → 마스터 확인/승인 → flutter-coder 위임(3번 나비바
수정 포함) → code-auditor PASS → 체크포인트 커밋.

---

## 라운드 2 — 2026-07-30 (상태바·내비게이션 바)

**참조 이미지**: `loop/layout_fixes/2_statusbar_navigationbar.png` — 실기기 스크린샷
3장(홈/지도, 코스 시트, 경로 옵션 시트). 화면마다 상단 상태바(투명+검정 아이콘 /
투명+지도가 비쳐 안 읽힘)와 하단 시스템 내비게이션 바(거의 흰색에 가까운 옅은 색 /
불투명 검정)가 제각각.

### 마스터 피드백 (원문)
로고 로딩 화면(스플래시)만 제외하고 나머지 모든 페이지에서 상태바·하단 내비게이션
바를 `#F5F1EC`로 통일.

### 조사 결과 (코드)
- system UI overlay를 건드리는 곳은 앱 전체에 단 두 곳뿐:
  - `lib/main.dart` L27-32(앱 시작 전 1회, statusBar transparent + 검정 아이콘,
    내비바는 미설정) / L49-53(`YuruNaviApp.build()`마다 재실행 — 라이더모드·
    야간모드 토글 시에도 재실행됨, statusBar를 매번 transparent로 되돌리고 내비바는
    여전히 안 건드림)
  - `lib/features/navigation/presentation/nav_screen.dart` L329-335(내비게이션
    진입 시 `Color(0xFFF8F4F0)`로 상태바+내비바 둘 다 설정) / L434-436(dispose
    시 `statusBarIconBrightness`만 복원, **`systemNavigationBarColor`는 복원 안
    함**)
  - 그 외 모든 화면(홈지도/코스선택/경유지추가/히스토리/설정/내장소/내계정/
    내오토바이 등)은 system UI overlay를 전혀 설정하지 않음 — OS 기본값에 의존.
- **버그 원인 규명**: 앱을 켜서 한 번도 실주행 내비게이션(nav_screen)에 들어가지
  않았으면 하단 내비바는 OS 기본 검정(스크린샷 2·3과 일치). 한 번이라도
  nav_screen을 들어갔다 나오면 dispose가 내비바 색을 복원하지 않아 `#F8F4F0`가
  이후 모든 화면에 계속 눌어붙음(스크린샷 1이 옅게 보이는 이유).
- **2차 불일치(코드로만 확인, 스크린샷엔 미포착)**: `main.dart`의 build()-레벨
  호출이 라이더모드/야간모드 토글마다 재실행되며 상태바만 강제로 transparent로
  되돌리고 내비바는 안 건드려서, 테마를 토글하면 상태바/내비바 조합이 또 어긋날
  잠재적 소지가 있음.
- 스플래시는 자체 overlay 호출이 전혀 없어 `main.dart` L27-32 최초 1회 값(투명
  상태바+검정 아이콘, 내비바 미설정=검정)에만 의존 — "스플래시 제외"를 정확히
  지키려면 스플래시가 `MainMapScreen`으로 전환된 *이후* 시점부터만 새 색이
  적용되게 하는 장치가 필요(그냥 전역으로 F5F1EC를 걸면 스플래시에도 적용돼버림).

### 확정된 수정 계획

**1. 전역 단일 진실원 도입 (스플래시 이후부터 적용)**
- 간단한 bool provider(예: `pastSplashProvider`, 기본 `false`)를 추가, `SplashScreen`이
  `MainMapScreen`으로 전환하는 시점(`_goToMain()` 진입 직전 또는 `MainMapScreen.initState`)에
  `true`로 설정.
- `main.dart`의 `YuruNaviApp.build()`가 이 provider도 watch:
  - `pastSplash == false`(스플래시 표시 중): 기존 그대로 유지 — 이번 통일 대상에서
    완전히 제외.
  - `pastSplash == true`(스플래시 이후 전체): 테마(라이트/야간모드/라이더모드)
    무관하게 항상 `statusBarColor`·`systemNavigationBarColor` 둘 다 불투명
    `Color(0xFFF5F1EC)`, 아이콘 `Brightness.dark`(밝은 배경이라 야간·라이더
    모드에서도 어두운 아이콘이 맞음 — 기존 `Brightness.light` 분기 제거),
    `systemNavigationBarContrastEnforced: false`(오버레이 스크림 방지,
    `nav_screen.dart`가 이미 쓰는 패턴과 동일).
    **확정(2026-07-30)**: 야간모드/라이더모드(원래 눈부심 방지 목적의 다크 배경,
    [[project_nav_ui_state]] 관련)도 예외 없이 동일 색상 적용 — 마스터 확인 완료,
    이전에 검토했던 "다크모드 제외" 가정은 폐기.
  - 이 구조면 라이더모드/야간모드 토글 등 어떤 이유로 `YuruNaviApp`이 재빌드되어도
    항상 올바른 값이 재적용되어, 위에서 발견한 2차 불일치도 함께 해소됨.

**2. `nav_screen.dart` 정리**
- L330/332 하드코딩 `Color(0xFFF8F4F0)` → `Color(0xFFF5F1EC)`로 정렬(1번 값과
  동일 상수 공유 권장).
- L434-436 dispose(): `statusBarIconBrightness`만 부분 복원하는 현재 코드가 실제
  버그 원인이므로, 상태바+내비바 전체를 F5F1EC 조합으로 명시적으로 복원하도록 수정.

**3. 그 외 화면**
- 홈지도/코스선택/경유지추가/히스토리/설정/내장소/내계정/내오토바이 등은 개별
  수정 불필요 — 1번 전역 조치가 system UI overlay를 개별 설정하지 않는 모든 화면에
  자동으로 적용됨.

### 상태: **구현 완료 (2026-07-31, 라운드8과 동일 세션)**
flutter-coder → code-auditor PASS → 커밋 `21f6440`(`feat(theme): 전 화면
상태바/내비게이션 바 #F5F1EC 통일`). `pastSplashProvider`(`lib/providers/app_providers.dart`)
+ 공유 상수 `kSystemBarColor`(`app_theme.dart`) 도입, `nav_screen.dart` dispose
전체 복원으로 수정. 라운드8이 먼저 반영되어 다크/라이더 테마 분기 없이 단순화된
형태로 구현됨(문서 내용 그대로가 아니라 "테마 하나뿐이므로 조건 없이 항상 적용"으로
축약).

---

## 라운드 3 — 2026-07-30 (홈 레이아웃 변경안)

**참조 이미지**: `loop/layout_fixes/3_home_layout.png` — 좌측 실기기 캡쳐(현재 상태) +
우측 마스터 손그림 와이어프레임(변경안). 와이어프레임 캔버스 폭이 실기기 캡쳐 폭과
거의 1:1(386px vs 387px, 픽셀 분석으로 확인)이라 가로 스케일은 실기기 기준으로 그대로
대응시킬 수 있음.

**정정(2026-07-30, 마스터 피드백)**: 처음엔 원 지름이 "과장되게 크게 그려진 것"으로 보고
기존 42px 버튼 치수를 재사용하는 쪽으로 해석했었으나 — **오판정**. 마스터가 큰 사이즈로
그린 건 의도된 것: 오토바이 주행 특성상 서행(~10km/h) 중이거나 장갑을 낀 상태로 조작하는
경우가 많아 터치 타겟을 일부러 크게 잡았다는 확인을 받음. **버튼 크기는 그림에 그려진
비율 그대로 가야 함** — 아래 조사 결과를 connected-component 픽셀 분석(scipy
`ndimage.label`)으로 재측정해 정확한 치수를 뽑았다.

### 마스터 피드백 요약
와이어프레임 기준으로: 상단엔 검색창 하나만 남고 그 옆에 설정 버튼, 그 아래 기록·
즐겨찾기가 타이트하게 붙고, 큰 여백을 두고 화면 아래쪽에 현위치·줌인·줌아웃이 다시
타이트하게 묶여 배치됨. 좌측 일출/일몰 바는 그대로. 등간격/부등간격 배치 모두 의도된
것이므로 임의로 뭉개지 말 것.

### 확인 질문 및 답변
- Q1. 현재 상단 로고 배지(YURU NAVI) · 라이더모드 토글(햇빛 아이콘) · 갤러리(코스등록)
  아이콘 3개가 와이어프레임에 전혀 안 보이는데, 어떻게 처리? (참고: `8_home_useless_buttons.png`가
  이 3개를 빨간 박스로 표시해둔 것과 일치)
  → **A. 완전 삭제** (기능 자체를 홈 화면에서 제거. 라이더모드 수동 토글 진입점이
  없어지는 것도 인지 후 확정 — 대체 진입점은 이번 라운드 범위 밖, 필요해지면 별도 논의)
- Q2. 현위치/줌인/줌아웃 그룹을 설정/기록/즐겨찾기 그룹과 큰 간격을 두고 화면 아래쪽에
  두는 배치 기준?
  → **A. 설정·기록·즐겨찾기는 화면 상단 기준, 현위치·줌인·줌아웃은 화면 하단 기준으로
  각각 정렬** — 기기 화면 비율이 달라도 상/하단 여백의 일관성이 유지되게. **코스 시트가
  열리면 좌측 일출/일몰 바는 위치가 올라가지만(`5_select_course_layout.png` 참조),
  우측 6개 버튼 그룹은 열림/닫힘과 무관하게 고정 — 코드상 현재와 정반대 방향의 변경**
  (아래 조사 결과 참조).
- Q3. 검색창 스타일(흰 배경 pill, 높이 42, 그림자)을 유지하고 위치·폭만 조정하면 되는지?
  → **A. "내가 그린 그대로 크기·모양·그림자 맞춰줘"** — 재측정 결과 검색창 높이는 버튼
  지름과 정확히 같게(같은 y좌표 구간) 그려져 있었음. 즉 검색창도 버튼과 함께 42px →
  **68px(측정치 반영)로 커짐** — 위 정정 사항과 동일한 이유(장갑·서행 중 조작). 그림자·
  pill 모양(`circular(24)`류 완전 라운드)·흰 배경은 스타일 그대로, 높이만 커지고 폭은
  설정 버튼 자리만큼 줄어드는 것으로 확정(코드 조사 결과 참조).

### 정밀 치수 측정 (와이어프레임 픽셀 분석)
손그림이라 눈대중 해석의 여지를 줄이기 위해 `scipy.ndimage.label`로 와이어프레임의
원형 버튼·검색창을 connected-component 단위로 정확히 분리해 bounding box를 측정함
(스크립트: 회색조 변환 → 링/텍스트 획 색상 대역(120~240)만 마스킹 → 8방향 연결 성분
라벨링). 와이어프레임 캔버스 폭(387px)이 실기기 캡쳐 폭(386px)과 거의 1:1이므로,
**측정된 px 값을 그대로 dp로 사용**(1px ≈ 1dp 근사 — 실제 기기 논리 해상도와 정확히
일치한다는 보장은 없으나, 상대적 비율과 "기존 42px 대비 확대 정도"를 보존하는 것이
핵심이므로 충분히 근거 있는 근사로 판단. 실기기 확인 후 미세조정 여지는 있음).

측정 결과 (컨텐츠 영역: 상태바 하단 y=68 ~ 내비바 상단 y=800, 총 732px):
| 요소 | y범위 | 크기 | 비고 |
|---|---|---|---|
| 검색창 + 설정 버튼 행 | 80–147 | 67px | 상태바 하단에서 12px 여백 |
| 기록 | 154–221 | 67px | 설정과 간격 7px |
| 즐겨찾기 | 229–296 | 67px | 기록과 간격 8px |
| (그룹간 큰 여백) | 296–446 | 150px | 즐겨찾기↔현위치, 전체의 20.5% |
| 현위치 | 446–513 | 67px | |
| 줌인 | 547–614 | 67px | 현위치와 간격 34px — **상단 그룹(7~8px)보다 훨씬 넓음** |
| 줌아웃 | 618–685 | 67px | 줌인과 간격 4px — 사실상 맞닿음, 구분선 없이 하나의 로커처럼 그려짐 |
| (하단 여백) | 685–800 | 115px | 줌아웃↔내비바 상단 |

핵심 발견: 버튼 지름은 6개 전부 **67px로 균일**(현재 코드 42px의 약 1.6배). 상단
그룹(설정·기록·즐겨찾기)은 7~8px의 매우 촘촘한 간격으로 거의 하나처럼 붙어 있고, 하단
그룹은 현위치↔줌인 사이만 34px(상단 그룹 간격의 4배 이상)로 벌어지고 줌인↔줌아웃은
다시 4px로 거의 붙어 있음 — **"등간격 vs 부등간격이 다 의도"라는 마스터 코멘트가
가리키는 실체**가 바로 이 비대칭 간격 패턴(상단 그룹 내부: 균일하게 촘촘 / 현위치↔줌인:
확연히 넓음 / 줌인↔줌아웃: 다시 촘촘)임을 확인.

### 조사 결과 (코드)
파일: `lib/features/map/presentation/main_map_screen.dart`

- **헤더** `_MapHeader` (L1993–2089), 배치 위치 L1844–1865(`Positioned(top:0,left:0,right:0)`
  → `SafeArea(bottom:false)`): 현재 `Container(color: bgColor(반투명 흰/라이더서피스),
  padding: EdgeInsets.fromLTRB(14,6,14,6))` 안에 `Column`으로 [로고+아이콘5개 Row] →
  `SizedBox(height:8)` → [검색창 Material] 순서. 아이콘 Row: `_LogoBadge`(L2091–2143,
  로고, 삭제 대상) → `Spacer()` → `_HeaderIcon`(라이더토글, 삭제 대상) → 갤러리
  `_HeaderIcon`(L2039, 삭제 대상. `onCourseRegister: () {}` 이미 no-op라 기능 손실 없음)
  → 기록 `_HeaderIcon`(L2041, 존치·이동 대상) → 즐겨찾기 `_HeaderIcon`(L2043, 존치·이동
  대상) → 설정 `_HeaderIcon`(L2045, 존치·이동 대상). 검색창은 L2050–2084, 높이 42 /
  `borderRadius.circular(24)` / 그림자 `secondary@0.13, blur 8, offset(0,3)`.
- **우측 패널** `_RightPanel` (L2236–2281), 배치 위치 L1880–1892
  (`Positioned(right:12, top:0, bottom:0)` → `SafeArea`): 현재 하나의 `Column`에
  현위치→줌인→구분선→줌아웃만 있고, `bottomPad = showCourseSheet ? 220.0 : 60.0`
  (L2252)로 **코스 시트가 열리면 이 그룹 전체가 위로 밀려 올라가는 구조** — Q2 답변과
  정반대 방향. 버튼 스타일은 `_MapCtrlBtn`(L2298–2336): 현재 **42×42** 흰 원, 그림자
  `secondary@0.13, blur 8, offset(0,3)` — 원형·흰색·그림자 스타일 자체는 재사용하되,
  크기는 위 정밀 측정치(67px→68dp 채택)로 **확대**해야 함(현재 42px 그대로 재사용 불가 —
  마스터가 명시적으로 지적한 부분).
- **좌측 일출/일몰 바** `_LeftDaylightBar`(L2207–2229), 배치 위치 L1870–1875:
  `Positioned(left:12, top: MediaQuery.height*0.30+100, bottom:160)` — **현재
  `_showCourseSheet`를 전혀 참조하지 않는 고정값**. `5_select_course_layout.png`가
  요구하는 "시트 열리면 올라감" 동작은 아직 구현되어 있지 않음 → 이번 라운드에서 반응형으로
  바꿔야 함(구체 수치는 5번 라운드에서 확정, 여기서는 우측 버튼 그룹과 반대로 시트 상태를
  받는 구조만 확보).
- 버튼 원문 아이콘: 설정=`Icons.settings_outlined`, 기록=`Icons.history_rounded`,
  즐겨찾기=`Icons.bookmark_border_rounded` (L2041/2043/2045에서 그대로 재사용).

### 확정된 수정 계획

**1. 상단 3개 요소 삭제**
- `_LogoBadge`(L2091–2143), 라이더모드 토글 `_HeaderIcon`(L2030–2037), 갤러리
  `_HeaderIcon`(L2039) 제거.
- `_MapHeader`의 `riderMode`/`onRiderModeToggle`/`onCourseRegister` 파라미터와
  호출부(L1851–1854)의 대응 인자도 함께 정리(더 이상 쓰이지 않음).
- `riderModeProvider` 자체(라이더모드 상태/야간모드 로직)는 다른 화면(나이트 모드 자동
  전환 등)에서 계속 쓰일 수 있으니 provider 자체는 건드리지 않고, 홈 화면의 수동 토글
  진입점만 제거.

**2. 헤더를 "검색창 + 설정 버튼" 한 줄로 축소 (크기 확대 반영)**
- `_MapHeader`를 배경 없는(현재 `Container(color:bgColor)` 제거) 투명 `Row`로 교체:
  `[Expanded(검색창), SizedBox(width: 12), 설정 버튼(_MapCtrlBtn 68px)]`.
- 검색창: 높이 **42→68**로 확대, `circular(34)`(높이 68의 완전 라운드 pill로 반경도
  비례 조정), 그림자 스타일(`secondary@0.13, blur8, offset(0,3)`)은 유지. 내부 검색
  아이콘·"장소 검색" 텍스트(L2071–2079)는 커진 pill 높이에 맞춰 폰트/아이콘 크기도
  비례 확대 필요(예 아이콘 20→24, 텍스트 13→15sp 정도) — 정확한 값은 실기기 확인 후
  조정.
- 상하 여백: 기존 `EdgeInsets.fromLTRB(14,6,14,6)` 중 좌우 14는 유지, 상단은 SafeArea
  아래 12dp(측정치, 상태바~버튼행 간격) 적용 — 배경 컨테이너가 없어지므로 검색창·설정
  버튼이 지도 위에 떠 있는 형태(현재 우측 줌/위치 버튼과 동일한 느낌)가 됨.
- 설정 버튼은 `_MapCtrlBtn(icon: Icons.settings_outlined, onTap: onSettings, size: 68)`.

**3. 기록·즐겨찾기 — 상단 기준 고정 그룹 (크기·간격 측정치 반영)**
- 새 `Positioned`(우측 패널과 별개, 헤더 바로 아래): `top: SafeArea.top + 헤더 행 높이
  (68) + 헤더 상단 패딩(12) + 그룹간 간격(측정치 7~8px→8dp)`, `right: 12`.
- `Column`: `_MapCtrlBtn(history_rounded, size:68)` → `SizedBox(height: 8)` →
  `_MapCtrlBtn(bookmark_border_rounded, size:68)`. 간격 8dp는 눈대중 값이 아니라
  와이어프레임 실측(설정↔기록 7px, 기록↔즐겨찾기 8px)을 그대로 반영한 것 — 세 버튼이
  거의 맞닿아 하나의 덩어리처럼 보이는 게 의도임.

**4. 현위치·줌인·줌아웃 — 하단 기준 고정 그룹 (시트 상태 무관, 크기·간격 측정치 반영)**
- 기존 `_RightPanel`(L2236–2281)에서 `showCourseSheet` 파라미터와 `bottomPad` 삼항
  분기(L2252) 제거 → 항상 고정 `bottom` 오프셋(측정치 115px 기반, 예:
  `MediaQuery.padding.bottom + 96`) 하나만 사용.
- 내부 Column을 측정치대로 재구성: `_MapCtrlBtn(my_location, size:68)` →
  `SizedBox(height: 34)`(측정치 — 상단 그룹의 8dp보다 4배 이상 넓은, 확실히 분리돼
  보이는 간격) → `_MapCtrlBtn(add, size:68, bold:true)` → `SizedBox(height: 4)` →
  `_MapCtrlBtn(remove, size:68, bold:true)`. **줌인↔줌아웃 사이 `_ZoomTrackDivider`
  (L2284–2296, 점선 트랙 표시용 작은 바)는 와이어프레임에 대응하는 표시가 없음(4px
  간격뿐, 구분선 없이 거의 맞닿은 로커 형태) — 이번 라운드에서 제거 후보로 표시. 완전히
  없앨지, 아주 얇게 남길지는 실기기 시안에서 최종 확인.**
- 배치 컨테이너를 `Positioned(right:12, top:0, bottom:0)` + 내부 Padding(top) 방식에서
  `Positioned(right:12, bottom: 고정값)`로 변경(그룹이 스스로 하단에 붙고, 위쪽은
  Column의 실제 높이만큼만 차지 — 남는 공간이 자동으로 "그룹 사이 큰 여백"이 되므로
  즐겨찾기↔현위치 간의 150px 여백을 따로 하드코딩할 필요 없음. 상단 그룹은 위에서,
  하단 그룹은 아래에서 각자 고정 → 사이 간격은 화면 크기에 따라 자동으로 늘고 줄어듦,
  이게 Q2 답변이 요구한 "비율 기반" 정렬의 실질적 구현).
- `showCourseSheet: _showCourseSheet` 호출부 인자(L1886)도 제거.

**5. 좌측 일출/일몰 바 — 코스 시트 반응형으로 전환 (5번 라운드와 공유)**
- `_LeftDaylightBar` 배치(L1870–1875)에 `_showCourseSheet` 값을 전달받아 시트가 열리면
  `top`/`bottom`을 위로 당기는 로직 추가 필요 — 구체적 목표 위치·수치는 라운드 5
  (`5_select_course_layout.png`, 코스 선택 레이아웃)에서 확정. 이번 라운드에서는 "우측
  버튼 그룹은 고정, 좌측 바만 반응형"이라는 방향만 확정하고 실제 구현은 5번과 함께 처리.

**6. 버튼 시각 통일 + 크기 확대 (핵심 변경)**
- 설정·기록·즐겨찾기·현위치·줌인·줌아웃 6개 전부 `_MapCtrlBtn` 계열(흰 원,
  `secondary@0.13/blur8/offset(0,3)` 그림자) 스타일은 통일하되, 고정값 `42`였던 지름을
  **`size` 파라미터로 뽑아 68로 확대** — 와이어프레임 실측(67px) + 오토바이 주행 중
  장갑·서행 조작을 고려한 마스터의 명시적 요구 반영. 내부 아이콘 크기도 42px 기준
  20~22px였던 것을 68px 기준으로 비례 확대(예 32~34px) 필요.
- `_MapCtrlBtn`에 아이콘 3종(`settings_outlined`, `history_rounded`,
  `bookmark_border_rounded`) 추가 지원만 하면 되고 새 위젯은 필요 없음.
- `_HeaderIcon`(L2155–2201)·`_LogoBadge`(L2091–2143)는 다른 화면에서 참조하는 곳이
  없다면 함께 삭제(구현 단계에서 grep으로 재확인).

### 미확정 / 구현 시 확인
- 버튼·검색창 크기(68dp)와 간격(8 / 34 / 4 / 상단여백12 / 하단여백96)은 와이어프레임을
  connected-component 픽셀 분석으로 실측한 값 — 42px 재사용안은 폐기. 다만 px→dp
  변환은 "패널 폭 1:1" 가정에 기반한 근사이므로, 실기기 빌드 후 마스터 육안 확인으로
  미세조정 여지는 있음을 재확인.
- 줌인↔줌아웃 사이 기존 `_ZoomTrackDivider`(점선 표시 바)를 제거할지 — 와이어프레임엔
  대응 요소가 없어 제거 후보로 표시했으나 최종 확정은 시안 확인 후.
- 검색창 내부 아이콘/텍스트 크기 확대폭 — 68px pill에 맞춘 비례값은 제안일 뿐, 실기기
  시안에서 가독성 확인 필요.
- 라이더모드 수동 토글 진입점이 완전히 사라지는 것 재확인됨(Q1) — 자동 전환 로직
  유무는 이번 라운드 조사 범위 밖.

### 상태: **구현 완료 (2026-07-31, 라운드8과 동일 세션)**
flutter-coder → code-auditor PASS → 커밋 `644a757`(`feat(theme,map): 라이더모드/
야간모드 전체 삭제 + 홈 화면 레이아웃 재구성`). 헤더 검색창+설정버튼 68px 축소,
기록·즐겨찾기 상단 고정그룹, 현위치·줌인·줌아웃 하단 고정그룹(시트상태 무관) 전부
반영됨. **주의(다음 라운드가 알아야 할 것)**: `_MapCtrlBtn`에 `size` 파라미터는
추가됐지만(기본42/호출부68), `lib/core/widgets/`로의 공용 위젯 추출은 **아직
안 됨** — 여전히 `main_map_screen.dart`의 private 클래스다. 라운드6이 이 추출을
맡기로 한 계획 그대로 유효. 좌측 일출/일몰 바 반응형 로직도 계획대로 라운드5로
그대로 이연됨(이번에 손대지 않음).

---

## 라운드 4 — 2026-07-30 (POI 선택 카드)

**참조 이미지**: `loop/layout_fixes/4_select_location.png` — 좌측 실기기 캡쳐(현재 상태) +
우측 마스터 손그림 와이어프레임(변경안).

### 마스터 피드백 요약
POI 선택 시 아래에서 위로 올라오는 카드(POI 이름 + 출발/경유지/목적지 버튼)의 문제점:
(1) POI 이름 폰트가 너무 작음 (2) "어디로 추가할까요?" 같은 불필요한 안내문구 (3) 경유지
버튼이 줄바꿈되는 디자인 재앙. 요구사항: 이름을 크게, 안내문구 삭제, 버튼 한 줄 유지,
출발지/경유지/목적지 버튼 중 하나를 누르면 브랜드 지정 컬러로 색이 들어옴, 우측 상단에
즐겨찾기 등록용 별 버튼 추가(빈 상태는 외곽선 별, 이미 즐겨찾기된 POI는 노란색 꽉 찬
별), 별을 누르면 즐겨찾기 등록 카드(14번 이미지 참조)가 위에 추가로 뜸.

### 확인 질문 및 답변
- Q1. 즐겨찾기 등록 카드는 다른 시트에 이미 구현된 `_FavoriteStarButton` +
  `_AddFavoriteSheet`(이름 입력 + 카테고리 선택, 14번 그림과 동일 개념)를 그대로
  재사용하면 되는지?
  → **A. 그대로 재사용**
- Q2. 버튼을 누르면 "색깔이 들어온다"는 것이, 현재 코드의 즉시-`Navigator.pop`(누르자마자
  시트가 닫히고 동작 실행, 경유지 여러 곳 순차 선택 불가) 동작은 그대로 두고 누르는
  순간의 시각 피드백(브랜드색 채움)만 의미하는지, 아니면 여러 개를 순서대로 고를 수
  있도록 동작 자체를 바꿔야 하는지?
  → **A. 탭 피드백만 의미. 현재의 즉시-닫힘 동작·로직은 변경하지 않음.** 경유지를 여러
  곳 순차 등록하는 UX는 이번 라운드 범위 밖 — 6번 이미지(`6_add_waypoint_layout.png`,
  경유지 추가 레이아웃) 라운드에서 별도로 다룸.
- Q3. 현재 코드는 출발=파랑, 목적지=프라이머리색(주황 계열), 경유지=회색으로 버튼마다
  색이 다른데, 와이어프레임엔 3개가 동일한 스타일로 그려져 있음. 색상을 어떻게 정리할지?
  → **A. 3개 버튼 모두 동일한 브랜드컬러 하나로 통일**
- Q4. 경유지 버튼은 목적지가 아직 없으면 비활성화(회색, 탭 불가)되는 기존 로직이 있는데
  이번 라운드에서 유지할지?
  → **A. 유지 — 이번 라운드는 시각만 정리, 기능 로직은 손대지 않음**

### 조사 결과 (코드)
파일: `lib/features/map/presentation/main_map_screen.dart`

- **카드 위젯**: `_AddToRouteSheet`(L3571-3690, `StatelessWidget`, `name`/`hasDest`
  파라미터). 진입 경로: POI 마커 탭 `_handlePoiTap`(L1050) → `_handleLocationTap`(L1062)
  → `_showAddToRouteSheet`(L1230, 시트는 L1238에서 빌드). 검색결과 탭
  (`_handleAddressTap`, L1130)도 동일 시트를 재사용.
- **안내 문구**: L3608-3615, `Text('어디로 추가할까요?', fontSize:13, grey)`. 삭제 대상.
- **POI 이름**: L3617-3625, `fontSize:15, w600, maxLines:2, ellipsis`. 확대 + 즐겨찾기
  별과 한 `Row`로 재배치 필요.
- **버튼 Row**(L3632-3683): 3개 `Expanded(OutlinedButton.icon(...))`.
  출발=`Colors.blue` 외곽선/아이콘/텍스트, 경유지=`hasDest` 여부에 따라
  `grey.shade600`/`grey.shade300`, 목적지=`AppColors.primary`(현재 값
  `#F28C28` — 2026-07-29 확정된 새 브랜드 아이덴티티 코랄 `#E2896F`와는 별개 팔레트,
  이는 로드맵 11번[하드코딩 스타일→토큰 기반 리팩터]에서 전사적으로 다룰 사안이라 이번
  라운드 범위 밖. 이번엔 기존 `AppColors.primary` 토큰을 그대로 "브랜드컬러"로 사용).
  "경유지"(3글자)가 "출발"/"도착"(2글자)보다 길고 `Text`에 `maxLines`/`softWrap:false`
  지정이 없어, 균등폭(`Expanded`) 제약 하에서 줄바꿈이 발생하는 게 실제 원인.
- **즐겨찾기 별 버튼**: `_FavoriteStarButton`(L2546-2588, `ConsumerWidget`) —
  `favoritePlacesProvider` watch, `FavoritePlace.findByLocation`으로 `isFav` 판정.
  즐겨찾기됨 = `Icons.star_rounded` 노란(`#FFB300`) 채움, 아니면
  `Icons.star_border_rounded` 회색 외곽선. 탭 시: 이미 즐겨찾기면 `.remove()` 바로 호출
  (즉시 토글 해제), 아니면 `_showAddFavoriteSheet` 오픈. 이미 `_showTapConfirmSheet`
  (L1181) 등 다른 시트 3곳(L1181/3377/3458)에 연결돼 있으나 `_AddToRouteSheet`에는
  아직 없음.
- **즐겨찾기 등록 카드**: `_AddFavoriteSheet`(L2593-2665+, `ConsumerStatefulWidget`) —
  이름 입력(POI/주소명 기본값) + `favoriteCategoriesProvider` 기반 카테고리 칩 선택 +
  확인 버튼(`favoritePlacesProvider.notifier.add(...)`). 14번 이미지(내 장소 화면
  즐겨찾기 카테고리 UI)와 동일 개념이며 이미 구현되어 그대로 재사용 가능.

### 확정된 수정 계획

**1. 안내 문구 삭제**
- L3608-3616의 `Text('어디로 추가할까요?', ...)`와 뒤따르는 `SizedBox(height:2)` 통째로
  제거.

**2. POI 이름 확대 + 즐겨찾기 별 버튼 추가 (한 Row로 재배치)**
- 기존 이름만 있는 `Column`(L3605-3627)을 `Row`로 변경:
  `[Expanded(POI 이름 Text — 확대 폰트 예 20~22sp w700, maxLines:1, overflow:ellipsis),
  SizedBox(width:8), _FavoriteStarButton(...)]`.
- `_FavoriteStarButton` 생성자가 요구하는 파라미터는 다른 사용처(L1181/3377/3458)와
  동일하게 맞춰 전달 — `_AddToRouteSheet`가 현재 `name`만 필드로 갖고 있어 좌표 등 추가
  데이터가 필요하면 `_showAddToRouteSheet` 호출부(L1230/1238)까지 전달 경로를 넓혀야
  할 수 있음(구현 시 확인).

**3. 버튼 Row 3개 — 줄바꿈 해결 + 색상 통일**
- "경유지" 줄바꿈 수정: `Text`에 `softWrap:false`(+필요시 버튼 내부 패딩 축소,
  `OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal:4))`)로 3글자가
  한 줄에 들어가게 처리. 아이콘 크기(16)는 유지 우선 시도하되, 라벨 폭이 부족하면
  아이콘 축소(14) 또는 제거를 실기기 확인 후 최종 결정.
- 색상 통일: 3개 버튼의 `Colors.blue`/`grey.shade600`/`AppColors.primary` 각각 다른
  색상 대신 **`AppColors.primary` 하나로 통일**(외곽선+아이콘+텍스트 모두). 단, 경유지
  비활성 상태(`hasDest==false`)는 기존처럼 회색 계열을 그대로 유지(Q4 답변에 따라 기능
  제약과 함께 그 시각적 구분도 유지).
- 탭 시각 피드백: `OutlinedButton`의 흐릿한 기본 잉크 스플래시 대신 `style`에
  `overlayColor: WidgetStateProperty.all(AppColors.primary.withOpacity(0.15))` 정도를
  추가해 눌렀을 때 브랜드컬러가 분명히 보이도록 처리 — "누르면 색이 들어온다"에 해당하는
  부분이며, `Navigator.pop` 즉시-닫힘 동작 자체는 변경하지 않음(Q2 확정 사항).

**4. 경유지 비활성화 로직 — 변경 없음**
- L3665-3667의 `onPressed: hasDest ? (...) : null` 그대로 유지.

### 미확정 / 구현 시 확인
- `_FavoriteStarButton` 생성자 파라미터를 다른 3개 사용처에서 정확히 확인 후
  `_AddToRouteSheet`에 맞춰 전달(좌표 등 추가 데이터 필요 시 호출부까지 전달 경로 확장).
- POI 이름 확대 폭(20~22sp 제안)은 실기기 확인 후 미세조정.
- 경유지 버튼 라벨 유지 여부(아이콘 유지 vs 제거)는 실기기 시안에서 최종 확인.
- 경유지 여러 곳 순차 등록 UX는 이번 라운드 범위 밖 — 6번 라운드
  (`6_add_waypoint_layout.png`)에서 별도 처리.

### 상태: **구현 완료 (2026-07-31, 배치2/라운드4→5→6 세션)**
flutter-coder → code-auditor PASS → 커밋 `b13923f`(`feat(map): POI 선택 카드
재디자인`). 안내문구 삭제, 이름 폰트 확대(20sp w700)+`_FavoriteStarButton`
추가(`_AddToRouteSheet`에 `lat`/`lng` 필드 신설, `_showAddToRouteSheet`가
`location`에서 전달), 출발/경유지/도착 버튼 `AppColors.primary` 통일(경유지
비활성 상태는 회색 유지) + `softWrap:false`로 줄바꿈 버그 수정 + 탭 시
`overlayColor` 브랜드컬러 피드백 추가. `hasDest` 비활성화 로직 불변.

---

## 라운드 5 — 2026-07-30 (코스 선택 카드)

**참조 이미지**: `loop/layout_fixes/5_select_course_layout.png` — 좌측 실기기 캡쳐(현재
상태) + 우측 마스터 손그림 와이어프레임(변경안).

### 마스터 피드백 요약
출발지·목적지 선택 후 아래에서 위로 올라오는 코스 선택 카드가 (1) 디자인 요소 없이
밋밋하고 (2) 글씨가 작으며 (3) 재미 점수가 직관적이지 않음. 요구사항: 출발지/목적지만
있고 경유지가 없으면 카드 상단에 "경유지" 글씨를 회색으로 표시. 경유지는 경로가 표시된
지도를 터치하면 4번 이미지의 POI 카드가 뜨는 방식으로 선택(POI 없는 곳 터치 시 이름
자리에 좌표 표시). 가독성 개선 + 선택한 코스는 브랜드 컬러로 강조. "Start your Engine"
슬라이드 버튼은 플로팅 스타일로 다듬고, 드래그 로직은 유지한 채 문구를 "Slide to
Ride"로 교체, 폰트는 마스터가 쓴 폰트를 따름.

### 확인 질문 및 답변
- Q1. 코스 시트가 열려 있을 때(경로 표시 중) 지도를 탭하면 뜨는 시트 — 현재 코드는
  마커/검색결과를 탭할 때 뜨는 4번 카드(`_AddToRouteSheet`)와, 빈 지도를 탭할 때 뜨는
  별도의 단순 확인시트(`_showTapConfirmSheet`)로 나뉘어 있음. 어느 쪽으로 통일할지?
  → **A. 항상 4번 카드로 통일** (코스 시트가 열려 있는 동안은 지도 탭 시 항상
  `_AddToRouteSheet`, POI 없으면 좌표 문자열을 이름 자리에 표시)
- Q2. 와이어프레임 카드엔 재미 점수가 아예 없음(거리/시간만) — 완전히 뺄지, 표현만
  바꿀지?
  → **A. 카드에서 완전히 제거**
- Q3. "디자인 요소도 없다"는 지적을 구체적으로 어떻게 반영할지(아이콘 추가 vs 카드
  표면 자체 디자인)?
  → **A. 카드 표면 디자인 강화** (아이콘 추가가 아니라 배경 톤/그림자 등 카드 자체의
  마감을 브랜드 무드에 맞게 새로 입힘)
- Q4. "Slide to Ride" 폰트 — 프로젝트에 등록된 커스텀 브랜드 폰트가 없어 그림에 쓰인
  폰트를 코드만으로 특정 불가.
  → **A. 원래 희망은 iOS 밀어서 잠금해제와 같은 Helvetica Neue(Light)이나, 마스터 PC에
  헬베티카가 없어 이 와이어프레임에서는 나눔고딕 Light로 대체 표기한 것. 앱에 폰트
  파일을 넣거나 다운로드할 필요 없이, 마스터가 파워포인트에서 SVG로 내보낸 벡터
  텍스트 이미지를 제공하기로 함** — `Text` 위젯 대신 `Image.asset`(SVG)로 렌더링.

### 조사 결과 (코드)
- **위젯**: `CourseSheet` (`lib/core/widgets/course_sheet.dart:14-211`), 라우트 카드
  `RouteCard`(`:219-321`), 슬라이드 버튼 `SliderStartButton`
  (`lib/core/widgets/slider_start_button.dart:18-169`). `main_map_screen.dart`와
  `nav_screen.dart` 양쪽에서 공유(`main_map_screen.dart:1947-1963`,
  `nav_screen.dart:2476-`).
- **상단 요약 행** (`course_sheet.dart:96-141`): 현재 파랑/빨강 원 점 + "현재
  위치"/`destinationName ?? '목적지'` + 가운데 "→"(경유지 0개) 또는 "· 경유 N개 ·"
  텍스트. 와이어프레임의 "이름 >> 경유지 >> 이름" 형태(점 없음, 실제 지명, 화살표
  대신 ">>")와 다름.
- **지명 버그 발견**: `_applyDestination`(`main_map_screen.dart:1245-1298`)이
  `setDestination(dest, dist, snapshotOrigin: origin)`(L1249) 호출 시 `name:` 인자를
  넘기지 않아 `RouteStop.name`이 항상 null. 실제 POI/검색 지명은 비동기로
  `setDestinationName()`(L1291/1295) → `MapInteractionState.destinationName`
  (`map_providers.dart:115`, `stops`와는 별개 필드)에만 저장되고, `CourseSheet` 호출부
  (`main_map_screen.dart:1960-1962`)는 `interaction.stops.last.name`만 읽어서 항상
  폴백 문구("목적지")가 표시됨. **결론: `destinationName` 파라미터를
  `interaction.destinationName ?? interaction.stops.last.name`로 한 줄만 고치면
  해결** — provider 구조는 건드릴 필요 없음.
- **경유지 이름**: `MapInteractionState.waypointNames` 게터
  (`map_providers.dart:143-145`)가 이미 존재 — `stops[1..last-1]`의 이름 리스트. 단일
  경유지면 `waypointNames.first`를 그대로 쓸 수 있음.
- **경유지 진입점 2종 공존**: (1) `course_sheet.dart:144-161`의
  칩/버튼(`onWaypointEntryTap` → `main_map_screen.dart:1460-1467`
  `_showWaypointSheet` → `WaypointManagementSheet`, 검색 기반), (2)
  `_onMapTap`(L978-998)의 지도 빈 곳 탭 → `_showTapConfirmSheet`(L1136-1226) →
  `hasRoute`(=`_showCourseSheet`)일 때만 "경유지 추가" `ListTile` 노출(L1205-1213).
  마커/검색결과 탭은 이미 `_handlePoiTap`→`_handleLocationTap`(L1050-1126) →
  `_showAddToRouteSheet`(L1230-1243, 4번 카드 `_AddToRouteSheet`)로 연결되어 있어
  Q1 답변과 무관하게 이미 4번 카드를 씀 — **바꿔야 할 건 `_onMapTap`(빈 지도 탭)
  하나뿐**.
- **재미 점수**: `RouteCard`(`course_sheet.dart:293-315`) — `'재미
  ${windingScore.toStringAsFixed(0)}'`, 최고점 카드만 색 강조. 제거 대상.
- **선택 강조 색상**: `RouteCard`(`:248-263`)는 이미 `context.skin.colors
  .courseLineColor`(스킨별 브랜드 컬러, 예 유루캠 스킨
  `yurucam_skin.dart:87-91` 코랄/모스/슬레이트)로 선택 시 배경 tint+보더+그림자를
  입히는 구조 — "브랜드 컬러 내에서 강조"라는 요구는 색상 소스 자체는 이미 맞게
  구현돼 있고, 이번 라운드는 그 강조를 표면 디자인(문의 Q3)과 통합해 더 뚜렷하게
  만드는 폴리시 작업임.
- **슬라이드 버튼**: `slider_start_button.dart:131-168` — 트랙
  `borderRadius.circular(14)`(완전 pill 아님) + `AppColors.primary` 15% tint 배경,
  썸(`_thumbSize=52`)은 `AppColors.primary` 단색 원 + 흰 `double_arrow_rounded`
  아이콘, 텍스트는 `_StartLabel`(L171-186) `AppTextStyles.labelLG` 진한 네이비 굵게.
  와이어프레임은 트랙 전체가 완전 pill(둥근 양끝) + 흰색/옅은 배경 + 은은한 플로팅
  그림자, 썸도 흰 배경에 얇은 `>` 쉐브론(아웃라인), 텍스트는 연회색(placeholder
  톤) — 상당히 다른 스타일.
- **폰트**: `pubspec.yaml:77-81`엔 `DSEG7Classic`(LED 게이지 전용) 하나뿐, 코스
  시트/버튼은 전부 `GoogleFonts.plusJakartaSans`(`app_theme.dart:67-121`) 사용 중.
  `flutter_svg: ^2.0.10`이 이미 의존성에 있고(`pubspec.yaml:41`) `assets/images/`가
  이미 통째로 에셋 등록되어 있어(`pubspec.yaml:67`) SVG 한 장 추가에 pubspec 수정
  불필요.
- **CourseSheet 배경은 다크/야간모드 무관**: `course_sheet.dart:56`이 `Colors.white`
  하드코딩 — `nav_screen.dart` 야간 내비게이션 중에도 항상 흰 배경으로 뜸. 즉
  "Slide to Ride" 벡터 텍스트는 다크 배경 대응 버전 없이 라이트 버전 하나만 있으면 됨.

### 확정된 수정 계획

**1. 상단 요약 행 재설계 (지명 버그 수정 + 와이어프레임 스타일)**
- `main_map_screen.dart:1955-1962` 호출부: `originName`은 현행 유지(GPS 출발지면
  "현재 위치", 아니면 `stops.first.name`), `destinationName`은
  `interaction.destinationName ?? interaction.stops.last.name`로 수정(1줄, 위에서
  찾은 버그의 근본 수정) — 이제 실제 검색/POI 지명이 표시됨.
- `course_sheet.dart:96-141`을 와이어프레임처럼 재작성: 파랑/빨강 원 점 제거, 구분자를
  "→"/"· 경유 N개 ·" 대신 ">>"로 통일, 가운데 세그먼트는:
  - `waypointCount == 0`: 회색 "경유지" 텍스트(마스터 명시 요구사항)
  - `waypointCount == 1`: `waypointNames.first` 표시(진한 텍스트)
  - `waypointCount > 1`: "경유지 N곳"(순차 다중 경유지 UX는 6번 라운드
    `6_add_waypoint_layout.png` 범위 — 여기서는 표시만 정리)
  - 가운데 세그먼트 전체를 탭 가능하게 유지해 기존 `onWaypointEntryTap`
    (`WaypointManagementSheet`, 검색 기반 추가/편집)에 연결 — 별도의
    "+ 경유지 추가" 텍스트버튼 행(`:144-161`)은 이 통합 행으로 흡수되어 삭제.
    지도 탭으로 추가하는 경로(2번 계획)와 검색으로 추가하는 경로가 모두 살아있는
    상태 유지.

**2. 지도 탭 → 4번 카드(`_AddToRouteSheet`)로 통일 (Q1)**
- `_onMapTap`(`main_map_screen.dart:978-998`)에 분기 추가: `_showCourseSheet ==
  true`(경로 표시 중)이면 `_showTapConfirmSheet` 대신 `_showAddToRouteSheet` 호출.
  `name`은 `poi?.name ?? '${tapped.latitude.toStringAsFixed(5)},
  ${tapped.longitude.toStringAsFixed(5)}'`(POI 없으면 좌표 — 마스터 명시 요구사항),
  `hasDest: true`(이미 목적지 있는 상태이므로 항상 true).
- 반환된 `_RouteAddAction`(origin/waypoint/destination) 처리 로직은
  `_handleLocationTap`(L1107-1125)에 이미 있는 것과 동일 — 중복 구현하지 않고 공용
  헬퍼로 추출해 `_onMapTap`의 새 분기와 `_handleLocationTap` 양쪽에서 재사용.
- `_showCourseSheet == false`(아직 목적지 선택 전)일 때는 기존
  `_showTapConfirmSheet` 흐름 그대로 유지 — 이 상태에선 4번 카드가 필요한 "경유지"
  옵션 자체가 없으므로 변경 불필요.
- **정리(죽은 코드 제거)**: 위 분기로 `_showTapConfirmSheet`는 이제 `hasRoute`가
  항상 `false`인 채로만 호출되므로, `hasRoute` 파라미터와 L1205-1213의 "경유지 추가"
  `ListTile` 분기를 함께 제거. `_applyTapAction`(L1002-1044)의
  `_TapAction.waypoint` 케이스(L1021-1036)도 도달 불가능해지므로 함께 제거.

**3. 재미 점수 완전 제거 (Q2)**
- `course_sheet.dart:293-315`(`windingScore`/`isBestFun` 배지 블록) 통째로 삭제.
  `RouteCard`의 `windingScore`/`isBestFun` 파라미터, `CourseSheet`의 `bestWs`
  계산(L176-177)도 더 이상 안 쓰이면 함께 정리.
- `routeMeta`의 `windingScore` 필드 자체(타입/계산 파이프라인,
  `native_engine.dart` `scoreFunV2` 등)는 안 건드림 — 카드에 안 보여줄 뿐, 향후 다른
  화면(예 히스토리 상세)에서 쓸 수 있으니 계산 로직은 유지.

**4. 코스 카드 표면 디자인 강화 + 가독성 (Q3)**
- `RouteCard`(`course_sheet.dart:219-321`) 표면을 지금의 "흰 배경(미선택)/색
  tint(선택)" 이분법에서, 미선택 상태에도 카테고리 색을 아주 옅게(alpha 0.05 수준)
  깔아 카드마다 은은한 색 정체성을 주고, 선택 시 tint를 더 진하게(현재 0.09→약
  0.14) + 보더/그림자를 더 뚜렷하게 강화 — "선택한 코스만 브랜드 컬러로 강조"가
  훨씬 분명하게 보이도록.
- 도로 타입 라벨("시골길로\n느긋하게")을 일반 텍스트 대신 카테고리 색 배경의 작은
  둥근 pill/태그로 감싸 시각적 무게를 줌(아이콘 없이 타이포+색만으로 "디자인 요소"
  보강, Q3 답변에 따라 별도 아이콘은 추가하지 않음).
- 가독성: 거리(`distStr`) 폰트 15→약 18~20sp, 소요시간(`duration`) 10→12sp,
  라벨(pill 안 텍스트) 약 13sp로 확대. 재미 점수 배지가 빠지며 생기는 여유 공간은
  카드 세로 패딩 확대에 사용.
- 정확한 alpha/px 값은 실기기 시안에서 마스터 확인 후 미세조정(다른 라운드와 동일한
  패턴).

**5. "Start your Engine" → "Slide to Ride" 플로팅 리디자인 (Q4)**
- 드래그/완료 판정 로직(`_onDragUpdate`/`_onDragEnd`/`_animateTo`,
  `slider_start_button.dart:83-117`)은 **전혀 변경하지 않음** — 마스터가 명시적으로
  "현행 드래그 인식률이 좋다"고 확인한 부분.
- 트랙(`:131-137`) 스타일만 교체: `borderRadius.circular(14)` →
  `_trackHeight/2`(완전 pill), 배경을 `AppColors.primary` 15% tint에서 흰색/옅은
  배경 + 플로팅 그림자(`secondary@0.13, blur 10, offset(0,4)` — `_MapCtrlBtn`류와
  같은 계열의 그림자 토큰 재사용)로 변경.
- 썸(`:147-159`) 스타일 조정: 단색 `AppColors.primary` 원 대신 흰 배경 + 자체 그림자
  + 얇은 쉐브론(`>`) 아이콘(브랜드 색, 예 `AppColors.primary` 또는 skin
  코스라인컬러[2])으로 와이어프레임에 맞춤. 도형은 원 유지(와이어프레임이 완전한
  원인지 둥근 사각형인지 raster 상 애매 — 실기기 시안에서 최종 확인).
  `Icons.double_arrow_rounded` → `Icons.chevron_right_rounded`(홑화살표)로 교체.
- 텍스트(`_StartLabel`, `:171-186`): `Text('Start your Engine', ...)` →
  `Image.asset('assets/images/slide_to_ride_label.svg')`로 교체(마스터가 파워포인트
  → SVG로 제작해 전달 예정, `flutter_svg` 이미 의존성에 있어 추가 설치 불필요,
  `assets/images/`는 이미 pubspec에 등록돼 있어 파일만 넣으면 됨). 다크모드 대응
  불필요(코스 시트 배경이 항상 흰색으로 고정돼 있음, 조사 결과 참조) — 라이트 버전
  한 장이면 충분.
- 텍스트 위치/정렬(`Align(Alignment(0.15,0))`, `:140-143`)은 새 이미지 크기에 맞춰
  좌표 조정 필요 — 정확한 값은 자산 전달 후 확인.

### 미확정 / 구현 시 확인
- `_onMapTap`의 `_RouteAddAction`/`_TapAction` 공용 헬퍼 추출 방식(어떤 이름·시그니처로
  합칠지)은 구현 단계에서 확정.
- 카드 표면 tint alpha, 라벨 pill 색상 진하기, 폰트 확대 폭 등은 실기기 시안 확인 후
  미세조정.
- 슬라이드 버튼 썸 모양(원 vs 둥근 사각형), 트랙/썸 정확한 배경색(순백 vs 아주 옅은
  브랜드 tint)은 실기기 시안에서 최종 확인.
- "Slide to Ride" SVG 자산은 마스터가 별도 제작해 전달할 예정 — 전달 전까지는 임시로
  기존 `Text` 위젯 유지한 채 문구만 바꿔서라도 먼저 진행할지, 자산 도착까지 이 항목만
  보류할지는 배치 구현 시작 시점에 확인.
- 경유지 다건(2곳 이상) 표시 문구("경유지 N곳" 등)와 그 처리 UX는 6번 라운드
  (`6_add_waypoint_layout.png`)와 연계해 최종 확정.

### 상태: **구현 완료 (2026-07-31, 배치2/라운드4→5→6 세션)**
flutter-coder → code-auditor PASS → 커밋 `4ae6ccf`(`feat(map): 코스 선택
카드 재디자인 + 지도탭 배관 통합`). `destinationName` 미참조 버그 수정
(`interaction.destinationName ?? interaction.stops.last.name`), 상단 요약행
재설계(점 제거·`>>` 구분자·`waypointNames` 신설 파라미터로 경유지 이름
표시), `_onMapTap`이 `_showCourseSheet==true`일 때 `_showAddToRouteSheet`로
분기(공용 헬퍼 `_applyRouteAddAction`으로 `_handleLocationTap`과 로직
공유) + `_showTapConfirmSheet`의 `hasRoute`/`_TapAction.waypoint` 죽은
코드 정리, 재미점수 배지 카드에서 제거(계산 로직은 유지), 카드 표면
tint/보더/그림자 강화 + 폰트 확대, 슬라이드 버튼 완전 pill+흰배경+그림자
+ 흰 썸+쉐브론 아이콘 + `slide_to_ride_label.png` 이미지로 텍스트 교체
(드래그 로직 무변경, 감사에서 바이트 단위 확인), 좌측 일출/일몰 바
`_showCourseSheet` 반응형 위치(`bottom: 380/160`) 적용(라운드3 이월 항목).

---

## 라운드 6 — 2026-07-30 (경유지 관리 카드)

**참조 이미지**: `loop/layout_fixes/6_add_waypoint_layout.png` — 좌측 실기기 캡쳐(현재
"경유지 관리" 시트) + 우측 마스터 손그림 와이어프레임(5번 화면 위에 겹쳐진 형태로 그림).

### 마스터 피드백 요약
5번 카드 상단의 "경유지" 글씨가 활성화(경유지 1개 이상 추가된 상태 = 검정색)된 상태에서
그 글씨를 터치하면 5번 카드 위에 경유지 관리 카드가 아래→위로 슬라이드하여 나타남. 카드
맨 위는 출발지, 맨 아래는 도착지, 중간은 경유지 — 구분 없이 자유롭게 순서 변경 가능(출발지
↔경유지, 경유지↔도착지 맞바꿈 포함), 순서를 바꾸면 즉시 재탐색해 지도에 경로 갱신. 우측
원형 `-` 버튼으로 경유지 개별 삭제. 출발지·도착지 옆의 `+` 버튼을 누르면 경유지 관리
카드가 폰 아래로 내려가고, 지도 위에서 직접 위치를 골라 경유지를 추가할 수 있음(4번
이미지의 POI 카드를 거쳐서).

### 확인 질문 및 답변
- Q1. 출발지 옆 `+`와 도착지 옆 `+`를 눌러 지도에서 고른 위치가 리스트의 어디에 삽입되는지?
  → **A. 버튼 위치에 따라 다름** — 출발지 옆 `+` → 첫 번째 경유지로 삽입(출발지 바로
  다음), 도착지 옆 `+` → 마지막 경유지로 삽입(도착지 바로 앞, 현재 `addWaypoint`와 동일).
- Q2. `+` → 지도에서 위치 선택 → 4번 POI 카드에서 "경유지" 선택까지 완료되면 화면이
  어디로 돌아가는지?
  → **A. 6번 경유지 관리 카드로 자동 복귀** — 갱신된 목록을 바로 보여줌.
- Q3. 기존 하단의 검색 기반 "+ 경유지 추가" 버튼(주소 검색 시트)을 유지할지?
  → **A. 제거** — 이번 라운드의 지도 기반 `+` 버튼 두 개로 완전히 대체.
- Q4. 리스트 행 시각 스타일 — 기존 색깔 점(주황/회색/빨강) 인디케이터 유지 여부?
  → **A. 와이어프레임대로(점 제거, ⇕/⊕/⊖ 아이콘 중심)** 가되, **출발지·도착지 행은
  글씨를 bold로 표시**해 경유지 행과 구분한다(점 대신 타이포로 구분).

### 조사 결과 (코드)

- **시트 위젯**: `WaypointManagementSheet`
  (`lib/features/map/presentation/waypoint_management_sheet.dart:16-22`, 실제 UI는
  `_SheetBody:114-293`). `DraggableScrollableSheet`(초기 0.6/최대 0.9/최소 0.4,
  L82-86) 안에 핸들바(L144-154) → 재계산 중 `LinearProgressIndicator`(L158-165) →
  헤더 "경유지 관리"+닫기 버튼(L168-189) → `ReorderableListView`(L197-258) → 하단
  "+ 경유지 추가" `TextButton.icon`(L263-288, Q3에 따라 **통째로 삭제 대상**).
- **재정렬·삭제는 이미 구현되어 있어 그대로 재사용 가능**:
  - 드래그 재정렬: `ReorderableListView.onReorderItem`(L204-209) → 시트의
    `onReorder` 콜백(L93-98) → `MapInteractionNotifier.reorderStop`
    (`lib/features/map/providers/map_providers.dart:263-272`) — 출발지·경유지·
    도착지 구분 없이 전부 재배치 가능(코드 주석 자체가 이를 명시), 위치 제약 없음.
    재정렬 직후 `_recalculate()`(시트 L30-58, `RoutingService.fetchRoutes` 호출)로
    즉시 경로 갱신 — 마스터 요구사항과 이미 일치, **변경 불필요**.
  - 삭제: 리스트 아이템의 `IconButton(Icons.remove_circle_outline)`은 `0 < i <
    total-1`(중간 경유지)에서만 노출(L234-245) → `onRemove` → `removeWaypoint`
    (`map_providers.dart:254-260`, 도착지 삭제는 자체 가드로 거부). **이미
    와이어프레임의 "⊖는 중간 행에만" 요구와 일치, 로직은 변경 불필요** — 이번
    라운드는 아이콘을 `Icons.remove_circle_outline`(단순 아이콘 버튼) →
    와이어프레임 스타일(원형 배지)로 시각만 교체.
- **신규로 필요한 것: 출발지/도착지 옆 `+`(지도 기반 추가) — 현재 코드에 없음.**
  - `addWaypoint(LatLng wp, {String? name})`(`map_providers.dart:238-243`)은
    **항상** `stops.length-1` 위치(도착지 바로 앞)에만 삽입 — Q1에서 확정된
    "출발지 옆 `+`는 맨 앞에 삽입" 케이스를 지원하지 못함. `insertAtStart` 같은
    bool 파라미터를 추가하거나(삽입 인덱스를 `1`로 바꾸는 분기), 별도
    `addWaypointAtStart`/`addWaypointAtEnd` 두 메서드로 나누는 방식 중 구현 시
    선택 필요.
  - 지도에서 위치를 고르는 흐름 자체는 이미 있음: 검색결과 탭 →
    `_handleLocationTap`(`main_map_screen.dart:1062-1126`) → `_showAddToRouteSheet`
    (L1230-1243) → `_AddToRouteSheet`(L3571~, 4번 카드) → "경유지" 선택 시
    `_RouteAddAction.waypoint` 반환(L1110-1122) → `addWaypoint` 호출 후
    `_fetchAndStoreAllRoutes`로 재탐색. 지도 빈 곳 탭(`_onMapTap`, L978-998)도
    라운드 5 계획에 따라 코스 시트가 열려 있으면 동일하게 `_showAddToRouteSheet`로
    합류될 예정 — **즉 "지도에서 위치를 고르면 4번 카드가 뜬다"는 배관은 라운드
    5가 이미 준비 중**이므로, 6번 라운드는 이 배관을 그대로 재사용하고 "어느
    `+`를 눌렀는지" + "완료 후 6번 시트로 복귀"만 추가로 배선하면 됨.
  - `MapInteractionMode.waypointSelecting` / `startWaypointSelection()`
    (`map_providers.dart:104, 249-251`)이 "다음 탭이 경유지로 즉시 확정"되는
    구조로 만들어져 있으나 **현재 코드베이스 어디서도 호출되지 않는 죽은 코드**이고,
    Q2 답변("4번 POI 카드를 거쳐서 확정")과도 맞지 않음(이 모드는 확인 카드 없이
    즉시 확정하는 구조) — **이번 라운드에서 재사용하지 않음**, 기존 `_showAddToRouteSheet`
    경로를 그대로 씀. 죽은 코드 정리(삭제) 여부는 구현 시 판단.
  - `+` 클릭 → 시트를 내려보내고(`Navigator.pop`) → 사용자가 지도를 탭 →
    `_handleLocationTap` → `_showAddToRouteSheet` → "경유지" 선택 → `addWaypoint`
    → 재탐색 → **6번 시트 재오픈**까지는 `WaypointManagementSheet`(별도 파일)와
    `main_map_screen.dart`의 지도 탭 파이프라인 사이를 가로지르는 비동기 흐름이라,
    "어느 `+`를 눌렀는지"(시작/끝 삽입)와 "완료 후 경유지 시트를 다시 열어야 한다"는
    두 가지 상태를 시트 간에 전달할 매개체가 필요 — provider에 임시 플래그(예:
    `pendingWaypointInsert` — null / `start` / `end`)를 두고, `+` 클릭 시 이
    플래그를 설정한 뒤 시트를 닫고, `_handleLocationTap`의 `waypoint` 케이스가 이
    플래그를 읽어 삽입 위치를 결정 + 처리 후 플래그를 지우면서
    `_showWaypointSheet(context)`를 다시 호출하는 방식을 제안(다른 대안이 있으면
    구현 시 조정 가능 — 정확한 설계는 flutter-coder 재량).
- **행 스타일**: 현재 `leading: Icon(Icons.circle, color: iconColor(i,total))`
  (색깔 점, L214-218) — Q4에 따라 제거. `title: Text(stopLabel(...), fontWeight:
  w500)`(L219-228, 전 행 동일 굵기) — 출발지(`i==0`)·도착지(`i==total-1`) 행만
  `FontWeight.w700`(또는 `w800`)로 bold 처리, 중간 경유지는 현재의 `w500` 유지.
  드래그 핸들 `Icons.drag_handle`(L249-252)은 와이어프레임의 ⇕에 대응하는 기존
  요소이므로 아이콘만 `Icons.unfold_more`/`Icons.swap_vert` 계열로 교체 검토
  (실기기 시안에서 확정), 기능(`ReorderableDragStartListener`)은 그대로.
- **원형 `-`/`+` 버튼 스타일**: 다른 화면의 원형 흰 배경+그림자 버튼은
  `_MapCtrlBtn`(`main_map_screen.dart:2298-2336`, 42×42, `AppColors.secondary`
  아이콘, 그림자 `secondary@0.13/blur8/offset(0,3)`)인데 이건 `main_map_screen.dart`
  파일 안의 **private 클래스**라 다른 파일(`waypoint_management_sheet.dart`)에서
  직접 재사용 불가. 라운드 3 계획이 이미 `_MapCtrlBtn`에 `size` 파라미터를 추가하는
  변경을 포함하고 있으므로(68px 확대), 이번 라운드에서 같은 스타일을 쓰려면
  `_MapCtrlBtn`을 `lib/core/widgets/` 아래 공용 위젯으로 추출해 두 파일에서 함께
  쓰는 편이 중복 클래스를 안 만드는 방법 — 구현 순서상 **라운드 3(또는 이번 라운드)
  중 먼저 처리되는 쪽에서 공용 위젯 추출**을 하고 나머지 라운드가 그걸 재사용하는
  방식을 제안.

### 확정된 수정 계획

**1. 하단 검색식 "+ 경유지 추가" 버튼 제거 (Q3)**
- `waypoint_management_sheet.dart` L262-288 통째로 삭제. `AddressSearchSheet`
  import(L8)는 다른 곳에서 안 쓰면 함께 정리(구현 시 grep 재확인).

**2. 리스트 행 재디자인 (Q4)**
- `leading`의 색깔 점(L214-218) 제거.
- `title`(L219-228): 출발지·도착지 행은 `FontWeight.w700` bold, 중간 경유지는
  기존 `w500` 유지 — `_stopLabel`은 그대로 두고 스타일 분기만 `i==0 ||
  i==total-1` 조건 추가.
- `trailing`의 삭제 아이콘(`Icons.remove_circle_outline`, L234-245)을 와이어프레임
  느낌의 원형 배지 스타일로 교체(정확한 값은 실기기 시안 확인 — `_MapCtrlBtn` 공용
  추출 여부에 따라 재사용 or 로컬 스타일).
- 드래그 핸들 아이콘 교체 검토(L249-252) — 기능 변경 없음.

**3. 출발지/도착지 행에 `+` 버튼 추가 (신규 기능, Q1·Q2)**
- 출발지 행(`i==0`)과 도착지 행(`i==total-1`)의 `trailing`에 `+` 버튼 추가.
- 탭 시: (a) 삽입 위치 의도를 저장(출발지=`start`, 도착지=`end`) — 상태 전달
  매개체는 위 조사 결과에서 제안한 provider 플래그 방식 중 flutter-coder가
  구현 시 확정. (b) `Navigator.of(context).pop()`으로 경유지 관리 시트를 닫음
  (요구사항의 "카드가 폰 아래로 내려간다"에 대응).
- `addWaypoint`(`map_providers.dart:238-243`)에 삽입 위치를 받는 파라미터 추가
  (예: `atStart: bool`) — `atStart==true`면 `insertIdx = stops.length>=2 ? 1 :
  stops.length`, 아니면 기존 로직(도착지 바로 앞) 그대로.
- `_handleLocationTap`의 `waypoint` 케이스(`main_map_screen.dart:1110-1122`)가
  위 플래그를 읽어 `addWaypoint(location, name: name, atStart: ...)` 호출 +
  처리 완료 후 플래그 초기화 + `_showWaypointSheet(context)` 재호출(Q2, 자동
  복귀).
- 라운드 5가 `_onMapTap`을 코스 시트 열림 상태에서 `_showAddToRouteSheet`로
  합류시키는 작업을 이미 계획 중이므로, 지도 빈 곳 탭으로 경유지를 고르는 경로도
  자동으로 이 흐름을 함께 탄다 — 6번 라운드에서 별도 배관 불필요(라운드 5 구현과
  순서 조율 필요, 아래 참고).

**4. 재정렬·삭제 로직 — 변경 없음 확인**
- `reorderStop`/`removeWaypoint`와 시트의 `onReorder`/`onRemove` 콜백은 이미
  요구사항과 일치 — 이번 라운드에서 로직 수정 없음, 시각 스타일만 위 2번대로 정리.

**5. `_MapCtrlBtn` 공용 위젯 추출 (스타일 재사용)**
- 원형 `+`/`-` 버튼을 다른 화면(줌 컨트롤 등)과 시각적으로 통일하려면
  `_MapCtrlBtn`(`main_map_screen.dart:2298-2336`)을 `lib/core/widgets/` 아래
  공용 위젯으로 추출 — 라운드 3(홈 레이아웃, 이미 이 위젯에 `size` 파라미터 추가
  예정)과 작업이 겹치므로 **두 라운드 중 먼저 구현되는 쪽에서 추출하고 나머지가
  재사용**하는 순서로 진행.

### 미확정 / 구현 시 확인
- 출발지/도착지 옆 `+` 클릭 → 지도 탭 → 4번 카드 → 6번 시트 재오픈까지의 상태 전달
  방식(provider 플래그 vs 다른 설계)은 flutter-coder 구현 시 최종 확정.
- `addWaypoint`의 삽입 위치 파라미터 이름/시그니처(`atStart: bool` vs 별도 메서드
  분리)는 구현 시 확정.
- 원형 `-`/`+` 버튼의 정확한 크기·색상(브랜드 컬러 vs 회색조)은 실기기 시안에서
  마스터 확인 후 미세조정.
- 드래그 핸들 아이콘 교체 여부·모양은 실기기 시안에서 최종 확인.
- 라운드 5(`_onMapTap`의 `_showAddToRouteSheet` 합류)와 구현 순서 조율 필요 — 6번
  라운드의 지도 기반 `+` 흐름이 라운드 5의 배관을 전제로 하므로, 배치 구현 시
  라운드 5를 먼저 처리하거나 동일 세션에서 함께 처리하는 편이 매끄러움.

### 상태: **구현 완료 (2026-07-31, 배치2/라운드4→5→6 세션)**
flutter-coder → code-auditor PASS → 커밋 `287f2bb`(`feat(map): 경유지 관리
카드 재디자인 + 지도기반 추가`). `_MapCtrlBtn`을 `lib/core/widgets/map_ctrl_btn.dart`의
공용 `MapCtrlBtn`으로 추출(라운드3이 미룬 항목, 메인 지도 화면 6개 호출부
전부 갱신), 검색식 "+ 경유지 추가" 버튼+`AddressSearchSheet` import 제거,
리스트 행 색깔 점 제거+출발/도착 행만 `w700` bold+삭제 아이콘 원형 배지화
(가시성/활성화 로직은 완전 동일), 출발지/도착지 행에 `+` 버튼 신규 추가
— `map_providers.dart`에 `WaypointInsertPosition` enum·`pendingWaypointInsert`
상태(기존 `destinationName`/`clearDestinationName` 패턴 그대로 미러링)·
`addWaypoint(atStart:)` 파라미터 추가, `_applyRouteAddAction`이 플래그를
읽어 삽입 위치 결정 + 처리 후 플래그 클리어 + (플래그가 있었을 때만) 시트
자동 재오픈. 재정렬(`reorderStop`)·삭제(`removeWaypoint`) 로직은 무변경
확인(감사에서 diff 0줄 확인).

---

## 라운드 7 — 2026-07-30 (내비게이션 레이아웃)

**참조 이미지**: `loop/layout_fixes/7_navigation_layout.png` — 좌측 실기기 캡쳐(현재
상태) + 가운데/우측 마스터 제작 디지털 목업 2장(일반 주행 중 / 목적지 도착 시).
가장 중요한 화면으로 명시됨.

### 마스터 피드백 요약
(1) 줌아웃 버튼이 하단 카드에 가려짐 (2) 하단 navigation bar가 하단 카드 위에
투명하게 떠서 카드 안에 있는 것처럼 보임 (3) status bar가 지도 위에 투명해 가독성
저하 (4) 속도계·아이콘 색이 브랜드 컬러와 동떨어진 파란색 (5) 도착 시 종료 카드가
하단 카드와 별개로 상단에 따로 뜸. 변경안: 우측에 큰 둥근 버튼 5개(주유소→나침반→
현위치→줌인→줌아웃)를 통일된 스타일로 배치, 줌인/줌아웃은 붙이고 현위치와는
의도적으로 띄움. 도착 시 상단 카드1은 "목적지 도착/소요시간"으로 바뀌고 카드2는
사라지며, 도착 또는 시스템 뒤로가기 시 하단 카드가 "탐색 유지"(녹색 계열)/
"내비게이션 종료"(적색 계열) 버튼으로 전환. 안드로이드 뒤로가기 두 번 = 종료와 동일
동작. 상단 카드 방향지시 아이콘 색은 스킨 무관 현행 파란색 유지, 상단/하단 카드
배경은 흰색 유지.

### 확인 질문 및 답변
- Q1. 5버튼·속도계 아이콘 색을 어떤 방식의 "브랜드 컬러"로 바꿀지 — 스킨 연동
  vs 홈 화면과 동일한 고정 네이비?
  → **A. 스킨 연동** (`skinProvider.colors.brand` — 스킨 바뀌면 색도 바뀜, "탐색
  유지"/"내비게이션 종료" 버튼과 동일한 원리로 통일)
- Q2. 뒤로가기로 하단 카드가 확인 버튼으로 바뀐 뒤 실제 종료로 이어지는 방식 —
  시간제한 없음 vs 표준 2초 패턴?
  → **A. 시간제한 없음** — 확인 카드가 뜬 상태에서 뒤로가기를 다시 누르면 언제든
  바로 종료.
- Q3. "목적지 도착" 후 "내비게이션 종료" 버튼에 기존 정차+지오펜스 안전장치를
  유지할지, 도착 즉시 무조건 노출할지?
  → **A. 기존 안전장치 유지** — 정차 조건(`_canExit`) 만족 전까지 종료 불가/비활성
  유지, 만족 시 10초 자동종료 로직도 그대로.
- Q4. 상단 카드1의 "소요시간"이 실제 경과시간인지 경로 예상 ETA인지?
  → **A. 실제 주행 경과시간** — 내비게이션 시작~도착까지 실측(스톱워치), 신규
  트래킹 필요.

### 조사 결과 (코드)
파일: `lib/features/navigation/presentation/nav_screen.dart` (3283줄)

- **우측 버튼 — 현재 2개 그룹으로 분리, 크기·스타일도 제각각**:
  - L2273-2330 `Positioned(right:12, bottom:245)`: `_CompassBtn`(L3230-3282,
    57×57 원)→`_NavIconBtn`(L2982-3008, 57×57 원, 주유소)→`_NavIconBtn`(현위치)
    순, 각 `SizedBox(height:10)` 간격. 이미지 순서(주유소→나침반→현위치)와 다름.
  - L2333-2350 `Positioned(right:12, bottom:125)`: `_ZoomBtn`(L3205-3228, 46×46
    둥근 사각형, `borderRadius:12`) 줌인/줌아웃, `SizedBox(height:4)` 간격.
  - 아이콘 색: `_NavIconBtn`/`_CompassBtn`은 `cs.tertiary`, `_ZoomBtn`은
    `cs.onSurface` — 전부 `Theme.of(context).colorScheme`발(=`AppColors.tertiary
    0xFF00B1F0` 등 하드코딩, 스킨 무관. 전 스킨의 `toThemeData()`가 동일한
    `AppTheme.light`를 반환하기 때문). "동떨어진 파란색" 불만의 실체.
- **줌아웃 가림 버그 원인**: 하단 ETA 카드(아래 항목)가 `bottom:12`+`SafeArea`
  기준으로 높이가 기기별 하단 인셋에 따라 가변인데, 줌 그룹은 `bottom:125`
  고정값이라 인셋이 큰 기기에서 카드 상단이 125px 여유를 넘어서면 겹침. 둘 다
  `Scaffold.body`의 같은 `Stack`(L1862) 안 형제이고 ETA 카드가 `children`에서
  더 나중에 선언돼(L2353 > L2333) z-order상 위에 그려짐.
- **상단 카드 1·2**: `if (!_arrivalBannerVisible) Positioned(top:
  MediaQuery.of(context).padding.top, left:0, ...)`(L2064-이하) 안에 메인 회전
  카드(카드1, `_steps[_stepIdx]` 기반, 폭 화면62%, SVG 회전아이콘+거리+도로명)와
  `if (_stepIdx+2 < _steps.length)`일 때만 뜨는 "다음" 미리보기 카드(카드2, 폭
  카드1의 70%) 두 개로 이미 구성돼 있음 — 이미지의 "상단 카드1/2"와 정확히 대응.
- **도착 시 종료 카드가 별도로 뜨는 문제의 실체**: `_arrivalBannerVisible`
  블록(L1929-2056)이 상단 카드1/2와 **완전히 별개인 독립 `Positioned` 배너**로,
  "목적지 도착"+POI 3개 리스트(`_arrivalPois`)+"계속 안내"/"안내 종료" 버튼을
  자체 카드에 렌더링(L2064의 `if (!_arrivalBannerVisible)`로 카드1/2를 숨기고
  이 배너로 대체하는 구조). 하단 ETA 카드(재탐색/ETA/종료)는 도착 중에도 전혀
  안 바뀜 — 이게 마스터가 "종료 카드가 별도의 카드로 상단에 뜬다"고 지적한 지점.
- **도착 판정 vs 종료 안전게이트, 서로 다른 두 단계**:
  - 도착 판정: `prog.arrived && !_arrived && 모든 경유지 통과`(L520-522) →
    `_arrived=true`, `_arrivalBannerVisible=true`, 도착지 500m 내 POI 조회
    시작(`_fetchNearbyPois`, L523-525).
  - 종료 안전게이트(Q3의 "기존 안전장치"): `_updateExitGate`(L554-572)가
    지오펜스(`_kExitGeofenceM=30m`, L210)+속도(`_kExitSpeedKmh=30km/h`, L211)를
    만족해야 `_canExit=true`로 전환, 전환 즉시 10초 타이머(L567-569) 시작해
    시간 초과 시 자동 `_exitNav()`. `_canExit==false`면 "정차 후 종료 가능",
    `true`면 "10초 후 자동 종료" 힌트 텍스트(L1991-2002)로 안내.
  - 이 게이트는 **도착 근접 여부**를 재는 것이라 "뒤로가기로 촉발되는 확인
    카드"(주행 중, 목적지와 무관)에는 의미가 없음 — Q3 답변(안전장치 유지)은
    도착 흐름에만 적용하고, 뒤로가기 흐름은 게이트 없이 즉시 활성 버튼으로
    처리하는 것이 논리적으로 맞음(아래 계획 1-C 참고).
- **하단 ETA 카드**: `Positioned(bottom:12,left:12,right:12,...)`
  (L2353-2466) — `LinearProgressIndicator`(진행률)+`SafeArea`+`Row`[재탐색
  버튼(L2391-2405, `onTap: canReroute ? _openCourseSheet : null`) | 구분선 |
  중앙 목적지명+ETA+거리(L2408-2440) | 구분선 | 종료 버튼(L2443-2456,
  `onTap: () => _exitNav()`, `cs.error` 아이콘/텍스트)]. **종료 버튼이 현재
  아무 확인 없이 즉시 `_exitNav()`를 호출** — 뒤로가기 쪽(`_confirmExit` 다이얼로그,
  L997-1019)과 비대칭. 계획에서 두 경로를 하나의 카드 전환 메커니즘으로 통일.
- **안드로이드 뒤로가기**: `PopScope(canPop:false, onPopInvokedWithResult: ...)`
  (L1855-1859)가 `_confirmExit(context)`(L997-1019, `AlertDialog` "내비게이션
  종료"/"내비게이션을 종료할까요?"/취소·종료) 모달을 띄움 — 이미지가 요구하는
  "하단 카드 내 인라인 전환"과 다른 패턴(별도 다이얼로그). 코스 재선택
  시트(`_showCourseSheet`)가 열려 있을 때의 별도 처리는 없음(기존 그대로 둠,
  이번 라운드 범위 밖).
- **속도계**: `_Speedometer`(L2793-2863) 88×88 원, 테두리·텍스트 색
  `cs.tertiary`(L2837/2846) — 위 버튼과 동일한 원인(비-스킨 연동 하드코딩)으로
  파랗게 보임.
- **상단 카드 방향지시 아이콘**: `_TurnStep.svgAsset`(L3010-3057 부근,
  `assets/images/nav_icons/*.svg`) — 코드가 색을 지정하지 않고 SVG 파일 자체
  색이 그대로 렌더링되는 구조로 보임(별도 `color:` 파라미터 없음) → "스킨
  영향 없이 현행 파란색 유지" 요구사항과 이미 일치, **코드 변경 불필요**.
- **총 주행 시간 소스**: 경과시간을 직접 들고 있는 필드가 없음.
  `_tourRecorder.start(loc, DateTime.now())` 호출(L488, `_tourRecorderStarted`
  가드)이 내비 시작 시각과 정확히 일치하는 시점이라, 같은 자리에 로컬
  `DateTime? _navStartedAt`을 함께 기록하면 됨(`TourRecorder` 내부
  `_startedAt`은 private라 굳이 getter를 추가하지 않아도 됨 — 로컬 필드로
  충분, [[feedback_prefer_simple_reuse]] 원칙에 따라 최소 변경 선호). 포맷은
  이미 있는 `lib/features/tour_summary/tour_log_format.dart`의
  `formatTourDuration(int durationS)`("H시간 M분"/"M분") 재사용 후보 — 목업의
  "3:15" 콜론 표기와는 형식이 다름(아래 미확정 참고).
- **스킨 시맨틱 컬러 토큰 — 이미 4개 스킨 전부 구현돼 있어 바로 재사용 가능**:
  `lib/core/skin/skin.dart`의 `SkinColors`(L16-45) 추상 정의에 `brand`/
  `danger`/`success` 존재. 스킨별 실값: `default_skin.dart`
  brand=`AppColors.primary`(주황)/danger=`AppColors.error`/
  success=`AppColors.success`; `yurucam_skin.dart`
  brand=`0xFFE2896F`/danger=`0xFFC94F3F`/success=`0xFF6E9B6B`;
  `cub_buddy_skin.dart`, `retro_motoring_skin.dart`도 동일 패턴으로 3색 보유.
  nav_screen.dart는 현재 `courseLineColor`(L1190/1726)만 `ref.read(skinProvider)
  .colors`로 읽고 있고 `brand`/`danger`/`success`는 아직 미사용 — 이번
  라운드에서 처음 연결.
- **홈 화면 참조 위젯**: 라운드3의 `_MapCtrlBtn`(`main_map_screen.dart`
  L2298-2336, 42×42→68 확대 예정)은 아이콘 색이 고정 `AppColors.secondary`
  (네이비)라 Q1 답변(스킨 연동)과 스펙이 다름 — 이번 라운드는 그대로 재사용하지
  않고 **아이콘 색을 스킨에서 읽는 별도 버튼**을 사용(구조는 유사, 색상 소스만
  다름 — 공용화 여지는 미확정 항목 참고).

### 확정된 수정 계획

**1. 우측 버튼 5개 통합 — 단일 컬럼 + 크기 확대 + 스킨 연동 색상**
- **1-A. 배치 통합**: L2273-2330과 L2333-2350 두 `Positioned`를 하나로 합쳐
  단일 `Positioned(right:12, bottom: 고정값)` + `Column`으로 재구성. 순서를
  이미지대로 주유소→나침반→현위치→줌인→줌아웃으로 재배열(현재 나침반→주유소→
  현위치 순서에서 변경).
- **1-B. 간격**: 주유소·나침반·현위치 3개는 촘촘하게(기존 `_NavIconBtn`
  그룹과 동일한 10dp 유지 — 라운드3 홈 화면의 "촘촘한 상단 그룹"과 같은 언어),
  현위치↔줌인 사이만 의도적으로 넓게(라운드3에서 실측한 34dp 재사용 — 동일한
  "일부러 띄운 간격" 컨셉이라 값도 맞춤), 줌인↔줌아웃은 기존처럼 4dp로 거의
  맞닿게 유지.
- **1-C. 줌아웃 가림 버그 근본 수정**: 버튼 그룹을 `Positioned(right:12,
  bottom: 하단 ETA카드 실측 높이 + 여백)` 하나로 통합하면서, 하단 위치 기준을
  더 이상 매직넘버(`125`)로 고정하지 않고 ETA 카드가 차지하는 실제 공간(카드
  높이 + `MediaQuery.of(context).padding.bottom`)에서 역산해 항상 카드 위
  여백에 오도록 계산 — 기기별 하단 인셋 차이로 인한 겹침을 원천 차단(단순히
  숫자를 키우는 임시방편이 아니라 카드 실측 기반으로 만드는 것).
- **1-D. 크기·스타일 통일**: 5개 전부 원형, 지름은 라운드3 홈 화면 확정치
  68px로 통일(화면 간 시각적 통일성 확보 — "정확히 일치"의 취지). 흰 배경
  원 + 그림자는 기존 `_NavIconBtn`/`_CompassBtn` 스타일(테두리 `cs.outline`
  1px + `black@0.25 blur8` 그림자) 유지, 아이콘 크기는 26px 기준에서 68px
  지름에 맞춰 비례 확대(예 32px 정도, 실기기 확인).
- **1-E. 색상 스킨 연동 (Q1)**: 5개 버튼 아이콘 전부 `ref.watch(skinProvider)
  .colors.brand`로 교체(`_NavIconBtn`/`_ZoomBtn`/`_CompassBtn`이 각각 다르게
  쓰던 `cs.tertiary`/`cs.onSurface` 제거). `_CompassBtn` 내부 N/S/E/W 글자·
  고정 화살표 색(L3260-3277)도 스킨 브랜드색 계열로 통일할지, 방위 텍스트는
  현행 대비색(`cs.error`/`cs.onSurfaceVariant`) 유지할지는 실기기 확인 후
  결정(핵심은 화살표·아이콘, 보조 라벨은 가독성 우선 가능).

**2. 속도계 색상 스킨 연동 (Q1 연장)**
- `_Speedometer`(L2793-2863)의 테두리·그림자·숫자 텍스트 색(`cs.tertiary`
  3곳, L2837/2838/2846)을 전부 `ref.watch(skinProvider).colors.brand`로 교체.
  GPS 검색 중 상태(L2851-2860, "GPS"/"검색 중" 텍스트)도 동일 색상으로 통일.
  `RearCameraGaugeSwitcher`가 감싸는 다른 게이지(카메라 접근/포스트존, 18번
  로드맵 관련)는 이번 라운드 범위 밖 — 손대지 않음.

**3. 도착 시 상단 카드 재구성 — 독립 배너 폐기, 카드1/2 재활용**
- `_arrivalBannerVisible` 전용 배너 블록(L1929-2056) **통째로 삭제**.
- 카드1(현재 메인 회전 카드, L2072-2177 부근)에 `_arrivalBannerVisible`
  분기를 추가: 도착 시엔 회전 아이콘·거리·도로명 대신 "목적지 도착" 텍스트 +
  아래 항목의 실제 경과시간(`_navStartedAt` 기반)을 같은 카드 프레임/배경
  안에 표시. 카드2(다음 미리보기, L2178-2220)는 `_arrivalBannerVisible`일 때
  단순히 숨김(이미 있는 `if (_stepIdx+2 < _steps.length)` 조건에
  `&& !_arrivalBannerVisible` 추가).
- L2064의 `if (!_arrivalBannerVisible)`로 카드1/2 전체를 숨기던 기존 분기는
  제거(이제 카드1은 도착 중에도 계속 보여야 하므로) — 카드1 내부에서만
  도착/비도착 분기.
- **경과시간 트래킹 신규 추가**: `_tourRecorderStarted` 가드 옆(L486-488)에
  `_navStartedAt = DateTime.now();` 추가, 도착 판정 시점(L520-522 부근)에
  `_arrivalDurationS = DateTime.now().difference(_navStartedAt!).inSeconds`
  같은 값을 확정해 카드1에 표시(주행 중 실시간 갱신이 아니라 도착 순간
  스냅샷 — 계속 흐르는 스톱워치일 필요는 없음).
- `_arrivalPois`(도착지 500m 내 주유소/편의점/식당 추천, L207/523-525/
  1974-1986) 표시 자리가 새 목업엔 없음 — 이번 라운드에서는 표시하지 않는
  것으로 간주(완전 제거 vs 다른 화면으로 이전은 미확정 항목 참고, 최소한
  `_fetchNearbyPois` 호출 자체는 부작용 없는 조회라 당장 지울 필요는 없음).

**4. 하단 카드 — "탐색 유지"/"내비게이션 종료" 인라인 전환 (신규 UX 통합)**
- 하단 ETA 카드(L2353-2466)에 새 상태(`_showExitConfirm` 등 bool)를 추가해,
  기존 [재탐색|목적지정보|종료] 3열 대신 [탐색 유지|내비게이션 종료] 2버튼
  레이아웃으로 통째로 스왑하는 조건부 렌더링 추가.
- **트리거 통합 (2가지 경로, Q2·Q3)**:
  - **(a) 도착 트리거**: `_arrivalBannerVisible=true`가 되는 순간 하단 카드도
    자동으로 확인-버튼 상태로 전환. "내비게이션 종료" 버튼은 기존 안전게이트
    그대로 적용(`_canExit`이 `false`면 비활성/회색, `true`면 활성/적색 +
    10초 자동종료 타이머 유지, L554-572 로직 재사용) — Q3 답변(안전장치
    유지)에 따름. 힌트 텍스트("정차 후 종료 가능"/"10초 후 자동 종료",
    기존 L1991-2002)는 두 버튼 위에 작은 캡션으로 이식.
  - **(b) 뒤로가기 트리거**: `PopScope`의 `onPopInvokedWithResult`
    (L1855-1859)가 기존 `_confirmExit(context)` 다이얼로그 대신
    `_showExitConfirm = true`로 하단 카드를 전환. 이 경로는 도착과 무관(주행
    중일 수 있음)하므로 지오펜스/속도 게이트를 적용하지 않고 "내비게이션
    종료" 버튼을 즉시 활성 상태로 노출(Q3 답변은 도착 게이트 한정, 위 조사
    결과 참고).
  - **뒤로가기 두 번 = 종료 (Q2)**: `PopScope` 핸들러에서 이미
    `_showExitConfirm == true`(또는 `_arrivalBannerVisible == true`)인
    상태에서 뒤로가기가 다시 들어오면 바로 `_exitNav()` 호출(시간제한 없음).
    처음 상태(카드 전환 전)에서는 카드만 전환하고 pop하지 않음.
  - "탐색 유지" 탭 → `_showExitConfirm=false` (+ 도착 트리거였다면
    `_arrivalBannerVisible=false`, `_canExit=false`, 관련 타이머 취소 — 기존
    배너의 "계속 안내" 로직, L1959-1966/2007-2014와 동일 효과)로 원래
    [재탐색|목적지정보|종료] 카드로 복귀.
- **버튼 색상 (Q1 연장)**: "탐색 유지" = `ref.watch(skinProvider)
  .colors.success`, "내비게이션 종료" = `ref.watch(skinProvider)
  .colors.danger` (비활성 시엔 회색조로 오버라이드).
- **기존 온스크린 X/종료 버튼과의 일관성 (2026-07-30 마스터 확정)**: 현재
  하단 카드의 종료 버튼(L2443-2456)은 확인 없이 즉시 `_exitNav()`를
  호출하는데, 뒤로가기 경로만 확인 단계를 거치면 "뒤로가기는 2단계, 화면
  터치는 1단계"로 비대칭이 되어 오히려 오조작 위험이 커진다는 구현팀 제안을
  마스터가 그대로 승인 — **온스크린 종료(X) 탭도 뒤로가기 트리거 (b)와 동일한
  로직으로 확인 카드 전환을 거치도록 통일**(즉시 `_exitNav()` 호출 대신
  `_showExitConfirm=true`로 전환, 이후 "내비게이션 종료" 버튼을 다시 눌러야
  실제 종료).

**5. 상단/하단 카드 배경·방향아이콘 색 — 변경 없음 확인**
- 카드1/2 배경(`cs.surface`, 흰색)과 SVG 방향아이콘 색은 이미 스킨 무관 고정
  값이라 요구사항과 일치 — 코드 변경 불필요.

### 미확정 / 구현 시 확인
- `_arrivalPois`(도착지 주변 POI 추천) 완전 제거 vs 다른 자리로 이전 — 목업엔
  없어 이번 라운드는 "표시 안 함"으로 처리하되, 기능 자체를 지울지는 별도 확인.
- "소요시간" 표기 형식 — 목업의 "3:15"(콜론) vs 기존
  `formatTourDuration`의 "H시간 M분"/"M분" 표기. 앱 내 일관성(투어 요약
  화면과 동일 형식)을 우선해 기존 포맷터 재사용을 기본안으로 제안,
  콜론 표기를 원하면 별도 포맷 함수 신규 작성 필요 — 실기기 시안에서 확인.
- 5버튼 정확한 지름(68px 제안)·간격(10 / 34 / 4dp 제안)은 라운드3 실측치를
  준용한 것으로, 이 화면 자체의 목업이 손그림이 아니라 디지털 목업이라
  픽셀 실측은 생략함 — 실기기 확인 후 미세조정 여지 있음.
- `_CompassBtn`의 N/S/E/W 텍스트·회전 링 색상까지 브랜드색으로 바꿀지, 대비
  색 유지할지는 시안에서 확인.
- 우측 버튼 위젯을 라운드3(`_MapCtrlBtn`, 고정 네이비)·라운드6(경유지 관리
  카드의 원형 ±버튼)과 공유되는 공용 위젯으로 통합할지(예: `iconColor`
  파라미터로 스킨연동/고정색 분기) 여부는 구현 시 flutter-coder 재량.
- 하단 카드 확인-버튼 상태의 정확한 레이아웃(버튼 폭 비율, 힌트 캡션 위치)은
  실기기 시안에서 확정.

### 상태: **구현 완료 (2026-07-31, 배치3/라운드7 세션, 커밋 `210961f`)**
우측 버튼 5개 단일 컬럼(68px, 스킨연동 brand색) + ETA카드 실측높이 기반
줌아웃 가림버그 근본수정, 속도계 스킨연동, 도착 배너 폐기→카드1/2 재활용
(실경과시간 `formatTourDuration`), 하단카드 "탐색유지/내비게이션종료"
인라인 전환 통일(뒤로가기·온스크린X 동일 로직) 전부 구현. `_ZoneBtn`은
스펙상 `_NavIconBtn`과 동일 스타일이 요구돼 흡수 통합(라운드3/6과의
공용 위젯 추출은 이번엔 보류 — 결정 아님, 미실행).
**code-auditor 1차 FAIL** — 도착 중 시스템 뒤로가기 1회로 `_canExit`
안전게이트를 우회해 즉시 종료되는 버그(`_showExitConfirm ||
_arrivalBannerVisible`가 도착 트리거와 뒤로가기 트리거를 구분 못함) →
`_backExitArmed` 별도 플래그로 분리 수정(도착 트리거는 `_canExit`로만,
뒤로가기 트리거는 `_backExitArmed`로만 게이트) → **재감사 PASS**.
`flutter analyze`/`flutter build apk --debug`/관련 테스트(34개) 전부 통과.

---

## 라운드 8 — 2026-07-30 (홈 불필요 버튼 — 지시용, 라운드3 후속 확정)

**참조 이미지**: `loop/layout_fixes/8_home_useless_buttons.png` — 레이아웃 지시가 아니라
"무엇을 지울지"만 표시하는 지시용 이미지. 3번 실기기 캡쳐 위에 상단 3개 요소(로고 배지
/ 해 모양 아이콘 / 갤러리 아이콘)에 빨간 테두리로 표시.

### 마스터 피드백 요약
3번 이미지 레이아웃 변경에 따라 헤더 컴포넌트 묶음(로고+아이콘 5개)은 사라지고, 그중
빨간 박스 3개(로고, "다크 모드" 버튼, 이미지 버튼)는 완전 삭제. "다크 모드" 버튼에 딸린
기능(버튼을 누르면 화면 일부가 까맣게, 글자가 밝은 회색으로 바뀌는 동작)까지 삭제 —
단순히 진입점만 없애는 게 아니라 그 뒤의 테마 전환 기능 자체를 없앤다. 다크모드는 추후
설정 페이지에서 선택하는 형태로 재구현(이번 라운드 범위 밖).

### 확인 질문 및 답변
- Q1. "다크 모드 버튼에 딸린 화면 설정"이 정확히 무엇을 가리키는지(코드상 그 버튼은
  provider 값만 바꾸고 별도 화면을 열지 않는 것으로 보임)?
  → **A. 별도 화면이 아니라, 버튼을 누르면 화면 일부가 까맣게 변하고 글자가 밝은
  회색으로 바뀌는 동작(=라이더모드 강제 발동 시 앱 전체 테마가 다크로 바뀌는 효과)을
  가리키는 것이었음.** 이 기능까지 삭제.
- Q2. 삭제 범위 — 버튼(진입점)만 없앨지, `riderModeProvider`/`AppTheme.rider`와 관련
  코드(마커색 분기 등) 전부 삭제할지?
  → **A. 전부 삭제.** 진입점이 없어 이미 죽은 코드이므로 지금 정리. 추후 설정 페이지
  다크모드는 새로 구현.
- Q3. 자동 야간모드(`isNightProvider`, 위경도 기반 실제 일출·일몰로 앱 전체 테마를
  `AppTheme.night`로 자동 전환하는 기능)는 이번 삭제 대상과 별개인지?
  → **A. 같이 삭제.** 라이더모드와 마찬가지로 "앱 전체 테마 자동/수동 전환" 기능 전체를
  없애고, 추후 설정 페이지에서 사용자가 직접 선택하는 방식으로 일원화.
- Q4. 조사 중 별도로 발견된 것 — 지도 화면에만 있는 야간 디밍 오버레이(`isDayProvider`
  기반, 밤에 지도 위에 검은 35% 반투명을 깔아 지도만 어둡게 하는 기능, 앱 전체 테마와는
  무관)는 이번 삭제 대상에 포함되는지?
  → **A. 코드는 유지하되, 켜고 끄는 스위치를 설정 페이지에 추가할 것** — "밤이라도 밝은
  화면을 보고 싶을 때가 있다"는 이유. 완전 상시 온(on) 동작에서 사용자 선택 가능하게
  변경.

### 조사 결과 (코드)

**앱 전체 테마 전환 (삭제 대상)**
- `lib/main.dart:41-53` — `riderMode`(`riderModeProvider`)·`isNight`
  (`isNightProvider`) 두 상태를 읽어 `AppTheme.rider` / `AppTheme.night` /
  `AppTheme.light` 중 하나를 고르고, 상태바 아이콘 밝기도 `isDark` 여부로 분기.
- `lib/features/map/providers/map_providers.dart:354` — `isNightProvider`
  (`!isDayProvider`, `isDayProvider`는 `daylightCycleProvider`의 `isDay`를 그대로 반환
  — 위경도 기반 실제 일출·일몰 계산, `DaylightService`). **`isDayProvider`/
  `daylightCycleProvider` 자체는 삭제 대상 아님**(Q4, 아래 "유지" 항목 참고) — 삭제
  대상은 `isNightProvider` 정의 한 줄과 그걸 읽는 `main.dart`뿐.
- `lib/features/map/providers/map_providers.dart:466-474` — `riderModeProvider`
  (`NotifierProvider<_RiderModeNotifier, bool>`, `toggle()`/`set()`) 정의 전체.
- `lib/core/theme/app_theme.dart:358-481` — `AppTheme.night`(L358-414)·
  `AppTheme.rider`(L416-481) getter 전체 삭제. 함께 쓰이는 색상 토큰 클래스
  `NightModeColors`(L132-160, 내부 전용 — `AppTheme.night`에서만 참조)·
  `RiderModeColors`(L167-191)·`RiderModeTextStyles`(L193-257)도 이 두 테마 getter
  밖에서 참조하는 곳이 없음이 확인됨(조사 결과, `AppTheme.light`/`AppTextStyles`와는
  완전히 독립된 블록이라 삭제해도 라이트 테마에 영향 없음) — 통째로 삭제.
- `lib/features/map/presentation/main_map_screen.dart` — `riderModeProvider` 읽는
  자리 다수(라운드3이 지우는 헤더 UI 자체와 겹치는 부분 제외하고도 더 있음):
  - L1583 `final riderMode = ref.watch(riderModeProvider);`
  - L1596/1599 목적지·출발지 마커 색 분기(`RiderModeColors.mapOrigin`/
    `mapDestination` vs `AppColors.*`)
  - L1621 배경색 분기(`RiderModeColors.background` vs `AppColors.background`)
  - L1851/1853 `_MapHeader`에 `riderMode`/`onRiderModeToggle` 전달(**라운드3이 헤더
    UI 자체를 지우면서 이 전달부도 함께 정리하기로 이미 계획돼 있음** — 아래 "라운드3과의
    관계" 참고)
  - L1994/2003/2014-2036 `_MapHeader` 내부 `riderMode` 파라미터·배경색·토글 버튼
    스타일 분기(**라운드3이 `_MapHeader`를 통째로 재작성하며 자연히 정리되는 범위**)
  - L2092-2132 `_LogoBadge`의 `riderMode` 파라미터·배경/보더/텍스트 색 분기(**라운드3이
    `_LogoBadge` 자체를 삭제 대상으로 이미 지정**)
  - 정리하면: L1583/1596/1599/1621(마커·배경색)은 **이번 라운드에서 새로 정리해야 하는
    부분**, 나머지(L1851-2132 범위 대부분)는 **라운드3 구현 시 자연히 함께 제거되는
    부분** — 두 라운드가 같은 파일의 겹치는 코드를 다루므로 반드시 같은 세션에서 함께
    구현.
- `lib/features/tour_summary/presentation/tour_summary_detail_screen.dart:197-210` —
  `riderModeProvider`를 `ref.read`로 1회 읽어 출발/도착 마커 색을 `RiderModeColors.
  mapOrigin` vs `AppColors.mapOrigin`으로 분기. 분기 제거, `AppColors.*` 고정값만
  사용.

**유지 (이번 삭제 대상 아님, Q4)**
- `lib/features/map/providers/map_providers.dart`의 `isDayProvider`/
  `daylightCycleProvider`/`DaylightService` — `_LeftDaylightBar`(일출·일몰 바,
  `main_map_screen.dart`/`nav_screen.dart` 양쪽)와 지도 야간 디밍 오버레이가 계속
  사용. 삭제하지 않음.
- `main_map_screen.dart:1970-1981` "LAYER 8 · 야간 디밍 오버레이"
  (`if (!isDay) Positioned.fill(... Colors.black.withValues(alpha: 0.35) ...)`) —
  코드 자체는 유지, 아래 "신규" 항목대로 온/오프 스위치만 추가.

**신규로 필요한 것 (Q4 — 지도 야간 디밍 온/오프 설정)**
- 기존 `navHeadingUpProvider` 패턴(`lib/features/settings/providers/
  settings_providers.dart:10-25`, `AsyncNotifierProvider` + `SharedPreferences`
  key-value 저장) 그대로 재사용 — 새 `mapNightDimEnabledProvider`(가칭, 기본값 `true`
  = 현재 상시 온 동작과 동일하게 유지) 추가.
- `main_map_screen.dart:1974`의 `if (!isDay)` 조건에 `&& mapNightDimEnabled` 추가.
- `settings_screen.dart:71`의 `// TODO Phase 2: 다크모드` 자리(또는 "주행 설정" 섹션,
  L46-58 `지도 방향` 스위치 바로 아래)에 같은 `SwitchListTile` 스타일로 "야간 지도
  어둡게" 항목 추가 — `navHeadingUpProvider`용 스위치(L48-57)와 동일한 코드 패턴.

### 라운드3과의 관계 (구현 순서 주의)
라운드3(홈 레이아웃)은 이미 `_LogoBadge`·라이더모드 토글 아이콘·갤러리 아이콘을
"헤더 레이아웃 변경" 이유로 삭제하기로 계획돼 있었음. 이번 라운드는 같은 삭제를
"버튼 뒤에 연결된 기능 자체가 필요 없어졌다"는 별도 근거로 확인·확정하고, 거기서 한
걸음 더 나가 `riderModeProvider`/`isNightProvider`/`AppTheme.rider`·`night`까지 코드
전체에서 뿌리 뽑는 것. **구현 시 라운드3과 라운드8을 반드시 같은 세션·같은 커밋
계열에서 함께 처리** — 라운드3만 먼저 하면 헤더 UI는 사라지지만 provider·테마는
죽은 코드로 남고, 라운드8만 먼저 하면 `_MapHeader`/`_LogoBadge`가 참조하는
`riderMode` 파라미터가 컴파일 에러가 남.

### 확정된 수정 계획

**1. 앱 전체 테마 전환 기능 완전 삭제**
- `lib/main.dart:41-53`: `riderMode`/`isNight`/`theme`/`isDark` 관련 라인 제거,
  `MaterialApp.theme: AppTheme.light` 고정. 상태바 아이콘 밝기도 `Brightness.dark`
  고정(라이트 테마 하나뿐이므로 분기 불필요) — 단, 이 값은 라운드2 계획(`pastSplashProvider`
  기반 상태바·내비바 F5F1EC 통일)이 별도로 다시 손대는 지점이므로 라운드2 구현 시
  이 단순화를 전제로 진행할 것(라운드2가 검토했던 "야간모드/라이더모드도 예외 없이
  동일 색상 적용"이라는 조건 분기 자체가, 이 라운드로 야간모드/라이더모드 개념이
  없어지면서 자동으로 무의미해짐 — 분기 없이 항상 F5F1EC 하나만 적용하면 됨, 오히려
  더 단순해짐).
- `map_providers.dart:354`(`isNightProvider`)와 `map_providers.dart:466-474`
  (`riderModeProvider`, `_RiderModeNotifier`) 정의 삭제.
- `app_theme.dart:358-481`(`AppTheme.night`/`AppTheme.rider` getter)과
  `NightModeColors`(L132-160)/`RiderModeColors`(L167-191)/`RiderModeTextStyles`
  (L193-257) 클래스 삭제.

**2. `main_map_screen.dart` — 마커·배경색 분기 제거 (라운드3과 함께 구현)**
- L1583 `riderMode` 변수 삭제, L1596/1599/1621의 삼항 분기를 `AppColors.mapOrigin`/
  `AppColors.mapDestination`/`AppColors.background` 고정값으로 단순화.
- L1851/1853/1994/2003/2014-2036/2092-2132의 `riderMode` 관련 파라미터·분기는
  라운드3의 `_MapHeader` 재작성·`_LogoBadge` 삭제로 자연히 함께 정리됨(중복 작업 없이
  라운드3 구현에 포함).

**3. `tour_summary_detail_screen.dart` — 마커색 분기 제거**
- L197-210의 `riderModeProvider` 읽기·분기 제거, `AppColors.mapOrigin` 등 고정값만
  사용.

**4. 지도 야간 디밍 오버레이 — 코드 유지 + 설정 스위치 신규 추가 (Q4)**
- `main_map_screen.dart:1970-1981`의 오버레이 코드 자체는 그대로 둔다.
- `settings_providers.dart`에 `navHeadingUpProvider`(L10-25)와 동일한 패턴으로
  `mapNightDimEnabledProvider` 신규 추가(기본값 `true`, `SharedPreferences` 키 신규
  발급).
- `main_map_screen.dart:1974` 조건을 `if (!isDay && mapNightDimEnabled)`로 변경.
- `settings_screen.dart`의 "주행 설정" 섹션(L46-58, `navHeadingUpProvider` 스위치
  바로 아래)에 동일 스타일의 `SwitchListTile` "야간 지도 어둡게" 항목 신규 추가.

### 미확정 / 구현 시 확인
- `AppTheme.rider`/`night` 삭제 후 `app_theme.dart` 파일 내 import(`google_fonts` 등)가
  더 이상 필요 없어지는지는 구현 시 재확인(라이트 테마도 `GoogleFonts` 쓰므로 실제로는
  안 지워질 가능성 높음).
- 다크모드 자체(테마 전환)를 설정 페이지에서 다시 구현하는 것은 이번 라운드 범위 밖 —
  `settings_screen.dart:71`의 `// TODO Phase 2: 다크모드` 주석은 그대로 남겨 향후
  작업 표시로 유지.
- "야간 지도 어둡게" 스위치의 정확한 배치(주행 설정 섹션 vs 앱 설정 섹션)는 실기기
  확인 후 최종 결정 가능.

### 상태: **구현 완료 (2026-07-31, 라운드3과 동일 세션)**
flutter-coder → code-auditor PASS → 커밋 `644a757`(라운드3과 통합 커밋).
`riderModeProvider`/`isNightProvider`/`AppTheme.rider`/`AppTheme.night`/
`NightModeColors`/`RiderModeColors`/`RiderModeTextStyles` 전부 삭제, 잔여 참조
없음(grep 확인). `isDayProvider`/`daylightCycleProvider`/야간 디밍 오버레이는
계획대로 유지, `mapNightDimEnabledProvider` 신규 추가 + 설정화면 스위치 반영됨.

---

## 라운드 9 — 2026-07-30 (PIP 동작)

**참조 이미지**: `loop/layout_fixes/9_pip.png` — 다른 라운드들과 달리 레이아웃 지시용이
아니라 문제 상황 설명용. 빨간 원은 "PIP가 이렇게 뜬 적이 있다"는 예시 표시일 뿐, 이
화면 자체(위치/크기/내용)에 문제가 있다는 뜻은 아님(마스터 확인) — 진짜 문제는 아래
트리거 조건과 알림 잔류 쪽.

### 마스터 피드백 요약
PIP 모드가 제대로 동작하지 않아 코드 리뷰 필요. 기대하는 PIP 동작 조건:
0. (전제) 앱이 내비게이션 안내 중일 때
1. 사용자가 홈 버튼을 눌렀을 때
2. 사용자가 멀티태스킹(최근앱) 버튼을 눌러 다른 앱을 켰을 때
3. 다른 이유로 다른 앱이 켜졌을 때 (예: 전화 수신, 알람 등 사용자가 직접 홈/멀티태스킹을
   누르지 않았는데 다른 화면이 뜨는 경우)

별개로 상태바 알림(notification) 관련 버그도 있음: 앱을 닫아도 내비게이션 알림이
status bar에 계속 남아있음. 요구사항:
- 유루나비 앱만 켜져 있을 때(홈 화면 등, 내비게이션 아님): 알림 없어야 함
- 내비게이션 시작 시: 알림은 뜨되, 매번 바뀌는 회전 안내까지 반영할 필요는 없음(고정
  문구면 충분)

### 확인 질문 및 답변
- Q1. 스크린샷의 빨간 원이 "이 상태 자체가 문제"라는 뜻인지, "PIP가 뜨긴 뜬다"는 예시일
  뿐인지?
  → **A. PIP가 뜨긴 뜬다는 예시일 뿐.**
- Q2. 트리거 조건 1/2/3 중 실기기에서 실제로 안 되는 게 어떤 것인지?
  → **A. 전부 다 안 됨 / 잘 모르겠음** (1·2·3 모두 선택 — 특정 조건만 콕 집어 재현하긴
  어렵고, 전반적으로 못 미더운 상태로 파악).
- Q3. 알림 잔류 버그가 정확히 어떤 방식으로 앱을 닫았을 때 발생하는지?
  → **A. 기타/잘 모르겠음** (정확한 재현 경로 특정은 안 됨, 눈치채 보니 남아있었음).
- Q4. 알림에 남길 최소 내용은?
  → **A. 고정 문구만** (예: "경로 안내 중" — 턴바이턴 갱신 불필요).

### 조사 결과 (코드)
파일: `lib/features/navigation/presentation/nav_screen.dart`,
`android/app/src/main/kotlin/com/westinx/yurunavi/MainActivity.kt`,
`android/app/src/main/kotlin/com/westinx/yurunavi/NavForegroundService.kt`,
패키지 `android_pip` (`~/.pub-cache/hosted/pub.dev/android_pip-2.0.2`).

**PIP 트리거 구조 — 현재는 전부 "수동 진입" 방식 하나뿐**
- `nav_screen.dart:355-373`: Android에서만 `AndroidPIP` 인스턴스 생성 +
  `nav_pip_hint` 채널로 네이티브 `onUserLeaveHint()`를 수신해 `_maybeEnterPip()`
  (L416-427) 호출 → `pip.enterPipMode()`(수동 1회성 API, `PictureInPictureParams`를
  그때그때 만들어 즉시 진입 시도).
- `MainActivity.kt:51-54`: `onUserLeaveHint()` 오버라이드해 그 채널로 포워딩.
- `didChangeAppLifecycleState`(L405-414)가 `inactive`/`hidden` 상태에서도
  `_maybeEnterPip()`를 보완 호출 — 화면 꺼짐/전원 버튼 케이스 대응이지 조건 1/2/3과는
  다른 케이스.
- **구조적 결함(조건 3의 근본 원인)**: Android 공식 문서상 `onUserLeaveHint()`는
  "사용자가 명시적으로 화면을 떠나는 행동(홈/최근앱 전환 등)"에서만 보장되어 발화하며,
  전화 수신·알람 등 시스템이 다른 화면을 위에 띄우는 인터럽션에는 발화하지 않는다.
  즉 조건 3("다른 이유로 다른 앱이 켜졌을 때")은 현재 구조로는 **애초에 감지 자체가
  불가능** — 코드 버그가 아니라 선택한 메커니즘 자체의 한계.
- 조건 1/2도 이 수동 방식은 OEM(특히 마스터 스크린샷에 보이는 삼성 One UI 계열)마다
  `onUserLeaveHint` 발화 타이밍이 들쭉날쭉하다고 알려진 패턴이라, "전부 다 못 미더움"이라는
  마스터 체감과 부합.
- **발견**: 이미 의존성에 들어있는 `android_pip` 패키지가 Android 12(API 31)부터의 공식
  "Auto-enter PiP" API(`PictureInPictureParams.Builder().setAutoEnterEnabled(true)`)를
  `setAutoPipMode()` / `enterPipMode(autoEnter: true)`로 이미 노출하고 있음
  (`AndroidPIPModePlugin.kt` `setAutoPipMode`/`enterPipMode` 분기, `isAutoPipAvailable`
  게터까지 존재). 이 API는 "액티비티가 어떤 이유로든 백그라운드로 가면 OS가 알아서 PIP로
  전환"해주는 선언적 방식이라, `onUserLeaveHint` 수동 트리거와 달리 조건 3(전화 수신 등)도
  구조적으로 커버한다. **현재 코드는 이 메서드를 한 번도 호출하지 않고 있음** — 즉 이미
  프로젝트에 들어와 있는 도구를 안 쓰고 있는 상태.

**알림 잔류 버그**
- `NavForegroundService.kt` 전체에 `onTaskRemoved()` 오버라이드가 없음. 서비스 종료는
  전적으로 Dart 쪽 `nav_screen.dart:447` `unawaited(NavForegroundService.stop())`
  (`dispose()` 내부)에 의존.
- 앱을 최근앱(멀티태스킹) 목록에서 스와이프로 종료하는 것은 가장 흔한 "앱을 닫는" 방식인데,
  이 경우 Flutter 위젯의 `dispose()`가 보장되어 호출된다는 보장이 없고, `onTaskRemoved()`
  미구현 상태에서는 포그라운드 서비스가 태스크와 무관하게 계속 살아남아 알림도 같이 남는다
  — foreground service가 태스크 제거 후에도 죽지 않는 잘 알려진 Android 패턴.
- **"홈 화면에서도 알림이 보인다"는 첫 번째 불만과 "닫아도 남는다"는 두 번째 불만은 사실
  같은 근본 원인일 가능성이 높음**: `NavForegroundService.start()`는 코드상
  `nav_screen.dart:385`에서 내비게이션 시작 시에만 호출되고 홈 화면(main_map_screen 등)
  에서는 전혀 호출되지 않음(전수 grep 확인, `lib/` 전체에 호출부 3곳뿐 — start/update/stop
  전부 nav_screen.dart 안에 있음) → 홈 화면 자체가 알림을 새로 띄우는 게 아니라, 예전
  내비게이션 세션이 남긴 알림이 안 지워진 채로 홈 화면에서도 계속 보이는 것으로 추정.
- 앱을 설정에서 강제 종료하거나 프로세스가 통째로 죽는 경우는 서비스도 프로세스와 함께
  죽으므로 알림도 같이 사라짐 — 이 경로는 문제 없음, "스와이프로 최근앱 종료" 경로만이
  실질적 원인 후보.

**알림 문구 — 매 GPS 틱마다 갱신되는 구조**
- `nav_screen.dart:498-517` `_progressSub` 리스너가 매 위치 갱신마다 다음 턴 라벨+거리
  문자열(`fgText`)을 만들어, 이전 값과 다르면(`_lastForegroundText` 비교)
  `NavForegroundService.update(fgText)`(L516) 호출 → `NavForegroundService.kt`
  `ACTION_UPDATE` → `buildNotification(text)`의 `contentText`(L90)로 그대로 반영.
- 마스터 요구사항(고정 문구만)대로면 이 턴바이턴 갱신 호출 자체가 불필요 — 알림 채널명
  "주행 안내"(L33)는 이미 있지만 알림 본문(`contentText`)은 항상 매개변수로 받은 동적
  텍스트를 그대로 쓰는 구조.

### 확정된 수정 계획

**1. Auto-enter PiP 도입 (조건 1/2/3 전부 커버, API 31+)**
- `nav_screen.dart` 초기화 흐름(현재 `_pipReady` 게이트와 같은 자리, Android +
  `AndroidPIP.isPipAvailable` + `AndroidPIP.isAutoPipAvailable` 모두 true일 때)에서
  `_pip!.setAutoPipMode(autoEnter: true)` 호출 — `PictureInPictureParams`에
  `setAutoEnterEnabled(true)`를 등록해, OS가 액티비티를 어떤 이유로든(홈/멀티태스킹/전화
  수신 등) 백그라운드로 보낼 때 자동으로 PIP 진입하게 한다.
- `isAutoPipAvailable == false`인 기기(API 26~30)는 기존 `onUserLeaveHint` +
  `didChangeAppLifecycleState` 수동 경로를 그대로 폴백 유지 — 코드 삭제 없이 조건부로
  두 경로를 병행.

**2. 알림 잔류 버그 — `onTaskRemoved()` 추가 (네이티브)**
- `NavForegroundService.kt`에 `onTaskRemoved(rootIntent: Intent?)` 오버라이드 추가:
  `stopForeground(STOP_FOREGROUND_REMOVE)` + `stopSelf()` 호출. 앱이 최근앱 목록에서
  스와이프로 제거되는 순간 Dart `dispose()` 호출 여부와 무관하게 서비스·알림이 확실히
  정리됨 — 이 한 가지 수정이 마스터가 말한 두 증상(닫아도 남음 / 홈 화면에서도 보임)을
  함께 해결할 것으로 예상.

**3. 알림 문구 고정화**
- `nav_screen.dart:512-517`의 매 GPS 틱 `fgText` 계산 + `NavForegroundService.update()`
  호출부 제거. `NavForegroundService.start()`(L385) 호출 시 문구를 처음부터 고정 문자열
  ("경로 안내 중")로 전달하고 이후 갱신하지 않음.
- `ACTION_UPDATE`/`NavForegroundService.update()` 메서드 자체(Kotlin/Dart 양쪽)는
  인프라로 남겨두되 이번 라운드에서는 호출부가 없어짐 — 완전히 죽은 코드가 되면
  구현 시점에 삭제할지 유지할지 재확인(미확정 항목 참고).

### 미확정 / 구현 시 확인
- Auto-enter를 항상 켜둘지, 현재 `_maybeEnterPip()`가 걸던 가드(`_isManualMode`,
  `_showCourseSheet`일 때는 PIP 진입 안 함, L419-423)를 auto-enter 방식에서도 재현할지.
  선언적 API라 앱이 백그라운드로 가면 이 두 모드 중이어도 OS가 그냥 PIP를 띄워버림 —
  재현하려면 `_isManualMode`/`_showCourseSheet`가 바뀌는 지점(대략 5곳,
  `nav_screen.dart:1532/1536/1576/1679/1709/2318`)마다
  `setAutoPipMode(autoEnter: false/true)`를 다시 호출해 토글해야 함. 실효성 대비 구현
  복잡도를 실기기 확인 후 결정.
- `setAutoPipMode` 등록 타이밍 — 기존 2초 지연(`_pipReady`) 게이트를 그대로 쓸지, 조건
  3(전화 수신처럼 내비 시작 직후에도 즉시 벌어질 수 있는 인터럽션) 커버리지를 위해 지연
  없이 즉시 등록할지.
- 이번 계획은 코드 리뷰 기반 가설(공식 문서 + 패키지 소스 분석)이라 **구현 후 실기기
  검증이 특히 중요** — 조건 1/2/3 각각, 그리고 "최근앱에서 스와이프 종료 후 알림 사라짐"을
  실제로 재현/확인해야 함(마스터가 정확한 재현 경로를 특정 못 한 상태로 시작하는 라운드라
  다른 라운드보다 사후 검증 비중이 큼).
- `NavForegroundService.update()`/`ACTION_UPDATE` 죽은 코드 정리 여부 — 도착 임박 시점에
  문구를 한 번 바꾸는 등 향후 활용 가능성이 있어 남겨둘지, 이번에 같이 제거할지는 구현
  시 결정.
- 네이티브(Kotlin) 변경이 포함되는 라운드 — `flutter-coder`가 `android/` 네이티브까지
  같이 처리할지, 별도로 진행할지는 구현 착수 시 확인.

### 상태: 계획 확정, 구현 대기
다음 단계: (다른 라운드들과 함께) 마스터가 배치 구현 시작을 지시하면 코더 위임(Dart +
네이티브 Kotlin 변경 포함) → code-auditor PASS → 체크포인트 커밋. 실기기 PIP 3조건 +
알림 잔류 재현 검증 필수.

---

## 라운드 10 — 2026-07-30 (투어 히스토리 화면)

**참조 이미지**: `loop/layout_fixes/10_history.png` — 실기기 캡쳐. 상단 앱바("투어 기록"
+ 뒤로가기)와 상태바가 다크네이비로 보이고, 하단 시스템 내비게이션 바도 검정. 리스트
카드 자체(흰 배경, 거리/시간/속도/출발-도착 주소)는 크림 배경 위에 자연스럽게 놓여
있음.

### 마스터 피드백 (원문)
1. 상단 색상과 status bar, navigation bar의 색상이 검은색이라서 유루나비가 아니라 다른
   앱처럼 보임
2. 우측 삭제 버튼 눌렀을 때 바로 지워지지 말고 1회 확인 절차가 필요 (삭제하시겠습니까?
   에서 확인/취소 선택)
3. 브랜드 컬러 적용 희망

### 확인 질문 및 답변
- Q1. 삭제 시 이미 `AlertDialog`로 확인 절차가 구현돼 있는데(코드 조사 결과), 요청
  취지가 "실기기에서 안 뜨는 버그 의심"인지 "있는 줄 몰랐고 스타일만 다듬어달라"는
  것인지?
  → **A. 몰랐음 — 스타일만 다듬어줘.** 기존 확인 로직·트리거는 그대로 두고 다이얼로그
  겉모습(기본 Material 흰 배경/버튼)만 브랜드 톤으로 리스타일.
- Q2. 상단 헤더(AppBar) 색 변경 범위 — 이 화면만 로컬 오버라이드 vs 전역(다른 AppBar
  화면에도 동시 적용)?
  → **A. 전역으로 변경(권장안 채택).** `app_theme.dart`의 `AppBarTheme` 자체를 바꿔,
  아직 라운드 진행 전인 13 설정/14 내 장소/15 내 계정/16 내 오토바이 등도 동시에 같은
  헤더색을 갖게 됨 — 해당 라운드들에서 헤더색을 다시 다룰 필요 없어짐.
- Q3. 새 헤더 색 톤 — 라운드1 확정 브랜드 팔레트(코랄 `#E2896F`/크림 `#FBF1E7`/모스그린
  `#8CA283`/다크브라운 `#4A3B33`) 중 크림 블렌드형 vs 코랄·모스그린 solid형?
  → **A. solid + 흰 텍스트, 색상은 모스그린 `#8CA283`.**

### 조사 결과 (코드)
- **AppBar 배경**: `lib/core/theme/app_theme.dart:283-289` `AppTheme.light`의
  `appBarTheme.backgroundColor: AppColors.secondary`(다크네이비 `#1A2B3C`, 2026-07-29
  확정 브랜드 아이덴티티 이전의 구 팔레트 — `AppColors.primary`도 마찬가지로 구
  `#F28C28` 오렌지, [[project_brand_identity]] 참고). `foregroundColor: Colors.white`는
  이미 흰색이라 그대로 재사용 가능.
- 이 `appBarTheme`은 `ThemeData` 전역 설정이라 기본 `AppBar` 위젯을 쓰는 모든 화면(이
  히스토리 화면 포함, 13/14/15/16번 등 아직 미검토 화면 포함)에 공통 적용됨 — 전역
  변경 시 해당 화면들도 동시에 모스그린 헤더가 됨. 단 헤더 외 다른 레이아웃 문제는 각
  화면 라운드에서 계속 개별 검토.
- night/rider 테마의 `appBarTheme`(`app_theme.dart:381-386`, `437-`)은 조사만 하고
  변경 대상에서 제외 — 야간모드/라이더모드의 어두운 배경은 눈부심 방지를 위한 의도된
  디자인([[project_nav_ui_state]], [[feedback_safety_priority]] 연관 원칙: 안전 관련
  요소는 UX보다 안전 우선)이지 이번 "브랜딩이 다른 앱처럼 보인다"는 이슈와 무관.
- **상태바(상단)는 별도 조치 불필요**: Flutter `AppBar`는 `backgroundColor` 밝기에
  따라 상태바 아이콘 명도를 자동 계산해 `AnnotatedRegion`으로 적용하며, 이게
  `main.dart:27-32/49-53`의 수동 `SystemChrome.setSystemUIOverlayStyle` 호출보다
  화면 표시 중엔 우선 적용됨. 즉 지금 상태바가 검게(정확히는 배경이 비쳐) 보이는 것도
  AppBar 자체 배경색 때문 — 헤더를 모스그린(중간 밝기)으로 바꾸면 상태바 아이콘도
  자동으로 밝은 색(흰색)으로 맞춰질 것으로 예상.
- **하단 시스템 내비게이션 바(검정)는 이 화면만의 문제가 아님**: 라운드2("상태바·
  내비게이션 바" 전 화면 `#F5F1EC` 통일, 스플래시 제외)가 이미 이 이슈를 전역으로
  커버하도록 계획돼 있음 — 이번 라운드에서 별도 구현 불필요, 배치 구현 시 라운드2
  작업과 함께 자동 해결됨.
- **삭제 확인 다이얼로그**: `tour_summary_list_screen.dart:65-87` `_confirmDelete()` —
  이미 `AlertDialog`(제목 "투어 기록 삭제", 본문 "이 투어 기록을 삭제할까요?\n삭제하면
  되돌릴 수 없습니다.", `취소`/`삭제` 버튼)로 구현돼 있고, 삭제 아이콘의
  `GestureDetector`(L125-128)가 바로 이 함수를 호출함 — 즉시 삭제가 아니라 이미
  요구사항 충족. 다이얼로그는 `shape`(radius 20)만 커스텀이고 배경색·버튼 스타일은
  Flutter 기본 `AlertDialog`/`ElevatedButton`/`TextButton` 테마 그대로라 브랜드 톤이
  반영돼 있지 않음.

### 확정된 수정 계획

**1. AppBar 배경색 전역 변경 (브랜드 컬러 적용)**
- `app_theme.dart`의 `AppColors`에 신규 상수 추가(예: `static const brandMoss =
  Color(0xFF8CA283);`) — 라운드1에서 확정한 팔레트와 동일 계열 재사용, 별도 클래스
  분리 없이 기존 `AppColors`에 추가.
- `AppTheme.light`의 `appBarTheme`(L283-289) `backgroundColor: AppColors.secondary`
  → `AppColors.brandMoss`로 교체. `foregroundColor: Colors.white`,
  `titleTextStyle` 흰색은 그대로 유지(모스그린 배경에도 흰 텍스트 대비 충분).
- `AppColors.secondary`(`#1A2B3C`) 값 자체는 바꾸지 않음 — 다른 곳(텍스트 등)에서
  참조 중일 수 있어 이번 라운드 스코프(AppBar 배경 한 줄)를 벗어나는 부수효과를 피함.
  구현 시 `AppColors.secondary` 참조처 전수 grep 권장(미확정 항목 참고).
- night/rider 테마의 `appBarTheme`(L381-386, 437-)은 변경하지 않음.

**2. 삭제 확인 다이얼로그 스타일 브랜드화 (로직 변경 없음)**
- `_confirmDelete()`(`tour_summary_list_screen.dart:65-87`)의 다이얼로그 구조·트리거·
  버튼 동작(취소=false/삭제=true, `Navigator.pop`)은 손대지 않고 그대로 유지.
- 스타일만 조정: 배경색을 `AppColors.background`/`surface` 계열로, 텍스트는
  `AppTextStyles`(프로젝트 공통 텍스트 스타일) 재사용. "삭제" 버튼은 파괴적 액션임을
  시각적으로 유지하기 위해 기존 `AppColors.error`(경고색) 계열 유지 — 브랜드
  모스그린으로 바꾸면 "삭제=안전한 액션"처럼 오인될 수 있어 위험 액션은 경고색이
  적절(구현 시 최종 확인). "취소" 버튼은 브랜드 톤(`AppColors.brandMoss`)으로.

### 미확정 / 구현 시 확인
- `AppColors.secondary` 참조처 전수 확인 — 이번 변경은 `appBarTheme.backgroundColor`
  한 줄만 새 상수로 교체하는 것이라 `AppColors.secondary`를 직접 쓰는 다른 곳은 원래
  값 그대로 유지되지만, `Theme.of(context).appBarTheme.backgroundColor`를 별도로
  참조하는 코드가 있는지도 확인 필요.
- 모스그린 배경에서 Flutter AppBar의 자동 상태바 아이콘 명도 계산이 기대대로(흰 아이콘)
  나오는지 실기기 확인 — 아니라면 `AppBar.systemOverlayStyle`을 명시적으로 지정.
- 이 라운드가 라운드2보다 먼저 단독 구현될 경우 하단 내비게이션 바는 일시적으로 여전히
  검정으로 남을 수 있음 — 배치 구현 순서상 문제 없을 것으로 예상되나, 개별 구현 시엔
  라운드2와 함께 처리 권장.
- 13/14/15/16번 등 다른 AppBar 화면이 이번 전역 변경으로 먼저 모스그린 헤더를 갖게 됨
  — 해당 라운드 진행 시 "헤더 색은 이미 반영됨" 전제로 진행하고 헤더 외 다른 레이아웃
  이슈만 신규로 다루면 됨(중복 작업 방지).
- 삭제 다이얼로그 배경/버튼 색의 정확한 톤(예: `surface` vs `background`, 삭제 버튼을
  `error` 그대로 vs 약간 다듬을지)은 실기기 시안 확인 후 최종 결정.

### 상태: **1번(AppBar 전역 모스그린) 구현 완료 (2026-07-31)** / 2번(삭제 확인
다이얼로그 브랜드화)은 **미구현 — 범위에서 의도적으로 제외됨**
1번은 flutter-coder → code-auditor PASS → 커밋 `6a9ce00`
(`feat(theme): AppBar 전역 배경색을 모스그린 브랜드 컬러로 교체`)로 완료.
`AppColors.brandMoss(#8CA283)` 신규 추가, `AppTheme.light.appBarTheme.backgroundColor`만
교체(`AppColors.secondary` 값 자체는 안 건드림). `settings_screen.dart` 등
로컬 오버라이드가 있는 화면(13/14/15/16번)은 이 전역 변경이 아직 자동 적용 안 됨 —
각 라운드가 로컬 오버라이드 제거를 맡을 때 반영됨(계획대로).
`tour_summary_list_screen.dart`의 삭제 확인 다이얼로그 스타일링(2번 항목)은
**이번엔 손대지 않았다** — 다른 화면들의 확인 다이얼로그(14/15번 등)와 함께
묶어서 나중에 처리하는 편이 낫다고 판단, 아직 미구현 상태로 남아있음.

---

## 라운드 11 — 2026-07-30 (히스토리 상세 화면)

**참조 이미지**: `loop/layout_fixes/11_history_contents.png` — 실기기 캡쳐 3장. 좌측(현재
상태)은 상단 통계 카드(시간대 15:00–16:23 + 거리/평균/최고)와 지도 위 회색 주행 궤적
폴리라인. 가운데는 메모 입력 모듈("이 투어에 대한 메모를 남겨보세요" + 체크 버튼) 열린
상태. 우측은 마스터가 그린 참고 이미지 — 메모 입력 후 화면 하단에 반투명 코랄색 카드로
"7월 26일 (월)" + 메모 본문이 지도 위에 상시 떠 있고, 주행 궤적은 초록색으로 표시됨.

### 마스터 피드백 (원문)
1. 카드(상단 통계 카드) 색상이 맵 색상과 비슷한 톤이라 강조가 안 됨 — 브랜드 컬러 중에서도
   진한 보색 컬러로 가야 함 (모스그린?)
2. 주행 경로도 검은색은 부정적인 인상을 줌 (코스 선택 시 "선택받지 못한 경로"가 이런
   회색으로 나옴) — 색상 변경 희망
3. 메모 입력 모듈은 예쁘고 좋음. 그런데 입력 완료해도 화면에는 상시 표시가 안 되고 데이터로만
   남아서, 다시쓰기 버튼을 눌러야 입력 모듈에 표시됨 — 투어의 추억을 기록하는 것이니, 입력하면
   살짝 반투명한 카드가 코스를 되도록 가리지 않도록 하면서 항상 맵 위에 표시되어야 함
4. (후속) 경로의 시작과 끝은 코스 선택 화면과 동일하게 포인터를 넣어달라. 중간에 경유지를
   들렸다면 경유지 포인터도 넣어달라.

### 확인 질문 및 답변
- Q1. 상단 통계 카드 색상 — 라운드10(히스토리 목록)에서 이미 AppBar를 모스그린 solid
  (`#8CA283`) + 흰 텍스트로 확정했는데, 상세 페이지 카드도 같은 모스그린으로 통일할지,
  아니면 카드는 구분되게 다른 보색(코랄 계열)으로 갈지?
  → **A. 모스그린 통일** — AppBar와 동일 계열 `#8CA283`.
- Q2. 주행 경로선 색상 — 회색/검은 계열을 어떤 색으로 바꿀지?
  → **A. 코랄(브랜드 강조색)**.
- Q3. 메모 카드를 지도 위에 상시 표시할 때 정확한 위치/트리거?
  → **A. 화면 하단 고정** (참고 이미지 그대로 — 경로와의 겹침을 감지해 위/아래로 피하는
  동적 배치가 아니라 항상 하단 고정).
- Q4. 메모 카드가 상시 표시되면 기존 "다시쓰기"(연필 아이콘) 진입점은 어떻게 될지?
  → **A. 상시 카드 + 기존 진입점 별도 유지.** 카드 자체는 탭 대상이 아닌 순수 표시 전용 —
  수정은 계속 기존 연필 아이콘으로만. 카드 투명도는 "완전 불투명은 아니라는 걸 알 수 있는
  정도"(약 0.9 알파 = 10%만 비침)로, 가독성이 최우선.
- Q5. (후속) 출발지 포인터 — 코스 선택 화면 조사 결과, 그 화면도 출발지를 정적 핀이 아닌
  실시간 GPS 화살표 퍼크로 표시해서 "그대로 재사용할 출발 핀" 자산이 없음이 확인됨. 어떻게
  처리할지?
  → **A. 새 출발지 핀 이미지를 제작.**
- Q6. (후속) 경유지 포인터 — `TourLog`에 경유지 데이터가 애초에 저장되지 않아 이번 라운드
  범위에서 바로 넣을 수 없음이 확인됨. 별도 데이터 저장 과제로 미루고 이번 라운드는 UI만
  진행할지?
  → **A. 경유지는 이번 계획에서 제외.**

### 조사 결과 (코드)
파일: `lib/features/tour_summary/presentation/tour_summary_detail_screen.dart`

- **상단 통계 카드**: L300–381. 배경 `cs.surfaceContainerHigh`(L312, Material
  `ColorScheme` surface tone이라 지도와 톤이 비슷해 안 도드라짐 — 마스터 지적의 실체).
  텍스트/아이콘 색은 전부 `cs.onSurface`/`cs.onSurfaceVariant`(L338/348-350/363,
  `_StatItem` 내부 L465/469)로 라이트 테마 기준 어두운 색.
  **함정**: `_StatItem`(L453–472)은 별도 `StatelessWidget`이라 `Theme.of(context)`에서
  **자기 스스로** `cs`를 다시 얻음(L460) — 부모 카드 배경만 모스그린으로 바꾸면 `_StatItem`
  라벨/값 텍스트는 전역 테마의 `onSurface`(어두운 텍스트)를 그대로 읽어 카드 배경과 대비가
  깨짐. `_StatItem`에 텍스트 색 오버라이드 파라미터를 추가해야 함.
  `AppColors`(`app_theme.dart:6-45`)엔 아직 신 브랜드 팔레트(코랄/크림/모스/다크브라운)
  상수가 없음 — 라운드10에서 `AppColors.brandMoss = Color(0xFF8CA283)` 신규 추가를
  계획해뒀음(아직 미구현). 이번 라운드도 동일 상수를 재사용하면 됨(두 라운드 중 먼저
  구현되는 쪽에서 상수를 추가하고, 나중 라운드는 재사용만 하면 중복 없음).
- **주행 경로선**: L184–195, `ml.addLineLayer`의 `lineColor`가
  `colorToHex(ref.read(skinProvider).colors.courseLineColor[2]!)`(L189) — 스킨의
  `courseLineColor` 맵 인덱스 2를 하드코딩 참조. 활성 스킨 `yurucam_skin.dart`
  (`courseLineColor` L87-91)에서 인덱스 2는 `#7C8B99`(탁한 청회색) — 실제 지도 화면
  `main_map_screen.dart:407/868`의 "미선택 경로" 회색 `#9E9E9E`와 톤이 거의 같아, 마스터
  지적("선택받지 못한 경로"와 같은 회색)이 코드로도 확인됨.
  **좋은 소식**: 스킨마다 이미 `routeLine`이라는 전용 시맨틱 getter가 있음 —
  `yurucam_skin.dart:74` `#E2896F`(코랄, 정확히 원하는 색), `cub_buddy_skin.dart:74`
  `#C05F4C`, `retro_motoring_skin.dart:74` `#78B4AC`, `default_skin.dart:73`
  `AppColors.mapRoute`. 즉 `courseLineColor[2]` → `.routeLine`으로 한 줄만 바꾸면
  인덱스 하드코딩 없이 스킨별로 항상 그 스킨의 브랜드 강조색이 나오고, 현재 활성 스킨
  (유루캠)에서는 정확히 코랄이 적용됨 — 스킨 시스템을 거스르지 않는 정공법.
- **메모 기능**: 입력 패널 `_buildMemoPanel`(L403–450), 하단 `Positioned`
  (L384–397)의 `AnimatedSize` 안에서 `_memoExpanded ? _buildMemoPanel(cs) :
  const SizedBox.shrink()`(L394)로 토글 — 즉 **패널이 닫혀 있으면 메모 존재 여부와
  무관하게 완전히 사라짐**, 이게 마스터가 지적한 "상시 표시 안 됨"의 정확한 코드 위치.
  저장은 `tourLogListProvider.notifier.updateMemo`(`tour_log_providers.dart:21-31`,
  모델은 `TourLog.memo`, `models/tour_log.dart:19`) → 로컬 스냅샷 `_currentMemo`(L51)로
  즉시 반영. "다시쓰기" 진입점은 별도 버튼이 아니라 상단 카드의 연필 아이콘
  (`edit_note`/`edit_note_outlined`, L342-352)이 `_toggleMemoPanel`(L75-84) 호출 — 열 때마다
  `_memoCtrl.text`를 `_currentMemo`로 리셋(L80)해 기존 메모를 불러와 수정 가능하게 함(이
  동작은 그대로 유지).

### 확정된 수정 계획

**1. 상단 통계 카드 — 모스그린 solid + 흰 텍스트**
- `AppColors.brandMoss`(라운드10과 공유하는 신규 상수, 없으면 이번 라운드에서 선제 추가)로
  L312 배경 교체.
- `_StatItem`(L453-472)에 `Color? labelColor`/`Color? valueColor` 파라미터 추가(또는 단일
  `Color textColor` + 라벨은 그 위에 알파를 낮춘 버전) — 상세 화면 호출부(L371-373)에서
  흰색 계열(라벨 `Colors.white70`, 값 `Colors.white`) 전달. 다른 화면에서 `_StatItem`을
  재사용하는 곳이 있는지 grep 후 기본값은 기존 `cs.onSurface`/`cs.onSurfaceVariant` 유지해
  회귀 방지.
- 상단 행의 시간 텍스트(L334-340)·연필 아이콘(L344-351)·공유 아이콘(L359-364) 색도
  `cs.onSurface` → 흰색 계열로 교체(모스그린 배경 위 가독성).
- 연필 아이콘의 "메모 있음" 강조색(현재 `cs.primary`, L349)은 흰 배경 대비용이었으므로
  모스그린 카드 위에서도 눈에 띄는 색(예: 코랄 강조 or 그대로 흰색 굵게)으로 재검토 —
  실기기 확인 후 결정(미확정 항목).
- 그림자(`Colors.black.withValues(alpha:0.15)`, L316)는 배경색과 무관하게 유지.

**2. 주행 경로선 — 코랄(스킨 `routeLine`)로 교체**
- L189 `ref.read(skinProvider).colors.courseLineColor[2]!` →
  `ref.read(skinProvider).colors.routeLine`로 한 줄 교체. 인덱스 하드코딩을 없애는 부수효과도
  있고, 현재 활성 유루캠 스킨에서 정확히 코랄(`#E2896F`)이 적용됨 — 스킨별 값이 달라도
  일관되게 "그 스킨의 브랜드 강조색"이 나오므로 스킨 시스템과 충돌 없음.

**3. 메모 — 지도 위 상시 반투명 카드 추가 (기존 입력 진입점은 그대로 유지)**
- 하단 `Positioned`(L384-397)의 `AnimatedSize` 자식 분기를 확장: `_memoExpanded`면 기존
  `_buildMemoPanel(cs)` 그대로, 아니면 `(_currentMemo?.isNotEmpty ?? false)`일 때 새
  `_buildMemoDisplay(cs)`, 둘 다 아니면 기존처럼 `SizedBox.shrink()`.
- 신규 `_buildMemoDisplay(cs)`: `_buildMemoPanel`과 동일한 `margin(12)`/
  `borderRadius(20)`/`boxShadow` 톤은 유지하되, 배경을 스킨 `routeLine`(코랄, 위 2번과 같은
  색 소스 재사용 — 경로선과 메모 카드가 같은 강조색 계열로 통일되는 효과)의
  `withValues(alpha: 0.9)`(약 10%만 비치는 정도, 정확한 값은 실기기 가독성 확인 후 조정)로,
  텍스트는 흰색(참고 이미지와 일치).
- 카드에는 `GestureDetector`/`onTap` 등 탭 핸들러를 넣지 않음(Q4 답변 — 상시 카드와 편집
  진입점은 별개, 카드는 순수 표시 전용). 편집은 계속 상단 연필 아이콘 하나로만 가능.
- 메모 본문 텍스트는 `maxLines` 제한(예 6줄) + `TextOverflow.ellipsis` 적용 검토 — 상시
  고정 위치라 메모가 길면 지도를 과도하게 가릴 수 있음(미확정 항목, 실기기 확인).

**4. 출발·도착 포인터 — 코스 선택 화면과 동일한 이미지 핀 방식으로 전환 (경유지 제외)**
- 후속 조사 결과: 코스 선택 화면(`main_map_screen.dart`)은 출발/도착/경유지를 `ml.addCircle`
  단순 원이 아니라 **이미지 핀**(`ml.addSymbol` + `ml.addImage`)으로 그림 — 목적지
  `pointer_red.png`(아이콘 상수 `_kDestIcon`, `main_map_screen.dart:131-132`, 심볼 생성
  L780-797), 경유지 `pointer_yellow.png`(`_kWpIcon`, L133-134/848-851), 이미지 등록은
  L1707-1712. **단, 출발지는 코스 선택 화면에서도 정적 핀이 아니라 실시간 GPS 화살표 퍼크
  (`nav_arrow`, `_kArrowIcon`)로 표시** — 즉 "그대로 재사용할 출발 핀 자산"이 앱에 없음.
  히스토리 상세 화면은 과거 완료된 투어라 실시간 위치가 없어 화살표 퍼크를 쓸 수 없음.
  → **마스터 확인: 새 출발지 핀 이미지를 제작**(추천안 채택). 목적지는 기존
  `pointer_red.png` 그대로 재사용.
  → **경유지 포인터는 이번 라운드에서 제외**(마스터 확인) — `TourLog`
  (`models/tour_log.dart:5-19`)에 경유지 데이터 자체가 저장되지 않고 있음을 확인(경유지는
  `nav_screen.dart`에서 주행 중에만 메모리에 존재하다 투어 종료 시 버려짐, 저장 로직 없음).
  경유지 표시는 별도 데이터 저장 과제(투어 종료 시 `TourLog`에 경유지 목록 persist)가 먼저
  필요해 이번 UI 라운드 범위 밖 — 필요해지면 로드맵 항목으로 별도 논의.
- 현재 구현: `tour_summary_detail_screen.dart` L197-213, `ml.addCircle`로 출발
  `circleColor: AppColors.mapOrigin`(초록 `#4CAF50`)/도착
  `circleColor: AppColors.mapDestination`(빨강 `#E53935`), 반지름 8, 흰색 2px 스트로크.
  이걸 `main_map_screen.dart:780-797`과 동일한 패턴(`ml.addImage`로 스타일 로드 후 1회
  등록 → `ml.addSymbol(SymbolOptions(iconImage:..., iconSize:~1.05, geometry:...))`)으로
  교체.
  - 도착: `iconImage: 'pointer_red'`(코스 선택과 완전히 동일한 자산·크기 재사용).
  - 출발: 신규 핀 자산(가칭 `pointer_start` 또는 `pointer_green`) 제작 필요 — 현재 이 화면의
    기존 원 색(초록 `AppColors.mapOrigin`)과 일관되게 초록 계열로 제안, `pointer_yellow`와
    같은 핀 모양(형태만 재사용, 색만 교체)이 가장 작업량이 적음. 정확한 색상·형태는 시안
    단계에서 확인(로고 제작 방식과 동일하게 별도 디자인 승인 필요).

### 미확정 / 구현 시 확인
- 연필 아이콘의 "메모 있음" 강조색을 모스그린 카드 배경 위에서 무엇으로 할지(흰색 굵게 vs
  코랄 포인트) — 실기기 시안에서 확인.
- 상시 메모 카드의 정확한 알파값(0.9 근사치) — 실기기에서 지도 위 가독성 확인 후 조정.
- 참고 이미지엔 메모 카드 안에 "7월 26일 (월)" 같은 날짜 헤더가 함께 그려져 있으나, 마스터
  피드백 원문엔 날짜 표시에 대한 언급이 없어 이번 계획에는 포함하지 않음 — 손그림의 부가
  연출인지 실제 요구사항인지 구현 전 확인 필요(작게 추가하는 정도면 비용 낮음).
- 긴 메모의 카드 높이 제한(`maxLines`) 적용 여부·줄 수 — 실기기 확인 후 최종 결정.
- `_StatItem` 재사용처가 이 화면 외에 있는지 grep 확인 후 파라미터 기본값으로 회귀 방지.
- 신규 출발지 핀 이미지의 정확한 색상·형태(시안) — 로고(라운드1)와 동일하게 별도 디자인
  승인 절차 필요, 확정 전까지 임시로 `pointer_yellow` 색만 초록으로 바꾼 버전을 가안으로
  가정.

### 상태: 계획 확정, 구현 대기
다음 단계: (다른 라운드들과 함께) 마스터가 배치 구현 시작을 지시하면 flutter-coder
위임(카드 배색+`_StatItem` 파라미터, 경로선 스킨 참조 교체, 메모 상시 카드 신규 위젯,
출발/도착 핀 심볼 전환) → code-auditor PASS → 체크포인트 커밋. 출발지 핀 이미지는
디자인 시안 승인이 선행되어야 함(로고와 동일한 절차).

---

## 라운드 12 — 2026-07-30 (히스토리 상세 공유 화면)

**참조 이미지**: `loop/layout_fixes/12_history_contents_share.png` — OS 공유 시트 스크린샷
2장. 좌측(현재 상태)은 "이미지 1개" 미리보기에 상단 통계 카드만 작게 떠 있음(지도 없음).
우측(마스터가 원하는 상태, 기존 공유시트 스크린샷을 편집해 만든 참고 이미지)은 같은
미리보기 자리에 카드 + 그 아래 경로가 그려진 지도 전체가 함께 보임. 아래 공유 대상 앱
목록(퀵셰어/KDE Connect/카카오톡/Instagram/Drive 등)은 두 장이 동일 — 이번 라운드는
공유되는 **이미지의 내용/비율**만 다루고 공유 대상 앱 목록 UI는 대상이 아님.

### 마스터 피드백 (원문)
12번은 히스토리의 공유 화면. 이미지로 다운받거나, 그걸 인스타나 페이스북 같은데에 올리는
것인데, 지금은 카드만 달랑 올리게 되어 있음. 이미지 사이즈는 카드+온전한 경로를 포함하는
지도와 함께 해서 1:1 정방형 이미지로 하되, 만약 카드+지도가 1:1을 훌쩍 넘어서 세로로
길쭉할 경우에는 길쭉한 지도 그대로 이미지화 할 것. 11번에서 텍스트를 입력해 놓았다면,
입력한 텍스트 카드는 공유 이미지에 포함되지 않으며, 대신 텍스트의 내용이 자동으로
클립보드에 복사될 것 — 이때 하단에 토스트 메시지로 "텍스트가 클립보드에 복사되었습니다."
안내.

### 확인 질문 및 답변
- Q1. 카드+지도를 1:1로 만들려면 지도가 정사각형 영역 안에 전체 경로가 들어가도록 공유
  시점에 지도 위젯의 크기/줌을 재조정해서 캡처해야 하는데(그래야 경로가 잘리지 않음), 이
  재조정 과정이 사용자 화면에 잠깐 보여도 되는지?
  → **A. 화면에 보여도 무방** — 공유 버튼을 누르면 잠깐 지도가 재조정되었다가 공유시트가
  뜨는 정도는 자연스러운 UX로 수용.
- Q2. 메모(11번에서 입력한 텍스트)가 있을 때 "클립보드 자동 복사"가 기존에 OS 공유시트
  텍스트 필드를 채우던 동작을 대체하는지, 그 동작은 유지한 채 클립보드 복사가 추가되는지?
  → **A. 클립보드가 대체** — 공유시트에는 이미지만 전달, 텍스트 필드는 비움. 원문의 "카드에
  포함되지 않는 대신 클립보드로"라는 표현과 가장 일치.
- Q3. "다운받거나 인스타/페이스북에 올리는 것"이라 하셨는데 지금은 공유 버튼(OS 공유시트)
  하나뿐 — 공유시트 안에서 '내 드라이브'/'파일로 저장' 선택도 사실상 다운로드라 이 버튼
  하나로 다운로드+SNS업로드가 다 커버되는데 충분한지, 갤러리 직접저장용 별도 '다운로드'
  버튼이 새로 필요한지?
  → **A. 기존 공유 버튼으로 충분** — 별도 다운로드 버튼 불필요.

### 조사 결과 (코드)
- **공유 로직**: `lib/features/tour_summary/tour_share_helper.dart` `shareTourImage()`
  (L28-110) — 이미 헤더(통계 카드)와 지도 스냅샷을 세로로 합성해 공유하는 구조가 존재.
  헤더는 `RenderRepaintBoundary.toImage(pixelRatio: 3.0)`(L49)로 고정 배율 캡처, 지도는
  `mapController.takeSnapshot()`(L57-59, 6초 타임아웃)으로 **네이티브 지도가 현재 화면에
  그리고 있는 뷰포트를 있는 그대로** 스냅샷 — 정사각형/비율에 대한 제약이 전혀 없다.
  `_compositeVertically`(L131-157)는 두 이미지를 단순히 위/아래로 쌓기만 함(폭이 다르면
  좁은 쪽만 가운데 정렬, 리사이즈는 하지 않음).
- **"카드만 나오는" 원인**: L51-64 주석에 이미 명시 — 일부 실기기에서 네이티브
  `MapSnapshotter`가 타임아웃/오류를 내면 지도 없이 헤더만 폴백 공유(L71-75)하도록 설계돼
  있음. 마스터가 실기기에서 본 "카드만 달랑" 현상은 이 폴백 경로가 실제로 자주 타는 것으로
  보임(라운드11 조사에서도 동일 이슈 별도 확인). 이번 라운드에서 정사각형 재구성 로직을
  더해도 이 폴백 자체는 안전장치로 유지해야 함(구현 난이도가 늘수록 실패 지점도 늘어나므로).
- **지도 위젯 구조**: `tour_summary_detail_screen.dart` L268-278, `ml.MapLibreMap`이
  `Positioned.fill`로 화면 전체를 채움(헤더 카드는 그 위에 얹힌 오버레이). 카메라는
  `_maybeDrawTrack()`(L177-232)에서 트랙 로드 완료 시 `animateCamera(newLatLngBounds(...,
  left:40, top:100, right:40, bottom:40))`(L221-232)로 전체 경로가 화면 안에 들어오게 1회
  피팅됨 — **이 피팅은 항상 "전체 화면" 크기 기준**이라, 지금 구조 그대로 스냅샷을 찍으면
  화면 전체 높이(세로로 매우 긴 폰 화면 비율)가 그대로 찍혀 헤더+지도 합계가 정사각형과는
  거리가 멀다. 정사각형을 만들려면 캡처 시점에 지도 위젯의 레이아웃 박스 자체를 좁은
  높이로 줄이고, 그 줄어든 뷰포트 기준으로 `animateCamera`를 다시 호출해야 전체 경로가
  잘리지 않고 다시 피팅된다(Q1에서 확인한 그 재조정).
- **헤더 캡처 범위**: `_statHeaderKey`는 상단 통계 카드(L306-379)만 감싼 `RepaintBoundary`
  — 하단 메모 입력 패널(`_buildMemoPanel`, L384-397, 403+)은 이 키 범위 밖이라 **이미
  자동으로 캡처 대상이 아님**. 라운드11에서 계획된 "메모 상시 표시 카드"(`_buildMemoDisplay`,
  아직 미구현 — 현재 코드엔 `_memoExpanded ? _buildMemoPanel(cs) : SizedBox.shrink()`
  (L394)만 있고 상시 카드 분기는 없음)가 나중에 추가되어도 같은 이유로 헤더 캡처엔 안 잡히고,
  지도는 `takeSnapshot()`으로 네이티브 지도 레이어만 찍으므로 그 위에 얹힌 Flutter 오버레이
  위젯(메모 카드 포함)도 스냅샷에 안 찍힘 — **"메모 카드가 공유 이미지에 포함되지 않아야
  한다"는 요구사항은 현재/향후 구조상 별다른 조치 없이 이미 만족됨.** 이번 라운드가 실제로
  구현해야 할 새 동작은 "클립보드 복사 + 토스트" 쪽이다.
- **메모 데이터 소스**: 라운드11의 상시 카드 UI는 아직 미구현이지만, 메모 **데이터**
  자체(`_currentMemo` 필드, `widget.tourLog.memo`)는 이미 존재하고 저장/로드가 동작 중
  (`_saveMemo`, L86-107) — 이번 라운드의 "메모가 있으면 클립보드 복사" 조건 판단은
  라운드11 UI 구현 여부와 무관하게 이 필드만으로 충분히 처리 가능.
- **현재 공유 텍스트 동작(대체 대상)**: `_shareTour()`(L109-127)이 `shareTourImage(...,
  memo: _currentMemo)`로 호출하고, `shareTourImage` 내부(L86-91)는 `trimmedMemo`가 있으면
  `ShareParams(files:[...], text: shareText)`로 OS 공유시트 텍스트 필드에 메모를 채움 —
  Q2 확정에 따라 이 `text:` 전달 자체를 제거해야 함.

### 확정된 수정 계획

**1. 지도 스냅샷용 "캡처 모드" 도입 — 정사각형/세로형 판정 + 뷰포트 재구성**
- `_TourSummaryDetailScreenState`에 `bool _capturing = false` 추가. `_shareTour()` 시작 시
  `setState(() => _capturing = true)`로 전환.
- L268-278의 지도 `Positioned.fill`을 `_capturing`일 때만 다른 높이로 바꾸는 조건부
  `Positioned`로 변경: 평상시는 기존 그대로 `top:0,left:0,right:0,bottom:0`(fill), 캡처
  모드에서는 `top:0,left:0,right:0`+`height: _captureMapHeight`(계산값, 아래 참조) —
  즉 지도가 화면 상단부터 그 높이만큼만 차지하도록 임시로 줄어듦(화면에 실제로 보임,
  Q1 확정).
- `_captureMapHeight` 계산(신규 헬퍼, `tour_share_helper.dart` 또는 화면 클래스 내부):
  1. `headerHeight` = `_statHeaderKey.currentContext!.findRenderObject()`의 `size.height`
     (캡처 직전 실측값, logical px).
  2. `screenWidth` = `MediaQuery.of(context).size.width`.
  3. `squareMapHeight = screenWidth - headerHeight` (헤더+지도 합이 정사각형이 되는
     기본값).
  4. 트랙의 위경도 bounding box를 미터 단위 근사 종횡비로 변환(경도 delta ×
     cos(중위도), 위도 delta는 그대로 비교)해 `routeAspect = bboxHeightM / bboxWidthM`
     계산.
  5. `routeAspect`가 `squareMapHeight` 기준 뷰포트 종횡비(`squareMapHeight / screenWidth`)
     대비 과도하게 크면(즉 경로가 남북으로 너무 길어 정사각형 안에 넣으면 지나치게
     축소돼 거의 안 보이게 되는 경우) → 세로형 모드로 전환: `_captureMapHeight`를
     `routeAspect`에 비례해 더 크게(예: `screenWidth * routeAspect` 근사, 상한은 화면
     높이의 2~3배 정도로 캡) 계산. 임계값·배율 정확한 수치는 실기기에서 실제 경로 몇 건
     테스트 후 조정(미확정 항목).
     그렇지 않으면(경로가 정사각형 안에 무리 없이 들어가는 경우) → `_captureMapHeight =
     squareMapHeight` 그대로(정사각형 모드).
- `setState`로 지도 높이를 바꾼 뒤, 트랙의 새 bounds fit을 그 새 높이 기준으로 다시
  호출: 기존 `_maybeDrawTrack()`의 `animateCamera(newLatLngBounds(...))` 부분(L221-232)을
  재사용 가능한 함수로 뽑아 캡처 모드 진입 시 한 번 더 호출(패딩 값은 그대로 재사용).
  레이아웃 반영 + 카메라 애니메이션이 프레임에 실제로 그려질 시간을 확보하기 위해
  `setState` 이후 짧은 지연(예: 다음 프레임 콜백 + 카메라 애니메이션 완료 대기)을 두고
  나서 `takeSnapshot()` 호출 — 정확한 대기 방식/시간은 구현 시 확인(미확정).
- 캡처(`shareTourImage` 호출) 완료 후(성공/실패 무관) `finally`에서 `_capturing = false`로
  되돌리고, 지도를 원래 전체화면 bounds로 다시 `animateCamera`(기존 `_maybeDrawTrack`의
  피팅 파라미터 재사용) — 사용자가 상세 화면으로 돌아왔을 때 원래 보던 화면 그대로
  복귀되도록.

**2. `tour_share_helper.dart` 합성 로직 — 스케일 통일**
- 헤더는 `pixelRatio: 3.0` 고정, 지도 스냅샷은 (1번에서 리사이즈된 위젯 크기 ×) 기기
  `devicePixelRatio` 기준 네이티브 해상도로 나올 가능성이 커 두 이미지의 px/논리픽셀
  스케일이 다를 수 있음 — 현재 `_compositeVertically`(L131-157)는 폭 차이를 가운데
  정렬만 할 뿐 리사이즈하지 않으므로, 최종 결과가 의도한 정사각형에서 어긋날 수 있음.
  지도 이미지(또는 헤더 이미지)를 상대 스케일에 맞춰 리사이즈한 뒤 합성하도록 보정 —
  정확한 스케일 보정 계수는 구현 시 실측 후 확정(미확정 항목).
- 나머지 세로 스택 합성 자체(흰 배경, 좌우 중앙 정렬)는 기존 로직 재사용 — 1번에서 이미
  목표 높이에 맞춰 캡처했으므로 사후 크롭/패딩은 불필요.

**3. 메모 → 클립보드 복사 + 토스트 (공유 텍스트 대체)**
- `shareTourImage()`의 `memo` 파라미터·`ShareParams.text` 전달(L86-91) 제거 — 공유시트에는
  항상 이미지 파일만 전달(`ShareParams(files:[XFile(path)])`).
- `_shareTour()`(L109-127)에서 `_currentMemo`를 trim한 값이 비어있지 않으면:
  `Clipboard.setData(ClipboardData(text: trimmed))`(`flutter/services.dart`, 신규 import)
  호출 + `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('텍스트가
  클립보드에 복사되었습니다.')))` 표시. 메모가 비어있으면 클립보드/토스트 둘 다 생략(기존과
  동일하게 이미지만 공유).
- 타이밍: OS 공유시트가 뜨면 그 아래 화면의 스낵바가 가려질 수 있어, 클립보드 복사+토스트
  호출은 `SharePlus.instance.share(...)` 호출 **직전**(이미지 파일 준비가 끝난 시점,
  공유시트가 뜨기 직전)에 실행해 토스트가 잠깐이라도 보이는 타이밍을 확보 — 실기기에서
  실제 노출 여부 확인 필요(미확정).

**4. 별도 다운로드 버튼 — 추가하지 않음**
- Q3 확정에 따라 기존 `ios_share` 아이콘(L359-364, `_shareTour` 연결) 하나만 유지, 새
  위젯/패키지 추가 없음.

### 미확정 / 구현 시 확인
- 정사각형 vs 세로형 판정의 정확한 경로-종횡비 임계값과 세로형일 때의 높이 배율 —
  실기기에서 짧은/남북으로 긴/동서로 긴 경로 등 몇 케이스를 실제로 캡처해보고 눈으로 확인
  후 조정.
- 헤더(`pixelRatio 3.0` 고정)와 지도 네이티브 스냅샷 간 스케일 불일치 보정 방식 — 구현
  시 실측 후 리사이즈 계수 확정.
- 지도 위젯 리사이즈 → bounds 재피팅 → 카메라 애니메이션 완료 → 스냅샷 캡처 순서의 정확한
  대기 처리 — `takeSnapshot()` 자체도 이미 실기기 타임아웃 이슈가 있어(조사 결과 참조),
  리사이즈 단계가 늘어난 만큼 실패 가능성도 늘 수 있음. 기존 헤더-only 폴백(L71-75)은
  안전장치로 그대로 유지.
- 클립보드 복사+토스트 호출 시점(공유 직전 vs 공유 시트가 뜬 뒤)의 실제 사용자 체감 —
  실기기 확인 후 최종 조정.
- 라운드11의 메모 상시 카드가 나중에 실제 구현될 때, 그 카드도 이번 조사에서 확인한 대로
  헤더 `RepaintBoundary` 범위 밖·지도 네이티브 스냅샷 범위 밖이라 공유 이미지에 자동으로
  제외됨을 재확인해둘 것(별도 조치 불필요, 회귀 확인 차원).

### 상태: 계획 확정, 구현 대기
다음 단계: (다른 라운드들과 함께) 마스터가 배치 구현 시작을 지시하면 flutter-coder
위임(캡처 모드 지도 리사이즈+재피팅 로직, 합성 스케일 보정, 클립보드/토스트 치환) →
code-auditor PASS → 체크포인트 커밋.

---

## 라운드 13 — 2026-07-30 (설정 화면)

**참조 이미지**: `loop/layout_fixes/13_setting.png` — 실기기 캡쳐 1장. 상단 다크네이비
AppBar("설정"+뒤로가기), 프로필 편집 `ListTile`(소제목 없음), 지도 표기 언어(라디오
2줄), 스킨(원형 컬러칩+이름 3줄), 주행 설정(on/off 스위치), 앱 설정(즐겨찾기 카테고리),
기타(이용약관) 순으로 항목별 세로 간격이 넓게 배치됨. 하단 시스템 내비게이션 바도 검정.

### 마스터 피드백 (원문)
1. 상단 색상과 status bar, navigation bar의 색상이 검은색이라서 유루나비가 아니라 다른
   앱처럼 보임
2. 항목별로 위아래가 너무 띄어져 있는 느낌. 한국어-English의 상하 간격, 스킨의 각
   항목별 간격이 과도하게 넓어 보임
3. 다른 항목은 다 작게 소제목이 들어가 있는데, 프로필 편집만 없음. 수정 요망
4. 지도 표기언어, 지도 방향 항목은 즐겨찾기 카테고리와 함께 앱 설정 안에 같이 넣을 것.
   지도 표기언어는 풀다운 메뉴 형태로 하여 한 줄로 표현할 것(디폴트는 한국어)
5. 스킨 이름을 임의로 붙인 이름 대신, 색상 기조를 한 단어로 나타내는 단어로 바꿀 것
6. 주행 설정(헤딩업, 노스업)은 현재 on/off 토글스위치인데, 전환 토글 스위치가 있는지
   확인하여 변경할 것
7. (화면과 별개) 앱 빌드 시 앱 이름을 스마트폰 시스템 언어별로 분기 — 한글 기기=
   "유루나비", 영어=Yurunavi, 일본어="ゆるナビ"

### 확인 질문 및 답변
- Q1(AppBar 색 충돌). 라운드10에서 이미 AppBar 전역 배경을 모스그린 `#8CA283`으로
  확정했고 "13/14/15/16은 이미 반영된 것으로 전제하고 넘어가라"고 명시까지 돼 있는데,
  이번 세션 첫 답변에서 주황 `#F28C28`을 고르셔서 충돌을 짚어드림 →
  **A. 모스그린 `#8CA283` 유지(라운드10 결정 그대로).** 단, 조사 결과 설정 화면은
  로컬에서 `AppColors.secondary`로 명시 오버라이드 중이라 라운드10 전역 변경만으론 이
  화면에 반영되지 않음 — 이번 라운드에서 그 오버라이드를 제거해야 실제로 적용됨(조사
  결과 참조).
- Q2(스킨 이름). 색상 hex 기준 "코랄/틸/테라코타" 직역 제안을 드렸으나 →
  **A. 감성적인 이름으로 지어달라**(직역 대신 위임). 아래 확정 계획의 제안 참조 —
  구현 전 최종 확인 권장.
- Q3(토글 형태). "전환 토글 스위치"가 두 옵션이 나란히 보이고 선택된 쪽만 강조되는
  세그먼트 버튼을 뜻하는지 확인 → **A. 맞음**, `SegmentedButton<bool>` 채택.
- Q4(앱 이름 범위). 이 서버(Linux)로는 iOS 빌드·검증이 불가능하고 iOS 로케일 분기는
  Xcode 프로젝트 설정까지 손대야 해 코드만 남고 검증이 안 됨 — Android만 우선할지 확인
  → **A. Android만 우선.** iOS는 이번 계획 범위 밖.

### 조사 결과 (코드)
파일: `lib/features/settings/presentation/settings_screen.dart`(174줄),
`lib/features/settings/providers/settings_providers.dart`,
`lib/core/theme/app_theme.dart`, `lib/core/skin/skins/*.dart`,
`android/app/src/main/AndroidManifest.xml`

- **AppBar**: L20-24 `AppBar(title:'설정', backgroundColor: AppColors.secondary,
  foregroundColor: Colors.white)` — 라운드10이 전역 `AppBarTheme.backgroundColor`를
  모스그린으로 바꾸기로 확정했지만, 이 화면은 로컬 `backgroundColor:
  AppColors.secondary`로 다시 덮어쓰고 있어 전역 변경이 무력화됨. **로컬 오버라이드
  두 줄을 삭제하고 전역 테마를 그대로 물려받게** 해야 라운드10 결정이 실제로 적용됨 —
  이번 라운드가 그 제거를 담당.
- **간격**: 프로필 `ListTile`(L28-35)·언어 `ListTile`(L115-124, 옵션당 1개)·스킨
  `ListTile`(L138-149, 옵션당 1개) 모두 `visualDensity`/`contentPadding` 미지정 →
  플랫폼 기본 밀도 그대로. `_SectionHeader`(L154-173) 패딩도
  `EdgeInsets.fromLTRB(16,20,16,4)`로 섹션 위 여백만 20dp. 옵션이 여럿 이어지는
  언어/스킨 섹션에서 이 기본 밀도가 누적되어 "위아래가 너무 뜬" 느낌의 실체.
- **소제목 구조**: `_SectionHeader` 위젯이 이미 존재(회색 12sp 소제목)하고 지도
  표기언어/스킨/주행 설정/앱 설정/기타 5곳에 붙어있는데, 리스트 최상단 프로필 편집
  (L28-35)만 헤더 없이 바로 시작.
- **병합 대상 3개**: 지도 표기언어는 `_LanguageSelector`(L99-129,
  `RadioGroup<MapLanguage>` 옵션 2개 세로 나열), 지도 방향은 주행 설정 섹션의
  `SwitchListTile`(L48-57, `navHeadingUpProvider` bool), 즐겨찾기 카테고리는 이미 앱
  설정 섹션(L61-69) 안에 있음 — 셋을 앱 설정 섹션 하나로 모으면 됨.
- **스킨 이름**: `kAvailableSkins`(`registry.dart`) 3개 — `YuruCamSkin.displayName`
  (`yurucam_skin.dart:16`)='유루캠 무드'(brand `#E2896F`), `RetroMotoringSkin
  .displayName`(`retro_motoring_skin.dart:16`)='레트로 모터링'(brand `#78B4AC`),
  `CubBuddySkin.displayName`(`cub_buddy_skin.dart:16`)='동네 라이딩 메이트'(brand
  `#C05F4C`) — `displayName` 게터 문자열 3곳만 교체하면 됨(id/선택 로직 변경 없음).
- **토글 스위치**: `navHeadingUpProvider`(`settings_providers.dart:10-27`)가 이미
  `bool`(headingUp=true/false) 상태·퍼시스턴스를 관리하고 있어 `SegmentedButton<bool>`
  로 교체해도 provider 로직은 그대로 재사용 가능 — 위젯 레벨 교체만 필요.
- **앱 이름**: `android/app/src/main/AndroidManifest.xml:12`
  `android:label="yurunavi"` 하드코딩 리터럴(리소스 참조 아님).
  `android/app/src/main/res/`엔 아직 `strings.xml`이 전혀 없음(`values`/`values-night`
  디렉토리만 존재, `values-ko`/`values-ja`도 없음) — 표준 안드로이드 로케일 리소스
  분기(`values/`, `values-ko/`, `values-ja/`)로 해결 가능.

### 확정된 수정 계획

**1. AppBar 로컬 오버라이드 제거 (라운드10 반영)**
- L20-24에서 `backgroundColor: AppColors.secondary`, `foregroundColor: Colors.white`
  두 줄 삭제, `AppBar(title: const Text('설정'))`만 남겨 전역 `AppBarTheme`(라운드10에서
  모스그린으로 변경)을 그대로 상속.
- **배치 구현 시 주의**: 이 삭제만으로는 효과가 없고, 라운드10의 전역
  `appBarTheme.backgroundColor` 변경이 먼저(또는 같은 배치에서) 적용돼 있어야 함 —
  순서 누락 방지용으로 명시.

**2. 항목 간격 축소**
- 프로필/언어/스킨 `ListTile` 3곳 모두 `visualDensity: VisualDensity.compact`,
  `dense: true`, `contentPadding: EdgeInsets.symmetric(horizontal:16)` 추가.
- `_SectionHeader`(L154-173) 상단 패딩 `20`→`12`로 축소(하단 `4`는 유지).
- 정확한 목표 dp는 제안값 — 실기기 확인 후 미세조정 필요(미확정 항목).

**3. 프로필 편집 소제목 추가**
- L27 앞에 `const _SectionHeader(title: '프로필')` 삽입 — 기존 5개 섹션과 동일한
  위젯 재사용, 신규 위젯 불필요.

**4. 앱 설정 섹션 재구성 (지도 표기언어 + 지도 방향 + 즐겨찾기 카테고리 통합)**
- 최상단의 `_LanguageSelector` 섹션(L38-40)과 주행 설정 섹션의 지도 방향 항목
  (L46-57)을 원래 자리에서 제거하고, 기존 "앱 설정" `_SectionHeader`(L61) 아래로
  이동. 순서: ① 지도 표기언어(풀다운, 5번 참조) → ② 지도 방향(세그먼트 버튼, 6번
  참조) → ③ 즐겨찾기 카테고리(기존 L62-69 그대로).
- "주행 설정" 섹션은 지도 방향 하나만 있던 섹션이라 통합 후 헤더째 사라짐(빈 섹션
  제거).
- "스킨" 섹션(L42-44)은 이번 병합 지시에 포함되지 않았으므로 그대로 별도 섹션 유지.

**5. 지도 표기언어 — 풀다운 메뉴로 교체**
- `_LanguageSelector`(L99-129)를 `RadioGroup` 세로 나열 대신
  `ListTile(title: Text('지도 표기 언어'), trailing: DropdownButton<MapLanguage>(...))`
  한 줄 형태로 교체 — 라벨 매핑(한국어/English)과 `mapLanguageProvider` 로직은 그대로
  재사용, 위젯만 축소.
- 기본값은 이미 `LanguageService.load()`(L11-13)가 `korean` 폴백이라 별도 조치
  불필요(요구사항 이미 충족 확인됨).

**6. 지도 방향 — 세그먼트 버튼으로 교체**
- 기존 `SwitchListTile`(L48-57)을 `SegmentedButton<bool>`로 교체:
  `segments: [ButtonSegment(value:true, label:Text('헤딩업')),
  ButtonSegment(value:false, label:Text('노스업'))]`, `selected: {headingUp}`,
  `onSelectionChanged: (s) => ref.read(navHeadingUpProvider.notifier).set(s.first)`.
- provider·퍼시스턴스 로직(`settings_providers.dart`)은 변경 없음 — 위젯 레벨 교체만.
- 두 라벨이 항상 같이 보이고 선택된 쪽만 강조되는 형태라 기존 `subtitle`(설명 텍스트,
  L53)은 불필요해져 제거.

**7. 스킨 이름 — 감성적 색상 연상 단어로 교체 (제안, 최종 확인 필요)**
- `displayName` 게터 3곳 문자열만 교체:
  - `YuruCamSkin`(`yurucam_skin.dart:16`, 코랄 `#E2896F`) → **"노을빛"**
  - `RetroMotoringSkin`(`retro_motoring_skin.dart:16`, 틸 `#78B4AC`) → **"박하빛"**
  - `CubBuddySkin`(`cub_buddy_skin.dart:16`, 테라코타 `#C05F4C`) → **"황토빛"**
- 3개 모두 "~빛" 접미사로 통일해 이름 패턴의 일관성을 확보(색상을 직접 지칭하는
  외래어 대신 감성적 연상 단어, 마스터 요청 반영). `id`/선택 저장값 등 로직은 건드리지
  않음(표시 문자열만 교체).
- 처음 제안하는 이름이라 구현 전 마스터 최종 확인 권장(다른 이름 원하면 교체 가능).

**8. 앱 이름 로케일 분기 (Android, 화면과 별개 항목)**
- `android/app/src/main/res/values/strings.xml` 신규 생성:
  `<string name="app_name">Yurunavi</string>` (기본값/폴백 — ko/ja 이외 모든 시스템
  언어).
- `android/app/src/main/res/values-ko/strings.xml` 신규 생성:
  `<string name="app_name">유루나비</string>`.
- `android/app/src/main/res/values-ja/strings.xml` 신규 생성:
  `<string name="app_name">ゆるナビ</string>`.
- `AndroidManifest.xml:12` `android:label="yurunavi"` →
  `android:label="@string/app_name"`로 교체 — 나머지 매니페스트 구조는 변경 없음.
- iOS(`CFBundleDisplayName`)는 이번 계획 범위 밖(Q4 확정) — 필요해지면 별도 라운드에서
  Xcode 프로젝트 로컬라이제이션 등록까지 함께 다룸.

### 미확정 / 구현 시 확인
- 항목 간격 축소값(`visualDensity`/패딩 구체 수치)은 제안값 — 실기기 확인 후
  미세조정.
- 스킨 3종 새 이름("노을빛"/"박하빛"/"황토빛")은 이번에 처음 제안하는 것이라 구현 전
  마스터 최종 확인 권장.
- 지도 표기언어 드롭다운 세부 스타일(`DropdownButton` vs `DropdownMenu`, 언더라인
  유무 등)은 실기기 시안에서 확인.
- **라운드10의 AppBar 전역 변경(모스그린)이 이 라운드와 반드시 같은 배치에서(또는
  먼저) 구현돼야 함** — 이 라운드의 로컬 오버라이드 삭제만으로는 전역 테마 자체가 아직
  안 바뀌어 있으면 효과 없음(구현 순서 누락 방지용 재확인).
- 하단 시스템 내비게이션 바(검정)는 라운드2 전역 조치로 자동 해결 — 이번 라운드 별도
  작업 불필요.

### 상태: 계획 확정, 구현 대기
다음 단계: (다른 라운드들과 함께) 마스터가 배치 구현 시작을 지시하면 flutter-coder
위임(라운드10/2 전역 변경과 함께 처리, 스킨 이름 최종 확인 포함) → code-auditor PASS
→ 체크포인트 커밋.

---

## 라운드 14 — 2026-07-30 (즐겨찾기 관리 페이지 + 즐겨찾기 카드)

**참조 이미지**: `loop/layout_fixes/14_myPlaces.png` — 실기기 캡쳐 3장. ① 지도 위
즐겨찾기 버튼을 눌렀을 때 뜨는 카드(단일 즐겨찾기 장소 + "최근 경로" 목록), ②
주황 AppBar의 "즐겨찾기 카테고리" 관리 화면(미분류/집/회사/맛집 목록, 각 항목
우측에 삭제 아이콘), ③ 같은 화면에서 "+" 눌렀을 때 뜨는 "카테고리 추가" 카드형
다이얼로그.

### 마스터 피드백 (원문)
1. 즐겨찾기 카드에 나오는 최근 경로 우측에 ☆ 버튼 넣어서 바로 등록할 수 있게 할
   것, 이미 즐겨찾기된 곳이면 노란 ★로 표시
2. 즐겨찾기 옆의 삭제 버튼 누르면 바로 지워지지 말고 한번 물어보게 할 것
3. 즐겨찾기 카테고리 관리 페이지에서도 상단 색상과 status bar, navigation bar
   색상을 히스토리 페이지와 동일하게 맞출 것
4. 카테고리 삭제 버튼도 즉시 삭제 대신 확인(확인/취소) 절차 추가
5. 카테고리 추가 누르면 카드가 뜨는 대신, 리스트 밑에 바로 입력칸이 나와서 바로
   입력하도록
6. 집/회사/맛집 등 좌측에 순서 변경 핸들 추가(6번 이미지 경유지 카드 참조)

(※ 이어 붙어 있던 "항목별 간격/한국어-English 간격/스킨 이름/주행설정 토글/앱
이름 언어분기" 피드백은 마스터 확인 결과 붙여넣기 실수 — 이미 라운드13(설정
화면)에 동일 내용으로 확정 기록돼 있어 이번 라운드 범위에서 제외.)

### 확인 질문 및 답변
- Q1(7~10번 중복). 간격 과다/스킨 이름/주행설정 토글/앱 이름 언어분기 항목은
  코드 확인 결과 즐겨찾기 화면이 아니라 설정 화면(13번 이미지) 얘기와 내용이
  완전히 겹침("한국어-English 간격", "스킨" 등은 즐겨찾기 화면엔 없는 요소) →
  **A. 붙여넣기 실수, 삭제.** 라운드13 계획 그대로 유효, 14번 계획엔 미포함.
- Q2(별 탭 동작). 즉시 등록 vs 등록 시트(이름 수정+카테고리 선택) 오픈 →
  **A. 등록 시트 열기.** 4번 라운드에서 이미 확정된 `_FavoriteStarButton`/
  `_showAddFavoriteSheet` 패턴 그대로 재사용.
- Q3(미분류 순서 변경 가능 여부). → **A. 미분류는 항상 최상단 고정, 핸들 없음.**
- Q4(카테고리 삭제 시 소속 즐겨찾기 처리). 현재 코드엔 재배정 로직이 전혀 없어
  삭제해도 그 즐겨찾기들은 존재하지 않는 카테고리명을 계속 들고 있게 됨 →
  **A. 자동으로 미분류 재배정.** 이번 라운드 범위에 포함.

### 조사 결과 (코드)
파일: `lib/features/map/presentation/main_map_screen.dart`(즐겨찾기 카드),
`lib/features/settings/presentation/favorite_categories_screen.dart`(카테고리
관리), `lib/features/map/providers/map_providers.dart`(provider),
`lib/services/places_service.dart`(저장소), `lib/models/saved_place.dart`(모델),
`lib/features/map/presentation/waypoint_management_sheet.dart`(핸들 재사용 참고),
`lib/features/tour_summary/presentation/tour_summary_list_screen.dart`(삭제 확인
다이얼로그 재사용 참고)

- **즐겨찾기 카드**: `_PlacesSheet`(`main_map_screen.dart:2746-2874`). "즐겨찾기"
  섹션(단일/복수 장소, L2790-2826)의 각 행은 이미 삭제 `IconButton`(L2816-2819,
  `onRemoveFavorite(p.id)` 즉시 호출 — 확인 절차 없음)을 갖고 있음. "최근 경로"
  섹션(L2830-2859)의 각 `ListTile`(L2841-2853)에는 **`trailing`이 아예 없음** —
  별 버튼이 화면에 보였다는 마스터 인지와 달리 코드상 미구현 상태(신규 추가
  필요).
- **재사용 가능한 별 버튼**: `_FavoriteStarButton`(L2546-2588, 최상위 private
  위젯, `_PlacesSheet`와 같은 파일이라 바로 참조 가능) — `lat`/`lng`/
  `initialName` 3개 파라미터만 받아 `FavoritePlace.findByLocation`으로 즐겨찾기
  여부 판정 후 노란 채움/회색 외곽선 별을 그리고, 탭 시 이미 즐겨찾기면 즉시
  `remove`(확인 없음, 기존 동작 그대로 유지 대상), 아니면
  `_showAddFavoriteSheet`(L2593-2606) → `_AddFavoriteSheet`(이름 입력+카테고리
  칩, L2608-)를 염. 4번 라운드(POI 카드)에서 이미 같은 위젯을 검색결과 2곳
  (L3377, L3458)에 재사용 중 — 최근 경로 행에 세 번째 사용처로 추가하면 됨.
- **이름 폴백 이미 구현됨**: `_routeTitle(r)`(L2869-2873)이 `destName`이 없으면
  `"→ lat, lng"` 형태로 이미 폴백 처리 — 별 버튼의 `initialName`에 그대로
  재사용 가능(추가 로직 불필요).
- **카테고리 관리 화면**: `favorite_categories_screen.dart`(161줄,
  `ConsumerWidget`). AppBar가 `backgroundColor: AppColors.primary`(구 팔레트
  오렌지, L51), `foregroundColor: Colors.white`(L52)로 로컬 오버라이드 중 —
  라운드13이 `settings_screen.dart`에서 정리하기로 한 것과 동일한 패턴(다만
  그쪽은 `AppColors.secondary` 오버라이드, 이쪽은 `AppColors.primary`).
  라운드10(전역 AppBar 모스그린 `#8CA283`화)·라운드2(전역 상태바/내비바
  `#F5F1EC`화)가 아직 미구현 상태라 이 화면도 그 두 라운드가 처리하는 "13/14/
  15/16 자동 반영" 대상에 이미 포함돼 있었음 — 이번 라운드는 그 전역 처리를
  무력화하는 로컬 오버라이드 2줄(L51-52)을 제거하는 것만 담당.
- **카테고리 삭제**: `_removeCategory`(L40-42) → `IconButton.onPressed`
  (L95-99)에서 직접 호출, 확인 절차 없음. **재배정 로직 전무**:
  `FavoriteCategoriesNotifier.remove`(`map_providers.dart:425-429`)는 카테고리
  이름 목록에서만 제거하고, 이미 그 카테고리로 저장된 `FavoritePlace.category`
  값은 건드리지 않음 — 삭제 후에도 존재하지 않는 카테고리명을 계속 들고 있는
  "고아 데이터" 상태가 됨(Q4로 확인, 이번 라운드에서 자동 재배정 로직 추가하기로
  함).
- **카테고리 추가**: `_addCategory`(L14-21) → `showDialog<String>` +
  `_CategoryEditDialog`(`AlertDialog`, L110-160) — 카드형 팝업으로 뜨는 것 확인.
  같은 다이얼로그를 이름 변경(`_renameCategory`, L23-38, 행 탭 시 트리거)에도
  재사용 중 — 마스터 피드백은 "추가"만 지목했으므로 이번 라운드는 추가 흐름만
  인라인으로 바꾸고, 이름 변경은 기존 다이얼로그 방식 유지(미확정 항목에 재확인
  필요로 표시).
- **핸들 좌측 배치 참고 위젯**: `WaypointManagementSheet`
  (`waypoint_management_sheet.dart:16-110`) 내부 `_SheetBody`(L114-293)가
  `ReorderableListView`(L197-258)로 각 행에 `Icons.drag_handle`을
  `ReorderableDragStartListener`로 감싸 배치하는 패턴을 이미 사용 중(단, 그쪽은
  trailing 배치) — 이번 라운드는 동일한 `ReorderableListView` + 핸들 아이콘
  메커니즘을 재사용하되 배치만 leading(좌측)으로 바꾸면 됨.
- **순서 데이터 모델 부재**: 카테고리는 `FavoriteCategory` 같은 모델 없이
  `List<String>`(`favoriteCategoriesProvider`, `map_providers.dart:396-430`)으로만
  관리 — 리스트의 인덱스 순서 자체가 곧 표시 순서이자 저장 순서
  (`PlacesService.saveCategories`, `places_service.dart:75-78`,
  `SharedPreferences.setStringList`)이므로, 드래그 결과로 리스트 순서를 바꾼 뒤
  그대로 `saveCategories`하면 별도 필드 추가 없이 구현 가능.
- **삭제 확인 다이얼로그 재사용 패턴**: `tour_summary_list_screen.dart:65-87`
  `_confirmDelete()` — 라운드10에서 이미 "히스토리 화면 삭제 확인" 스타일
  기준으로 채택된 패턴(`AlertDialog`, 제목+본문+취소/삭제 버튼,
  `Navigator.pop(true/false)`). 이번 라운드의 즐겨찾기 삭제·카테고리 삭제 확인
  다이얼로그 둘 다 동일 패턴을 그대로 복제해 쓰면 라운드10이 정한 버튼 스타일
  (취소=브랜드톤, 삭제=`AppColors.error`)과 자연히 통일됨.
- **FavoritePlace/PlacesService 저장 방식**: `PlacesService`
  (`places_service.dart`)는 `addFavorite`/`removeFavorite`만 있고 기존 항목의
  필드를 부분 수정하는 API가 없음(L28-46) — 카테고리 일괄 재배정을 구현하려면
  신규 메서드가 필요(계획 참조). `loadFavorites()`(L18-26)는 저장 순서를
  **뒤집어서**(`reversed`, 최신순) 반환하므로, `FavoritePlacesNotifier.state.value`
  (이미 뒤집힌 리스트)를 그대로 다시 저장하면 저장 순서가 오염됨 — 재배정 구현
  시 원본 저장 순서를 보존하는 방식으로 처리해야 함(구현 시 주의사항으로 명시).

### 확정된 수정 계획

**1. 최근 경로 행에 즐겨찾기 별 버튼 추가**
- `_PlacesSheet`의 최근 경로 `ListTile`(`main_map_screen.dart:2841-2853`)에
  `trailing: _FavoriteStarButton(lat: r.destLat, lng: r.destLng, initialName:
  _routeTitle(r))` 추가. 기존 `_FavoriteStarButton`/`_showAddFavoriteSheet`/
  `_AddFavoriteSheet`를 그대로 재사용(신규 위젯 불필요), 탭 시 이미 즐겨찾기면
  즉시 해제(★→☆, 확인 없음, 기존 동작 유지), 아니면 등록 시트가 열림(Q2 확정).
- `onTap`(행 전체, 목적지로 이동)과 별 버튼 탭이 겹치지 않도록 `trailing` 영역은
  `ListTile`이 자동으로 별도 히트테스트 처리하므로 추가 처리 불필요(4번
  라운드에서 이미 검증된 동일 패턴).

**2. 즐겨찾기/카테고리 삭제에 확인 절차 추가**
- `main_map_screen.dart:2816-2819`(즐겨찾기 장소 삭제)와
  `favorite_categories_screen.dart:95-99`(카테고리 삭제) 각각에
  `tour_summary_list_screen.dart:65-87` 패턴을 복제한 `_confirmDelete` 헬퍼
  추가 — `AlertDialog`(제목 "즐겨찾기 삭제"/"카테고리 삭제", 본문에 되돌릴 수
  없음 안내, 취소/삭제 버튼) 확인 후에만 기존 `onRemoveFavorite(p.id)`/
  `_removeCategory(ref, name)` 호출.
- 카테고리 삭제 확인 다이얼로그 본문에는 "이 카테고리로 등록된 즐겨찾기는 모두
  '미분류'로 이동합니다" 안내 문구 추가(Q4 확정 사항을 사용자에게도 고지).

**3. 카테고리로 지정된 즐겨찾기 자동 미분류 재배정**
- `PlacesService`(`places_service.dart`)에 저장 순서를 보존하는 신규 메서드
  추가(예: `reassignFavoriteCategory(String from, String to)` — raw
  `SharedPreferences` 문자열 리스트를 직접 순회하며 `category == from`인 항목만
  디코드→카테고리 교체→재인코드, 순서는 그대로 유지) —
  `FavoritePlacesNotifier.state.value`(뒤집힌 표시용 리스트)를 그대로 재저장하지
  않도록 주의(조사 결과 순서 오염 이슈 참고).
- `FavoritePlacesNotifier`(`map_providers.dart:378-392`)에 이 서비스 메서드를
  호출하고 `ref.invalidateSelf()`하는 `reassignCategory(from, to)` 추가.
- `_removeCategory`(`favorite_categories_screen.dart:40-42`)가
  `favoriteCategoriesProvider.notifier.remove(name)` 호출 전에
  `favoritePlacesProvider.notifier.reassignCategory(name,
  kUncategorizedFavoriteCategory)`를 먼저 호출하도록 수정(두 provider 모두 같은
  파일 `map_providers.dart`에 있어 참조 문제 없음).

**4. 카테고리 관리 화면 색상 — 로컬 오버라이드 제거**
- `favorite_categories_screen.dart:51-52`의 `backgroundColor:
  AppColors.primary`, `foregroundColor: Colors.white` 두 줄 삭제,
  `AppBar(title: const Text('즐겨찾기 카테고리'), actions: [...])`만 남겨 전역
  테마 상속.
- **전제조건(순서 누락 방지)**: 라운드10(AppBar 전역 모스그린화)과 라운드2
  (상태바/내비바 전역 `#F5F1EC`화)가 같은 배치에서 함께 구현돼야 실제로 히스토리
  화면과 동일한 색으로 보임 — 이 라운드 단독 구현 시 로컬 오버라이드만 사라지고
  여전히 구 팔레트 전역값(`AppColors.secondary` 다크네이비)이 보일 수 있음.

**5. 카테고리 추가 — 인라인 입력으로 전환**
- `favorite_categories_screen.dart`를 `ConsumerWidget` → `ConsumerStatefulWidget`
  으로 전환, `_isAdding`(bool) + `TextEditingController` + `FocusNode`(자동
  포커스용) state 추가.
- AppBar의 `+` 버튼(L54-57): 다이얼로그 호출(`_addCategory`) 대신
  `setState(() => _isAdding = true)`.
- `ListView`의 카테고리 목록 마지막(맛집 등 뒤, `categories.asMap().entries
  .map(...)` 다음)에 `_isAdding == true`일 때만 보이는 인라인 `Row`
  (`TextField(autofocus, controller, focusNode, hintText: '예: 집, 회사, 맛집',
  onSubmitted: (v) => _submitAdd(v))` + 확인 `IconButton(Icons.check)` + 취소
  `IconButton(Icons.close)`) 추가.
- 확인(체크 아이콘 또는 키보드 완료) 시: `favoriteCategoriesProvider.notifier
  .add(text)` 호출 후 `setState(() { _isAdding = false; controller.clear(); })`.
  취소(X 아이콘) 시 입력값 버리고 `_isAdding = false`만.
- 이름 변경(`_renameCategory`, L23-38, 행 탭 트리거)은 기존
  `_CategoryEditDialog` 방식 그대로 유지 — 마스터 피드백이 "추가" 흐름만
  지목했으므로 이번 라운드 범위에서 제외(미확정 항목에 재확인 표시).

**6. 카테고리 좌측 순서 변경 핸들**
- `categories.asMap().entries.map(...)`로 그리던 카테고리 목록(L87-101, 미분류
  제외)을 `waypoint_management_sheet.dart:197-258`와 동일한
  `ReorderableListView`(`shrinkWrap:true`, `NeverScrollableScrollPhysics`, 각
  `ListTile`에 `key: ValueKey(name)`) 구조로 교체.
- 각 행의 `leading`을 기존 `Icons.label_rounded` 단독에서
  `Row(mainAxisSize.min, [ReorderableDragStartListener(index: index, child:
  Icon(Icons.drag_handle)), SizedBox(width:6), Icon(Icons.label_rounded, ...)])`
  로 변경 — 핸들을 기존 아이콘 좌측에 추가(마스터 피드백 "좌측에 핸들 추가"
  그대로 반영, 기존 아이콘 삭제 아님).
- "미분류" 행(L70-76)은 이 `ReorderableListView` 바깥(기존처럼 상단 고정
  `ListTile`)에 그대로 남겨 핸들 없이 최상단 고정 유지(Q3 확정).
- `FavoriteCategoriesNotifier`(`map_providers.dart:400-430`)에 `reorder(int
  oldIndex, int newIndex)` 추가 — 로컬 리스트 순서만 바꾼 뒤 `saveCategories`로
  영속화(모델 변경 불필요, 리스트 인덱스 = 순서, 조사 결과 참고).

### 미확정 / 구현 시 확인
- 카테고리 이름 변경(rename) 흐름은 이번 라운드에서 다이얼로그 방식 그대로
  유지하기로 가정 — "추가"만 인라인화하고 "변경"은 그대로 두는 것이 일관성 면에서
  어색해 보이면 별도 라운드나 이번 라운드 확장으로 재검토 여지 있음, 구현 전
  재확인 권장.
- 인라인 입력 취소 방식(X 아이콘)만 넣었는데, 화면 다른 곳을 탭하는 것으로도
  취소되길 원하는지는 실기기 시안에서 확인.
- 삭제 확인 다이얼로그 문구("이 카테고리로 등록된 즐겨찾기는 모두 '미분류'로
  이동합니다" 등)는 제안 문구 — 최종 워딩은 구현 시 확인.
- `PlacesService.reassignFavoriteCategory` 신규 메서드명은 제안 — 기존
  네이밍 컨벤션(`addFavorite`/`removeFavorite`)에 맞춰 구현 시 조정 가능.
- 라운드10/라운드2(AppBar·상태바·내비바 전역화)가 이 라운드보다 먼저 또는 같은
  배치에서 구현되어야 함(위 4번 항목 전제조건과 동일 — 순서 누락 방지 재확인).

### 상태: 계획 확정, 구현 대기
다음 단계: (다른 라운드들과 함께) 마스터가 배치 구현 시작을 지시하면 flutter-coder
위임(라운드10/2 전역 변경과 함께 처리) → code-auditor PASS → 체크포인트 커밋.

---

## 라운드 15 — 2026-07-30 (프로필 설정 화면)

**참조 이미지**: `loop/layout_fixes/15_myAccount.png` — 실기기 캡쳐 3장. ①
로그아웃 상태(회색 실루엣 아바타, "Google로 로그인" 버튼, 닉네임/인스타그램 빈
입력란, "등록된 바이크가 없습니다"), ② 안드로이드 네이티브 계정 선택 다이얼로그가
뜬 중간 상태, ③ 로그인 후 상태(계정 행에 실제 구글 프로필 사진+이름+이메일+로그아웃
버튼, 닉네임 "limera", 인스타그램 "@david_w_ha", 바이크 1대 등록됨). 상단은 주황
AppBar, 하단 시스템 내비게이션 바는 검정.

### 마스터 피드백 (원문)
1. 여기도 상단 색상과 status bar, navigation bar의 색상을 브랜드 컬러로
2. 프로필 이미지 등록 버튼은 아예 동작하지 않음. 로컬 폴더에서 사진 등록할 수
   있게 해줄 것, 지금은 목업인 듯
3. 구글로 로그인 버튼이 지금 뭔가 구글 로그인이 아닌 것 같음. 다른 구글로 로그인
   하는 모듈 디자인 참조할 것, 흔히 보는 구글로 로그인 버튼이었으면 함
4. 인스타그램 ID 입력란은 앞에 인스타그램 아이콘이 아니라 @ 아이콘이 붙어있는데,
   입력칸에도 @ 이 자동으로 붙어서 @@ 이 되니 신경쓰임. 아이콘을 인스타그램을
   나타내는 것으로 변경 희망
5. 내 바이크 삭제 버튼도 누르자마자 바로 지워짐. 여기도 확인 단계 필요

(※ 이와 별개로 "구글/인스타그램 로그인을 해서 얻는 이점이 하나도 없다"는 활용
방안 논의는 별도 문서 `RECON_account_login_value.md`로 정리 — 이 화면 레이아웃
계획과는 분리해 기록.)

### 확인 질문 및 답변
- Q1(메인 아바타 vs 구글 사진 관계). 코드 확인 결과 상단 큰 아바타와 구글 로그인
  사진은 완전히 분리되어 있음(로그인해도 상단 아바타는 그대로 회색 실루엣) —
  갤러리 등록 기능을 넣을 때 이 관계를 어떻게 할지 →
  **A. 완전 독립.** 로그인 여부와 무관하게 로컬 갤러리에서 고른 사진만 상단
  아바타로 사용, 구글 프로필 사진과는 연동하지 않음.
- Q2(구글 버튼 디자인 확보 방식). 마스터가 참고 캡처를 줄지, 공식 가이드라인대로
  직접 제작할지 →
  **A. 구글 공식 브랜드 가이드라인대로 직접 제작.** 별도 참고 이미지 없이 진행.
- Q3(인스타그램 아이콘 에셋 확보 방식). 프로젝트에 아이콘 폰트 패키지가 없어
  신규 패키지 추가 vs 마스터가 SVG 제공(라운드5 로고 텍스트와 동일 방식) →
  **A. 마스터가 SVG 제공** (라운드5와 동일한 방식).

### 조사 결과 (코드)
파일: `lib/features/profile/presentation/profile_screen.dart`(618줄, 화면
전체·계정 섹션·바이크 카드 전부 한 파일에 있음), `lib/models/user_profile.dart`,
`lib/models/bike_profile.dart`, `lib/services/auth_service.dart`,
`lib/features/auth/providers/auth_providers.dart`

- **AppBar**: L86-89 `AppBar(backgroundColor: AppColors.primary,
  foregroundColor: Colors.white)` — 라운드13(설정 화면)·14(즐겨찾기 카테고리
  화면)와 동일한 로컬 오버라이드 패턴. 라운드10(AppBar 전역 모스그린)·라운드2
  (상태바/내비바 전역 `#F5F1EC`)가 "13/14/15/16 자동 반영" 대상으로 이미 이
  화면을 포함해뒀음 — 이번 라운드는 그 전역 처리를 무력화하는 로컬 오버라이드
  두 줄만 제거하면 됨.
- **아바타 편집 버튼 — 완전 미구현 확인**: L102-122 `Stack`(큰
  `CircleAvatar`(`Icons.person` 고정) + 우하단 작은 연필 아이콘 배지)에
  `GestureDetector`/`InkWell` 등 탭 핸들러가 전혀 없음 — 마스터가 "목업인 듯"이라
  본 게 정확함. `UserProfile` 모델(`user_profile.dart`)에도 사진 경로/URL 필드
  자체가 없음 — 신규 필드 추가부터 필요.
- **구글 로그인은 실제로 동작 중(로그인 자체는 목업 아님)**: `_AccountSection`
  (L392-541)이 `google_sign_in ^7.2.0`(네이티브 계정 선택 다이얼로그, 스크린샷
  ②) + `firebase_auth`로 실제 로그인·로그아웃을 수행 — 문제는 버튼 시각 디자인만.
  `_buildSignedOut()`(L457-484)이 `Icons.g_mobiledata`(Material 내장 아이콘,
  파란 점 하나로 표시되는 자리표시자 성격 아이콘 — 실제 구글 4색 G 로고와 다름) +
  텍스트 Row를 흰 배경 `OutlinedButton` 안에 넣은 형태.
- **인스타그램 이중 `@` 원인**: L139-145 `_LabeledField(prefixIcon:
  Icons.alternate_email, prefixText: '@')` — 아이콘 자체가 이미 "@" 글리프이고
  텍스트필드 내부에도 `prefixText: '@'`가 또 붙어 "@@username"처럼 보임. 저장
  로직(`_save`, L41-43 `replaceFirst('@','')`)과 로딩(`initState`, L26-27)은
  이미 `@` 없이 순수 핸들만 저장/복원하므로 데이터 레이어는 손댈 필요 없음 —
  아이콘 자산만 교체하면 되는 순수 표시 문제.
- **바이크 삭제 — 확인 없음 확인**: `_BikeCard`의 `onDelete` 트리거는
  L270-274 `GestureDetector(onTap: onDelete, child: Icon(Icons.delete_outline))`
  → `ProfileScreen._removeBike`(L65-71)를 확인 절차 없이 바로 호출.
- **로그인 인프라가 이 화면 밖 어디에도 안 쓰임(별도 문서 근거 조사)**:
  `authStateProvider` 사용처는 `profile_screen.dart` 단 한 곳(grep 확인),
  `FirebaseAuth` 참조도 `auth_service.dart` 뿐. `userProfileProvider`(닉네임/
  인스타그램/바이크)·`favoritePlacesProvider`·투어 히스토리(`TourLog`,
  `tour_log.dart`) 전부 `SharedPreferences`/로컬 파일 기반이고 Google 계정 UID와
  전혀 연결되지 않음 — `pubspec.yaml`에 `firebase_core`/`firebase_crashlytics`/
  `firebase_auth`는 있지만 `cloud_firestore`/`firebase_storage`는 없음(백업용
  클라우드 저장소 미도입). 로그인 상태가 앱 동작에 미치는 영향이 정말로 0.

### 확정된 수정 계획

**1. AppBar 로컬 오버라이드 제거 (라운드10/13/14와 동일 패턴)**
- L86-89에서 `backgroundColor: AppColors.primary`, `foregroundColor:
  Colors.white` 삭제, `AppBar(title: const Text('프로필 설정'), actions: [...])`만
  남겨 전역 테마 상속.
- **전제조건**: 라운드10(AppBar 전역 모스그린화)·라운드2(상태바/내비바 전역
  `#F5F1EC`화)가 같은 배치에서 먼저 적용돼야 실제로 색이 바뀜 — 단독 구현 시
  무효(다른 화면들과 동일한 주의사항).

**2. 프로필 사진 갤러리 등록 기능 신규 구현**
- `pubspec.yaml`에 `image_picker` 패키지 추가(현재 미도입, 로컬 갤러리 접근에
  꼭 필요 — 대체 가능한 기존 코드 패턴 없음).
- `UserProfile`(`user_profile.dart`)에 `avatarPath`(String?, nullable) 필드
  추가 — `toJson`/`fromJson`/`copyWith`에 반영.
- 아바타 `Stack`(L102-122) 전체를 `GestureDetector`로 감싸 탭 시
  `ImagePicker().pickImage(source: ImageSource.gallery)` 실행 → 선택한 파일을
  앱 문서 디렉토리(`path_provider`)로 복사해 영구 경로 확보(갤러리 원본이 나중에
  삭제/이동돼도 깨지지 않도록) → `userProfileProvider.notifier.save(current
  .copyWith(avatarPath: 저장된경로))`.
- `CircleAvatar`는 `avatarPath`가 있으면 `backgroundImage: FileImage(File(
  avatarPath))`, 없으면 기존 `Icons.person` 플레이스홀더 유지.
- Q1 확정에 따라 구글 로그인 사진(`user.photoURL`, `_buildSignedIn` L502-510의
  작은 계정 행 아바타)과는 완전히 독립 — 상단 큰 아바타는 로그인 상태와 무관하게
  항상 로컬 `avatarPath` 기준으로만 표시.

**3. 구글 로그인 버튼 — 공식 브랜드 가이드라인 기반 재제작**
- `assets/images/google_g_logo.svg` 신규 에셋 추가(공식 4색 "G" 로고, Google
  Identity 브랜딩 가이드라인 사양 — 흰 배경, 옅은 회색 테두리, 좌측 20×20 로고 +
  텍스트, Roboto Medium 14sp 부근, 버튼 높이 40~48dp). `flutter_svg`가 이미
  의존성에 있어 패키지 추가 불필요.
- `_buildSignedOut()`(L457-484)의 `Icons.g_mobiledata` + 텍스트 Row를
  `SvgPicture.asset('assets/images/google_g_logo.svg', width:20, height:20)` +
  `Text('Google로 로그인')`로 교체. 버튼 컨테이너(`OutlinedButton`, 흰 배경 +
  옅은 회색 테두리)는 이미 공식 스펙에 가까운 스타일이라 큰 변경 불필요.
- 로그인 로직(`_signIn`, `AuthService.signInWithGoogle`) 자체는 이미 정상
  동작 — 이번 라운드는 시각 디자인만 교체, 인증 플로우 변경 없음.

**4. 인스타그램 아이콘 교체 + 이중 `@` 해소**
- L139-145 인스타그램 `_LabeledField`의 `icon: Icons.alternate_email`을
  마스터가 제공할 인스타그램 브랜드 SVG(`assets/images/instagram_icon.svg`,
  라운드5 "Slide to Ride" 벡터 텍스트와 동일한 전달 방식)로 교체. `_LabeledField`
  에 SVG 아이콘을 받을 수 있도록 `icon`(IconData) 파라미터 옆에 `svgIcon`
  (String?, 에셋 경로) 선택적 파라미터를 추가해 `prefixIcon`을
  `svgIcon != null ? SvgPicture.asset(svgIcon) : Icon(icon)`로 분기(다른
  `_LabeledField` 사용처 — 닉네임, 바이크 추가 다이얼로그 4곳 — 는 영향 없음,
  기존 `icon` 그대로 사용).
  `prefixText: '@'`는 그대로 유지 — 아이콘이 이제 인스타그램을 나타내므로
  텍스트필드 안의 `@`는 더 이상 중복이 아니라 유일한 `@` 표시가 됨(마스터가 지적한
  "@@" 현상 해소).
- 저장/로딩 로직(`_save` L41-43, `initState` L26-27)은 이미 `@` 없이 순수
  핸들만 다루므로 변경 불필요.

**5. 바이크 삭제 확인 절차 추가**
- `_BikeCard.onDelete`(L270-274) 트리거 지점에 라운드10/14가 채택한
  `tour_summary_list_screen.dart:65-87` `_confirmDelete` 패턴을 그대로 복제한
  확인 다이얼로그 추가 — `AlertDialog`(제목 "바이크 삭제", 본문 "등록한 바이크
  정보가 삭제됩니다", 취소/삭제 버튼) 확인 후에만 기존 `onDelete` 콜백
  (`ProfileScreen._removeBike`) 호출.
- 버튼 색상은 라운드10 확정 규칙 그대로(취소=브랜드톤, 삭제=`AppColors.error`).

### 미확정 / 구현 시 확인
- 사진 등록을 갤러리 전용으로 우선 구현(마스터가 "로컬 폴더에서"라고 명시) —
  카메라 촬영 옵션 추가 여부는 이번 라운드 범위 밖, 필요해지면 별도 논의.
- 구글 로그인 버튼 SVG는 코드/에셋 제작 시 구글 공식 스펙을 최대한 따르되, 실기기
  확인 후 크기·여백 미세조정 여지 있음.
- 인스타그램 아이콘 SVG는 마스터가 라운드5분과 함께 전달 예정 — 도착 전까지는
  구현 순서상 `Icons.camera_alt_outlined` 등 임시 플레이스홀더로 자리만 잡아두고,
  에셋 도착 후 교체.
- 라운드10/2(AppBar·상태바·내비바 전역화) 구현 순서 의존성 — 다른 화면들과 동일한
  주의사항, 반드시 같은 배치 또는 먼저 적용.

### 상태: 계획 확정, 구현 대기
다음 단계: (다른 라운드들과 함께) 마스터가 배치 구현 시작을 지시하면 flutter-coder
위임(라운드10/2 전역 변경과 함께 처리, `image_picker` 신규 의존성 추가·인스타그램
SVG 에셋 수급 포함) → code-auditor PASS → 체크포인트 커밋.

---

## 라운드 16 — 2026-07-30 (내 바이크 추가 카드)

**참조 이미지**: `loop/layout_fixes/16_myBike.png` — 실기기 캡쳐 3장(로그아웃 상태
빈 바이크 목록, 바이크 1대 등록된 상태, "바이크 추가" 팝업 다이얼로그가 화면
중앙에 떠 있는 상태). 다이얼로그는 브랜드(`Honda, BMW ...`)/모델명(`CB650R,
R1250GS ...`)/배기량(`650`)/연식(`2026`, 달력 아이콘) 4개 입력 필드 + 취소/추가
버튼.

### 마스터 피드백 (원문)
1. 여기도 상단 색상과 status bar, navigation bar의 색상을 브랜드 컬러로
2. 회색 예시(placeholder)로 들어간 브랜드명을 한글로 "혼다, 베스파 ..."로 (BMW
   라이더는 우리 대상 사용자 아님)
3. 모델명 예시도 "슈퍼커브, 프리마베라 ..."로 (이게 우리 앱을 누가 쓰는지
   은연중 드러냄)
4. 배기량 예시도 "125"로
5. 연식은 터치해서 년도 위아래로 스크롤해서 고르는 방식으로 변경
6. 카드 디자인을 팝업이 아니라 아래에서 위로 스윽 올라오는 카드 형태(6번
   경유지 카드와 동일)로 변경
7. (참고) 여기서 등록한 바이크 정보를 어떻게 활용할지는 15번 라운드에서 파생된
   `RECON_account_login_value.md`(구글 로그인 활용방안 문서)에서 함께 다룸 —
   이번 라운드 범위 밖.

### 확인 질문 및 답변
- Q1. 연식 선택 UI — 필드를 탭하면 별도 휠피커가 모달로 뜨는 방식 vs 카드 안에
  처음부터 인라인 휠피커가 보이는 방식?
  → **A. 탭하면 모달 휠피커**(필드엔 선택된 연도 값만 표시, 탭하면 아래에서
  휠피커가 팝업으로 뜨고 고르면 닫힘).
- Q2. 연식 휠피커의 연도 범위?
  → **A. 1970 ~ 내년(2027)**.
- Q3. 브랜드/모델명 입력 방식 — 예시 문구만 한글로 바꾸고 자유 텍스트 입력은
  유지 vs 실제 후보 목록에서 고르는 자동완성/드롭다운으로 전환?
  → **A. 자유 텍스트 유지**(요청 그대로 placeholder 문구만 교체, 입력 로직·
  데이터 모델 변경 없음).
- Q4. 바텀시트 크기 동작 — 6번(경유지 관리) 카드처럼 드래그로 크기 조절 가능한
  `DraggableScrollableSheet` vs 입력 폼 크기에 맞는 고정 높이로 그냥 슬라이드업만
  하는 형태?
  → **A. 고정 높이**(필드 4개 + 버튼 정도의 짧은 폼이라 리사이즈 불필요 — 다만
  "6번 카드와 동일한 형태"라는 마스터 지시는 진입 방식(아래→위 슬라이드,
  showModalBottomSheet + isScrollControlled + transparent 배경 + 둥근 위쪽
  모서리)과 카드 룩앤필을 뜻하는 것으로 확인, 드래그 리사이즈 자체를 의미하는
  것은 아님).

### 조사 결과 (코드)
파일: `lib/features/profile/presentation/profile_screen.dart`,
`lib/models/bike_profile.dart`

- **AppBar/상태바/내비바(피드백 1)**: 이 화면(`profile_screen.dart`)은 이미
  라운드15에서 L86-89 로컬 `AppBar(backgroundColor: AppColors.primary,
  foregroundColor: Colors.white)` 제거가 계획되어 있고, 라운드10(AppBar 전역
  모스그린)·라운드2(상태바/내비바 전역 `#F5F1EC`)가 전역으로 적용됨 —
  **16번 전용 추가 조치 불필요**, 같은 배치에서 라운드15/10/2가 함께 구현되면
  자동 반영됨(단독 구현 시 무효인 것도 다른 화면들과 동일).
- **다이얼로그 위젯**: `_BikeEditDialog`(`StatefulWidget`, L284-387) —
  `AlertDialog` 기반. 진입점은 `ProfileScreen._addBike()`(L53-63)의
  `showDialog<BikeProfile>(context, builder: (_) => const _BikeEditDialog())`
  단 한 곳.
- **브랜드/모델명/배기량 placeholder(피드백 2~4)**: `_LabeledField`
  (L317-337) 3개의 `hint` 값 — 브랜드 `'Honda, BMW ...'`(L320), 모델명
  `'CB650R, R1250GS ...'`(L327), 배기량 `'650'`(L334) — 순수 표시용 문자열
  교체만으로 충분, 저장 로직(`_brandCtrl`/`_modelCtrl`/`_ccCtrl`,
  L292-294)은 자유 텍스트 그대로라 변경 불필요(Q3 확정).
- **연식 필드 현황(피드백 5)**: `_yearCtrl`(L295-296,
  `TextEditingController(text: DateTime.now().year.toString())`)로 초기값이
  이미 현재 연도로 채워진 **텍스트 입력** 필드 — `_LabeledField`(L339-345,
  `keyboardType: TextInputType.number`)로 렌더링. 저장 시
  `int.tryParse(_yearCtrl.text.trim()) ?? DateTime.now().year`(L363-364)로
  파싱 — `BikeProfile.year`는 이미 `int` 타입(`bike_profile.dart:6`)이라
  컨트롤러를 없애고 `int` state 변수로 바꿔도 데이터 모델 변경 불필요.
- **휠피커 관련 기존 코드 없음**: 프로젝트 전체에 `CupertinoPicker`/
  `ListWheelScrollView` 사용처가 전무(grep 확인) — 이번 라운드가 첫 도입.
  다만 `flutter/cupertino.dart`는 Flutter SDK 표준 패키지라 신규 의존성 추가
  없이 바로 사용 가능.
- **바텀시트 전환 참고 패턴**: `main_map_screen.dart:1460-1467`
  `_showWaypointSheet`가 쓰는 `showModalBottomSheet(context, isScrollControlled:
  true, backgroundColor: Colors.transparent, builder: (_) =>
  WaypointManagementSheet())` 패턴을 그대로 재사용 가능 — `_BikeEditDialog`가
  이미 `showDialog<BikeProfile>`로 결과값을 반환하는 구조라 `showModalBottomSheet
  <BikeProfile>`로 바꿔도 `_addBike()`(L53-63)의 `Navigator.pop(context,
  BikeProfile(...))` 반환 처리 로직은 변경 불필요 — 함수 호출부 한 곳만 교체.
- **카드 시각 스타일 참고**: 6번 라운드가 다루는 `WaypointManagementSheet`의
  `_SheetBody`는 흰 배경 + 위쪽 모서리만 둥글게(`BorderRadius.vertical(top:
  Radius.circular(...))`) + 상단 핸들바(작은 회색 바)로 구성 — 이번 라운드도
  동일한 골격(핸들바+헤더+필드+버튼)을 새 `_BikeEditSheet`에 적용.

### 확정된 수정 계획

**1. 브랜드/모델명/배기량 placeholder 교체 (Q3)**
- `_LabeledField` 3곳의 `hint`만 교체: 브랜드 `'Honda, BMW ...'` →
  `'혼다, 베스파 ...'`(L320), 모델명 `'CB650R, R1250GS ...'` →
  `'슈퍼커브, 프리마베라 ...'`(L327), 배기량 `'650'` → `'125'`(L334). 입력
  로직·검증(L365-368 브랜드/모델 빈값 체크)은 변경 없음.

**2. 연식 필드 → 탭-투-오픈 모달 휠피커 (Q1·Q2)**
- `_yearCtrl`(TextEditingController) 제거, `int _selectedYear`(초기값
  `DateTime.now().year`) state로 교체.
- 기존 `_LabeledField`(텍스트 입력) 대신 읽기전용 표시 필드(같은
  `_LabeledField` 룩앤필 유지하되 `TextField` 대신 `AbsorbPointer`+
  `GestureDetector` 또는 별도 소형 위젯 `_YearField`로 "$_selectedYear년"
  텍스트 표시 + 기존 `calendar_today` 아이콘 유지)를 탭하면
  `showModalBottomSheet`로 연도 휠피커 오픈.
- 휠피커 내용: `CupertinoPicker`(`flutter/cupertino.dart`, 신규 패키지 불필요)
  + `itemExtent` 지정, `children`은 1970~2027(Q2 확정 범위) `Text` 리스트,
  `scrollController: FixedExtentScrollController(initialItem: 선택된
  연도-1970)`으로 현재 값에서 시작. 확정 방식(스크롤 멈추면 `onSelectedItemChanged`로
  즉시 `_selectedYear` 갱신 후 확인 버튼으로 닫기, 혹은 스크롤 자체가 곧 확정)은
  구현 시 정함(아래 미확정 항목 참고).
- 저장 시 `BikeProfile(year: _selectedYear, ...)`(기존 L378 `year: year`
  자리)로 바로 연결 — 파싱 로직(`int.tryParse` 등) 제거.

**3. 팝업 다이얼로그 → 바텀업 카드 전환 (Q4)**
- `ProfileScreen._addBike()`(L53-63)의 `showDialog<BikeProfile>(...)`를
  `showModalBottomSheet<BikeProfile>(context, isScrollControlled: true,
  backgroundColor: Colors.transparent, builder: (_) => const
  _BikeEditSheet())`로 교체(`_showWaypointSheet` 패턴 재사용). 반환값 처리
  (`result == null` 체크, L58-62)는 변경 없음.
- `_BikeEditDialog`(`AlertDialog` 래핑, L284-387)를 `_BikeEditSheet`로
  리네임/재구성: 바깥 `AlertDialog` → `Container`(흰 배경, 위쪽 모서리만 둥글게
  `BorderRadius.vertical(top: Radius.circular(20))`, `SafeArea(top:false)`)로
  교체. 내부 구조: 상단 작은 핸들바(장식용, 6번 카드 룩앤필 통일용 — Q4 확정에
  따라 실제 드래그 리사이즈 기능은 없음) → 헤더 "바이크 추가"(제목 텍스트, 필요시
  우측 닫기 `IconButton`) → 필드 4개(기존 `_LabeledField` 3개 + 신규 연식
  필드) → 하단 취소/추가 버튼 `Row`(기존 `TextButton`/`ElevatedButton` 스타일
  그대로 재사용, 폭만 카드 형태에 맞게 조정).
- 필드 검증·`BikeProfile` 생성·`Navigator.pop(context, BikeProfile(...))`
  로직(L362-380)은 그대로 유지, `year` 파싱만 위 2번 계획대로 교체.

**4. 바이크 데이터 활용 방안 — 이번 라운드 범위 밖 (피드백 7)**
- `RECON_account_login_value.md`(라운드15에서 파생된 구글/인스타그램 로그인
  활용방안 문서)에서 바이크 프로필 활용도 함께 논의 — 이번 라운드는 카드
  UI/UX만 다룸, 데이터 활용·연동 로직은 변경하지 않음.

### 미확정 / 구현 시 확인
- 휠피커 선택 확정 UX — 스크롤이 멈추면(`onSelectedItemChanged`) 즉시 반영할지,
  별도 "확인" 버튼을 눌러야 반영할지는 실기기 조작감 확인 후 flutter-coder 재량으로
  결정.
- 바텀시트 헤더에 닫기(X) 버튼을 넣을지, 하단 "취소" 버튼만으로 충분할지는
  실기기 시안에서 확인.
- 핸들바를 순수 장식으로만 넣을지(고정 높이라 실제 리사이즈 기능 없음), 아예
  생략할지는 6번 카드와의 시각적 통일성을 보고 구현 시 결정.
- `_MapCtrlBtn` 등 공용 위젯 추출과 무관한 화면이라 라운드3/6의 공용 위젯화
  작업과는 의존성 없음 — 독립적으로 구현 가능.

### 상태: 계획 확정, 구현 대기
다음 단계: (다른 라운드들과 함께) 마스터가 배치 구현 시작을 지시하면 flutter-coder
위임(라운드15/10/2 전역 변경과 같은 배치에서 처리 권장, 휠피커 UX 세부사항은
flutter-coder 재량) → code-auditor PASS → 체크포인트 커밋.

---

## 라운드 17 — 2026-07-30 (앱 종료 확인 카드)

**참조 이미지**: `loop/layout_fixes/17_exitToast.png` — 좌측 유루나비 실기기 캡쳐(현재
상태, 지도 화면 하단에 스낵바 토스트 "뒤로 한 번 더 누르면 앱이 종료됩니다") + 우측
GS25 편의점 앱 참고 사례(뒤로가기 1회 시 화면 중앙에 딤드 배경과 함께 흰 카드가 뜸 —
"앱을 종료하시겠습니까?" 제목, "뒤로가기 클릭시 앱이 종료됩니다" 부제, 카드 내부에
카카오뱅크 광고 배너, 우측 상단 X 닫기 버튼).

### 마스터 피드백 (원문)
1. 지금은 단순 토스트만 뜨는데, GS25 앱처럼 카드를 띄우고 앱을 종료하겠냐고 물어보는
   방식으로 변경
2. 카드가 떠 있는 상황에서 뒤로 버튼을 한 번 더 누르면 완전 종료 — 종료된다는 사실을
   사용자에게 확실히 각인시키는 효과
3. 마지막 화면(=이 카드)에 광고를 노출할 수 있는 기회
4. 우측 상단 X 버튼 또는 카드 바깥 화면 탭 시 취소
5. 이 방식은 안드로이드 전용. iOS는 마스터가 안 써봐서 모르니 Claude가 좋은 사례를
   조사해서 추천

### 확인 질문 및 답변
- Q1. 카드 모양 — 화면 중앙에 뜨는 GS25식 플로팅 카드(딤드 배경+사방 둥근 모서리, 이미
  `nav_screen.dart`의 "내비게이션 종료" `AlertDialog`가 이 패턴을 씀) vs 앱 전체에서
  반복 사용 중인 하단 슬라이드업 카드(4/5/6/14/16번 라운드와 동일 룩앤필)?
  → **A. 하단 슬라이드업 카드** — GS25 예시와는 다르지만 앱 자체의 일관성을 더 우선.
- Q2. 카드 안 광고 영역을 이번 라운드에서 어디까지 다룰지 — 실제 광고 SDK
  (`google_mobile_ads` 등 신규 의존성 + 광고 계정 연동)까지 붙일지, 레이아웃상 빈
  자리만 확보해둘지?
  → **A. 빈 자리만 확보.** 광고 SDK 연동은 별도 작업으로 분리, 이번 라운드는 신규
  의존성 없이 완결.
- Q3. 카드가 떠 있는 동안 "뒤로가기 재입력 → 종료" 확인이 유효한 범위 — 기존 토스트처럼
  일정 시간(예 2~3초) 안에만 유효한지, 카드가 화면에 떠 있는 한 계속(타이머 없이) 유효한지?
  → **A. 카드가 열려있는 동안 계속 유효** (타이머 없음) — 카드 자체가 곧 "확인 대기
  상태"이므로 별도 시간 제한 불필요.

### iOS 조사 결과 및 추천 (구현 대상 아님, 참고용)
Apple Human Interface Guidelines는 앱에 "종료/Quit" 메뉴나 확인창을 넣는 것을 명시적으로
권장하지 않는다 — iOS에는 하드웨어 뒤로가기 버튼이 애초에 없고(제스처 back은 네비게이션
스택 내 화면 전환용이지 앱 종료가 아님), 사용자는 홈 제스처/앱 스위처로 앱을 벗어나는
것이 표준 동작이다. 실제로 심사를 통과하는 iOS 앱들은 예외 없이 이런 "앱을 종료하시겠습니까"
확인창 자체를 구현하지 않는다(프로그램적으로 앱을 강제 종료시키는 API도 애초에 노출되어
있지 않음).
- **추천: iOS에서는 이 기능을 아예 구현하지 않는다.** `main_map_screen.dart`의 `PopScope`를
  플랫폼 분기해 iOS(`defaultTargetPlatform == TargetPlatform.iOS`, `foundation.dart`에 이미
  있는 상수라 신규 의존성 불필요)에서는 이번 라운드의 카드 로직을 아예 타지 않도록 하고
  (기존 아무 동작 없음 상태 유지 — 어차피 루트 화면이라 시스템이 처리할 상위 라우트도 없음),
  안드로이드에서만 아래 계획을 적용.

### 조사 결과 (코드)
파일: `lib/features/map/presentation/main_map_screen.dart`

- **현재 구현**: `PopScope`(L1601-1618, `canPop: false`) — `onPopInvokedWithResult`에서
  `_lastBackPress`(L163, `DateTime?` 필드) 기준 2초 이내 재입력이면
  `SystemNavigator.pop()`(완전 종료), 아니면 `_lastBackPress` 갱신 + `SnackBar` 토스트
  (`'뒤로 한 번 더 누르면 앱이 종료됩니다'`, L1612-1617) 표시.
- **PopScope와 명시적 `Navigator.pop()`의 차이(핵심 설계 근거)**: `PopScope.canPop`은
  시스템 뒤로가기(하드웨어 버튼/제스처, `Navigator.maybePop()` 경로)만 게이팅하고, 코드에서
  직접 호출하는 `Navigator.pop(context)`(X 버튼 `onPressed`, `showModalBottomSheet`의
  기본 배리어-탭-닫기 내부 호출 포함)는 이 게이트를 우회해 항상 정상 동작한다. 이 특성을
  이용하면 "하드웨어 뒤로가기만 종료로 가로채고, X 버튼·카드 바깥 탭은 그대로 카드만
  닫히게" 하는 것이 표준 `PopScope` 하나로 구현 가능 — 별도 패키지·raw key 이벤트 처리
  불필요. (다만 Flutter 버전별 미묘한 차이가 있을 수 있어 아래 "구현 시 확인"에도 재기재.)
- **참고 가능한 기존 바텀시트 골격**: 라운드16 계획의 `WaypointManagementSheet._SheetBody`
  패턴(흰 배경, 위쪽 모서리만 둥글게, 상단 핸들바) — 이번 카드는 드래그 리사이즈가
  필요 없는 고정 높이 카드라 라운드16의 `_BikeEditSheet`와 같은 계열(핸들바는 장식 여부만
  결정하면 됨).
- **`SystemNavigator` import**: `flutter/services.dart`(L7)에 이미 있어 신규 import 불필요.
- **플랫폼 분기용 상수**: `defaultTargetPlatform`은 `flutter/foundation.dart`(L5, 이미
  `kDebugMode`로 import돼 있음)에 포함 — `dart:io Platform` 신규 import 불필요.

### 확정된 수정 계획

**1. `PopScope` 콜백 교체 — 토스트 제거, 카드 오픈으로 전환**
- `_lastBackPress`(L163) 필드 삭제, 타이머 비교 로직(L1605-1611) 전체 삭제.
- `onPopInvokedWithResult`(L1603-1617)를 안드로이드 분기로 교체:
  ```
  onPopInvokedWithResult: (didPop, _) {
    if (didPop) return;
    if (defaultTargetPlatform != TargetPlatform.android) return; // iOS: 아무 동작 없음
    _showExitConfirmSheet(context);
  },
  ```

**2. 신규 위젯 `_ExitConfirmSheet` + 호출부 `_showExitConfirmSheet`**
- `_showExitConfirmSheet(BuildContext context)`: `showModalBottomSheet(context: context,
  isScrollControlled: false, backgroundColor: Colors.transparent, isDismissible: true,
  builder: (_) => const _ExitConfirmSheet())` — `isDismissible: true`(기본값)가 "카드
  바깥 탭 시 취소"를 그대로 처리해줌.
- `_ExitConfirmSheet`: 최상위를 `PopScope(canPop: false, onPopInvokedWithResult: (didPop, _)
  { if (!didPop) SystemNavigator.pop(); })`로 감싸 — 이 라우트(카드)가 떠 있는 동안의
  시스템 뒤로가기만 골라 완전 종료로 연결(Q3 확정: 타이머 없이 카드가 떠 있는 한 계속
  유효, 이 구조 자체가 이미 그 조건을 만족).
- 카드 내부 레이아웃 (`Container`, 흰/크림 배경 `#FBF1E7` 계열, 위쪽 모서리만
  `BorderRadius.vertical(top: Radius.circular(20))`, `SafeArea(top: false)`):
  - 상단 `Row`: `[Expanded(Text('앱을 종료하시겠습니까?', 크게·굵게)), IconButton(
    Icons.close, onPressed: () => Navigator.of(context).pop())]` — X 버튼은 명시적
    `Navigator.pop()` 호출이라 위 PopScope 게이트를 우회, 카드만 정상적으로 닫힘(취소).
  - 부제 텍스트: 기존 토스트와 동일 문구 유지 `'뒤로 한 번 더 누르면 앱이 종료됩니다'`
    (이미 검증된 문구 재사용, 회색 톤).
  - 광고 플레이스홀더: 고정 높이(예 80~100dp) `Container`(연한 배경 톤 + 얇은 테두리,
    중앙에 작은 안내 텍스트 "광고 영역" 또는 빈 상태) — 실제 광고 SDK는 미연동(Q2 확정),
    추후 실제 배너로 교체하기 쉽도록 자리만 확보.
  - 하단 별도 확인/취소 버튼 없음 — GS25 예시와 동일하게 X/바깥 탭=취소,
    뒤로가기=종료 두 경로만 존재(마스터 원문에 명시적 버튼 언급 없음).

**3. iOS 배제**
- 위 1번의 `defaultTargetPlatform != TargetPlatform.android` 분기로 카드 로직 자체가
  iOS에서 전혀 실행되지 않음 — `PopScope(canPop:false)`는 유지하되 콜백이 조기 리턴,
  즉 iOS에서는 시스템 뒤로가기 제스처가 사실상 아무 효과도 없는 기존 관행(루트 화면이라
  더 갈 곳도 없음)과 동일하게 유지.

### 미확정 / 구현 시 확인
- X 버튼/바깥 탭이 `PopScope(canPop:false)` 게이트를 실제로 우회하는지는 Flutter 버전별
  미묘한 차이가 있을 수 있어 실기기(에뮬레이터 포함) 확인 필수 — 만약 우회되지 않고
  X 버튼까지 종료로 처리되는 문제가 발견되면, X 버튼 핸들러에서 `Navigator.of(context,
  rootNavigator: true).pop()` 등 대안 경로를 flutter-coder가 재량으로 시도.
- 카드 상단 핸들바(장식용) 포함 여부 — 라운드16과 동일하게 구현 시 시안에서 결정.
- 카드 배경을 항상 밝은 톤(크림/흰색) 고정할지, 야간모드/라이더모드에서 다크 배경
  대응이 필요할지 — 라운드5의 `CourseSheet`가 다크모드 무관하게 항상 흰 배경인 선례를
  따라 기본은 고정 밝은 톤으로 제안, 실기기 확인 후 조정.
- 광고 플레이스홀더의 정확한 높이·문구는 실제 광고 SDK 연동 시점(별도 작업)에 맞춰
  조정될 수 있음 — 이번 라운드는 자리 확보 수준.

### 상태: 계획 확정, 구현 대기
다음 단계: (다른 라운드들과 함께) 마스터가 배치 구현 시작을 지시하면 flutter-coder
위임(iOS 분기 포함, X버튼/바깥탭 취소 동작 실기기 검증 포함) → code-auditor PASS →
체크포인트 커밋. 광고 SDK 실연동은 이번 라운드 범위 밖 — 별도 작업으로 추후 논의.
