# YuruNavi 코드 부검 리포트 (AUDIT_REPORT)

> 작성일: 2026-05-31
> 성격: **읽기 전용 부검**. 이 리포트를 만드는 동안 앱 코드는 한 줄도 수정/삭제/커밋하지 않았습니다. (이 리포트 파일만 새로 작성)
> 검증 방법: 핵심 파일을 전부 직접 열어 읽었고, `flutter analyze`(코드 검사기)를 1회 실행했습니다. 단, 실제 기기/에뮬레이터에서 **앱을 띄워 본 런타임 테스트는 하지 않았습니다.** 코드만으로 판단한 부분은 **[추정]** 으로 표시합니다.
> 대상: `/home/limera/development/yurunavi` — Flutter + OpenStreetMap + Rust 기반 이륜차(오토바이) 감성 내비 앱

---

## 0. 한 줄 결론 (먼저 보세요)

**겉보기보다 코드 상태가 훨씬 양호합니다. 새로 만들지 말고 고쳐 쓰는 쪽을 권합니다.**

직접 검사한 결과:
- ✅ **코드가 깨끗하게 통과합니다.** `flutter analyze` 결과 *"No issues found!"* (오류·경고 0개). → "빌드가 안 된다"는 **코드 문제가 아닙니다.**
- ✅ **지도와 경로 기능이 실제로 구현돼 있습니다.** 지도 화면은 정상적인 지도 타일(Carto Voyager)을 쓰고, **진짜 도로에 붙는 경로(OSRM)** 를 받아 화면에 선으로 그립니다.
- ⚠️ 그렇다면 왜 "안 나온다"고 느꼈을까? 저장소에 남은 빌드 로그(`build_errors.md`)를 보면, 개발하던 **윈도우 PC가 빌드 부품을 인터넷에서 못 받아(네트워크/보안 오류) 안드로이드 빌드가 실패**했습니다. 즉 **작동하는 APK를 한 번도 못 만들어 본 환경 문제**일 가능성이 큽니다 [추정]. 또한 안드로이드 **위치 권한 설정이 빠져** "내 위치"가 동작하지 않습니다.
- ⚠️ 진짜 미완성은 따로 있습니다: 이 앱의 정체성인 **"굽잇길(winding) 감성 경로" 차별화가 사실상 미구현**입니다. 3개 코스 카드(시골길/지방도로/국도)는 실제 도로 종류를 구분하지 않고 OSRM이 주는 대안 경로를 그냥 번호순으로 고를 뿐이며, 카드에 표시되는 **거리·시간 숫자는 고정 배수로 만든 가짜 값**입니다. 이를 위해 만들어 둔 **Rust 엔진은 앱에 연결되지 않은 채 방치**돼 있습니다.

→ 최종 판정: **(가) 대부분 재활용 가능 — 고쳐 쓰자** (구조 정리 + 핵심 기능 마무리 필요). 자세한 내용 5번.

---

## 1. 기술 스택 분석 (`pubspec.yaml` 직접 확인)

| 역할 | 패키지 | 버전 | 상태 | 메모 |
|---|---|---|---|---|
| 지도 표시 | `flutter_map` | ^8.2.2 | ✅ 현역·최신 | OSM 표준. 좋은 선택 |
| 좌표 | `latlong2` | ^0.9.1 | ✅ | |
| 상태관리 | `flutter_riverpod` | ^3.3.1 | ✅ 현역(매우 최신 v3) | 코드 품질 양호(아래) |
| 상태관리(자동생성 표식) | `riverpod_annotation` | ^4.0.2 | ⚠️ 사실상 미사용 | "주의 1" |
| 위치(GPS) | `geolocator` | ^14.0.2 | ✅ 최신 | |
| 시작 슬라이더 | `slider_button` | ^3.1.0 | ✅ | "밀어서 출발" UI |
| 진동 | `vibration` | ^3.1.8 | ✅ | 턴 알림 |
| 설정 저장 | `shared_preferences` | ^2.5.3 | ✅ | |
| 다국어/숫자 | `intl` | ^0.20.2 | ✅ | |
| 일출·일몰 | `sunrise_sunset_calc` | ^3.0.0 | ✅ | 일조시간 게이지 |
| Rust 연동 | `flutter_rust_bridge` | ^2.12.0 | ✅ 최신 | "주의 2" |
| 네트워크 | `http` | ^1.2.2 | ✅ | OSM/경로 서버 호출 |
| 폰트 | `google_fonts` | ^6.2.1 | ✅ | |
| 파일경로 | `path_provider` | ^2.1.5 | ✅ | 타일 캐시 위치 |
| 연결상태 | `connectivity_plus` | ^6.1.4 | ✅ | 오프라인 감지 |

