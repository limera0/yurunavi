# RECON: 설정 페이지 Phase 2
작성일: 2026-07-06 | 상태: 읽기 전용 정찰 완료 | 기준 브랜치: main (3d5e356)

전제: Phase 1(`RECON_settings_phase1.md`, `REPORT_settings_phase1_impl.md`)에서
`SettingsScreen`(`lib/features/settings/presentation/settings_screen.dart`)이
신설되고 지도 표기 언어(`mapLanguageProvider`)만 연결된 상태. 아래 6개 TODO는
Phase 1 완료 시점부터 그대로 미구현.

---

## 0. TODO 현재 위치 (실측)
`lib/features/settings/presentation/settings_screen.dart:38-47`:
```dart
38            // TODO Phase 2: 도로 선호도
39            // TODO Phase 2: 내비뷰 설정
40            // TODO Phase 2: 안내 음성 / 안내 언어
41
42            const _SectionHeader(title: '앱 설정'),
43            // TODO Phase 2: 다크모드
44            // TODO Phase 2: 지도 다운로드
45
46            const _SectionHeader(title: '기타'),
47            // TODO Phase 2: 약관 / 오픈소스 라이선스
```
`RECON_codebase_inventory.md`(main 루트, B-1) 예측 라인과 100% 일치 — 드리프트 없음.
섹션 구조: `_SectionHeader(title: '주행 설정')`(:37) 아래 1·2·3, `'앱 설정'`(:42) 아래 4·5,
`'기타'`(:46) 아래 6. `SettingsScreen`은 105줄(`ConsumerWidget`), 상태는
`_LanguageSelector`(:54-83, `ConsumerWidget`, `mapLanguageProvider` 구독)만 존재.

---

## 1. 도로 선호도 (road preference)

### 현재 상태: 부분 인프라 — 사용자 노출 없음
- Valhalla `costing_options`가 이미 존재하지만 **코스 3종 프리셋**(시골길/지방도로/국도)
  형태로 하드코딩되어 있고, 사용자가 개별 축(포장 여부·통행료·최단 대 굽이길 등)을
  조정하는 UI/상태는 전혀 없음.
- `lib/services/routing_service.dart:87-89` `_courseNames = ['시골길', '지방도로', '국도']`
- `lib/services/routing_service.dart:166-234` 코스별 `costingOptions` 배열(3개 Map) —
  `class_factors`, `curvature_penalty`, `use_living_streets`, `use_tracks`, `top_speed` 등
  코스마다 다른 값 하드코딩.
- `lib/services/routing_service.dart:97-112` `_ruralBalancedOpts` — 시골길 우회 과다 시
  완화용 대체 costing(폴백), 사용자 조작 아님.
- 이 3코스 선택은 **지도 화면의 코스 선택 카드**(`selectedRouteIdx`,
  `lib/features/map/providers/map_providers.dart`의 `mapInteractionProvider`)로
  이미 연결되어 있음 — `main_map_screen.dart:295,892`, `nav_screen.dart:295,425` 등에서
  `ref.read/watch(mapInteractionProvider).selectedRouteIdx` 사용. **설정 화면과는 무관.**
- `courseLineColor`(`lib/core/theme/app_theme.dart:47-51`)가 코스 인덱스별 색상 매핑.

### 결론
"도로 선호도"를 설정 화면에 넣으려면 (a) 기존 3코스 선택의 기본값을 설정에서
바꾸는 것인지, (b) 코스 선택과 별개로 개별 costing 축(예: 비포장 회피, 통행료 회피)을
새로 노출하는 것인지가 **불명확** — 이번 RECON에서는 기존 3코스 시스템 외
사용자 대면 "선호도" 개념이 코드에 전혀 없다는 사실만 확인. (SPEC §1 참조)

---

## 2. 내비뷰 설정 (nav view settings)

### 현재 상태: 인프라 없음 — 카메라 동작 전부 하드코딩
- `nav_screen.dart:518-522` `_zoomForSpeed(kmh)` — 속도별 줌 선형 보간(고정 커브,
  설정 불가).
- `nav_screen.dart:529-532` `_resolveHeading` — 3km/h 미만 시 마지막 heading 유지(고정 로직).
- `nav_screen.dart:535-579` `_recenter(...)` — heading-up 추종 카메라(북쪽 고정/2D-3D
  전환/수동 줌 잠금 등 옵션 전혀 없음). `bearing: brg`로 항상 진행방향 회전.
