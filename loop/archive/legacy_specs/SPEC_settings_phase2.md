# SPEC: 설정 페이지 Phase 2
작성일: 2026-07-06 | 근거: `loop/RECON_settings_phase2.md` | 기준 브랜치: main (3d5e356)

확정 규칙(Phase 1 관례 계승): 이 SPEC은 **구현 아님**. 커밋 단위로 쪼갠 계획만 제시.
분류: **T1/T2**(analyze+test만으로 객관 검증 가능, auto-merge 가능) /
**T3**(실주행 검증 필요, main 머지 전 라이딩 필수) /
**결정 필요**(마스터 확인 전 착수 금지 — 이 SPEC은 임의로 답을 고르지 않음).

---

## 0. 종합: 마스터 결정 필요 목록 (착수 전 필수 확인)

| # | 항목 | 결정해야 할 것 |
|---|---|---|
| D1 | 도로 선호도 | 기존 3코스(시골길/지방도로/국도) 선택과 무슨 관계인가 — (a) 설정에서 "기본 코스"만 지정, (b) 코스와 별개로 개별 costing 축(비포장/통행료 회피 등) 신규 노출, (c) 둘 다. 그리고 (b)라면 정확히 어떤 축을 노출할지 |
| D2 | 내비뷰 설정 | 이름이 가리키는 실제 기능 — 북쪽고정/진행방향고정 토글? 카드 표시 항목? 3D 틸트? 기존 자동 줌/카메라 커브(`_zoomForSpeed`)를 사용자가 바꿀 수 있게 할지 여부 |
| D3 | 안내 음성/언어 | "안내 음성"과 "안내 언어"가 별개 기능인지(음성 on/off·볼륨 vs 한/영/일 TTS 언어 전환). 언어 전환이라면 어떤 언어까지 지원할지(영어만? `supportedLocales`(ko/ja, `main.dart:51-54`)에 맞춰 일본어도?) — 각 언어별 음성팩 신규 제작 필요 |
| D4 | 다크모드 | 기존 자동 3테마(`riderMode`/`isNightProvider`) 시스템과의 관계 — 완전 독립된 수동 오버라이드(`ThemeMode`)를 추가할지, 기존 `isNightProvider`를 수동으로 강제하는 스위치만 추가할지. 후자를 택해도 "다크모드"용 신규 팔레트가 필요한지 아니면 기존 `AppTheme.night`를 재사용할지 |
| D5 | 지도 다운로드 | Phase 2 범위에 포함할지 자체를 재검토 필요 — 인프라 0%(RECON §5). 실제 다운로드 기능은 클라이언트 mbtiles 저장 + MapLibre 로컬 소스 전환 등 별도 기획급. 이번 Phase 2에서는 "준비 중" 자리표시자만 넣을지, 아예 스코프에서 뺄지 |
| D6 | 약관 | 실제 이용약관/개인정보처리방침 법률 텍스트 — 코드로 해결 불가, 콘텐츠(문구) 필요 |

이 SPEC은 위 D1~D6에 대해 **임의로 답을 고르지 않는다.** 아래 각 항목은 결정 이전에도
진행 가능한 "안전한 껍데기"(섹션 자리표시자) 커밋까지만 구체화하고, 결정이 필요한
실제 기능 커밋은 "결정 필요 — 착수 금지"로 명시한다.

---

## 1. 도로 선호도 — SPEC

### 결정 필요 (D1) — 아래는 결정 전 진행 가능한 범위만

| # | 커밋 | 내용 | 파일 | 분류 |
|---|---|---|---|---|
| C1 | `feat(settings): add road preference placeholder tile` | `settings_screen.dart:38` TODO 자리에 비활성(disabled) 또는 "준비 중" 안내용 `ListTile` 1개만 추가. 실제 상태/로직 없음 | `lib/features/settings/presentation/settings_screen.dart` | T1 |

D1 해소 후:
- (a)안(기본 코스 지정)이면 `roadPreferenceProvider`(`AsyncNotifierProvider<int>`,
  `mapLanguageProvider` 패턴 그대로, `SharedPreferences` 키 예: `default_course_idx_v1`)
  신설 → `main_map_screen.dart`의 `mapInteractionProvider` 초기값 주입 지점 확인 필요.
  이 경로는 **기존에 이미 동작하는 3코스 선택 자체를 재사용**하므로 라이브 TTS/카메라를
  건드리지 않음 → **T2**(analyze + 위젯 테스트로 검증 가능, 실주행 없이도 Valhalla curl
  응답으로 라우팅 변화 확인 가능, CLAUDE.md "로컬 개발/curl 계측").