**핵심: 버려진(deprecated) 패키지는 하나도 없습니다.** 부품 목록은 그대로 재활용 가능합니다. (참고: `flutter pub`은 "30개 패키지에 더 최신 버전 있음"이라 알리지만, 모두 정상 동작하는 최신 계열입니다.)

**주의 1 — 자동생성 도구가 반쪽.** `riverpod_annotation`(자동 코드 생성 "표식")은 들어 있는데, 코드를 찍어내는 도구(`build_runner`/`riverpod_generator`)가 `dev_dependencies`에 **없습니다.** 실제 코드(`map_providers.dart`)는 자동생성을 안 쓰고 **손으로 작성**돼 있고, 그래도 검사를 통과합니다. → 표식만 남고 자동생성은 포기한 상태 [추정]. 무해하지만 정리 대상.

**주의 2 — Rust 다리를 켜지 않음 (확인됨).**
- Rust 소스는 실재합니다(`native/src/api.rs`, `native/src/lib.rs`, `native/Cargo.toml`, git에 "테스트 15개 통과" 커밋).
- 그러나 ① 시작점 `lib/main.dart`에서 **`RustLib.init()` 미호출**, ② 통역 파일 `lib/src/rust/frb_generated.dart`이 **생성돼 있지 않음**(직접 확인: MISSING), ③ `native_engine.dart`에 본인들이 *"ROOT CAUSE: Rust 엔진이 아직 연결 안 됨, codegen 돌리기 전까지 Dart 임시 대체물 사용"* 이라 적어 둠.
- → **Rust 엔진은 완성됐지만 앱에 연결되지 않았습니다.** (단, 아래 2·4절에서 보듯 현재 지도 화면은 Rust도 그 Dart 대체물도 안 쓰고, 별도의 OSRM 경로를 씁니다.)

---

## 2. "지도/경로가 제대로 안 나오는" 원인 분석

> 결론 먼저: **코드 자체는 건강합니다.** "안 나온다"의 원인은 코드 버그보다 **빌드 환경 + 권한 설정 + 미완성 마무리** 쪽입니다.

### ✅ (확인) 코드는 검사 통과 — `flutter analyze` "No issues found!"
오류·경고 0개. 즉 현재 Dart 코드는 컴파일이 막히는 문제가 없습니다. 저장소의 `build_errors.md`에 있던 `map_providers.dart` 타입 오류는 **이미 수정**돼 있습니다(현재 코드 직접 확인 + git `fix: resolve type mismatch in map_providers` 커밋 일치). → 그 로그는 **지난 상태의 기록**입니다.

### ✅ (확인) 지도 위젯은 정상 구성 — 타일이 안 나올 코드적 이유가 안 보임
`main_map_screen.dart`의 지도 부분(직접 확인):
- 지도 타일: `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png` (Carto Voyager — 무료·표준 내비용 지도, 햇빛 가독성 좋은 밝은 스타일). subdomains a~d, maxZoom 19, **캐시 타일 제공자** 사용.
- 안드로이드 인터넷 권한도 **있음**(매니페스트 확인).
- → 인터넷만 연결되면 타일이 정상 표시돼야 합니다 [추정: 런타임 미검증].