- `main_map_screen.dart:930-935`(근방) `initialCameraPosition` 등 홈 화면 카메라도 별도 하드코딩.
- grep 결과 `camera|pitch|follow|northup` 관련 사용자 토글 코드 **0건**.

### 결론
"내비뷰 설정"이 구체적으로 무엇을 의미하는지(북쪽고정 vs 진행방향고정 토글? 주간/야간
지도 스타일 강제? 카드 표시 항목 커스터마이즈? 3D 틸트?) 전혀 정의돼 있지 않음.
이 카메라 로직은 최근 리라이드 검증을 거친(`3ad75fd` "nav-ui-redesign" 병합, 화살표
퍽·카메라 오프셋 관련 커밋 다수) 민감 영역 — 변경 시 실주행 재검증 필요(T3 소지 큼).

---

## 3. 안내 음성 / 안내 언어 (guidance voice / language)

### 현재 상태: 지도 언어와 별개의 하드코딩된 단일 파이프라인
- `nav_screen.dart:414-424` `_initTts()`:
  ```dart
  await _tts!.setLanguage('ko-KR');           // :416 하드코딩
  ...
  _vps = await VoicePackService.load('assets/voice_packs/default_ko.json', _tts!); // :420 하드코딩
  ```
- `assets/voice_packs/` 디렉토리에 **`default_ko.json` 1개뿐** — 영어/일본어 팩 없음.
- `lib/services/voice_pack_service.dart:1-41` — 팩 로드(`load`)와 템플릿 치환(`speak`)만
  담당, 언어 선택 개념 없음. 팩 경로는 호출부(`nav_screen.dart:420`)가 문자열 리터럴로 지정.
- **지도 표기 언어(`MapLanguage`/`mapLanguageProvider`, Phase 1)와는 완전히 별개 시스템.**
  `MapLanguage`는 지도 라벨 텍스트 필드만 바꿈(`lib/features/map/style_language_transform.dart`),
  TTS 언어·음성팩과 연결된 코드 없음.
- 이 TTS 파이프라인은 **바로 오늘 밤 라이딩 검증 대상**인 `feat/tts-audibility-v2`
  (audio focus·ducking·navigation audio usage, `nav_screen.dart:419`
  `setAudioAttributesForNavigation()`, `voice_pack_service.dart` `speak(text, focus: true)`)와
  **동일 파일·동일 메서드**를 건드리게 됨.

### 결론
"안내 음성"(on/off·볼륨?) vs "안내 언어"(한/영/일 TTS?)가 한 TODO 줄에 뭉쳐 있음.
언어 확장은 최소 영어 음성팩 JSON 신규 제작 + `flutter_tts` 언어팩 기기 지원 확인이
선행돼야 함 — 코드 변경만으로 끝나지 않음. **TTS 발화 경로 직접 수정 = T3 확정.**

---

## 4. 다크모드

### 현재 상태: 3-테마 시스템은 이미 있으나 전부 자동 전환, 수동 오버라이드 없음
- `lib/core/theme/app_theme.dart:261,357,415` — `AppTheme.light` / `AppTheme.night` /
  `AppTheme.rider` 3개 `ThemeData` 이미 구현됨.
- `lib/main.dart:27-32`:
  ```dart
  final riderMode = ref.watch(riderModeProvider);
  final isNight = ref.watch(isNightProvider);
  final theme = riderMode ? AppTheme.rider : (isNight ? AppTheme.night : AppTheme.light);
  final isDark = riderMode || isNight;
  ```
  테마 선택은 **`riderModeProvider`(수동 토글, 다크모드 목적 아님) + `isNightProvider`
  (일출일몰 기반 자동, 사용자 개입 불가)** 조합으로만 결정됨.
- `isNightProvider`(`lib/features/map/providers/map_providers.dart:274`) = `!isDayProvider`,
  `isDayProvider`(:267-269)는 `daylightCycleProvider`(일출일몰 계산, `daylight_bar` 모듈 연계)
  기반 — 사용자가 끄고 켜는 스위치 없음.
- `riderModeProvider`(`map_providers.dart:348` 부근, Phase1 RECON E-1에서 이미 인용)는
  이미 `main_map_screen.dart:1060`에서 토글 버튼으로 노출돼 있으나 이름·의도는
  "라이더 모드"(주간 가독성용 하이컨트라스트 추정)이지 "다크모드"가 아님.

