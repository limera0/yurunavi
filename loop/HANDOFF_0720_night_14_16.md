# 2026-07-20 야간 작업 — 14번(Crashlytics 감사) → 16번(구조물/급커브 카드 UI)

마스터가 12시간(출근) 부재 동안 자율 진행을 승인함(오늘 낮 세션). M32 실기기는 책상에
adb 연결 유지된 채로 대기 중(디바이스 `RZ8RC1N3V9W`) — 실기기 검증 가능.

**단일 소스**: `loop/RELEASE_ROADMAP.md`가 마스터 트래커다. 이 작업 완료/중단 시
그 파일의 14번/16번 항목 상태(TODO → DONE/PARTIAL/BLOCKED)와 커밋 해시도 같이 갱신할 것
— 이 HANDOFF 파일만 갱신하고 로드맵을 안 건드리면 다음 세션이 최신 상태를 놓친다.

## 순서
1. **14번 먼저** (배포 전 필수, 아래 A~D)
2. 14번 끝나면 **16번** (아래 E~H)

둘 다 하룻밤에 안 끝나도 무방 — 각자 체크포인트 단위로 커밋하고 다음 밤에 이어가면 됨.
CLAUDE.md 프로토콜대로 서브태스크 시작 전 체크포인트 커밋, code-auditor PASS 후 커밋,
감사 최대 3회 반복.

## 14번 상세 — Crashlytics fatal 오분류 전수 감사

배경: `lib/core/crash_reporting.dart:18`의
`FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;` 배선 때문에
Flutter 프레임워크의 non-fatal debug 경고까지 fatal로 잘못 기록되는 문제가 2026-07-13에
1건 발견·수정됐다(`main_map_screen.dart`, 커밋 `8e56b40`). 지금 사용자가 1인 디버그 테스트
중이라 우연히 발견됐을 뿐, 배포 후 여러 사용자·여러 기기에서 같은 유형이 동시다발로
fatal로 잡히면 크래시프리율 지표가 실제보다 나빠 보이고 진짜 버그가 노이즈에 묻힌다.

A. `flutter build apk --release` 빌드해서 **release 모드에서도** 프레임워크 debug 경고가
   `FlutterError.onError`를 타는지, 아니면 release에선(assert 스트립 등으로) 애초에
   발생 자체가 없는지 직접 확인해라. 추측 금지 — release APK를 M32에 설치해서 2026-07-13에
   고쳤던 것과 같은 유형의 시나리오(지도 탭 확인 바텀시트 등)를 재현해보고 adb
   logcat/Crashlytics 콘솔로 실제로 확인해라.
B. A의 결과에 따라 `recordFlutterFatalError`를 그대로 둘지, non-fatal인
   `recordFlutterError`로 완화할지 판단해서 반영해라. **이건 정책 판단이라 애매하면
   결정하지 말고 BLOCKED로 기록하고 마스터에게 넘겨라** — 추측으로 밀어붙이지 마라.
C. 2026-07-13에 고친 것과 같은 유형(색깔 있는 `Container`/`BoxDecoration`이 `Material`과
   `ListTile` 사이에 끼어 "ink splash 안 보일 수 있음" 경고가 나는 패턴, 커밋 `8e56b40`의
   `main_map_screen.dart` 수정 참고)이 다른 화면에도 남아있는지 `lib/features/*/presentation/`
   전수 점검. `settings_screen.dart` 포함해서 훑을 것.
D. release 빌드로 주요 화면(지도 열기 → POI 검색 → 내비 시작 → 설정 진입 등) 순회하며
   Crashlytics에 fatal 이벤트가 뜨는지 최종 확인.

## 16번 상세 — 구조물/지오메트리 급커브 카드 UI 신설

