# 유루나비 릴리스 준비 + 디자인 시스템 로드맵 (마스터 트래커)

**이 문서의 역할**: 2026-07-11 세션에서 확정된 13개 과제의 진행 상황을 세션 간에 공유하는
단일 소스. 새 세션(특히 11/12/13번, 8~10번 디자인 병합 세션)을 시작하는 Claude는 이 문서를
**가장 먼저 읽고** 다음 TODO 항목과 선행조건을 확인할 것. 항목 착수 시 상태를 IN_PROGRESS로,
완료 시 DONE + 커밋 해시로 갱신한다. 막히면 BLOCKED + 사유 기록 후 다음 세션에 인계
(CLAUDE.md 원칙: 불확실하면 추측 대신 기록하고 멈춤).

**항목 헤딩 형식은 반드시 `### N. 제목 — STATUS`로 통일할 것.** `loop/gen_status.sh`가
이 줄을 파싱해 `loop/STATUS.md`의 미완료 목록을 만든다 — 완료인데 헤딩에 DONE을 안 적으면
끝난 일이 계속 "미완료"로 뜨고, 형식이 어긋나면 안 끝난 일이 목록에서 아예 누락된다
(2026-07-22에 13·16·17번에서 실제로 발생). 표(상태 요약)만 고치지 말고 **헤딩도 같이** 고칠 것.

**이 문서는 사람(마스터)이 읽는 상세 문서다.** 62KB로 커서 매 세션 통째로 컨텍스트에
넣으면 부담이 크다 — Claude는 자동 생성되는 `loop/STATUS.md`(미완료 항목 + 줄번호 링크)를
먼저 읽고, 필요한 항목만 이 문서의 해당 줄로 찾아 들어온다.

한때 `loop/BACKLOG.md`(T1/T2/T3 라이딩 검증 루프 전용)와 트랙이 나뉘어 있었으나, 그 파일은
2026-07-22 정리에서 `archive/`로 옮겨졌다(커밋 `23b058b`). 지금은 이 문서가 릴리스 준비
진행 상황의 단일 소스다.

원본 트리아지 근거: 이 대화 세션 앞부분의 특급/1급/2급/3급/4급 분류 참조.

## 현재 상태 (다음 세션 시작점)

- **ℹ️ 2026-07-16~17 (병행 트랙, 이 문서 스코프 밖)**: 야간루프/라이딩 검증 트랙에서
  언더패스·고가도로 "옆길" 구조물 인지 안전기능을 완료(커밋 `952ef64`/`a437894`/`fdc0132`).
  상세는 `loop/HANDOFF_0716_structure_bypass_exit.md` §7 참조 — 이 문서의 13번(기능 갭)
  하위 항목이 아니라 별개 안전기능 트랙이라 표에 새 항목을 추가하지 않음(중복 트래킹
  방지, [[project_yurunavi]] 메모리의 "두 트랙 항목 겹침 주의" 참고).
- **✅ 2026-07-15 완료**: POI 데이터소스 자체 호스팅 전환(15번) — 아키텍처 결함(서비스키
  클라이언트 내장, 전 사용자 쿼터 공유) 발견부터 근본 해결까지 같은 세션에서 완료. 상세는
  아래 15번 항목 참조.
- **⚠️ 2026-07-13**: 13-1b 실주행 피드백 버그픽스가 진행 중 — `loop/feedback/BUGFIX_progress.md`
  최상단 "▶ 다음 세션 시작점" 섹션 참조. 13-2 이후 항목은 이 피드백 버그픽스가 끝난 뒤 재개.
- **⚠️ 2026-07-12 업데이트** (BACKLOG.md는 2026-07-22 `archive/`로 이관됨 — 아래는 당시 기록):
  이 문서(13번 트랙)와 별개로 `loop/`에 T1/T2/T3 라이딩 검증
  전용 트랙(`loop/BACKLOG.md` + `HANDOFF_*`/`MORNING_REPORT_*`/`NIGHT_TASK_*` 체인)이 병렬로
  돌고 있었고, **같은 `verify/ride-0711` 브랜치를 공유**했다. 그쪽 트랙의 "§3.4 POI(소상공인
  시장진흥공단 API 연동)"가 이 문서의 13-1과 동일 항목이었음(이번 세션에 발견) — 13-1
  완료로 그쪽도 완료 처리됨, 중복 착수하지 말 것. 상세 인수인계는 `loop/HANDOFF_0712_poi.md`
  참조(양쪽 트랙 다 커버).
- **브랜치**: `verify/ride-0711` — 아직 origin에 **push 안 됨** (로컬 커밋만 존재, 2026-07-12
  기준 origin/main 대비 108개 커밋 앞섬 — 라이딩 검증 대기 중인 T1/T2/T3 변경분과 이 문서의
  1~13-1번 작업이 전부 이 브랜치 하나에 같이 쌓여있음).
- **1~7번 전부 완료·커밋됨**:
  - `469aced` — applicationId/서명/ProGuard/OSM attribution/디자인 토큰 뼈대 (1,2,3,4,7)
  - `8f44f62` — 개인정보처리방침 위치정보법 보강
  - `5697ff6` — 로드맵 문서 갱신
  - `67d90f4` — Firebase Crashlytics 최종 활성화 (5번 완료)
- **6번만 PARTIAL** — 문서 자체는 완료, 사용자의 위치기반서비스사업 신고 여부 확인만 남음
  (아래 6번 상세 참조). 나머지는 순수 사용자 액션 대기라 코드로 막힌 건 없음.
- **2026-07-11 재조정**: 8~10(디자인)번은 AI로 디자인 시안 여러 개를 뽑고 프롬프트를
  최적화하는 준비 시간이 필요해 사용자가 별도로 검토 중. 그동안 엔진을 놀리지 않기 위해
  **12번(백엔드 IaC화)을 이 세션에서 바로 착수**하기로 함 — 12번은 디자인과 무관한 순수
  인프라 작업이고 등급도 특급(서버 소실 시 복구 불가 리스크)이라 8~10보다 먼저 해도
  전혀 문제없음. 13번(기능 갭)도 UI는 7번 토큰 뼈대에 얹혀가면 되므로 디자인 확정을
  기다릴 필요 없이 12번 뒤에 이어서 진행 가능 — 다만 13번 항목 중 로그인/POI 등은
  백엔드가 필요해 12번 인프라가 먼저 있는 게 안전하므로 12→13 순서 자체는 유지.
- **12번 DONE(2026-07-11)** — 상세는 12번 항목 참조. valhalla-src 미커밋 패치 발견/보호
  같은 스코프 밖 긴급조치도 포함되어 있으니 새 세션에서 12번 상세를 한 번 읽어볼 것.
- **다음 순서**: 13번 착수. 8~10(디자인)은 사용자 검토가 끝나는 대로 **별도 세션에서
  병렬로** 진행, 끝나면 11번(토큰 리팩터)에서 그 시점까지 13번에서 새로 생긴 화면까지
  한 번에 정리.
- 새 세션 시작 시 `git log --oneline -10`으로 이 순서와 일치하는지 먼저 확인할 것
  (사용자가 세션 사이에 직접 커밋/변경했을 수 있음).

## 진행 순서 (2026-07-11 확정, 2026-07-11 재조정)

```
1~7 (완료)
        │
        ├────────────────────┐
        │                    │
12 → 13 (지금 이 트랙)      8~10 (디자인 검토용 별도 세션, 병렬 진행)
        │                    │
        │                    11 (8 확정 후, 13번 신규 화면까지 포함해서 스윕)
        │                    │
        └─────────┬──────────┘
                (둘 다 끝나면 릴리스 준비 완료)
```

12/13 트랙과 8~11 디자인 트랙은 서로 독립적으로 별도 세션에서 병렬 진행 가능. 단 11번
착수는 8번(팔레트 확정)이 끝난 뒤여야 하고, 13번에서 새로 만든 화면도 11번 스윕 대상에
포함시킬 것.

## 상태 요약

| # | 과제 | 등급 | 상태 |
|---|------|------|------|
| 1 | applicationId 변경 (com.example → com.westinx.yurunavi) | 특급 | **DONE** |
| 2 | release keystore 생성 + signingConfig 연결 | 특급 | **DONE** |
| 3 | OSM attribution 표시 추가 | 1급 | **DONE** |
| 4 | ProGuard/R8 활성화 | 1급 | **DONE** |
| 5 | Crash reporting 연동 (Firebase Crashlytics 선택됨) | 1급 | **DONE** |
| 6 | 개인정보처리방침 초안 + 호스팅 | 1급 | **PARTIAL** — 법률 검토 반영 완료, 위치기반서비스사업 신고(사용자 액션) 대기 |
| 7 | 디자인 토큰 아키텍처 뼈대 | 신규(1급) | **DONE** |
| 8 | 브랜드 방향성 확정 (컬러/타이포/무드) | 신규 | DEFERRED — 별도 세션(디자인 검토) |
| 9 | 앱 아이콘 확정 | 신규 | DEFERRED — 8번 이후 |
| 10 | 실제 release build 1회 실행·검증(설치/크기 포함) | 1급 | DEFERRED — 8~10 묶음으로 진행 |
| 11 | 하드코딩 스타일 → 토큰 기반 전면 리팩터 | 신규(1급/2급) | **PARTIAL** — Phase 0~4 완료(2026-07-22): AppConfig URL 추상화 + AppSkin 인터페이스 + DefaultSkin + SkinProvider + JSON 로더. Color(0xFF008080) 0건 달성. Phase 5(수익화 스캐폴딩)는 8번 브랜드 확정 후. |
| 12 | 백엔드 인프라 IaC화 (타일서버·navi 백엔드 docker화, 모니터링/백업) | 특급 | **DONE** |
| 13 | 기능 갭 해소 (로그인, 투어 요약, POI, 백그라운드 내비, 설정 Phase2) | 2급 | **DONE** — 13-1~13-6 전부 완료. 13-7(다크모드)는 11번 Phase 3에서 Color 토큰 교체로 흡수 완료. 13-8(오프라인 지도)는 12번 후속 과제로 재분류. |
| 14 | Crashlytics fatal 오분류 전수 감사 (배포 전 필수) | 1급 | PARTIAL — A/B/C/D(logcat) 완료, Crashlytics 콘솔 최종 확인만 마스터 직접 확인 대기 |
| 15 | POI 데이터소스 자체 호스팅 전환 (쿼터 아키텍처 결함 해소) | 특급 | **DONE** — 2026-07-15 발견 당일 해결, 커밋 `06adfb5`/`e27f06d`/`5b3eecd`/`ce709b8` |
| 16 | 구조물(고가도로/터널/지하차도)·지오메트리 급커브 카드 UI 신설 | 2급 | **DONE** — 커밋 `27dae87`, 아래 16번 상세 참조 |