### ⚠️ (확인) 가장 유력한 "안 나온" 진짜 이유: 안드로이드 빌드 실패(환경)
`build_errors.md`(직접 확인)의 실제 실패는 **Gradle(안드로이드 빌드 도구)이 인터넷에서 빌드 부품을 못 받은 것**입니다:
> *"Could not resolve com.google.errorprone:error_prone_annotations:2.27.0 … (bad_record_mac) Received fatal alert: bad_record_mac"* (빌드 PC 경로: `C:\Users\David HA\…`)
- 이는 코드가 아니라 **그 PC의 네트워크/보안(TLS) 연결 문제**입니다. → **작동하는 APK를 아예 못 만들었을** 가능성이 큽니다. 안정적인 네트워크에서 다시 빌드하면 사라질 수 있습니다.

### ⚠️ (확인) 위치 권한 누락 → "내 위치" 실패
- 위치 요청 **코드는 있습니다**(`main_map_screen.dart` 116~142줄: 권한 확인·요청·위치 스트림 구독).
- 그러나 안드로이드 매니페스트에 **위치 권한(`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`) 선언이 없습니다.** → 안드로이드에서 권한이 항상 거부돼 내 위치 추적이 동작하지 않습니다. (iOS `Info.plist`는 [미확인])

**결론(2번):** 지도/경로 코드는 정상입니다. 사용자가 겪은 "안 나옴"은 ① 빌드 PC 네트워크 문제로 APK 자체가 안 나왔거나, ② 위치 권한 누락, ③ (아래) 미완성 기능 때문일 가능성이 큽니다.

---

## 3. 구조 평가 (모듈 분리 / 거대 파일)

### 좋은 점
- 상태관리(`lib/features/map/providers/map_providers.dart`, 251줄)와 서비스 계층(`routing_service`, `poi_service`, `daylight_service`, `connectivity_service`)이 **깔끔하게 분리**돼 있고 품질이 양호합니다.
- 지도 화면은 줌 단계별 표시(고속에선 경로만, 저속에서 POI 군집), 라이더 모드(고대비) 색상, 오프라인 배너, 목적지 근처 카페/편의점 스냅 등 **완성도 있는 UI 로직**을 갖췄습니다.

### 나쁜 점 ①: 옛/새 폴더 구조가 섞여 있음 (확인)
```
[옛 방식 — 평면]                      [새 방식 — 기능/계층]
lib/screens/   (화면 5개)            lib/features/map · navigation · auth/...
lib/services/  (서비스 8개)          lib/core/theme · widgets/...
lib/models/ · lib/widgets/ · lib/providers/
```
같은 이름 파일이 양쪽에 중복되고 한쪽은 빈 껍데기입니다 (확인):

| 파일 | 옛 위치 | 새 위치 |
|---|---|---|
| `main_map_screen.dart` | `lib/screens/` — **3줄(껍데기)** | `lib/features/map/presentation/` — **1,523줄(실물)** |
| `daylight_bar.dart` | `lib/widgets/` — **2줄(껍데기)** | `lib/core/widgets/` — **160줄(실물)** |
| `slider_start_button.dart` | `lib/widgets/` — **2줄(껍데기)** | `lib/core/widgets/` — **59줄(실물)** |
| `app_providers.dart` | `lib/providers/` — **3줄(껍데기)** | — |

### 나쁜 점 ②: 거대 파일 1개 (확인)
`main_map_screen.dart` = **1,523줄.** 다만 "한 화면 + 그 화면이 쓰는 작은 위젯들"을 한 파일에 모은 형태라, 뒤죽박죽 스파게티는 아닙니다. 그래도 너무 크니 위젯별로 파일을 쪼개는 게 좋습니다. (그 외 driving_screen 615, app_theme 554, nav_screen 506줄 등. 전체 ~6,290줄)

- 사소한 흔적: `main_map_screen.dart` 20줄에 자기 자신을 다시 내보내는 `export 'main_map_screen.dart';` 라는 무의미한 줄이 있음(잔재) [추정].

---

## 4. 위험 신호 (미완성 / 껍데기 / 비밀값)

