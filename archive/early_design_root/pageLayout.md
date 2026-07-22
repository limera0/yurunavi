# YuruNavi (유루나비) - App Architecture & UI/UX Blueprint
**Role Context for AI**: Act as a Top-tier Full-Stack Engineer (Flutter + Rust + Firebase) and UI/UX Designer. Generate modular, clean, and highly performant code based on the following specifications.

## 🎨 [Global Design System (ThemeData)]
* File: `// lib/core/theme/app_theme.dart`
* **Typography**: Plus Jakarta Sans (Headline, Body, Label - applying different weights).
* **Color Palette**:
  * Primary: `#F28C28` (Orange - Action buttons, Active routes)
  * Secondary: `#1A2B3C` (Dark Navy - App bars, Primary text, Inverted buttons)
  * Tertiary: `#00B1F0` (Light Blue - Water bodies on map, specific UI highlights)
  * Neutral/Background: `#F9F7F2` (Off-white - Card backgrounds, scaffolds)
* **Components**: Buttons must have 'Primary', 'Inverted', and 'Outlined' states. Form fields use rounded rectangles.

---

## 📱 [Screen Layouts & Business Logic]

### 1. [Intro_Splash_Screen]
* **Path**: `// lib/features/auth/presentation/splash_screen.dart`
* **UI**: 
  * 로고 (`@assets/images/yuru_2line.jpeg`) 중앙 배치.
  * 페이드인 및 크기 확대 애니메이션 (1초 미만).
* **Logic**: 
  * 백그라운드에서 Firebase Auth 로그인 상태 검사.
  * (로그인 O) -> `[Main_Map_Screen]`으로 이동.
  * (로그인 X) -> `[Sign_In_Screen]`으로 이동.

### 2. [Sign_In_Screen]
* **Path**: `// lib/features/auth/presentation/sign_in_screen.dart`
* **UI**:
  * 화면 중앙: 구글, 네이버, 카카오 소셜 로그인 버튼 (Outlined 스타일 디자인 가이드 적용).
  * 최하단: AdMob 배너 (성인/폭력 광고 차단 설정 적용).
* **Logic**: 
  * Firebase Authentication 연동. 글로벌 확장을 고려하여 전략 패턴(Strategy Pattern)으로 인증 로직 구현.

### 3. [Main_Map_Screen_Idle] (사용자 조작 전)
* **Path**: `// lib/features/map/presentation/main_map_screen.dart`
* **UI Structure** (`Stack` Widget 사용):
  * **Layer 1 (Background)**: OSM 기반 지도. 현재 위치 중앙. 반경 50km 축척. 고속도로 숨김 처리, 국도/지방도 강조 커스텀 스타일 적용.
  * **Layer 2 (Map Overlays)**: 
    * 녹색 점 (추천 코스), 주황색 점 (추천 카페). DB에서 GeoJSON 형태로 받아와 클러스터링 렌더링 (성능을 위해 Rust Core에서 처리 후 FFI로 전달).
  * **Layer 3 (UI Controls)**:
    * `Header` (SafeArea 적용): 좌측 로고 / 우측 아이콘 Row (코스등록, 투어요약, 저장코스, 설정).
    * `Right Panel`: 일출/일몰 인디케이터 (시간에 따른 게이지 및 색상 변화 애니메이션 적용).
    * `Floating Buttons (Right Bottom)`: 내 위치 복귀(GPS 강제 활성화), 줌 인/아웃 컨트롤러.
  * **Layer 4 (Bottom)**: 구글 AdMob 배너.

### 4. [Main_Map_Screen_Active] (사용자 터치 조작 시)
* **State Management**: Riverpod (`MapInteractionNotifier`)를 통해 터치 상태, 목적지/경유지 좌표 관리.
* **UI & Interaction**:
  * 터치 이벤트(`GestureDetector`): 터치 지점에 반투명 원(현위치 반경) 및 직선거리(ex: 96km) 텍스트 렌더링.
  * 핀치줌/드래그 동작 시 마커 및 플로팅 버튼의 위치는 유지(Stack의 Positioned 업데이트).
  * **경유지/목적지 플로팅 버튼**: 터치 지점 하단에 표시.
* **Auto-Recommendation Logic** (목적지 지정 시):
  * 설정값에 따라 반경 2km 이내 POI(카페/편의점) 검색 (Google Places API 또는 OSM Overpass API).
  * 최단 거리 필터링 알고리즘 적용.
