# 유루나비 릴리스 준비 + 디자인 시스템 로드맵 (마스터 트래커)

**이 문서의 역할**: 2026-07-11 세션에서 확정된 13개 과제의 진행 상황을 세션 간에 공유하는
단일 소스. 새 세션(특히 11/12/13번, 8~10번 디자인 병합 세션)을 시작하는 Claude는 이 문서를
**가장 먼저 읽고** 다음 TODO 항목과 선행조건을 확인할 것. 항목 착수 시 상태를 IN_PROGRESS로,
완료 시 DONE + 커밋 해시로 갱신한다. 막히면 BLOCKED + 사유 기록 후 다음 세션에 인계
(CLAUDE.md 원칙: 불확실하면 추측 대신 기록하고 멈춤).

이 문서는 `loop/BACKLOG.md`(T1/T2/T3 라이딩 검증 루프 전용)와 별개다 — 이건 일회성 릴리스
하드닝 + 디자인 아키텍처 작업이라 트랙을 분리했다.

원본 트리아지 근거: 이 대화 세션 앞부분의 특급/1급/2급/3급/4급 분류 참조.

## 현재 상태 (다음 세션 시작점)

- **⚠️ 2026-07-12 업데이트**: 이 문서(13번 트랙)와 별개로 `loop/`에 T1/T2/T3 라이딩 검증
  전용 트랙(`loop/BACKLOG.md` + `HANDOFF_*`/`MORNING_REPORT_*`/`NIGHT_TASK_*` 체인)이 병렬로
  돌고 있는데, **같은 `verify/ride-0711` 브랜치를 공유**한다. 그쪽 트랙의 "§3.4 POI(소상공인
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
| 11 | 하드코딩 스타일 → 토큰 기반 전면 리팩터 | 신규(1급/2급) | BLOCKED — 선행: 7+8 완료 |
| 12 | 백엔드 인프라 IaC화 (타일서버·navi 백엔드 docker화, 모니터링/백업) | 특급 | **DONE** |
| 13 | 기능 갭 해소 (로그인, 투어 요약, POI, 백그라운드 내비, 설정 Phase2) | 2급 | **IN_PROGRESS** — 8개 하위항목으로 분해(아래). 13-1 DONE(`2d91e4d`), 13-2부터 진행 |

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

### 13. 기능 갭 해소

**2026-07-11 착수 전 코드 조사 결과** (원래 이름만 나열되어 있던 5개 기능을 실제 코드
상태 기준으로 재조사 → 8개 하위 항목으로 분해 + 재우선순위화):

- **로그인/회원가입**: `lib/features/auth/`엔 `splash_screen.dart` 하나뿐, 실제 로그인/
  회원가입 UI 없음. `pubspec.yaml`에 `firebase_auth` 패키지조차 없음(현재 `firebase_core`/
  `firebase_crashlytics`만 존재). **더 중요한 발견**: 현재 앱에 계정으로 게이팅되는 기능이
  전혀 없음 — 프로필(`profile_service.dart`)/즐겨찾기·최근장소(`places_service.dart`)/
  저장경로(`route_service.dart`) 전부 `shared_preferences` 로컬 저장뿐, 클라우드 동기화
  자체가 없음. 즉 로그인을 지금 만들어도 연결할 데가 없음.
- **투어 요약(주행 이력)**: 데이터 모델·저장·화면 **전부 0%** — 관련 파일 자체가 없음
  (CLAUDE.md가 언급하는 `tour_summary` 모듈은 애초에 생성된 적 없음, [[project_yurunavi]]
  참조). 로그인 없이 로컬 저장(`shared_preferences` 또는 파일)만으로 1차 MVP 가능.
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
| 13-2 | 설정: 약관/오픈소스 라이선스 화면 | 완전 독립, 정적 화면, 스토어 컴플라이언스 | TODO |
| 13-3 | 투어 요약(주행 이력) 로컬 MVP | 로그인 불필요, 데이터모델부터 신규 구축 | TODO |
| 13-4 | 설정: 도로 선호도 / 내비뷰 설정 | 착수 시 Valhalla costing 옵션 재조사 필요 | TODO |
| 13-5 | 백그라운드/오버레이 내비게이션 | 네이티브 포그라운드 서비스+알림, 리스크 최고. **`loop/` 야간루프 트랙의 §3.6과 동일 항목** — 그쪽도 "가장 무거움, 단독 세션 권장"으로 이미 표시돼 있음(`MORNING_REPORT_0711_night2.md`). 착수 시 두 트랙 다 여기 하나로 처리하고 양쪽에 완료 기록할 것, 중복 작업 금지 | TODO |
| 13-6 | 로그인/회원가입 | 게이팅할 기능 없음 — 13-3 이후 "클라우드 동기화 필요" 시점에 재평가 | TODO |
| 13-7 | 설정: 다크모드 | 11번(팔레트 확정 후 토큰 리팩터)과 병합 권장, 여기서 별도로 안 함 | DEFERRED → 11번에 흡수 |
| 13-8 | 설정: 지도 다운로드(오프라인 지도) | 타일 저장/용량 관리 — 12번(인프라) 성격에 더 가까움 | DEFERRED → 12번 후속 과제로 재분류 검토 |

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
- **⚠️ 여전히 실기기 육안 확인 못함**(헤드리스 서버) — 다음에 `adb install` 후 줌 레벨별로
  카테고리가 순서대로 나타나는지, 10개 컷이 실제로 걸리는지, 홈/내비 화면 둘 다 확인 필요.
- 다음 세션: 13-2(설정: 약관/오픈소스 라이선스 화면)부터 이어가면 됨.

## 세션 프로토콜
- 새 세션 시작 시: 이 파일 먼저 읽고 상태 요약표에서 다음 항목 확인
- 착수 시: 상태 IN_PROGRESS + 체크포인트 커밋
- 완료 시: 상태 DONE + 커밋 해시 기록 + analyze/test PASS 여부 기록
- 막히면: 상태 BLOCKED + 사유, 추측으로 진행 금지