### 🥚 4-1. (확인) 핵심 차별점 "감성/굽잇길 경로"가 사실상 미구현 — 가장 중요한 미완성
이 앱의 정체성은 "시골길/지방도로/국도" 감성 경로 추천인데, 실제 동작을 뜯어보면:
- 3개 코스 카드를 누르면 모두 **같은 OSRM 호출**(`RoutingService.fetchRoutes`)을 하고, OSRM이 돌려준 대안 경로를 **번호순(0·1·2)으로 그냥 고릅니다.** 즉 "시골길 vs 국도"라는 도로 종류 구분이 실제로는 없습니다 (`main_map_screen.dart` 295~314줄).
- 카드에 보이는 **거리·시간은 가짜**입니다. 직선거리에 고정 배수(1.55 / 1.22 / 1.0)와 고정 평균속도(38 / 52 / 68km/h)를 곱해 만든 값으로(1206~1209줄), 화면에 그려지는 실제 경로 길이와 따로 놉니다.
- 이걸 제대로 하려고 만든 **Rust 엔진(굽잇길 점수 계산)과 Dart 임시 엔진(`native_engine.dart`)은 정작 지도 화면에서 호출되지 않습니다**(import 목록에 없음). → 만들어 두고 안 쓰는 **죽은 코드**.

### 🥚 4-2. (확인) 더미/데모 코드
- `native_engine.dart`의 `calcDummyRoute` = sin 곡선으로 만든 가짜 경로 생성기. 현재 지도 화면에서는 **미사용**(다른 화면에서 쓰는지는 [추정] — 활성 흐름에선 안 보임).
- `route_options_screen.dart`의 `_registerDummyCourse` = "가짜 코스 등록".
- 헤더 버튼 일부가 빈 동작: `onCourseRegister: () {}`, `onSettings: () {}` 등(604~607줄) → 버튼은 있는데 기능 미연결.
- 하단 "Ads" 광고 배너가 자리표시자 상태(1384~1404줄).

### 🔧 4-3. (확인) 미연결/잔재
- Rust 다리 미생성 + `RustLib.init()` 미호출(1절 주의 2).
- 자동생성 표식만 있고 도구 없음(1절 주의 1).
- 옛/새 구조 중복·껍데기 파일(3절).

### 🔑 4-4. (확인) 하드코딩된 비밀값(API 키) — 발견되지 않음
- `lib/` 전체를 `mapbox`/`pk.`/`sk.`/`api_key`/`access_token`/`Bearer` 패턴으로 검색 → **해당 없음.** 지도(Carto)·경로(OSRM) 모두 키가 필요 없는 공개 엔드포인트를 씁니다. (보안상 양호)
- ⚠️ 다만 **공개 서버 의존**이 위험: OSRM **공개 데모 서버**(`router.project-osrm.org`)와 Carto 무료 타일은 학습/시험용이라 **실서비스엔 부적합**(속도 제한·중단 가능). 출시 전 자체/유료 서버로 교체 필요.

### 🗑️ 4-5. 저장소 정리
- 루트에 `build_errors.md`(지난 로그), `CLAUDE.md.dup`(중복), `build/`·`native/target/` 산출물 등 잔재.

---

## 5. 최종 판정

### ➡️ 판정: **(가) 대부분 재활용 가능 — 고쳐 쓰자**

근거:
- **코드가 검사를 깨끗이 통과**하고(`flutter analyze` 무오류), 지도·경로·POI·일조시간·라이더모드 등 **실제 동작 코드가 대부분 갖춰져 있습니다.**
- "안 나온다"의 주원인은 **빌드 PC의 네트워크 문제(환경)** 와 **위치 권한 누락(설정)** 으로 보이며, 둘 다 코드 재작성과 무관하게 고칠 수 있습니다.
- 남은 핵심 미완성("감성 경로 차별화")도 **이미 만들어 둔 Rust 엔진을 연결**하면 되는 일이지, 처음부터 새로 짤 일이 아닙니다.
- 전면 재작성을 하면 위의 멀쩡한 UI·서비스·테마·Rust 자산을 버리게 되어 **손해**입니다.

> (나) "일부만 재활용"이 아니라 (가)로 본 이유: 버려야 할 코드(죽은 더미·중복 껍데기)는 전체에서 일부일 뿐이고, 살릴 코드가 압도적으로 많습니다.