* **Course Selection Bottom Sheet**:
  * 목적지 확정 시 화면 하단에서 올라옴.
  * 3가지 버튼: `시골길로 느긋하게`, `지방도로 여유롭게`, `국도로 빠르게`.
  * **Core Logic (Rust FFI `// native/src/routing/calculator.rs`)**: 
    * Dijkstra/A* 기반 커스텀 가중치 탐색. (이륜차 통행금지 구역 Weight = 무한대).
  * 스와이프 버튼(`Start your Engine`): 슬라이드 시 `[Navigation_Screen]`으로 전환.

### 5. [Course_Info_Popup] (추천 코스 터치 시)
* **UI (Modal Bottom Sheet / Floating Dialog)**:
  * 코스 이름, 해시태그(특징).
  * 코스 사진: `PageView`로 좌우 스와이프. 탭 시 전체화면 확대(`InteractiveViewer`).
  * 작성자 프로필: 탭 시 사용자 프로필 카드 오버레이 팝업.
  * 인터랙션 아이콘: 하트(좋아요), 북마크(저장), 경유지 추가, 목적지 추가.

### 6. [Navigation_Screen] (주행 모드 - 정북고정 / 진행방향)
* **Path**: `// lib/features/navigation/presentation/nav_screen.dart`
* **UI Structure**:
  * 전체 화면 지도 (내 위치 중앙 하단 배치).
  * 10초 무입력 시 현위치 자동 복귀 로직 (`Timer` 활용).
  * `Top Left Container`: 다음 회전 방향(Turn-by-turn) 아이콘 및 남은 거리.
  * `Left Center Control`: 나침반 아이콘 (탭 시 정북고정 <-> 진행방향 토글. Riverpod 상태 연동).
  * 현재 속도계 (`Geolocator` 패키지 활용).
* **Core Logic (Rust)**: 주행 중 경로 이탈 시(Off-route) 초고속 재탐색 알고리즘 실행.

### 7. [Tour_Summary_Screen]
* **UI**:
  * 상단: 헤더 (날짜, 시작/종료 시간, 총 주행거리, 평균/최고 속도).
  * 중앙: 전체 주행 경로가 한눈에 들어오도록 맵 Bound 자동 조절 (`LatLngBounds` 사용).
    * 경로선: 주황색 Polyline. 시작점/종료점 마커 표시 (동서 방향에 따른 패딩 10% 유지).
  * 우측 상단 Action Icons: 공유(SNS), 삭제, 설정.
* **Share Logic**: `screenshot` 패키지로 맵+데이터 위젯 캡처 후 `share_plus`로 인스타그램/X에 전송.

### 8. [Course_Registration_Screen] (코스 등록 단계)
* **Step 1 (Map Selection)**: 출발지(초록), 경유지(노랑), 목적지(빨강) 지정 후 3가지 경로 중 하나 선택 (Main 화면 로직 재사용).
* **Step 2 (Data Input Floating Panel)**:
  * 폼 컨트롤: 코스 이름, 코스 특징(자동 `#` 삽입 텍스트 필드, 정규식으로 비속어 필터링).
  * 사진 등록: `image_picker` 활용.
* **Serverless Architecture & Media Handling**:
  * **Image Compression**: `flutter_image_compress` 적용 (가로 1080px, WebP, Quality 70%).
  * **Upload Flow**: 
    1. Firebase Functions에서 AWS S3 Presigned URL 발급.
    2. 클라이언트가 S3로 WebP 다이렉트 업로드 (서버 부하 제로).
  * **Validation**: 저장 전 백엔드(Rust 또는 Firebase)에서 기존 코스와 Polyline 비교 (Fréchet distance 등 활용하여 70% 이상 유사 시 중복 차단).

### 9. [Saved_Courses_Screen] & [Settings_Screen]
* **UI**: `ListView.builder`를 활용한 리스트 디자인.
* **Settings Options**:
  * User Profile & 바이크 다중 등록 (List 형태).
  * Slider 위젯: 도로 선호도 조절 바.
  * Dropdown/Radio 버튼: 목적지 자동추천, 내비게이션 뷰, 다크모드, 음성/언어 설정.
  * 지도 다운로드: 지역 선택 후 Rust Core를 통해 `.mbtiles` 또는 OSM 오프라인 데이터 다운로드 및 로컬 캐싱 진행.