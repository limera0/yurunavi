# 유루나비 릴리스 준비 + 디자인 시스템 로드맵 (마스터 트래커)

**이 문서의 역할**: 2026-07-11 세션에서 확정된 13개 과제의 진행 상황을 세션 간에 공유하는
단일 소스. 새 세션(특히 11/12/13번, 8~10번 디자인 병합 세션)을 시작하는 Claude는 이 문서를
**가장 먼저 읽고** 다음 TODO 항목과 선행조건을 확인할 것. 항목 착수 시 상태를 IN_PROGRESS로,
완료 시 DONE + 커밋 해시로 갱신한다. 막히면 BLOCKED + 사유 기록 후 다음 세션에 인계
(CLAUDE.md 원칙: 불확실하면 추측 대신 기록하고 멈춤).

이 문서는 `loop/BACKLOG.md`(T1/T2/T3 라이딩 검증 루프 전용)와 별개다 — 이건 일회성 릴리스
하드닝 + 디자인 아키텍처 작업이라 트랙을 분리했다.

원본 트리아지 근거: 이 대화 세션 앞부분의 특급/1급/2급/3급/4급 분류 참조.

## 진행 순서 (사용자 확정, 2026-07-11)

```
1~7 (이번 세션, 순서 무관·병렬 가능)
        │
8~10 (디자인 검토용 별도 세션 — 사용자가 시간 두고 검토 후 병합)
        │
       11 (별도 세션)
        │
       12 (별도 세션)
        │
       13 (별도 세션)
```

11번부터는 각 번호가 독립된 새 세션에서 실행된다.

## 상태 요약

| # | 과제 | 등급 | 상태 |
|---|------|------|------|
| 1 | applicationId 변경 (com.example → com.westinx.yurunavi) | 특급 | **DONE** |
| 2 | release keystore 생성 + signingConfig 연결 | 특급 | **DONE** |
| 3 | OSM attribution 표시 추가 | 1급 | **DONE** |
| 4 | ProGuard/R8 활성화 | 1급 | **DONE** |
| 5 | Crash reporting 연동 (Firebase Crashlytics 선택됨) | 1급 | **PARTIAL** — 코드 배선 준비 완료, Firebase 콘솔 작업(사용자) 대기 |
| 6 | 개인정보처리방침 초안 + 호스팅 | 1급 | **PARTIAL** — 법률 검토 반영 완료, 위치기반서비스사업 신고(사용자 액션) 대기 |
| 7 | 디자인 토큰 아키텍처 뼈대 | 신규(1급) | **DONE** |
| 8 | 브랜드 방향성 확정 (컬러/타이포/무드) | 신규 | DEFERRED — 별도 세션(디자인 검토) |
| 9 | 앱 아이콘 확정 | 신규 | DEFERRED — 8번 이후 |
| 10 | 실제 release build 1회 실행·검증(설치/크기 포함) | 1급 | DEFERRED — 8~10 묶음으로 진행 |
| 11 | 하드코딩 스타일 → 토큰 기반 전면 리팩터 | 신규(1급/2급) | BLOCKED — 선행: 7+8 완료 |
| 12 | 백엔드 인프라 IaC화 (타일서버·navi 백엔드 docker화, 모니터링/백업) | 특급 | BLOCKED — 1~7 이후 |
| 13 | 기능 갭 해소 (로그인, 투어 요약, POI, 백그라운드 내비, 설정 Phase2) | 2급 | BLOCKED — 12번 이후 |

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

### 5. Crash reporting 연동 — PARTIAL
- 사용자 결정: **Firebase Crashlytics** (Sentry 대신 선택됨, 2026-07-11).
- 완료: `pubspec.yaml`에 `firebase_core: ^4.11.0`, `firebase_crashlytics: ^5.2.4` 추가.
  `lib/core/crash_reporting.dart` 신규 — `initCrashReporting(FirebaseOptions options)`
  함수 준비(호출부는 아직 연결 안 함, dormant). `lib/main.dart`의 `main()`에 정확한
  연결 지점을 가리키는 TODO 주석만 추가 — **실제 호출은 걸지 않음**(Firebase 프로젝트
  없이 호출하면 앱이 즉시 크래시하므로 의도적으로 비활성 상태 유지).
  Android Gradle 쪽(Google Services 플러그인)은 아직 손대지 않음 —
  `google-services.json` 없이 적용하면 빌드가 깨짐.
- **검증**: `flutter analyze`(0 issues) / `flutter build apk --debug`+`--release`(둘 다 성공)
  / `flutter test`(96/96) — 전부 이 상태로 그린 확인됨.
- **⚠️ 남은 사용자 액션 (3단계)**:
  1. Firebase 콘솔에서 프로젝트 생성 → Android 앱 등록(패키지명 `com.westinx.yurunavi`)
     → `google-services.json` 다운로드 → `android/app/google-services.json`에 배치
  2. `flutterfire configure` 실행(Firebase CLI 로그인 필요) 또는 수동으로
     `lib/firebase_options.dart` 작성
  3. (다음 세션에서) `android/build.gradle.kts` + `android/app/build.gradle.kts`에
     Google Services Gradle 플러그인 추가, `main.dart`의 TODO 지점에
     `await initCrashReporting(DefaultFirebaseOptions.currentPlatform);` 연결

### 6. 개인정보처리방침 초안 + 호스팅 — PARTIAL
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

### 9. 앱 아이콘 확정
- 8번 확정 후 진행.

### 10. 실제 release build 검증
- `flutter build apk --release` (또는 `appbundle`) 실행, 설치, 크기/동작 확인.
- 8~10 묶음으로 진행하기로 사용자가 결정했으나, **1/2/4가 끝나면 기술적으로는 언제든
  당겨서 해도 무방** — 다음 세션 판단에 맡김 (디자인 자산 없이도 서명/난독화만
  검증 가능하므로).

### 11. 하드코딩 스타일 → 토큰 기반 전면 리팩터
- 선행조건: 7번(뼈대) + 8번(팔레트 확정) 완료. 기존 `lib/features/*` 전 화면의
  하드코딩된 `Colors.*`/`TextStyle` 리터럴을 7번 토큰 참조로 교체.
- 규모가 커서 여러 커밋으로 분할 예정 (착수 세션에서 계획 수립).

### 12. 백엔드 인프라 IaC화
- 목표: 타일서버(tileserver-gl)와 `navi.westinx.com` 백엔드를 `docker/` 안에
  Dockerfile/compose로 재현 가능하게 만들기. 현재 `docker/docker-compose.yml`엔
  valhalla만 있음 — 나머지 두 서비스는 이 리포에 설정이 전혀 없어 서버 소실 시
  복구 불가능한 상태 (특급 등급 근거).
- 추가로 고려: TLS 인증서 자동갱신, 헬스체크/모니터링, 백업.

### 13. 기능 갭 해소
- 로그인/회원가입, 투어 요약(주행 이력), POI 탐색 UI, 백그라운드/오버레이 내비게이션,
  설정 Phase 2. 착수 세션에서 세부 항목 순서 재분류 필요 (범위가 넓음).

## 세션 프로토콜
- 새 세션 시작 시: 이 파일 먼저 읽고 상태 요약표에서 다음 항목 확인
- 착수 시: 상태 IN_PROGRESS + 체크포인트 커밋
- 완료 시: 상태 DONE + 커밋 해시 기록 + analyze/test PASS 여부 기록
- 막히면: 상태 BLOCKED + 사유, 추측으로 진행 금지