배경: 고가도로/터널/지하차도 진입과 지오메트리 급커브 이벤트가 TTS는 있는데 화면 카드가
아예 없다(2026-07-18 발견, `loop/VOICE_MESSAGES_KO_REVIEW.csv` 검토 세션). 선행조건 없음
— 12번(백엔드) 완료 상태라 바로 착수 가능. 8~11번(디자인 토큰 확정) 전이라도 순수 기능이라
진행 가능(다만 새 위젯이니 나중에 11번 스윕 대상에 포함되도록 표시는 해둘 것).

E. `nav_screen.dart`에 기존 상단 회전카드(`_TurnStep`/`_labelForType`, Valhalla maneuver
   step 목록만 참조)와는 **완전히 별개인** 신규 위젯을 설계해라. 기존 회전카드 파이프라인에
   억지로 끼워넣지 마라 — 회전카드는 "다음 turn maneuver 하나"만 가정하는 구조라
   구조물/커브 zone과 개념이 안 맞는다.
F. 데이터 소스는 새로 만들 필요 없음 — `route_progress_provider.dart`의 `RouteProgress`가
   이미 `distToNextStructureM`/`nextStructureType`/`distToNextCurveM`/`nextCurveDirection`
   필드를 들고 있다(구조물 TTS가 이미 이 필드로 동작 중, 확인 완료). 이 provider를
   그대로 구독해라.
G. 카드 문구는 `loop/VOICE_MESSAGES_KO_REVIEW.csv`의 "고가도로"/"터널"/"지하차도" 행과
   `sharp_turn_left`/`sharp_turn_right`의 "코너링 중 지오메트리로만 감지된 급커브도
   표시할 것" 비고를 참고해라. 실제 회전이 아닌 이벤트에 "회전" 표현 쓰지 말 것, 안전
   관련 임계값·표시 타이밍은 좁게 잡지 말고 넉넉하게(사용자가 이미 여러 번 확인해준
   원칙 — 애매하면 넓게 잡는 쪽으로 판단해라).
H. 검증: `flutter analyze`/`flutter test` 통과 + 가능하면 M32에 debug APK 설치 후 vGPS
   하네스로 구조물/급커브 구간이 포함된 경로를 재생해서 카드가 실제로 뜨는지 확인해라.

## 실기기 검증 시 필수 — vGPS 하네스만 사용, 절대 손으로 GPS 모킹 만지지 마라

M32가 밤새 연결돼 있다고 adb로 GPS 좌표를 직접 주무르지 마라. 반드시 기존 E2E 자동주행
하네스(gpsinjector, GPS/NETWORK/FUSED 3-provider 동시 모킹)를 써라 — 3개 provider를 같이
안 잡으면 60~100초마다 위치 데이터가 오염된다. 하네스 사용 예시는
`loop/REPORT_reroute_heading_vgps_verify.md`, `loop/REPORT_structure_turnangle_vgps_verify.md`,
`loop/feedback/VGPS_BGNAV_PHASE_A_0717.md`류를 먼저 읽고 그대로 재사용해라(새로 만들지 말 것).

## 완료 후
- `loop/RELEASE_ROADMAP.md`의 14번/16번 항목 상태 갱신(TODO → DONE/PARTIAL/BLOCKED) +
  커밋 해시 기록.
- 마지막 틱에서 `loop/MORNING_REPORT_0721_night.md`(또는 실제 종료 날짜 기준 파일명)
  작성 — 코드 못 읽는 사람 기준으로, 뭐가 됐고 뭐가 막혔는지, 검증 방법(커밋 해시/실행법)
  포함.

## 건드리지 말 것
- 8~11번(디자인 토큰/팔레트 확정, 하드코딩 리팩터) 관련 화면 작업은 스코프 밖.
- 13-4/13-7/13-8 등 이 두 항목(14, 16) 외 다른 로드맵 항목은 건드리지 마라.
- `git push` 금지(하드룰, 재확인 — origin에도 백업 remote 아닌 곳에도 push 안 함).
- 워킹트리에 이미 있는 기존 미커밋/미추적 변경들(CLAUDE.md, 각종 RECON_*/HANDOFF_* 등)은
  이 밤 작업 스코프 밖이니 별도 지시 없이 건드리지 마라.