### ✅ 그대로 살릴 부분 (대부분 직접 확인)
| 항목 | 이유 |
|---|---|
| `pubspec.yaml` 부품 목록 | 전부 현역·적절 |
| `lib/features/map/presentation/main_map_screen.dart` | 지도·OSRM 경로·POI·줌단계·라이더모드 — 핵심 화면이 작동 수준 (파일만 분할 권장) |
| `lib/services/` (routing/poi/daylight/connectivity) | 동작하는 외부 연동 |
| `lib/features/map/providers/map_providers.dart` | 깔끔한 상태관리 |
| `lib/core/theme/app_theme.dart` + 라이더(고대비) 모드 | 이 앱의 차별점 |
| `lib/core/widgets/` 공용 위젯 | 완성도 양호 |
| `native/` Rust 엔진(테스트 통과) | 연결만 하면 되는 핵심 자산 |

### 🔧 해야 할 일 (우선순위 순)
1. **안드로이드 빌드 정상화** — 안정적 네트워크에서 재빌드(Gradle 부품 다운로드 문제 해결). → 우선 "작동하는 APK"부터 확보.
2. **위치 권한 추가** — 매니페스트에 `ACCESS_FINE/COARSE_LOCATION` 선언(iOS도 점검).
3. **감성 경로 마무리(핵심 가치)** — `flutter_rust_bridge_codegen generate`로 Rust 다리 생성 → 3개 코스 카드를 실제 도로 종류/굽잇길 점수에 연결, 카드의 가짜 거리·시간을 **실제 경로 값**으로 교체.
4. **죽은 코드/중복 정리** — 미사용 `calcDummyRoute`·`_registerDummyCourse`, 옛/새 구조 중복·껍데기 파일 삭제, 빈 버튼(`() {}`) 연결.
5. **거대 파일 분할** — `main_map_screen.dart`를 위젯별로 분리.
6. **출시 전 서버 교체** — OSRM 공개 데모 → 자체/유료 라우팅 서버.
7. **정리** — `build_errors.md`·`CLAUDE.md.dup`·빌드 산출물 정리.

### 💬 비개발자용 비유
> 이 앱은 "무너진 집"이 아니라 **"전기·수도·골조까지 멀쩡히 들어왔는데, 두꺼비집 올리는 날 정전(빌드 PC 네트워크)이라 한 번도 불을 못 켜본 집"** 에 가깝습니다. 게다가 거실의 메인 가구(굽잇길 경로 엔진)는 **진짜 가구가 창고에 들어와 있는데 아직 거실에 들여놓지 않은** 상태입니다. → 헐고 새로 짓지 말고, **전기부터 한 번 켜 보고(빌드+권한), 창고 가구를 들여놓는(Rust 연결) 편**이 훨씬 빠릅니다.

---

## 부록: 직접 확인한 근거
- `flutter analyze` → **No issues found!** (오류·경고 0)
- `pubspec.yaml` / `lib/main.dart` / `map_providers.dart`(251줄, 깨끗) 전문
- `main_map_screen.dart`(1,523줄) 전문 — Carto 타일, OSRM 경로 호출(295줄), 가짜 카드 거리·시간(1206~1209줄), 빈 버튼, 위치권한 코드(116~142줄)
- `native_engine.dart`(386줄) — "Rust NOT wired up" 원문 + 미사용 `calcDummyRoute`
- `routing_service.dart`(59줄) — 동작하는 OSRM 클라이언트(키 불필요)
- 안드로이드 매니페스트 3종 — INTERNET 있음 / 위치 권한 없음
- `lib/src/rust/frb_generated.dart` → **MISSING**(Rust 다리 미생성)
- 키 전수 검색(mapbox/pk./sk./api_key 등) → 해당 없음
- 전체 파일 목록·줄 수(30개 dart, ~6,290줄), `build_errors.md`(지난 Gradle 네트워크 실패 로그), git 로그

> 미검증: 실제 기기/에뮬레이터 런타임(앱을 띄워 지도가 실제로 그려지는지)과 iOS `Info.plist` 권한은 이번에 확인하지 않았습니다. 위 판정은 "코드 검사 통과 + 코드 직접 확인"에 근거하며, 런타임 확인이 필요하면 다음 단계로 진행할 수 있습니다.