- (b)안(신규 costing 축 노출)이면 `routing_service.dart`의 `costingOptions`(:166-234) 구조
  변경 필요 — 코스 3종 자체의 지오메트리 산출 로직을 건드리므로 **최소 T2, 실사용성
  검증까지 하려면 T3**(굽이길/비포장 선호가 실제로 체감되는지는 승차 필요).
  → D1이 (b)로 결정되기 전까지 이 갈래는 착수 금지.

---

## 2. 내비뷰 설정 — SPEC

### 결정 필요 (D2) — 아래는 결정 전 진행 가능한 범위만

| # | 커밋 | 내용 | 파일 | 분류 |
|---|---|---|---|---|
| C1 | `feat(settings): add nav view placeholder tile` | `settings_screen.dart:39` TODO 자리에 비활성/"준비 중" `ListTile` 1개만 추가 | `lib/features/settings/presentation/settings_screen.dart` | T1 |

D2 해소 후, 어떤 옵션이든 실제 구현은 `nav_screen.dart:518-579`(`_zoomForSpeed`,
`_resolveHeading`, `_recenter`)를 직접 수정하게 되며, 이 구간은 최근 카메라 리디자인
(`3ad75fd` 병합) 검증이 끝난 민감 영역 — **분류는 D2 답과 무관하게 T3 확정**
(라이딩 중 카메라 동작 변경은 실주행 없이 "작동한다"고 판단할 수 없음, `SPEC_guidance_p1.md`
"analyze 성공 ≠ 작동" 원칙과 동일). D2가 해소되기 전까지 이 갈래는 착수 금지.

---

## 3. 안내 음성 / 안내 언어 — SPEC

### 결정 필요 (D3) — 아래는 결정 전 진행 가능한 범위만

| # | 커밋 | 내용 | 파일 | 분류 |
|---|---|---|---|---|
| C1 | `feat(settings): add guidance voice placeholder tile` | `settings_screen.dart:40` TODO 자리에 비활성/"준비 중" `ListTile` 1개만 추가. 볼륨 슬라이더 등 실제 TTS 파라미터 연결 없음 | `lib/features/settings/presentation/settings_screen.dart` | T1 |

D3가 "음성 on/off·볼륨"으로 해소되면: `_tts!.setVolume(1.0)`(`nav_screen.dart:418`)을
provider 값으로 교체하는 정도의 작은 변경이라도 **TTS 발화 경로 직접 수정 = T3**
(RECON §3, `feat/tts-audibility-v2`와 동일 파일·메서드).

D3가 "안내 언어 전환(한/영/일)"으로 해소되면: 최소 언어별 음성팩 JSON 신규 제작
(`assets/voice_packs/default_en.json` 등, 콘텐츠 작업 — 번역 필요) +
`nav_screen.dart:416` `setLanguage('ko-KR')` 하드코딩 제거 + 기기별 TTS 언어팩 설치 여부
확인 로직이 필요. **코드 변경 자체도 T3**(RECON §3와 동일 이유)이며, 사전 조건으로
번역 콘텐츠(결정 필요 이상의 별도 작업)가 선행돼야 함. 두 경우 모두 D3 해소 전까지
착수 금지.

---

## 4. 다크모드 — SPEC

### 결정 필요 (D4) — 아래는 결정 전 진행 가능한 범위만

| # | 커밋 | 내용 | 파일 | 분류 |
|---|---|---|---|---|
| C1 | `feat(settings): add dark mode placeholder tile` | `settings_screen.dart:43` TODO 자리에 비활성/"준비 중" `ListTile` 1개만 추가 | `lib/features/settings/presentation/settings_screen.dart` | T1 |

D4가 "기존 `isNightProvider`를 수동으로 강제하는 스위치 추가, 신규 팔레트 없이
`AppTheme.night` 재사용"으로 해소되면(가장 인프라 재사용도가 높은 옵션 — 참고용으로만
제시, **최종 선택은 마스터 결정**):
- `darkModeOverrideProvider`(`AsyncNotifierProvider<bool?>`, `null`=자동/기존 동작 유지,
  `true`/`false`=수동 강제) 신설, `LanguageService`와 동일한 `SharedPreferences` 패턴
  (`lib/services/`에 신규 서비스 또는 `settings_providers.dart`에 추가) — **T1**
  (순수 상태/영속화, UI·테마 미연결 상태라 단독 컴파일 확인 가능).