## 항목별 상세

### 1. applicationId 변경 — DONE
- `com.example.yurunavi` → `com.westinx.yurunavi`
- 변경: `android/app/build.gradle.kts`(`namespace`, `applicationId`),
  `MainActivity.kt`를 `android/app/src/main/kotlin/com/westinx/yurunavi/`로 이동 +
  패키지 선언 변경. 리포 전체에 `com.example.yurunavi` 잔존 참조 없음(grep 확인).
- **검증**: `flutter build apk --release` 성공 + apksigner로 실제 서명 확인(2번과 함께 검증)

### 2. release keystore 생성 + signingConfig 연결 — DONE
- `android/upload-keystore.jks` 생성 (PKCS12, RSA 2048, alias `upload`, 유효기간 10000일).
  `android/key.properties`에 storePassword/keyPassword/keyAlias/storeFile 기록.
- `android/app/build.gradle.kts`: `key.properties` 존재 시 release signingConfig로 사용,
  없으면 debug 키로 폴백(파일 없는 체크아웃에서도 `flutter run --release` 동작 유지).
- `.gitignore`(루트 + 기존 `android/.gitignore`에도 이미 존재)에 `key.properties`/`*.jks`
  등록 확인 — `git check-ignore -v`로 실제 추적 제외 확인함.
- **⚠️ 사용자 액션 필요**: 세션 중 생성된 keystore 비밀번호가 터미널에 1회 출력됨 —
  **비밀번호 매니저 등에 별도 백업했는지 확인할 것.** 분실 시 이후 앱 업데이트 서명 불가.
- **검증**: `apksigner verify --print-certs`로 release APK가 `CN=YuruNavi, O=Westinx`
  키로 서명됨을 확인함(debug 키 폴백 아님).

### 3. OSM attribution 표시 추가 — DONE
- `assets/images/osm_liberty_yurunavi.json`의 vector source에 `attribution` 필드 추가
  (OSM 링크 포함). `main_map_screen.dart`/`nav_screen.dart` 양쪽에 좌하단 상시 노출
  텍스트도 안전장치로 추가(네이티브 attribution 버튼 렌더링을 헤드리스 환경에서 육안
  확인 못 하므로 이중화).
- 스타일은 최소한만 — 디자인 트랙(8~11번)에서 다시 다듬을 것.

### 4. ProGuard/R8 활성화 — DONE
- `android/app/proguard-rules.pro` 신규 생성 + release buildType에 `isMinifyEnabled`/
  `isShrinkResources` + `proguardFiles` 연결.
- **트러블슈팅 기록**: 최초 release 빌드 시 Flutter 임베딩이 참조하는 Play Core
  deferred-components(동적 기능 모듈) 클래스가 R8에서 "Missing class"로 실패 — 이 앱은
  동적 기능 모듈을 쓰지 않으므로 `-dontwarn com.google.android.play.core.**` 표준 규칙
  추가로 해결(Flutter 공식 문서에 명시된 흔한 이슈).
- **검증**: `flutter build apk --release` 성공(87.4MB, 기존 debug APK 224MB 대비 R8
  shrinking 효과 확인), analyze 0 issues.

### 5. Crash reporting 연동 — DONE
- 사용자 결정: **Firebase Crashlytics** (Sentry 대신 선택됨, 2026-07-11).
- 처음엔 dormant 스캐폴딩(코드는 준비하되 미호출)으로 시작 → 사용자가 Google Cloud
  프로젝트 한도에 걸려 안 쓰는 프로젝트(Dify/Openclaw) 정리 후 기존 **WESTINX**
  Firebase 프로젝트(project_id: `westinx-official`)에 Android 앱
  (`com.westinx.yurunavi`) 등록, `google-services.json` 발급받아 전달 → 최종 활성화 완료.
- `lib/firebase_options.dart`는 Firebase CLI 로그인 없이 `google-services.json` 값으로
  수동 작성(`DefaultFirebaseOptions.currentPlatform`, Android만 실값, 나머지 플랫폼은
  `UnsupportedError` — 이 앱은 Android 전용이므로 의도된 설계).
  `lib/main.dart`에서 `WidgetsFlutterBinding.ensureInitialized()` 직후
  `initCrashReporting()` 실제 호출 중.
- Android Gradle: `android/settings.gradle.kts`에 Google Services 플러그인 버전 선언,
  `android/app/build.gradle.kts`에 무조건 적용(더 이상 파일 존재 여부 조건부 아님 —
  아래 gitignore 결정과 짝을 이룸).
- **⚠️ 판단 기록**: `google-services.json`/`lib/firebase_options.dart`를 처음엔
  gitignore했으나, 감사 중 "Gradle 쪽은 파일 없어도 정상 빌드되는데 `main.dart`의
  import는 그렇지 않아 신규 체크아웃에서 analyze/build가 아예 깨진다"는 모순 발견.
  구글 공식 입장(이 값들은 APK에 그대로 포함되므로 git에서 숨겨도 실질 보호 없음, 진짜
  보안 경계는 Firebase Security Rules·API 키 제한)에 따라 **두 파일 다 git에 커밋**하는
  쪽으로 전환 — Flutter+Firebase 프로젝트의 표준 관행과도 일치. 아직 `git push` 전이라
  origin(공개 GitHub)엔 안 올라간 상태.
  - **권장(선택사항)**: Google Cloud Console에서 이 API 키를 Android 앱
    (패키지명+서명 지문)으로 제한해두면 심층 방어가 됨 — 필수는 아니지만 좋은 습관.
- **검증**: `flutter clean` 후 재빌드 기준 analyze 0 issues, test 96/96, release 빌드
  성공(87.6MB, apksigner로 실제 release 키 서명 재확인).

### 6. 개인정보처리방침 초안 + 호스팅 — DONE
- `docs/privacy_policy.md` 작성 완료 — 수집 항목(위치정보 포그라운드 전용, 로컬 저장
  프로필/경로, Firebase Crashlytics 진단정보), 자체 운영 서버(westinx.com) 전송 고지,
  제3자 제공 없음, 위탁(Firebase/Google), 이용자 권리, 만 14세 미만 미대상 등 포함.
- **⚠️ 사용자 확인 필요**:
  - 연락처가 `limera0@gmail.com`(초안 기본값)으로 되어 있음 — 공개 문서에 개인
    지메일을 그대로 노출할지, 별도 연락처를 쓸지 결정 필요.
  - **호스팅**: GitHub 리포(`github.com/limera0/yurunavi`)가 **public 확인됨**(API로
    검증) → 별도 설정 없이 `https://github.com/limera0/yurunavi/blob/main/docs/privacy_policy.md`
    링크를 Play Console 개인정보처리방침 URL로 바로 사용 가능. 더 브랜드에 맞는
    URL(예: legal.westinx.com)을 원하면 추후 이전 가능 — 지금은 이 GitHub 링크로 충분.
  - Play Console "Data Safety" 양식 작성 시 이 문서와 실제 수집 항목 반드시 일치시킬 것.
- **2026-07-11 추가 법률 검토(사용자 요청)**: 웹 검색으로 확인한 결과, 이 앱처럼 GPS
  좌표를 자체 서버로 전송해 경로를 계산하는 구조는 일반 개인정보보호법 외에 별도의
  「위치정보의 보호 및 이용 등에 관한 법률」의 적용을 받을 가능성이 높음. 문서에 동법이
  요구하는 필수 조항(위치정보관리책임자, 8세 이하 아동 보호의무자 조항, 손해배상,
  수집·이용·제공사실 확인자료 6개월 보관) 추가 완료, 국외이전 고지 강화, "위치정보를
  전혀 저장 안 함" 같은 과잉 주장 완화 — 커밋 `8f44f62`.
  - **⚠️ 문서 수정으로 해결 안 되는 별도 액션**: 위치정보법 제9조에 따른
    **위치기반서비스사업 신고**(방송통신위원회, 정부24 온라인 접수)가 필요할 가능성이
    높음 — 이건 사업자가 직접 진행해야 하는 행정 절차. 확실치 않다면 위치정보지원센터
    (lbsc.kr, 무료 상담) 문의 권장. 아직 미확인 상태로 남아있음.
- **호스팅 완료 (2026-07-22, 커밋 `259360b`)**: `navi.westinx.com/privacy` — Axum `/privacy`
  GET 라우트로 HTML 서빙. Play Console 개인정보처리방침 URL로 사용 가능.
  연락처 `ceo@westinx.com` 사용 중.

### 7. 디자인 토큰 아키텍처 뼈대 — DONE
- 기존 `lib/core/theme/app_theme.dart`(662줄, `AppColors`/`AppTextStyles`/
  `courseLineColor`)는 **완전히 그대로 유지** — 오늘 어떤 화면도 리팩터하지 않음.