### 결론
"다크모드"를 설정에 추가하려면 기존 자동 3테마 시스템과의 관계가 반드시 먼저 정의돼야 함
— 독립적인 4번째 수동 오버라이드(`ThemeMode` 개념)를 넣을지, 기존 `isNightProvider`를
수동 강제할 스위치만 추가할지에 따라 설계가 완전히 달라짐. 정확한 색상 팔레트도
코드에 없음(현재 3테마 각각의 색상 상수만 있고 "다크모드"용 4번째 팔레트는 미정).

---

## 5. 지도 다운로드 (offline map download)

### 현재 상태: 인프라 전무
- `lib/`, `assets/` 전체에서 `mbtiles|offline|tile.?download|OfflineRegion` 관련 코드
  **0건**(grep 결과).
- 타일은 100% 원격 HTTPS(`https://tiles.westinx.com/...`, CLAUDE.md 인프라 절)로만 서빙 —
  클라이언트 측 사전 다운로드/캐싱 경로 없음.
- 인접 인프라: `lib/services/connectivity_service.dart:14` `isOnlineProvider`(연결성 감지만,
  캐싱과 무관), `main_map_screen.dart:905`에서 구독. 이것은 "온라인 여부 배지"용으로
  타일 사전다운로드와는 목적이 다름.
- `maplibre_gl: ^0.26.1`(pubspec.yaml) 자체는 오프라인 타일 패키지(예: sideloaded mbtiles
  로컬 서빙)를 지원하는 하부 라이브러리이나, 그 기능을 사용하는 코드는 없음.

### 결론
"지도 다운로드"는 이번 세션에서 가장 인프라가 없는 항목. UI 스텁(리스트 자리 표시)
정도는 T1이지만, 실제 다운로드 기능은 클라이언트 mbtiles 저장·MapLibre 로컬 소스 전환·
저장 용량 관리 등 **Phase 2 범위를 크게 넘는 별도 기획**이 필요.

---

## 6. 약관 / 오픈소스 라이선스 (terms / OSS licenses)

### 현재 상태: 인프라 없음, 단 Flutter 기본 위젯은 패키지 추가 없이 사용 가능
- `LICENSE` 파일 리포 루트에 없음(`find . -maxdepth 1 -iname "LICENSE*"` 결과 없음).
- `pubspec.yaml`에 라이선스/약관 관련 패키지(`package_info_plus`, oss-licenses 생성기 등)
  없음.
- Flutter SDK 내장 `showLicensePage()`/`LicensePage`(material.dart, 별도 패키지 불필요)는
  빌드 시 pub 패키지들의 라이선스를 자동 수집해 보여주는 표준 위젯 — **오픈소스
  라이선스 표시 자체는 코드 인프라가 이미 SDK에 내장**돼 있어 신규 의존성 없이
  연결만 하면 됨.
- "약관"(이용약관/개인정보처리방침) 쪽은 완전히 다른 문제 — 표시할 실제 법률
  텍스트가 리포 어디에도 없음(신규 작성 필요, 코드 문제 아님).

### 결론
오픈소스 라이선스 항목은 T1(내장 위젯 연결)로 매우 가볍게 처리 가능. 약관 항목은
법률 텍스트 부재로 완전히 별개(코드로 해결 불가, 콘텐츠 필요).

---

## 7. 종합 표

| # | 항목 | 기존 인프라 | 인프라 성숙도 |
|---|---|---|---|
| 1 | 도로 선호도 | costing_options 3-프리셋(코스 선택, 설정과 무관) | 부분(다른 화면 소유) |
| 2 | 내비뷰 설정 | 없음(카메라 전부 하드코딩) | 없음 |
| 3 | 안내 음성/언어 | VoicePackService + 단일 ko 팩, TTS 언어 하드코딩 | 부분(확장 지점만 존재) |
| 4 | 다크모드 | 3-테마 시스템 + 자동전환 provider 2개 | 부분(수동 오버라이드만 부재) |
| 5 | 지도 다운로드 | 없음 | 없음 |
| 6 | 약관/OSS 라이선스 | OSS: SDK 내장 위젯. 약관: 없음 | OSS만 충분, 약관은 없음 |