- `main.dart:27-32`의 `isNight` 계산에 오버라이드 값을 반영
  (`final isNight = override ?? !ref.watch(isDayProvider);` 형태) — 테마 전환 자체는
  화면 렌더링만 바꾸고 GPS/TTS/라우팅에 영향 없음 → **T2**(analyze + 위젯 테스트로
  라이트/나이트 렌더 분기 검증 가능, 실주행 불필요). 단, "라이더 모드"와의 상호작용
  우선순위(`riderMode ? rider : (isNight ? night : light)`, `main.dart:29-31`)가
  달라지므로 위젯 테스트로 3가지 조합(라이더 on/오버라이드 dark/오버라이드 light) 회귀
  확인 필요.

D4가 "완전 독립 4번째 테마 팔레트 신설"로 해소되면 정확한 색상 값은 **이 SPEC이
정하지 않음** — 신규 palette 자체가 결정 필요 항목(색상 선택은 제품 결정).

---

## 5. 지도 다운로드 — SPEC

### 결정 필요 (D5)

| # | 커밋 | 내용 | 파일 | 분류 |
|---|---|---|---|---|
| C1 | `feat(settings): add offline map placeholder tile` | `settings_screen.dart:44` TODO 자리에 비활성/"준비 중" `ListTile` 1개만 추가 | `lib/features/settings/presentation/settings_screen.dart` | T1 |

C1을 넘는 어떤 단계도 D5(스코프 포함 여부 자체) 결정 없이는 무의미 — RECON §5에서
확인했듯 클라이언트 mbtiles 저장·MapLibre 로컬 소스 전환 등은 이번 6-항목 Phase 2
범위를 넘는 별도 기획 규모. **D5가 "이번 Phase 2에서는 자리표시자만"으로 해소되면
C1에서 종료.** "실제 다운로드 기능까지 포함"으로 해소되면 이 SPEC과 별도로 새
RECON/SPEC이 필요(현재 문서 범위 밖).

---

## 6. 약관 / 오픈소스 라이선스 — SPEC

두 하위 항목은 인프라 성숙도가 완전히 달라 분리한다.

### 6-A. 오픈소스 라이선스 — 결정 불필요, 바로 스펙 가능

Flutter SDK 내장 `showLicensePage()`가 신규 패키지 없이 사용 가능(RECON §6).

| # | 커밋 | 내용 | 파일 | 분류 |
|---|---|---|---|---|
| C1 | `feat(settings): add OSS license entry` | `settings_screen.dart:47` TODO 자리에 `ListTile(title: Text('오픈소스 라이선스'), onTap: () => showLicensePage(context: context, applicationName: 'YuruNavi'))` 추가. `applicationVersion`은 `pubspec.yaml`의 `version: 1.0.1+2`를 하드코딩하거나 `package_info_plus` 도입 여부는 선택(선택 사항이지 결정 필요 항목 아님 — 생략해도 `showLicensePage`는 동작) | `lib/features/settings/presentation/settings_screen.dart` | T1 |

검증: `flutter analyze` + 위젯 테스트(탭 → `LicensePage` push 확인, `showAboutDialog`류와
동일 패턴이라 `flutter_test`의 `pumpAndSettle` + `find.byType(LicensePage)`로 충분).
GPS/TTS/라우팅 무관 → 실주행 불필요.

### 6-B. 약관 — 결정 필요 (D6), 코드 문제 아님

| # | 커밋 | 내용 | 파일 | 분류 |
|---|---|---|---|---|
| C1 | `feat(settings): add terms placeholder tile` | 위 C1과 같은 `ListTile`에 "약관" 추가하되 `onTap`은 "준비 중" 안내(`SnackBar` 등)만 — 실제 문서 없음 | `lib/features/settings/presentation/settings_screen.dart` | T1 |

실제 약관 화면(텍스트 표시)은 D6(법률 텍스트 콘텐츠) 없이는 착수 불가.

---

## 7. 이번 Phase 2에서 즉시 진행 가능한 것 (요약)

결정(D1~D6) 없이도 지금 시작할 수 있는 것은 다음 7개 커밋뿐이며, 전부 T1
(analyze + `flutter test`만으로 검증, 실주행 불필요, 기존 코드 동작 변경 없음 —
순수 신규 UI 자리표시자 추가):

1. 도로 선호도 자리표시자 (§1 C1)
2. 내비뷰 설정 자리표시자 (§2 C1)
3. 안내 음성/언어 자리표시자 (§3 C1)
4. 다크모드 자리표시자 (§4 C1)
5. 지도 다운로드 자리표시자 (§5 C1)
6. 오픈소스 라이선스 — **완전 기능**(§6-A C1)
7. 약관 자리표시자 (§6-B C1)

나머지 실제 기능 구현은 전부 D1~D6 마스터 결정 이후, 그리고 §2/§3의 카메라·TTS
관련 갈래는 결정과 무관하게 **T3(실주행 검증 필수)**로 이미 확정돼 있다.