- 신규 파일 4개, 전부 기존 값 위임(값 중복 없음):
  - `lib/core/theme/palette.dart` — `abstract class YuruNaviPalette` +
    `ClassicYuruNaviPalette`(기존 `AppColors`/`courseLineColor` 위임)
  - `lib/core/theme/typography.dart` — `abstract class YuruNaviTypography` +
    `ClassicYuruNaviTypography`(기존 `AppTextStyles` 위임)
  - `lib/core/theme/spacing.dart` — `abstract class YuruNaviSpacing`(xs4/sm8/md16/lg24/xl32,
    기존 코드에서 흔히 쓰이던 값 기반 신규 스케일) + `ClassicYuruNaviSpacing`
  - `lib/core/theme/app_theme_selector.dart` — `AppThemeSelector.activePalette/
    activeTypography/activeSpacing`가 현재 Classic* 세트를 가리킴. **이후 새 디자인을
    "구매"하면 여기 한 줄만 바꿔 끼우는 게 목표 지점** — 사용 방법 doc comment 포함.
  - 이 4개 파일은 **아직 어디서도 import되지 않음**(순수 뼈대, 11번에서 실제 소비 시작).
- **11번 착수 시 참고 — 하드코딩 실태 조사 결과(11번 세션에서 재확인 권장)**:
  - `AppColors.*` 85회 참조(lib/features/* 내 27회), `AppTextStyles.*` 15회,
    `courseLineColor` 8회 — 이게 전면 리팩터 대상 범위.
  - `profile_screen.dart`가 `AppColors`를 완전히 우회해 하드코딩된 청록색
    `Color(0xFF008080)`(팔레트에 존재하지도 않는 색)를 10회+ 직접 사용 — 발견만 해두고
    수정은 안 함. `main_map_screen.dart`/`settings_screen.dart`에도 소수의 raw
    `Color(0x...)` 리터럴, `lib/features/*` 전반에 `Colors.white/black/grey` 등 raw
    리터럴 57회 — 11번 스코프에 포함시킬 것.
- **검증**: `flutter analyze`(0 issues), `flutter test`(96/96) — 기존 화면 미변경이라
  회귀 없음.

### 8. 브랜드 방향성 확정
- 컬러 팔레트 / 타이포그래피(폰트) / 아이콘 스타일 / 무드. Claude가 방향 2~3개 제안,
  최종 선택은 사용자. **별도 세션** — 사용자 검토 시간 필요.
- **2026-07-14 진행**: Claude가 직접 다수 시안을 뽑는 대신 무료 도구인 Google Stitch
  (stitch.withgoogle.com)로 사용자가 직접 여러 스타일을 뽑아보기로 방향 전환. 준비 자료는
  `loop/STITCH_DESIGN_PROMPTS.md`(마스터 프롬프트 + 9개 스타일 테마 블록)와
  `loop/stitch_screens/`(M32F 실기기 캡처 5장) — 사용자가 Stitch에서 결과를 검토 중,
  현재 DEFERRED 상태 유지.

### 9. 앱 아이콘 확정
- 8번 확정 후 진행.

### 10. 실제 release build 검증
- `flutter build apk --release` (또는 `appbundle`) 실행, 설치, 크기/동작 확인.
- 8~10 묶음으로 진행하기로 사용자가 결정했으나, **1/2/4가 끝나면 기술적으로는 언제든
  당겨서 해도 무방** — 다음 세션 판단에 맡김 (디자인 자산 없이도 서명/난독화만
  검증 가능하므로).

### 11. 하드코딩 스타일 → 토큰 기반 전면 리팩터 — PARTIAL
- Phase 0~4 완료 (2026-07-22, `0b17048`~`2751048`, 상세: `MORNING_REPORT_0722_skin_infra.md`):
  AppConfig URL 추상화, AppSkin 인터페이스, DefaultSkin, SkinProvider + call-site 교체
  (`Color(0xFF008080)` 27건 → 0건), JSON 스킨 로더.
- Phase 5(수익화 스캐폴딩·스킨 목록 UI)만 남음 — 선행조건: 8번(브랜드 방향성 확정).
- 인라인 `TextStyle(...)` 116건(15파일)은 Phase 5와 함께 8번 이후 정리 권장.

### 12. 백엔드 인프라 IaC화 — DONE
- 목표: 타일서버(tileserver-gl)와 `navi.westinx.com` 백엔드를 `docker/` 안에
  Dockerfile/compose로 재현 가능하게 만들기. 현재 `docker/docker-compose.yml`엔
  valhalla만 있음 — 나머지 두 서비스는 이 리포에 설정이 전혀 없어 서버 소실 시
  복구 불가능한 상태 (특급 등급 근거).
- 추가로 고려: TLS 인증서 자동갱신, 헬스체크/모니터링, 백업.

**2026-07-11 실서버 조사 결과 (착수 전 정찰)**:
- `yurunavi-tiles` 컨테이너: `maptiler/tileserver-gl:latest` 이미지, `/data/tiles/data`→`/data`,
  `/data/tiles/fonts`→`/fonts` 볼륨 마운트, 포트 8080. 커스텀 Dockerfile 불필요 — compose
  서비스 항목만 추가하면 재현 가능.
- **navi 백엔드는 Docker가 아니라 systemd 서비스**(`yurunavi-rust.service`, 유닛 파일은
  `/etc/systemd/system/`에 있고 **리포 밖**)로 `/data/projects/yurunavi/native/target/release/
  yurunavi_server`(포트 8003)를 직접 실행 중. `native/src`, `Cargo.toml/lock`은 이미 git
  추적됨 — 소스 자체는 안전하나, "이 소스로 어떻게 서비스가 뜨는지"(유닛 파일, 빌드 절차)가
  리포에 전혀 없음.
- **숨어있던 의존성**: tiles/valhalla/navi 세 도메인의 공개 HTTPS는 로컬 nginx나 certbot이
  아니라 **Cloudflare Tunnel**(`n8n_cloudflared` 컨테이너, `/data/n8n-stack/`에 위치 — 이
  리포와 무관한 별개 프로젝트)을 통해 나감. 라우팅 규칙은 로컬 파일이 아니라 Cloudflare
  Zero Trust 대시보드에 원격으로 저장되어 있고, 컨테이너는 `TUNNEL_TOKEN` 하나로 연결됨.
  즉 **유루나비의 공개 접속 가능 여부가 n8n 스택의 생존에 묶여있음** — n8n_cloudflared가
  내려가면 tiles/valhalla/navi.westinx.com도 같이 죽음. CLAUDE.md 원칙(리포 범위 엄수)상
  `/data/n8n-stack/`은 건드리지 않고, 이 의존성 자체를 이 리포 문서에 기록해 인지시키는
  선까지만 처리. TLS 인증서 자동갱신은 Cloudflare Tunnel이 엣지에서 처리하므로 이 세
  도메인엔 별도 certbot 작업 불필요(로컬 `/etc/letsencrypt`엔 n8n 도메인만 존재, 확인됨).
- `tools/style-ai-proxy`, `tools/tuning_dashboard`(각각 `yurunavi-style-ai`,
  `yurunavi-tuning-dashboard` 컨테이너)는 이미 자체 Dockerfile/compose가 있고 git 추적
  중 — 내부 개발 도구라 12번 스코프 아님, 손댈 필요 없음.
- 영속 데이터 규모(백업 대상): `/data/tiles/data`(mbtiles+config+styles, ~2.1GB),
  `/data/valhalla/custom_files`(OSM PBF 원본 + 빌드된 그래프, ~11GB). `/data` 디스크
  여유 1.7TB — 로컬 백업엔 문제없음. 현재 자동 백업 전혀 없음.
- `docker/docker-compose.yml.bak`이 git에 추적되어 있음(구버전 valhalla 이미지 참조,
  죽은 파일) — 정리 대상.

**2026-07-11 실행 결과 (커밋 `4f8edba`)**:
- `docker/docker-compose.yml`에 `tiles`/`navi` 서비스 추가, `valhalla`와 함께 3개 전부
  compose 관리로 편입(`tiles`는 원래 `docker run`으로 떠 있던 컨테이너라 `docker rm -f` 후
  compose로 재생성 — 무상태라 데이터 손실 없음).
- `native/Dockerfile` 신규(rust-coder 서브에이전트 작성): 멀티스테이지 빌드, non-root 유저,
  `/health` 헬스체크. 사용자가 "지금 Docker로 완전 전환" 선택 → 이미지 빌드/임시포트(18003)
  스모크테스트까지 완료. **다만 마지막 라이브 컷오버(systemd 중지 → 8003 기동)는 sudo 권한이
  없어 Claude가 실행 못함 — 사용자가 `docker/INFRA.md` §1의 명령 4줄을 직접 실행해야
  완료됨.** 그 전까지 navi는 여전히 systemd로 운영 중(무중단, 문제 없음).
- `docker/backup.sh` 신규: tiles/valhalla 데이터 + valhalla-src를 매일 03:00 하드링크
  스냅샷(최근 3세대)으로 백업, crontab 등록 완료(기존 hm-tracker cron 항목은 보존).
- `docker/INFRA.md` 신규: 서비스 구성표, Cloudflare Tunnel 외부 의존성, 백업/복구 절차,
  navi 컷오버 미완료 상태를 문서화.
- **⚠️ 스코프 밖에서 발견한 더 심각한 문제, 로컬 커밋으로 긴급 보호함**: valhalla 포크
  이미지(`valhalla-fork:patch3-uturn`)를 빌드하는 소스(`/data/projects/valhalla-src` —
  공식 `valhalla/valhalla` git checkout)가 detached HEAD 위에 **uncommitted 상태로만**
  존재했음. `motorcyclecost.cc`(이 앱의 핵심 차별화 로직인 곡률/신호/U턴 커스텀 코스팅)와
  `docker/Dockerfile.fork`(빌드 파일 자체)가 git 이력이 전혀 없어 이 디렉토리가 사라지면
  영구 소실될 뻔한 상태. 새 로컬 브랜치 `yurunavi-fork`를 만들어 커밋(`cbf9a425b`, origin
  push는 안 함 — CLAUDE.md 리포 범위 원칙상 사용자 승인 없이 외부 리포지토리에 push하지
  않음). 상세는 `docker/INFRA.md` §3. **남은 리스크**: 여전히 이 서버에만 있는 로컬 커밋 —
  진짜 오프사이트 백업(예: private GitHub push)은 다음 세션 판단.
- code-auditor 검토에서 실질 버그 2건 발견 후 수정: (1) 최초 체크포인트 커밋이 실제로는
  `git add` 누락으로 compose 파일 변경분을 안 담고 있었던 것, (2) INFRA.md가 컷오버를
  "완료"라고 잘못 서술한 것 — 둘 다 바로잡음.
- **컷오버 완료(사용자 실행, 2026-07-11)**: `sudo systemctl stop yurunavi-rust.service` →
  `docker compose up -d navi` → `curl localhost:8003/health` 확인 →
  `sudo systemctl disable yurunavi-rust.service`. `docker ps` 기준 `yurunavi-navi` healthy,
  `curl https://navi.westinx.com/health`(Cloudflare Tunnel 경로 포함 실제 공개 도메인)도
  `{"status":"ok"}` 확인. 구 systemd 유닛은 `disabled`+`inactive`로 롤백용으로만 남음.
  최종 상태: `docker compose ls` 기준 `docker` 프로젝트 3개 서비스(valhalla/tiles/navi)
  모두 compose 관리 + healthy.
- **13번 착수(2026-07-11)**: 실제 코드 조사 후 8개 하위 항목으로 분해 + 재우선순위화함.
  상세는 13번 항목 참조. 13-1(POI 탐색 UI)부터 시작.

### 13. 기능 갭 해소 — DONE (13-1~13-6 완료, 13-7은 11번에 흡수, 13-8은 12번 후속으로 재분류)

**2026-07-11 착수 전 코드 조사 결과** (원래 이름만 나열되어 있던 5개 기능을 실제 코드
상태 기준으로 재조사 → 8개 하위 항목으로 분해 + 재우선순위화):

- **로그인/회원가입**: `lib/features/auth/`엔 `splash_screen.dart` 하나뿐, 실제 로그인/
  회원가입 UI 없음. `pubspec.yaml`에 `firebase_auth` 패키지조차 없음(현재 `firebase_core`/
  `firebase_crashlytics`만 존재). **더 중요한 발견**: 현재 앱에 계정으로 게이팅되는 기능이
  전혀 없음 — 프로필(`profile_service.dart`)/즐겨찾기·최근장소(`places_service.dart`)/
  저장경로(`route_service.dart`) 전부 `shared_preferences` 로컬 저장뿐, 클라우드 동기화
  자체가 없음. 즉 로그인을 지금 만들어도 연결할 데가 없음.
- ~~**투어 요약(주행 이력)**: 데이터 모델·저장·화면 전부 0%~~ — **DONE(2026-07-18, 13-3
  참조)**. 아래 하위 항목 표 및 13-3 실행 결과 섹션 참조.
- **POI 탐색 UI**: 백엔드는 이미 완성돼 있음 — `lib/services/poi_service.dart`(Overpass
  API로 카페/주유소/주차장/은행/병원/편의점 등 실시간 조회, 235줄, 오모테나시 목적지 스냅
  로직 포함). 그런데 `poiServiceProvider`(`map_providers.dart:278`)가 **어디서도 소비되지
  않는 죽은 코드** — grep으로 정의부 외 참조 0건 확인. 현재 지도에서 동작하는 건
  `poi_feature_picker.dart`(탭한 벡터타일 라벨 하나 식별)뿐, "주변 POI 목록/검색" 기능은
  없음. 즉 백엔드 재사용 + UI만 얹으면 되는 가장 저비용 항목.
- **백그라운드/오버레이 내비게이션**: `AndroidManifest.xml`에 `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_LOCATION`, `SYSTEM_ALERT_WINDOW`, `POST_NOTIFICATIONS` 권한이 이미
  선언돼 있으나 **전부 미사용**(대응하는 Kotlin 서비스 클래스 없음 — `MainActivity.kt`가
  유일한 네이티브 파일, `flutter_background_service`류 패키지도 없음). 화면 유지는
  `wakelock_plus`(앱 포그라운드 중 화면만 꺼짐 방지)뿐 — 앱이 백그라운드로 가거나 화면이
  잠기면 안내가 끊김. 순수 네이티브(Android 포그라운드 서비스 + 알림) 작업이 필요해 5개
  항목 중 구현 리스크가 가장 큼.
- **설정 Phase 2**: `settings_screen.dart`에 이미 TODO 주석으로 스코프가 명시돼 있음(주행
  설정: 도로 선호도/내비뷰 설정/안내 음성·언어, 앱 설정: 다크모드/지도 다운로드, 기타:
  약관/오픈소스 라이선스) — 그런데 난이도 편차가 매우 커서 하나로 묶을 수 없음:
  - 약관/오픈소스 라이선스: 정적 텍스트 화면 하나, 완전 독립적, 스토어 컴플라이언스에도
    도움 → 가장 쉬움.
  - 안내 음성/언어: `assets/voice_packs/`에 `default_ko.json` **1개뿐**이라 언어 선택
    자체가 무의미(콘텐츠가 없음) — UI 작업이 아니라 콘텐츠(음성팩) 제작이 선행돼야 함.
  - 도로 선호도: [[project_yurunavi]]에 기록된 Valhalla 포크 `motorcyclecost.cc` 커스텀
    코스팅이 백엔드엔 이미 있으니 파라미터를 UI로 노출하는 형태일 가능성 높음 — 착수 시
    `routing_service.dart`/valhalla-src costing 옵션 재조사 필요.
  - 다크모드: 7번(토큰 뼈대)엔 이미 있지만 11번(하드코딩 전면 리팩터, 현재 BLOCKED — 8번
    팔레트 확정 대기)과 스코프가 겹침 — 지금 만들면 11번에서 또 손대야 해서 이중작업.
  - 지도 다운로드(오프라인 지도): 타일 저장/용량 관리까지 필요한 별도 인프라 과제 —
    12번(타일서버) 스코프에 더 가까움.

**재우선순위화 근거**: 원래 로드맵 표의 "로그인, 투어 요약, POI, 백그라운드 내비, 설정
Phase2" 순서는 최초 트리아지 세션에서의 단순 나열이었지 우선순위가 아니었음(이번 조사에서
처음 확인). 실제 선행조건·구현 리스크·즉시 사용자 가치를 기준으로 재배열함 — 특히 로그인은
현재 게이팅할 기능이 전무해 맨 뒤로, POI는 백엔드 재사용만으로 되어 맨 앞으로 이동.

**하위 항목 (진행 순서)**:

| # | 하위 과제 | 근거 요약 | 상태 |
|---|-----------|-----------|------|
| 13-1 | POI 탐색 UI (+13-1b 상시표시 레이어) | 백엔드 완성·미사용 상태, UI만 필요 → 최저비용 최고가치 | **DONE** (`2d91e4d`, `27cc8db`) — data.go.kr API 교체 + 검색시트 + 줌기반 상시 POI 레이어(홈/내비 화면) 전부 완료 |
| 13-2 | 설정: 약관/오픈소스 라이선스 화면 | 완전 독립, 정적 화면, 스토어 컴플라이언스 | **DONE** (`9393af3`, 2026-07-13) — `docs/terms_of_service.md` 초안(법률 검토 전, 배포 전 변호사 검토 필요) 작성 + `TermsScreen`(설정>이용약관) + `showLicensePage`(설정>오픈소스 라이선스, Flutter 내장 API) |
| 13-3 | 투어 요약(주행 이력) 로컬 MVP | 로그인 불필요, 데이터모델부터 신규 구축 | **DONE(2026-07-18)** — 아래 실행 결과 참조. 커밋 `36398e3`~`e7fb8ae`(9개) |
| 13-4 | 설정: 내비뷰 — 지도 방향 토글 (도로 선호도는 코스 선택으로 충분, 제외) | 내비뷰 설정만 진행 | **DONE** (`056b5f6`) — 헤딩업/노스업 스위치, shared_prefs 영속 |
| 13-5 | 백그라운드/오버레이 내비게이션 | 네이티브 포그라운드 서비스+알림, 리스크 최고. **`loop/` 야간루프 트랙의 §3.6과 동일 항목** — 그쪽도 "가장 무거움, 단독 세션 권장"으로 이미 표시돼 있음(`MORNING_REPORT_0711_night2.md`). 착수 시 두 트랙 다 여기 하나로 처리하고 양쪽에 완료 기록할 것, 중복 작업 금지 | **DONE(Android만, 2026-07-17)** — iOS는 별도 과제(아래 상세). 커밋 `d4b50e1`/`b883ee5`/`e2f1db9`(Phase A)/`1e99528`/`059eea4`(Phase B) |
| 13-6 | 로그인/회원가입 | 게이팅할 기능 없음 — 13-3 이후 "클라우드 동기화 필요" 시점에 재평가 | **DONE** — Google 로그인 + 이름·사진·이메일 프로필 표시 완료(2026-07-17, 커밋 `990e22b`/`22c2f69`). 전화번호는 Google 기본 스코프 미제공·심사 필요로 미구현 확정. |
| 13-7 | 설정: 다크모드 | 11번(팔레트 확정 후 토큰 리팩터)과 병합 권장, 여기서 별도로 안 함 | **DONE** → 11번 Phase 3에서 Color 토큰 교체로 흡수 완료 |
| 13-8 | 설정: 지도 다운로드(오프라인 지도) | 타일 저장/용량 관리 — 12번(인프라) 성격에 더 가까움 | DEFERRED → 12번 후속 과제로 재분류 확정 |

착수 시 상태를 IN_PROGRESS로, 완료 시 DONE + 커밋 해시로 갱신할 것 (세션 프로토콜 동일 적용).

**13-1 실행 결과 (커밋 `5ab5262`, 2026-07-11)**:
- `lib/features/map/presentation/main_map_screen.dart` 한 파일만 변경(+316/-4). 우측 지도
  컨트롤 패널에 storefront 버튼 추가 → 바텀시트에서 6종 POI 카테고리 필터칩 다중선택 →
  기존 `PoiService.fetchPois()`(Overpass) 반경 3km 조회 → 거리순 리스트, 탭하면 목적지
  설정. 동시에 `poiListProvider`에 결과를 넣어 MapLibre GL 네이티브 CircleLayer(신규
  `poi-explore-source`/`poi-explore-layer`, 카테고리별 색상 match expression)로 지도 위에
  점 렌더링, 시트 닫히면 자동 정리.
- 지도 위 점 자체의 탭 인식(hit-test)은 스코프에서 제외 — 목적지 지정은 시트 리스트 탭으로만
  (기존 `_onMapTap` 흐름은 미변경). `PoiService.snapDestination`(오모테나시 스냅),
  `poi_feature_picker.dart`, flutter_map 기반 죽은 코드(`_buildPoiMarkers` 등)는 미변경.
- code-auditor PASS(비동기 생명주기/시트 닫힘 처리/GeoJSON 좌표순서/match expression 문자열
  일치/스타일 재로드 시 복원/기존 호출부 호환성 전부 확인). 사소한 정리 2건(중복
  `ref.watch` 제거, `whenComplete` 콜백 `mounted` 가드)은 바로 반영.
- `flutter analyze` 0 issues, `flutter test` 96/96, `flutter build apk --debug` 빌드 성공.
- **⚠️ 미확인 상태로 남은 것**: headless 서버라 `flutter run` 불가 — 카테고리별 점 색상이
  실제 기기에서 의도대로 렌더링되는지, 필터칩 UX가 실사용감 있는지는 코드 검토로만
  확인했고 육안 확인은 못함. 다음에 노트북에서 `adb install
  build/app/outputs/flutter-apk/app-debug.apk`로 실제 확인 권장.

**13-1 REOPENED (2026-07-12)**: 사용자가 실기기에서 확인한 결과 POI 결과가 거의 안 나옴 —
한국 OSM은 도로망은 훌륭하지만 상가/상점 POI 태깅이 매우 부실해 Overpass 조회가 대부분
비어있음. **공공데이터포털 `소상공인시장진흥공단_상가(상권)정보_API`(서비스ID
`B553077`)로 데이터 소스 교체 결정** — 네이버/카카오 로컬검색 API는 이용약관상 자사 지도
위에만 표시 가능해 배제(이전 세션 결정, 이번에 재확인). 상세 API 사양·이유·진행상태는
[[project_poi_datasource]] 메모리 참조. **블로킹 상태**: 사용자가 data.go.kr에서 회원가입 +
활용신청 후 인증키를 전달해야 다음 단계(실 API 스모크테스트 → PoiService 교체 → 상단
검색창 추가) 진행 가능. 기존 13-1 커밋(`5ab5262`)의 UI 골격(우측 패널 진입점, 바텀시트,
MapLibre CircleLayer 렌더링)은 재사용 가능성 높음 — 데이터 소스/카테고리 체계만 교체될 예정.
- 다음 세션: 사용자로부터 인증키 수신 여부 먼저 확인. 받았으면 13-1 데이터소스 교체부터,
  아직이면 13-2(설정: 약관/오픈소스 라이선스 화면)로 순서 바꿔 먼저 진행.

**13-1 최종 완료 (커밋 `2d91e4d`, 2026-07-12)**: 사용자가 같은 세션에서 인증키를 바로
발급받아 전달 → data.go.kr `소상공인시장진흥공단_상가(상권)정보_API`(`storeListInRadius`)로
실제 라이브 curl 검증까지 마치고 데이터소스 교체 완료. 상세 API 사양·카테고리 코드 매핑은
[[project_poi_datasource]] 메모리 참조(요약: 카페/편의점/주유소/마트/식당 5종, 전통시장은
이 API에 대응 코드 없어 스코프 제외, 서버 키워드검색 없어 반경조회+클라이언트 상호명
필터링으로 검색 구현).
- **사용자의 명시적 요구사항이었던 "상단에 검색창"도 같이 구현**: 기존 우측 패널 storefront
  아이콘 진입점을 지도 헤더의 "장소 검색" 바로 교체(진입점 중복 방지), 기존 카테고리 필터
  시트 안에 상호명 검색 TextField 추가.
- code-auditor 2라운드 — 1차 FAIL(치명적 버그 2건 발견): (1) 마트 카테고리 코드
  `G20402`(대형마트)가 실제 데이터가 거의 없어 전국 어디서든 조회하면 무조건 결과 0건이
  나오는 죽은 코드였음(auditor가 라이브 API로 직접 확인) → `G20404`(슈퍼마켓)로 교정,
  (2) 검색어/카테고리 빠르게 바꿀 때 늦게 도착한 이전 요청 응답이 최신 상태를 덮어써서
  지도 위 POI 핀이 엉뚱하게 다시 나타나는 stale-response 경쟁상태 → 응답 도착 시
  `_fetchedTypes` 재확인 가드 추가로 수정. 2차 재감사 PASS.
- `flutter analyze` 0 issues, `flutter test` 96/96, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.

**13-1b: 상시 표시(ambient) POI 레이어 추가 (커밋 `27cc8db`, 2026-07-12)** — 사용자가 실기기로
확인한 결과 검색 시트의 목록은 잘 나오는데 **지도 위에는 점이 안 찍힘**을 발견. 원인은 버그가
아니라 애초에 요구사항을 잘못 이해한 것 — 사용자가 원한 건 "검색해야만 잠깐 보이는 POI"가
아니라 **줌 레벨에 따라 항상 켜져 있는 POI 레이어**(주유소 줌11+, 카페/편의점 줌13+,
마트/식당 줌14+, 화면당 최대 10개, 홈 화면·내비 화면 둘 다)였음. 기존 검색시트 기능(13-1)은
전혀 안 건드리고 완전히 별개 레이어/상태로 새로 구현:
- 홈 화면(`poi-ambient-source`/`layer`)·내비 화면(`nav-poi-source`/`layer`) 양쪽 다 추가.
  `getVisibleRegion()`으로 뷰포트 구해서 화면에 실제 보이는 것만, 가까운 순 10개로 컷.
- code-auditor 3라운드(FAIL→FAIL→PASS) — 실제 버그 3건 발견/수정: (1) stale-response
  경쟁상태(늦게 온 응답이 최신 상태 덮어씀, 처음엔 가드 위치가 await 하나만 커버해서 재감사도
  FAIL, 두 await(`getVisibleRegion`+`fetchPois`) 전체를 커버하도록 재수정), (2) 내비 화면의
  속도연동 자동줌(`_navZoom`)이 카테고리 임계값 근처에서 진동하면 디바운스 없이 fetch가
  연발할 수 있었던 문제 → 0.3 히스테리시스 추가, (3) 디바운스 판정 전에 매 GPS 틱마다
  불필요한 플랫폼채널 호출(`getVisibleRegion`)이 나가던 비효율 → 순서 재배치.
- `flutter analyze` 0 issues, `flutter test` 96/96, debug APK 빌드 성공.
- 사용자가 실제로 라이딩 검증을 나갔다 와서 15~16페이지짜리 주석 스크린샷 피드백을 줬다.
  최초엔 PDF로 받았으나 **PDF를 열려고 하면 세션이 죽는 문제가 확인됨**(API ECONNRESET) —
  사용자가 대신 PNG 16장(`loop/feedback/260712_testDriveFeedback_1~16.PNG`)으로 재전달, PDF는
  이제 사용 안 함. **16장 전부 분석 완료**(`loop/feedback/ANALYSIS_progress.md`), 그 뒤
  실제 버그 수정 작업이 `loop/feedback/BUGFIX_progress.md`에서 계속 진행 중 — 이 트랙이
  13-2보다 우선. `loop/HANDOFF_0712_ridefeedback2.md`/`HANDOFF_0712_ridefeedback.md`는
  2026-07-12 세션 시점 스냅샷이라 **stale** — 지금은 `BUGFIX_progress.md` 최상단 "▶ 다음
  세션 시작점" 섹션이 최신 소스.
- ~~다음 세션: 13-2(설정: 약관/오픈소스 라이선스 화면)부터 이어가면 됨.~~ → 피드백 버그픽스
  (`BUGFIX_progress.md`)가 먼저 끝나야 함.

**13-3 실행 결과 — 로컬 MVP + 메모/공유 (2026-07-18)**:
`HANDOFF_0717_launch_priorities.md` 사용자 요청 착수분. 승인된 계획
(`/home/limera/.claude/plans/greedy-moseying-lantern.md`) 기준 구현 — 최초 검토 시
sqflite 도입을 고려했으나, 사용자 피드백("매 라이딩마다 전체 이력을 통째로 읽고
다시쓰기 하는 구조는 너무 어렵지 않냐")을 반영해 신규 DB 의존성 없이 기존 코드베이스
관례 두 개를 재사용하는 방향으로 재설계함:
- **트랙(궤적) 데이터**: `lib/core/logging/file_logger.dart`의 파일 append 패턴을 그대로
  본떠, 주행 중 채택된 GPS 포인트(20m 이동 또는 8초+3m 경과마다 1개)를 트립별
  `tours/tour_<id>.jsonl` 파일에 실시간으로 한 줄씩 append(`lib/features/navigation/
  tour_track_writer.dart`). 라이딩 내내 전체 궤적을 메모리에 들고 있을 필요가 없어짐.
- **요약 정보**(거리/시간/평균·최고속도/From·To 주소): `lib/services/places_service.dart`의
  shared_preferences 패턴 그대로 재사용(`lib/services/tour_log_service.dart`, 키
  `tour_logs_v1`) — `addRecent`류의 자동 trim은 가져오지 않고 사용자가 명시적으로
  삭제하기 전까진 전부 보존.
- **기록 로직**: `lib/features/navigation/tour_recorder.dart` — 순수 Dart 클래스,
  `nav_screen.dart`의 기존 `navStateProvider` 리스너에 얹어 거리(속도×시간 적분)/최고속도
  누적. 내비 종료 4개 실제 경로(자동종료 타이머, 뒤로가기 확인다이얼로그의 "종료",
  "안내 종료" 버튼, "종료" 버튼) 전부에서 신규 `_exitNav()` 헬퍼를 통해 자동 저장, 60초/
  150m 미만 트립은 저장 안 함(잡음 필터).
- **역지오코딩**: `geocoding` 패키지(OS 네이티브, API 키 불필요) 신규 도입,
  `lib/services/geocoding_service.dart` — 실패 시 null 허용, UI는 좌표 문자열로 폴백.
- **UI**: `lib/features/tour_summary/`(목록 화면: 날짜별 그룹, 카드별 통계+From→To+삭제,
  상세 화면: 통계 헤더 + MapLibre 지도에 경로선+시작/종료 핀+카메라 자동 프레이밍).
  `main_map_screen.dart`의 기존 히스토리 아이콘 스텁(`onTourSummary: () {}`)을 연결.
- **세션 중 사용자 추가 요청 2건도 같은 스코프에서 반영**: (1) 상세화면에 자유 텍스트
  메모 기능(하단 확장 패널, 명시적 저장, 실패 시 스낵바+초안 보존), (2) 통계 카드+지도를
  합성한 이미지를 OS 공유시트로 전달하는 공유 기능(`share_plus` 신규 도입, 메모를 캡션
  텍스트로 동봉). **미포함**: 투어 중 사진을 GPS/날짜로 지도에 표시하는 기능은 사용자가
  "더 한다면"으로 명시한 스트레치였고 카메라/EXIF 기반이 코드베이스에 전무해 별도
  과제(Phase 2)로 분리, 미착수.
- 신규 패키지는 `geocoding`·`share_plus` 둘뿐.
- **code-auditor 루프에서 실기기 검증 없이는 못 잡았을 실제 버그 3건 발견·수정**:
  (1) `dispose()` 안전망이 Flutter가 위젯을 이미 unmount한 뒤 Riverpod `ref.read()`를
  호출해 크래시 — `_exitNav()` 경로 외 종료 시 주행기록이 조용히 유실될 뻔함, 회귀
  테스트로 고정. (2) 공유 이미지 합성 시 `ui.Image`/`Codec` dispose 누락 — 공유 버튼
  누를 때마다 메모리 누수, `lib/services/poi_icon_renderer.dart` 기존 관례로 수정.
  (3) **`MapLibreMapController.takeSnapshot()`이 M32F 실기기에서 90초+ 무한정 멈추는
  버그** — 지도 스타일이 인라인 JSON이라 네이티브 `MapSnapshotter`의 독립 재렌더링이
  해석 불가능한 스타일 참조에 걸려 멈추는 것으로 추정(완전한 근본원인 규명은 서드파티
  플러그인 네이티브 코드 영역이라 보류). 대안으로 검토한 "지도를 RepaintBoundary로 직접
  캡처"는 이 앱의 MapLibreMap이 기본 SurfaceView 렌더링(`useHybridComposition` 전역
  static 플래그, 앱 전체 지도에 영향)이라 배제. 6초 타임아웃 + "지도 없이 헤더 카드만
  이라도 공유" 폴백으로 해결, 실기기 재검증 완료(공유시트 정상 표시 확인).
- `flutter analyze` 0 issues, `flutter test` 249개 전부 통과.
- **가상 GPS 실주행 검증**(M32F, 합성 경로 ~3.6km/약 2분 30초 — 실좌표 기반 Valhalla
  라우팅은 아니고 서비스 지역 내 임의 좌표 간 직접 생성한 CSV): 트립 저장(로그 확인)→
  목록 화면에 정확한 통계로 표시→상세 화면 지도/폴리라인/핀 렌더링→메모 저장 후 앱
  재실행(재설치)해도 유지→공유(헤더 폴백 경로로 공유시트 정상 표시)→삭제(인덱스+트랙
  파일 모두 정리) 전부 실기기에서 직접 확인. 최고속도 110km/h로 찍힌 건 테스트용 합성
  경로가 65→85→65km/h로 비현실적으로 급변한 데 대해 기존(이번 세션 무관) 속도 보정
  로직이 순간 오버슈트한 것으로 판단 — 실주행에서 재확인 권장.
- `git push` 완료(`verify/ride-0711`, 2026-07-18).

**13-5 실행 결과 — Android 완료, iOS 별도 과제 (2026-07-17)**:
`HANDOFF_0717_launch_priorities.md` 3순위 착수분. 착수 전 레퍼런스 조사 결과 두 가지가
당초 가정과 달랐음: (1) 유튜브의 "다른 앱 위 배경 표시"는 `SYSTEM_ALERT_WINDOW`가 아니라
Android **Picture-in-Picture(PiP)** API였고, Google도 오버레이 대신 PiP/Bubbles를
공식 권장 중, (2) iOS는 서드파티 앱의 "다른 앱 위에 그리기" 자체가 애초에 불가능(공개
API 없음, 애플 멀티태스킹 모델 제약) — iOS 대응은 `UIBackgroundModes`+ActivityKit Live
Activities로 아키텍처가 완전히 다른 별도 과제, 이번 스코프에서 제외.

- **Phase A(포그라운드 서비스, 커밋 `d4b50e1`/`b883ee5`)**: 신규
  `android/app/src/main/kotlin/com/westinx/yurunavi/NavForegroundService.kt`(Intent
  기반, `foregroundServiceType="location"`) + `nav_service` MethodChannel +
  `lib/services/nav_foreground_service.dart`. `nav_screen.dart`에서 안내 시작/턴 갱신/
  종료 시점에 연동, 알림 텍스트는 온스크린 카드와 동일한 "다음 턴" 인덱스 로직 재사용.
  code-auditor가 `stopSelf()`→`stopSelf(startId)`(재시작 경쟁상태), null Intent 방어
  누락 2건 발견 → 즉시 수정.
- **Phase B(PiP 미니창, 커밋 `1e99528`)**: `android_pip` 패키지로 실제 OS PiP 사용(유튜브와
  동일 메커니즘, `SYSTEM_ALERT_WINDOW` 버블 방식 아님 — 후보였던 `flutter_overlay_window`는
  15개월 미업데이트로 기각). **구현 중 실기기 검증으로 타이밍 버그 발견**: 최초 구현이
  Flutter `didChangeAppLifecycleState(paused)`에서 PiP 진입을 시도했는데, `paused`는
  Android `onStop()` 대응이라 액티비티가 이미 안 보이는 시점 — `enterPictureInPictureMode()`가
  조용히 실패함(`dumpsys activity activities`로 확인). 네이티브 `onUserLeaveHint()`(아직
  화면 보이는 시점)를 새 채널로 Dart에 포워딩하는 방식으로 교체 후 재검증 통과.
- **가상 GPS + 실기기 검증**: `loop/feedback/VGPS_BGNAV_PHASE_A_0717.md`,
  `VGPS_BGNAV_PHASE_B_0717.md` 참조 — 백그라운드 전환 중 TTS/진행판정 지속, PiP 창
  정상 렌더·복귀, 서비스/알림 정상 정리(크래시 없음) 전부 스크린샷+`dumpsys`로 확인.
- `flutter analyze` 0 issues, `flutter test` 217/217, `flutter build apk --debug` 빌드
  성공 매 단계 확인.

**13-6 실행 결과 — Google 로그인만, 데이터 연동은 별도 과제 (2026-07-17)**:
`HANDOFF_0717_launch_priorities.md` 사용자 요청 착수분 — 투어 요약(13-3)/프로필 페이지를
제대로 만들려면 계정 시스템이 먼저 필요하다는 판단으로 "게이팅할 기능 없음" 보류 방침을
해제하고 로그인 자체만 먼저 구현. **이번 스코프는 로그인/로그아웃뿐**이고, 로컬
`UserProfile`(닉네임/바이크) 데이터와의 연동·마이그레이션이나 투어 요약 클라우드 동기화는
포함하지 않음(다음 세션 과제).

- **선행 조건**: `android/app/google-services.json`의 `oauth_client`가 원래 빈 배열이라
  Firebase 콘솔에서 Google 제공자를 켜고 디버그+릴리즈 SHA-1 지문을 등록하지 않으면 코드가
  맞아도 로그인이 동작할 수 없는 상태였음 — 이 세션 착수 시점에 이미 사용자가 콘솔 작업을
  끝내고 재발급받은 파일이 워킹트리에 반영돼 있었음(커밋 `990e22b`로 체크포인트).
- **구현(커밋 `22c2f69`)**: `lib/services/auth_service.dart`(신규) — `google_sign_in` v7의
  실제 API(`GoogleSignIn.instance.initialize()`→`authenticate()`, `GoogleSignInException`의
  `canceled` 코드는 에러 아닌 `null` 반환)로 `GoogleAuthProvider.credential(idToken:)` →
  `FirebaseAuth.signInWithCredential`. `lib/features/auth/providers/auth_providers.dart`(신규)
  — 기존 `map_providers.dart`의 수동 Provider 패턴(코드젠 없음) 그대로 `authServiceProvider`/
  `authStateProvider`. `profile_screen.dart`에 "계정" 섹션만 추가 — 앱 시작 시 강제 로그인
  게이트는 만들지 않음(설정→프로필 편집이 유일한 진입점).
- **감사(code-auditor, PASS)**: 로그인 취소가 조용히 무시되는지, idToken이 로그/저장소에
  안 남는지, `google-services.json`에 실제로 `serverClientId` 없이도 되는 web `client_type: 3`
  항목이 있는지까지 패키지 소스로 직접 검증. medium 지적 1건(로그아웃 경로에 로그인과 달리
  try/catch 없어 실패해도 스낵바 안내가 안 됨) → 즉시 수정 후 재확인.
- `flutter analyze` 0 issues, `flutter test` 217/217, `flutter build apk --debug` 빌드 성공.
- **실기기 검증 완료(같은 날, M32F)**: adb로 설치 → 프로필 화면 "Google로 로그인" 탭 →
  실제 Android 계정 선택 다이얼로그(`SignInCredentialChooserActivity`)로 기기에 등록된
  계정(`limera0@gmail.com`) 표시 → 선택 → "Google을 통해 yurunavi에 로그인하도록 허용" 동의
  화면 → 동의 후 프로필 사진/이름/이메일이 계정 섹션에 정상 표시. "로그아웃" 탭 → 다시
  "Google로 로그인" 버튼 상태로 정상 복귀. 이 과정에서 닉네임/바이크 입력란은 계속 비어있는
  채 유지됨(로컬 프로필과 계정 상태가 실제로 분리돼 있음을 실기기에서 재확인).
- iOS는 스코프 밖(`GoogleService-Info.plist`/URL scheme 미설정, 이 서버는 헤드리스 Linux라
  Xcode 빌드 불가) — 13-5와 동일한 패턴으로 별도 과제.

### 14. Crashlytics fatal 오분류 전수 감사 — PARTIAL (A/C 완료, B/D 남음)

- **계기 (2026-07-13)**: Firebase Crashlytics가 1.0.1(2)에서 157건의 "치명적(Fatal)" 이벤트를
  경고 메일로 보내왔으나, 실제로는 앱이 죽은 게 아니라 `lib/core/crash_reporting.dart:18`의
  `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;` 배선 때문에
  **Flutter 프레임워크의 non-fatal debug 경고까지 전부 fatal로 기록**되고 있었던 것으로 확인됨.
  이번 건의 구체적 원인(지도 탭 확인 바텀시트에서 `Container`+`BoxDecoration`이 `ListTile`과
  Material 사이에 껴서 "ink splash 안 보일 수 있음" 경고 유발)은
  `lib/features/map/presentation/main_map_screen.dart`에서 `Material`로 감싸도록 수정해 해소함
  (커밋 `8e56b40`).
- **왜 배포 전에 반드시 정리해야 하는가**: 지금은 개발자 1인이 디버그 APK로 단일 기기 테스트 중이라
  발견·수정이 쉬웠지만, 배포 후 사용자가 여러 명이 되면 같은 종류의 프레임워크 경고가 여러 화면·
  여러 기기에서 동시다발적으로 fatal로 잡혀 Crashlytics 대시보드의 크래시프리율 지표가 실제보다
  훨씬 나빠 보이고, 진짜 치명적 버그가 노이즈에 묻혀 놓칠 위험이 있음.
- **배포 전 해야 할 일**:
  1. ✅ (2026-07-20) `flutter build apk --release`로 확인 완료 — release APK를 M32에 설치,
     `_PoiExploreSheet`(당시 미수정 상태)를 열어 칩/리스트타일을 실제로 여러 번 탭해 ink
     splash를 직접 유발시키면서 logcat을 관찰. **release 빌드에서는 이 프레임워크 debug
     경고 자체가 발생하지 않음** (Dart `assert()`가 release 컴파일 시 스트립되는 표준 동작과
     일치) — FlutterError/Crashlytics 관련 로그 전혀 없음, 앱 정상 동작. 근거: 로드맵 위
     "계기" 문단의 157건도 실은 디버그 APK(1.0.1(2)) 테스트 중 발생한 것이었음(사용자가
     "디버그 APK로 단일 기기 테스트 중"이라 명시) — release 배포본에서 이 노이즈가 재현될
     가능성은 낮다는 뜻.
  2. ✅ (2026-07-21) **`recordFlutterFatalError` 유지 확정** — 마스터 결정. release 빌드에서
     debug assert가 스트립되어 오분류 위험 없음, Firebase 공식 권장값과 일치. 코드 변경 없음.
  3. ✅ (2026-07-20) 전수 점검 완료 — `main_map_screen.dart`/`settings_screen.dart` 외
     `lib/features/{profile,tour_summary,auth,navigation}/presentation/` 전체 확인.
     **`main_map_screen.dart` 안에서 3건 추가 발견**: `_AddFavoriteSheet`/`_PlacesSheet`/
     `_PoiExploreSheet` — 전부 `_showTapConfirmSheet`(8e56b40에서 수정된 것)와 동일한
     `Container`+`BoxDecoration`이 `Material`과 `ListTile`/`ChoiceChip`/`IconButton` 사이에
     끼는 패턴. 커밋 `afc6048`로 3건 전부 동일한 `Material` 래핑 방식으로 수정,
     code-auditor PASS, `flutter analyze` 이상없음. 다른 화면(`settings_screen.dart`,
     `favorite_categories_screen.dart`, `profile_screen.dart`, `tour_summary_*`,
     `splash_screen.dart`)은 `Scaffold`/`Card`/`AlertDialog`가 이미 Material 조상을
     제공하는 구조라 문제없음 확인.
  4. ✅ (2026-07-22) Release APK 재빌드(14-C 픽스 포함), M32 설치 후 앱 시작 → logcat 확인.
     FlutterError/Crashlytics 관련 오류 전혀 없음. **Crashlytics 콘솔 측 최종 확인은 마스터가
     직접 Firebase 콘솔(Crashlytics → Issues)에서 최근 fatal 이벤트 없음을 확인할 것** —
     자율 루프에서 웹 콘솔 직접 접근 불가. logcat 근거상 신규 fatal 발생 가능성 낮음.

### 15. POI 데이터소스 자체 호스팅 전환 — DONE (2026-07-15, 발견 당일 해결)

- **발견 경위**: `RIDE_RESULTS_0715.md`의 P0(POI 미표시) 수정을 재빌드·재설치했는데도
  사용자가 재현 보고 → 서비스키로 실 API를 직접 curl 호출해보니 `HTTP 429 "API token quota
  exceeded"` — 빌드 문제가 아니라 개발계정 일일 쿼터(10,000건/일) 소진. 서비스키가 클라이언트
  (APK)에 박혀있어 전 사용자가 쿼터 하나를 공유하는 구조라 실사용자 증가 시 필연적으로
  터지는 스케일링 결함이었음(상세 근거는 `loop/HANDOFF_0715_poi_quota.md` 참조, 문서 자체는
  이제 완료된 작업의 설계 기록으로 보존).
- **해결**: data.go.kr가 실시간 API와 별개로 같은 데이터를 분기별 전국 CSV로도 무료
  배포한다는 걸 확인(로그인 불필요, "이용허락범위 제한없음") — 이 CSV(17개 시도, 2.73M행,
  341MB zip)를 다운로드해 `native/src/bin/ingest_poi.rs`(신규)로 SQLite+R-tree DB에 적재
  (696,255행, 153.6MB, ~12초), `native/src/main.rs`에 `GET /poi/nearby` 엔드포인트 추가.
  카테고리 매핑·업소명 오분류 필터(`협동조합/조합/...`, 카페 슬롯 식당 키워드)는 기존
  Dart `looksMisclassified` 로직을 Rust로 1:1 이관 — 데이터 적재 시점(분기 1회)에 한 번만
  적용되므로 매 요청마다 클라이언트가 필터링할 필요가 없어짐. `lib/services/poi_service.dart`는
  카테고리별 병렬 N회 호출 대신 `navi.westinx.com/poi/nearby` 단일 GET으로 교체,
  `SEMAS_SERVICE_KEY`/`String.fromEnvironment`/`--dart-define-from-file=env.json` 의존성
  완전 제거(`flutter build apk --debug` 플래그 없이 빌드 성공 확인).
- **인프라**: `docker-compose.yml`의 `navi` 서비스에 `/data/poi:/data/poi:ro` 볼륨 마운트
  추가, 실제 컨테이너 재빌드·재기동 후 `/health`·`/poi/nearby`·기존 라우팅 엔드포인트
  전부 라이브 회귀 확인(공개 `navi.westinx.com` 경로 포함). `docker/backup.sh`가 `/data/poi`를
  기존 일일 하드링크 스냅샷에 포함하도록 갱신(실행해서 1.6GB 스냅샷 생성 확인). 분기
  재동기화용 `docker/refresh_poi_data.sh` 신규 작성(다운로드 링크 자동 추출 + 검증 +
  원자적 교체 + 컨테이너 재시작) — **cron 자동 등록은 의도적으로 보류**, 이유와 수동 실행
  후 등록할 crontab 줄은 `docker/INFRA.md` §5 참조. 다음 갱신 예정일 2026-08-01.
- **검증**: `cargo test`(116개) + `flutter analyze`/`flutter test`(145개) 전부 통과,
  code-auditor 2회 PASS(Rust/Flutter 각 1회), Python sqlite3로 R-tree 무결성 및 실제
  공간 쿼리 결과를 Rust 코드와 독립적으로 재검증, 실서버에 배포 후 curl로 종단 확인.
  기존 카테고리 코드 선택(예: G20402 "대형마트"가 항상 빈 코드라는 이전 세션 판단)이
  국가 전체 CSV 행수로도 재확인됨(0건).
- **커밋**: `06adfb5`(Rust 백엔드), `e27f06d`(docker-compose 볼륨), `5b3eecd`(Flutter
  클라이언트), `ce709b8`(백업/재동기화 스크립트/문서).
- 상세 설계 배경은 `loop/HANDOFF_0715_poi_quota.md`, 인프라 운영 절차는
  `docker/INFRA.md` §5 참조.

### 16. 구조물/지오메트리 급커브 카드 UI 신설 — DONE (2026-07-22, 커밋 `27dae87`)

**배경 (2026-07-18, 음성/카드 문구 CSV 검토 세션 중 등록)**: `loop/VOICE_MESSAGES_KO_REVIEW.csv`로
카드/TTS 문구 전수 검토를 하던 중, 다음 두 종류의 이벤트가 **TTS만 있고 화면 카드가 아예
없다**는 게 확인됨 — 사용자가 이번엔 문구 교정만 반영하고 카드 UI 신설은 별도 작업으로
미루기로 결정.

- **구조물 진입(고가도로/터널/지하차도)**: `StructureVoiceEngine`(`voice_engine.dart`)이
  Valhalla maneuver가 아니라 구조물 zone 인덱스/거리 기반으로 독립 동작 — 상단 회전카드
  (`_TurnStep`/`_labelForType`)는 Valhalla maneuver step 목록만 참조하므로 이 이벤트를
  아예 모름. TTS 문구는 이번 세션에 교정 완료(`{dist}미터 앞 고가도로로 진입합니다` 등,
  underpass/tunnel 이벤트 분리 버그도 같이 수정함).
- **지오메트리 감지 급커브**: `CurveVoiceEngine`도 마찬가지로 maneuver가 아닌 shape
  geometry 기반 커브 zone에서 동작 — 교차로에서의 급회전(유형11/14, 카드 있음)과 달리
  코너링 중 지오메트리로만 잡히는 급커브는 카드가 없음.

**완료 (2026-07-22, 커밋 `27dae87`)**:
- `_StructureCurveAlert` 위젯 신설 — `_TurnStep` 파이프라인과 완전히 별개.
  `routeProgressProvider.distToNextStructureM`/`distToNextCurveM` 구독.
- 구조물 500m, 급커브 400m 임계값 (안전 우선 원칙, 넉넉하게).
- 급커브 라벨 "급커브 좌/우" — "회전" 표현 사용 안 함.
- `flutter analyze` PASS, code-auditor PASS, M32 debug APK 설치 확인.
- vGPS E2E 하네스(실제 구조물 구간 재생): 이번 세션에서 미실행 — 신규 CSV 생성
  파이프라인 30분+ 소요, 기존 REPORT_structure_turnangle_vgps_verify.md에서 동일
  `distToNextStructureM` 필드가 500m/300m에서 TTS 정확히 발화함이 이미 실증됨.
  마스터 다음 라이딩 때 실기기에서 배지가 실제로 뜨는지 확인 권장.
2. `RouteProgress`(`route_progress_provider.dart`)가 이미 `distToNextStructureM`/
   `distToNextCurveM`/`nextStructureType`/`nextCurveDirection`을 들고 있으므로(구조물
   TTS가 이미 이 필드로 동작 중) 신규 위젯은 이 provider를 그대로 재사용하면 됨 — 새
   데이터 소스 필요 없음.
3. 카드 문구는 `VOICE_MESSAGES_KO_REVIEW.csv`의 "고가도로"/"터널"/"지하차도" 행,
   `sharp_turn_left/right`의 "코너링 중 지오메트리로만 감지된 급커브도 표시할 것" 비고
   참고.

**선행조건 없음** — 12번(백엔드) 완료 상태라 바로 착수 가능. 디자인 트랙(7~11번) 확정 전
이라도 순수 기능이므로 진행 가능(단, 새 위젯이라 11번 스윕 대상에 포함시킬 것).

---

### 17. 경유지 관리 UI (투어링 라이더용) — DONE (2026-07-22, Phase 0~4)

**상태**: DONE (2026-07-22)

**브랜치**: `verify/ride-0711`

**배경**: 투어링 라이더는 경로 자체가 목적. 경유지를 자유롭게 추가·삭제·순서변경하고
출발지도 임의 장소로 설정할 수 있어야 함. 참조 UI: 네이버지도 경유지 편집 화면.

### Phase 0 — stops 통합 아키텍처 마이그레이션 (커밋 `08e0e94`)
- `lib/features/map/models/route_stop.dart` 신규: `RouteStop(latLng, name, isCurrentLocation)`
- `MapInteractionState.stops: List<RouteStop>` 통합 리스트 (`[출발지, 경유지..., 도착지]`)
- 기존 `destination`, `waypoints`, `waypointNames` → 계산 getter로 전환 (호출부 호환 유지)
- `reorderStop(oldIdx, newIdx)` 신규 메서드 + ReorderableListView 인덱스 보정 포함
- `setDestination(snapshotOrigin:)` 파라미터 추가 — GPS 스냅샷 저장
- `flutter analyze` PASS, code-auditor PASS

### Phase 1 — 경유지 포인터 숫자 표시 (커밋 `bb4b3ee`)
- `_syncWaypointMarkers()`: textField = 순서 번호(1,2,3), 흰색, 포인터 원 중앙 오프셋(-2.1)
- `flutter analyze` PASS

### Phase 2 — WaypointManagementSheet (커밋 `26e5c4a`)
- `lib/features/map/presentation/waypoint_management_sheet.dart` 신규
- `DraggableScrollableSheet` (60%/90%/40%) + `ReorderableListView`
- reorder/remove 후 즉시 `RoutingService.fetchRoutes` 재호출 + `mounted` guard
- 출발지(파랑)/경유지(회색·삭제가능)/도착지(빨강) 아이콘 구분
- code-auditor PASS (mounted 누락 버그 수정 포함)

### Phase 3 — 검색 결과 출발지/경유지/목적지 선택 (커밋 `f6b021c`)
- 주소 검색 탭 시 `_AddToRouteSheet("어디로 추가할까요?")` showModalBottomSheet
- `setOrigin()` notifier 메서드 추가
- 경유지 옵션은 destination 설정 후 활성화
- `flutter analyze` PASS, code-auditor PASS

### Phase 4 — 코스 시트 진입점 UI (커밋 `43b5c31`)
- `CourseSheet`에 `waypointCount`/`onWaypointEntryTap` 파라미터 추가 (optional, nav_screen 호환)
- 경유지 있으면 `ActionChip "경유지 N개·편집"`, 없으면 `TextButton "+ 경유지 추가"`
- 탭 시 `WaypointManagementSheet` showModalBottomSheet (isScrollControlled: true)
- `flutter analyze` PASS, code-auditor PASS

### 미완료/알려진 한계
- textOffset(-2.1) 미세조정: 실기기에서 pointer_yellow 아이콘 크기 확인 후 조정 필요
- Phase 5 (수익화 스캐폴딩)은 8번(브랜드 방향성) 확정 후 별도 착수
- 지도 우측 컨트롤 패널 경유지 뱃지는 미구현 (코스 시트 진입점으로 충분)

---

## 18번 — 후면단속카메라 안내

**상태**: 계획 완료, Phase 0 착수 대기 (공공데이터 다운로드 필요)

**배경**: 오토바이는 앞번호판 없어 후면카메라에만 잡힘. 투어링 중 과태료 방지.

**데이터**: 공공데이터포털 경찰청 무인교통단속카메라 현황
(https://www.data.go.kr/data/15028200/standard.do) — 후면단속 유형만 필터

**핸드오프**: `loop/HANDOFF_0724_rear_camera.md`

**Phase 구성**:
- Phase 0: 공공데이터 CSV 다운로드 → 후면단속 필터 → `assets/data/rear_cameras.json`
- Phase 1: Flutter asset 로더 + `RouteProgress` 탐지 엔진 (GPS 하버사인 + 방향 필터)
- Phase 2: 사이버포뮬러 스타일 원형 호 게이지 UI (500m→0m 색상 변화, "단속중" 맥박)
- Phase 3: TTS 안내 (500m/300m/100m/진입 시)

**선행 조건**: Phase 0 — 공공데이터 파일 마스터가 직접 다운로드 후 프로젝트에 배치
(data.go.kr 로그인 필요할 수 있음)

---

## 19번 — 실시간 최저가 주유소 안내

**상태**: API 키 발급 대기 중 (착수 불가)

**데이터**: 한국석유공사 오피넷 API (공공데이터포털)

**진입점**: 내비 화면 "주유소 찾기" 버튼 + 지도 검색창 "주유소" 버튼

**범위**: 현위치 반경 5km / 유종: 휘발유·고급휘발유 (설정 페이지에서 선택)

**아키텍처**: API 키 노출 방지 → navi 서버(Rust) 프록시 경유

**선행 조건**: 오피넷 API 키 발급 완료 후 착수

---

## 세션 프로토콜
- 새 세션 시작 시: 이 파일 먼저 읽고 상태 요약표에서 다음 항목 확인
- 착수 시: 상태 IN_PROGRESS + 체크포인트 커밋
- 완료 시: 상태 DONE + 커밋 해시 기록 + analyze/test PASS 여부 기록
- 막히면: 상태 BLOCKED + 사유, 추측으로 진행 금지
