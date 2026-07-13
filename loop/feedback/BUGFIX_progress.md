# 실주행 피드백 버그 수정 진행 상황 (2026-07-12 시작, 2026-07-13 세션에서 이어감)

이 세션에서도 API 에러(ECONNRESET)로 재차 끊길 가능성 있어 여기 기록하며 진행.
**16장 PNG 분석은 완료됨** (`ANALYSIS_progress.md` 참조).

## ⚠️ 2026-07-14 업데이트: 실주행 검증 결과는 `RIDE_RESULTS_0714.md` 참조

2026-07-13 밤 배포 빌드(`61de570`)로 실제 라이딩 테스트 완료. 17개 체크리스트
항목 결과 + 신규 발견 4건(경유지 재포함, 급커브 안내 누락, 고가/터널 안내,
재탐색 시 3코스 미표시) 전부 `loop/feedback/RIDE_RESULTS_0714.md`에 우선순위별
계획으로 정리됨. 다음 세션은 이 문서부터 읽을 것 — 아래 내용은 그 이전(07-13)
상태 기록이라 일부 stale(특히 2번 Y자 삼거리는 이번엔 재현 근거 없음으로 결론).

## ▶ 다음 세션 시작점 (2026-07-13 세션 계속, Y자 삼거리(2번) 확진·수정 완료 시점)

**상태**: 1,3,4,5,6,7,8,9,10번 전부 완료·커밋됨. **2번(Y자 삼거리 좌회전 오안내)도
이번 세션에 근본원인 확진 + 수정 완료·커밋됨(`4625048`)** — 상세는 아래 "완료: 2." 섹션
참조. `RELEASE_ROADMAP.md` 13-2(설정: 약관/오픈소스 라이선스 화면)도 이번 세션에 완료
(`9393af3`). **이 피드백 버그픽스 트랙에서 남은 항목은 유턴/스위치백 costing 튜닝
(슬라이드11) 하나뿐**이며 이것도 사용자가 명시적으로 보류 결정한 항목 — 먼저 꺼내지
말 것. 다음 세션은 `loop/RELEASE_ROADMAP.md` 13-3(투어 요약 로컬 MVP)으로 진행하거나,
유턴/스위치백 costing을 사용자가 먼저 꺼내면 그쪽부터. 이 문서 하나만 읽으면 전체 맥락
파악 가능 — `ANALYSIS_progress.md`(슬라이드 원본 분석)는 필요할 때만 참조.

**놓치면 안 되는 것**:
- 실기기 테스트 인프라가 이번에 갖춰짐 — westinx 서버에 Galaxy M32F가 상시 USB 연결되어
  있음(`adb -s RZ8RC1N3V9W ...`), Claude 전용 테스트 폰. 상세 사용법(udev 설정 완료
  상태, 좌표 계산 시 픽셀 스캔 권장 등)은 메모리([[project_yurunavi]])에 기록됨. **단,
  이 폰은 실주행 테스트에 쓰는 Galaxy A34와 다른 기기** — A34는 사용자가 상시 휴대,
  이 서버엔 연결 안 됨. M32F에서 확인한 사실을 A34에서도 참일 거라 넘겨짚지 말 것.
- 새 debug APK(`0ab27b2`~최신 커밋까지 전부 포함)가 있음 — 사용자가 A34에 접근 가능해지면
  **기존 앱 완전 삭제 후 이 최신 코드로 재빌드한 APK 재설치**해서 1번(마트/카페 칩 고정)
  재테스트 필요(아직 A34에서 미확진 상태, 아래 "재확인 결과 2차" 섹션 참조). 이번 세션의
  실기기 테스트는 전부 이 재설치 이후 한 번에 일괄 진행 예정(사용자 지시).
- 유턴/스위치백 costing 튜닝(슬라이드11)은 사용자가 명시적으로 미룸 — 먼저 꺼내지 말 것.
- `main_map_screen.dart`, `nav_screen.dart` 둘 다 `dart format` 기준과 스타일이 어긋나
  있는 상태(포맷팅 부채) — 이 파일들 편집 시 절대 파일 전체에 `dart format` 돌리지 말 것
  (무관한 대량 diff 발생 사고 이미 한 번 있었음, 수동으로 변경분만 정리할 것).

## 완료된 작업

### 1. 카테고리 필터링 버그 — 수정 완료, 커밋됨 (`0ab27b2`)
`_PoiExploreSheet`의 `_effectiveTypes` getter가 `_selectedTypes`를 참조로 반환해서
`_fetchedTypes`와 앨리어싱되던 버그. `Set<PoiType>.from(_selectedTypes)`로 방어적 복사.
code-auditor PASS, analyze 0 issues, test 96/96, debug APK 빌드 성공. 사용자가 실기기에서
정확한 트리거 시퀀스(칩A선택→해제→칩B선택 시 리스트가 칩A에 고정)로 재현 확인한 뒤 수정.
**사용자가 새 빌드로 재테스트 필요 — 아직 확인 못 받음.**

남은 별개 이슈(이 수정과 무관, 미해결):
- 카페 칩에 비카페 결과(할매국물닭발 등) 혼입 — 원인 미상, 별도 조사 필요
- "전통시장/대형마트" 구버전 칩셋 등장 — 여전히 미스터리, 코드에 해당 문자열 없음
- 번화가 10개 제한 — 검색시트 리스트는 애초에 제한이 없었을 수 있음(재확인 필요)

## 완료: 2. Y자 삼거리 좌회전 오안내 (슬라이드16) — 근본원인 확진, 수정 완료·커밋됨 (`4625048`)

좌표 (37.07016, 127.04945). 실제로는 우측(서정로, 직진처럼 보이는 완만한 각도)이 도로명
유지, 좌측(서정북로)이 더 큰 각도로 분기하는 갈림길인데, 앱이 좌회전(좌측/서정북로) 상황
에서 "직진입니다. 차선을 유지하세요" 오안내.

**2026-07-13 세션에서 확진**: 아래 "진행 중" 조사(보류됐던 라이브 API 조사)를 이어서
막혔던 지점(Overpass 406, 분기 전후 좌표 부재)을 둘 다 해소하고 실제 Valhalla maneuver를
직접 확인함.
- **Overpass 406 원인 규명**: curl 8.5의 기본 `Accept-Encoding`(zstd 포함)을
  overpass-api.de의 Apache가 content-negotiation 실패로 거부하던 것 — `-H
  "Accept-Encoding: identity"` 추가로 즉시 해결. 이걸로 서정로/서정북로 way geometry를
  전부 확보(way `111353656`=서정로 계속, way `486298549`=서정북로 분기, 공유 분기 노드
  `37.0703321, 127.0492441` — 사용자가 보고한 좌표와 오차 ~19m, 동일 교차로로 판단).
- **로컬 Valhalla(`localhost:8002`)에 분기 전/후 실좌표로 `/route` 직접 요청** 결과:
  - 서정북로(좌측 분기) 도착 목적지 → **`type=24, "Keep left to take 서정북로"`**
  - 서정로(직진처럼 보이는 쪽) 도착 목적지 → **`type=23, "Keep right to stay on 서정로"`**
  - 즉 이 Y자 분기는 Valhalla가 **정확하게** "회전"이 아니라 "keep"(유지) 계열로 분류하고
    있었음 — 서버(Valhalla)가 틀린 게 아니라 실제로 얕은 각도의 Y자 삼거리였음(직접
    bearing 계산으로도 확인: 두 분기 모두 진입 방향 대비 ±10° 이내로 시작해서 이후
    100~200m 구간에 걸쳐 서서히 벌어짐 — 교과서적인 "회전"이라기보단 진짜 Y자형).
- **진짜 버그 지점 특정**: 화살표 카드(`nav_screen.dart`의 `_iconForType`/라벨 switch,
  L1789-1822)는 이미 type 23→우측유지 아이콘/‘우측 유지’, type 24→좌측유지 아이콘/‘좌측
  유지’로 **정확히 좌우를 구분**하고 있었음. 그런데 **음성**(`voice_engine.dart`의
  `eventForType`)만 type 22/23/24를 **전부 `'keep'` 이벤트 하나로 뭉개서** 음성팩
  템플릿 `"차선 유지"`(방향 정보 전무) 하나로 통일해버리고 있었음 — 사용자가 좌측
  (서정북로)으로 가야 할 때도 음성은 그냥 "차선 유지"만 나와서 방향이 통째로 빠짐. 이게
  실제 오안내의 정체. (참고로 기존 `test/voice_engine_continue_test.dart`의 테스트 주석도
  type23/24 좌우가 뒤바뀌어 적혀 있었음 — 이 혼동이 코드베이스 안에 이미 잠재해 있었다는
  방증.)

**수정** (`lib/features/navigation/voice_engine.dart`,
`assets/voice_packs/default_ko.json`, `assets/config/guidance_profile.json`,
`lib/features/navigation/guidance_profile.dart`, `test/voice_engine_continue_test.dart`):
`keep` 이벤트를 `turn_left`/`turn_right`와 동일한 패턴으로 방향별 분리 — type 22
(kStayStraight, 무방향)는 기존 `keep` 그대로, type 23(kStayRight)은 신규 `keep_right`,
type 24(kStayLeft)는 신규 `keep_left`. 신규 음성 템플�트: `keep_right_imminent`="오른쪽
차선을 유지하세요", `keep_left_imminent`="왼쪽 차선을 유지하세요"(approach 버전 포함).
`guidance_profile.json`에 두 이벤트 `enabled:true` 추가, Dart `_fallback` 프로필에도 동일
반영. code-auditor PASS(type→방향 매핑을 `nav_screen.dart`/`loop/RECON_guidance_engine.md`
enum 참조 두 곳과 교차검증, `GuidanceProfile.load()`가 새 JSON 키를 별도 처리 없이
`enabledEvents`로 흘려보내는 것 확인, 테스트가 진짜로 새 키를 검증하는지 확인).
`flutter analyze` 0 issues, `flutter test` 103/103, `flutter build apk --debug
--dart-define-from-file=env.json` 빌드 성공.

- **⚠️ 미확인 상태로 남은 것**: 방향 정보가 음성에 포함되게 만드는 것까지는 확진된
  원인에 대한 직접 수정이지만, 실제 라이딩 중 "왼쪽 차선을 유지하세요"가 사용자에게
  충분히 명확하게 들리는지(예: "좌회전"만큼 즉각적으로 이해되는지)는 headless 서버라
  실기기 확인 못함. **다음 라이딩(특히 서정로/서정북로 동일 지점 재방문 가능하면 최적)
  에서 확인 필요.**

---

### 아래는 확진 이전 조사 기록 (참고용, 위 확진 결과로 대체됨)

**Explore 서브에이전트 조사 결과**:
- 음성 안내(`voice_engine.dart`)와 화살표 카드(`nav_screen.dart`)는 **같은 인덱스**
  (`activeStepIdx+1`)의 같은 `ManeuverStep.type`을 각각 다른 매핑 테이블로 변환 — 과거
  세션에서 이미 off-by-one 감사 완료(`loop/RECON_guidance_engine.md` §E), 인덱스 불일치는
  아님.
- **Odin(Valhalla 서버)의 maneuver 분류 로직은 100% stock** — 이 프로젝트의 Valhalla
  포크(`motorcyclecost.cc`)는 경로 선택(costing)만 건드리고 안내 문구/각도 분류는 전혀
  건드리지 않음. 즉 이 버그는 클라이언트 코드가 아니라 **Valhalla 서버가 이 Y자 분기를
  어떻게 분류해서 내려주느냐**의 문제일 가능성이 매우 높음.
- **유력 가설**: 도로명이 바뀌는 얕은 각도 분기(서정로→서정북로)에서 Valhalla가 실제
  좌회전(kLeft, type 15) 직전에 아주 짧은 kStayStraight/kStayLeft(type 22/24, 음성
  이벤트 'keep', 템플릿 "차선 유지"류) 을 하나 더 끼워넣고, 그 짧은 구간의 "keep" 음성이
  거의 동시에 발화되면서 사용자에게는 "좌회전 아이콘이 뜬 순간 직진 음성이 나왔다"로
  들렸을 가능성. `assets/config/guidance_profile.json`엔 `"continue"`(type 8, kContinue)만
  `enabled:false`로 꺼져있고, `"keep"`(type 22/23/24)은 여전히 켜져있어 이 가설과 부합.
- **기존에 이미 알려진 미해결 이슈**: `loop/RECON_voice_v2.md` §R4("사거리 직진 안내")가
  정확히 이 버그 클래스를 "실도로 검증 후 결정, 보류"로 이미 남겨둔 상태였음. 이번
  실주행 피드백이 바로 그 "실도로 검증" 사례가 됨.
- 관련 로그 계측 이미 존재: `YNAV_STEP`(`route_progress_provider.dart:148`, maneuver type
  기록), `YNAV_TTS`(`nav_screen.dart:247`) — adb logcat으로 재현 시 확인 가능하나 헤드리스
  서버라 실기기 필요.

**다음 단계로 시도 중**: 실기기 없이도 Valhalla 서버(`https://valhalla.westinx.com`, 또는
로컬 `localhost:8002`)에 이 좌표를 지나는 경로를 직접 curl로 요청해서 실제 maneuver
JSON(type/length 시퀀스)을 까볼 수 있음 — `routing_service.dart:79`
(`_valhallaBase='https://valhalla.westinx.com'`), POST `/route`,
`costing:'motorcycle'`, `costing_options:{motorcycle: opts}` (opts는 routing_service.dart
L159 근처 3개 코스별 세트 중 하나 참고).

**막힌 부분**: 이 좌표(37.07016, 127.04945) 자체가 교차로 노드라서, 경로 요청을 만들려면
분기 이전/이후의 좌표 2점(예: 서정로 진입 전 지점, 서정북로 진입 후 지점)이 필요함.
- Overpass API 시도 → 실패(406 Not Acceptable, 쿼리 인코딩 문제로 추정, 미해결).
- 로컬 Valhalla(`localhost:8002`, `yurunavi-valhalla` 컨테이너, 29시간 uptime 확인됨)
  `/locate`로 재시도 → 응답은 왔지만 `way_id: 111353656` 엣지 하나만 나오고 `names`
  필드가 없어(응답 스키마상 `/locate`는 이름을 안 줌 — `/route`나 다른 엔드포인트 필요)
  분기 판별에 불충분했음. **이 시도는 세션이 크래시(ECONNRESET)로 끊기기 직전이라 후속
  분석 못함.**
- **이 세션에서 4회 연속 ECONNRESET 발생** — PDF/PNG 읽기와 무관하게도 발생하는 걸로 보아
  "세션이 길어지면서 발생"이라는 기존 가설(HANDOFF_0712_ridefeedback2.md §2)에 더 무게가
  실림. 라이브 API 조사(curl 체이닝)를 더 끌면 계속 끊길 위험이 높음.

**판단: 이 이상 라이브 조사는 보류.** 이미 확보한 정황(아래)만으로도 다음 세션에서 결정
가능한 수준:
- `loop/RECON_voice_v2.md` §R4가 이미 이 버그 클래스("사거리에서 직진류 음성 오안내")를
  "실도로 검증 후 결정, 보류"로 남겨뒀었고, 이번 실주행이 바로 그 실도로 검증 사례가 됨.
- 서버(Valhalla) 쪽 maneuver 분류는 이 리포에서 손댈 수 없는 stock 로직이라, 근본 수정은
  범위 밖. **실현 가능한 완화책**: 클라이언트에서 "keep류(type 22/23/24) maneuver가 매우
  짧고 바로 다음이 실제 회전(좌/우회전)이면 그 keep 음성을 건너뛴다"는 휴리스틱을
  `voice_engine.dart`의 `eventForType`/`onProgress` 근처에 추가하는 것. 100% 확진된 원인은
  아니라서 사용자 확인 후 진행 여부 결정 필요(CLAUDE.md: 불확실하면 추측 대신 기록).
- **사용자 결정(2026-07-12): 보류 — 다른 버그부터 먼저 처리.** 휴리스틱 구현도, 로그
  재현도 지금 안 함. 다음에 다시 꺼낼 때 이 파일 상단부터 참조.

## 완료: 3. 블루투스 음악 볼륨 덕킹 복구 안 됨 (슬라이드12) — 수정 완료, 커밋 대기

**원인**: `flutter_tts` 4.2.5 플러그인 네이티브 코드(`FlutterTtsPlugin.kt`, pub-cache 확인)를
직접 읽어 확인. 오디오 포커스 요청/해제를 **단일 공유 변수** `audioFocusRequest` 하나로만
추적하는 구조라, 우리 앱이 재생 중인 발화 위에 새 `speak()`를 겹쳐서 호출하면(QUEUE_FLUSH가
기본값이라 새 호출이 이전 발화를 인터럽트) 이전 발화의 `onStop` 콜백이 이미 덮어써진 "새"
포커스 참조를 잘못 해제하고, 원래 발화가 잡았던 포커스 grant는 영영 해제되지 않고
leak된다. 겹치는 `speak()` 호출이 실제로 발생하는 지점: `nav_screen.dart`의
`_handleVoice()`가 한 GPS 틱에 여러 `SpeakIntent`를 `await` 없이 순차 호출하는 루프,
그 외 도착/재탐색/출발 안내 등 여러 호출부가 근접 타이밍에 겹칠 수 있음. 실주행에서
GPS 틱이 몰리는 상황(터널/다리 밑 등)이나 재탐색+회전 안내 근접 시 재현 가능성 높음.
`flutter_tts` 자체는 pub-cache 밖(리포 스코프 밖)이라 패치 불가 — 대신 우리 쪽에서
겹치는 `speak()` 호출 자체가 네이티브에 도달하지 않도록 직렬화하는 방식으로 우회 수정.

**수정 내용** (`lib/services/voice_pack_service.dart`, `lib/features/navigation/presentation/nav_screen.dart`):
- `VoicePackService.speak()`에 내부 `Future<void> _queue` 체인 추가 — 이전에 큐에 들어간
  발화가 settle된 뒤에만 다음 `_tts.speak()`가 네이티브로 나가도록 강제.
- `nav_screen.dart`의 `_initTts()`에 `await _tts!.awaitSpeakCompletion(true);` 추가 —
  이게 없으면 `speak()`의 Dart Future가 네이티브 발화 완료를 기다리지 않고 채널 호출
  성공만으로 즉시 resolve돼서 직렬화 큐가 무력화됨.
- code-auditor 2라운드(1차 FAIL → 2차 PASS): 1차에서 `awaitSpeakCompletion(true)`를 켜면서
  새로 깨어나는 별도의 네이티브 결함을 발견 — `onError(utteranceId[, code])`가
  `speakCompletion()`을 호출하지 않아 TTS 엔진 에러 시 Dart Future가 영원히 안 끝나고,
  그러면 우리 직렬화 큐가 영구히 막혀 **남은 주행 내내 모든 음성 안내가 조용히 먹통**이
  되는(원래 버그보다 심각한 회귀) 리스크였음. `.timeout(const Duration(seconds: 8),
  onTimeout: () => null)`로 무슨 일이 있어도 큐가 유한 시간 안에 반드시 settle되도록
  고쳐서 해소. 2차 감사에서 8초 타임아웃이 실제 음성팩 문구 길이(가장 긴 것도 정상
  속도로 몇 초 내) 대비 충분히 여유 있어 "말 잘림" 새 회귀는 안 생김을 확인.
- 신규 테스트 `test/voice_pack_service_queue_test.dart` 추가 — `MethodChannel('flutter_tts')`
  모킹으로 겹치는 두 `speak()` 호출이 실제로 순차 실행되는지 검증(기존 96개 테스트는
  `VoicePackService.resolveTemplate` 정적 헬퍼만 커버, 인스턴스 `speak()` 커버 없었음).
- `flutter analyze` 0 issues, `flutter test` 97/97, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.
- **⚠️ 미확인 상태로 남은 것**: 이건 정적 코드 분석(플러그인 소스 직접 리딩)으로 도출한
  강한 가설 기반 수정 — headless 서버라 실제 Android AudioFocus 스택 동작이나 Bluetooth
  코덱에서의 실제 복구 여부는 라이브 검증 못함. **사용자가 다음 라이딩에서 재확인 필요.**

## 재확인 결과 2차 (사용자가 새 빌드 없이 구버전 APK로 재현 → 사용자 재현 보고 + 라이브 조사로 결론)

**사용자가 마트/카페 칩 고정 버그를 다시 재현 보고**(주유소 선택→해제→다른 칩 선택해도
주유소 목록 고정, 카페도 동일 패턴 + 여전히 닭발집/협동조합 혼입). 이 재현이
`0ab27b2`(칩 aliasing 수정) 적용 후에도 일어난 건지 확인하기 위해 코드를 다시 처음부터
끝까지 정밀 재추적함(select→deselect→select 시퀀스를 현재 `_effectiveTypes`/`_fetchedTypes`/
`_fetch` 로직으로 한 줄씩 손으로 실행) — **현재 HEAD 코드는 이 시퀀스에서 논리적으로 항상
올바르게 동작함**(deselect 시 `_fetch({})`가 정상 트리거되어 `_results`가 즉시 비워지고,
이후 다른 칩 선택 시 새 `_fetch`가 정상 실행됨 — aliasing이 완전히 끊어져 있어 이전 값이
새는 경로가 없음).

- **"전통시장/대형마트" 문자열은 git 히스토리 확인 결과 `2d91e4d`(오늘, SEMAS API로
  데이터소스 교체한 커밋) 이전에만 존재했고 그 이후로는 코드 전체에서 완전히 제거됨**
  (`git log --all -S"전통시장" -- '*.dart'` 등으로 확인). 사용자가 "완전히 새로 빌드한
  앱을 설치했었다"고 했지만, 이 문자열이 보였다는 것 자체가 실제로는 `2d91e4d` **이전**
  빌드가 기기에서 실행되고 있었다는 강한 증거.
- **카페 칩 비카페 혼입(닭발집 등)도 라이브 API로 직접 재확인**: `storeListInRadius`에
  카페 소분류(`indsSclsCd=I21201`)로 정확히 질의해보니 130건 전부 정확히 `카페`로만
  라벨링되어 응답 — API 쪽 오염은 없음. 같은 좌표에서 `I2`(식당 대분류) 넓은 질의를 해보니
  "수신닭발"/"평산닭발" 등 닭발 계열 업소들이 `한식`/`주점`으로 정확히 존재 —
  **"닭발집"은 실제로 식당(I2) 카테고리 데이터이지, 카페 API 응답에 섞인 게 아님**.
- **가설(코드 트레이스 기준)**: 위 세 증상(칩 고정, 구버전 칩셋, 카페 오염)은 전부
  "오래된 빌드/구버전 앱을 실행했다"는 하나의 원인으로 수렴할 수 있음 — 실제로 이 세션
  중 연결한 실기기(Galaxy M32F, 아래 참조)에서 `com.example.winding_road`(4월 Cursor
  초기 프로토타입, 완전히 별개 패키지명)가 같이 설치된 걸 발견해 이 가설과 부합하는
  정황을 찾았음.
  **⚠️ 정정(사용자 확인, 2026-07-13)**: 이 M32F는 실주행 테스트에 쓰인 폰이 **아니고**
  별개의 채굴용 폰이었음 — 실제 테스트 폰은 Galaxy A34(사용자가 출근 시 항상 휴대,
  이 세션에선 연결 못 함). 즉 M32F에서 구버전 앱을 찾은 것 자체는 사실이지만, **A34에서
  실제로 무슨 일이 있었는지에 대한 직접 증거는 아님** — 정황만 강화됐을 뿐 확진은 아직
  안 됨. `adb install -r`은 앱 데이터를 안 지우므로, A34에서도 기존 앱 완전 삭제 후
  재설치를 권장하고, 이 세션에서 준비한 클린 빌드 새 debug APK로 **A34에서 직접
  재테스트 필요**(다음 A34 접근 가능한 세션에서).
- 슬라이드7 vs 슬라이드12 모순(내비 화면 POI 표시 여부)은 M32F로 직접 재현·해결 —
  이건 실제 코드 동작(네트워크 의존성) 검증이라 어느 폰이든 동일하게 적용됨, 아래 항목
  참조.

## 완료: 4. 도착 배너 종료버튼 활성화 안 됨 + 10초 자동종료 (슬라이드14)

슬라이드14 원본 이미지 직접 확인. 사용자 코멘트: "예전과 똑같았음(기존부터 있던 버그).
위 조건(30m+30km/h)일 때에도 화면 아래 카드에 커다랗게 종료 안내가 안 나옴(레퍼런스:
네이버지도). 종료 안내 후 10초 후 자동종료도 꼭 필요함(네이버지도 좌측 하단 카운트다운
버튼 참조)."

**원인**: `_updateExitGate()`가 종료버튼 게이트 판정에 `_distance(navState.pos,
widget.destination)`(사용자가 지정한 **원본 목적지 핀**까지의 직선거리)를 썼는데, "도착"
자체를 트리거하는 `arrived` 플래그(`route_progress_provider.dart`)는 **Valhalla가 실제
라우팅한 폴리라인 상의 잔여거리**(`distToDestM`, 25m 이내)를 씀. 목적지 핀이 도로에서
떨어진 위치(이 앱 특성상 시골/지방 식당·카페가 흔함)면 배너는 뜨는데(폴리라인 기준
도착 인정) 종료버튼은 원본 핀까지 직선거리가 30m를 넘어서 영원히 안 열리는 불일치가
발생 — 실제 버그로 확진.

**수정** (`lib/features/navigation/presentation/nav_screen.dart`):
- `_updateExitGate()`가 `distToDestM`(폴리라인 잔여거리, 호출부의 `RouteProgress`에서
  그대로 전달받음)을 게이트 거리 소스로 사용하도록 교체. 미사용이 된 `Distance()` 필드
  제거.
- `_canExit`이 false→true로 열리는 순간 10초 `Timer`로 자동 `Navigator.pop()`(신규 요청
  기능) — 게이트가 다시 닫히거나(재탐색 등) 배너를 수동으로 닫거나 수동 종료 버튼을
  누르면 반드시 타이머를 취소하도록 3곳 모두 처리(주행 중 갑자기 화면이 꺼지는 것 방지).
  `_canExit==true`일 때 "10초 후 자동 종료" 정적 힌트 텍스트 추가(실시간 카운트다운
  애니메이션은 스코프 아님, 의도적으로 제외).
- code-auditor PASS — 특히 안전 관련 포인트(GPS 잡음으로 게이트가 깜빡여도 오작동
  안 하는지, orphaned 타이머가 나중에 잘못 pop을 유발하지 않는지)를 직접 코드 추적으로
  검증받음. 사소한 방어적 보완(수동 종료 버튼에도 타이머 취소 추가) 1건은 감사 후 직접
  반영.
- `flutter analyze` 0 issues, `flutter test` 97/97, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.
- **⚠️ 미확인 상태로 남은 것**: 게이트 조건 자체(30m/30km/h)는 실기기 GPS로 검증 안 됨 —
  다음 라이딩에서 실제로 도착 시 종료버튼이 켜지는지, 10초 뒤 자동 종료되는지 확인 필요.

## 완료: 내비 화면 POI 완전히 안 뜸 시뮬레이션 검증 (슬라이드7) — 코드 버그 아님, 확진 완료

실물 폰(Galaxy M32F, `RZ8RC1N3V9W`)을 adb로 westinx 서버에 USB 연결해 직접 검증함.
**이 폰은 원래 채굴(Grass.io)용으로 쓰던 별개 기기 — 사용자가 앞으로 상시 westinx
서버에 꽂아두고 Claude가 언제든 쓸 수 있게 지정해준 전용 테스트 폰**(실주행 테스트에
쓰는 Galaxy A34와는 다른 기기, A34는 사용자가 출퇴근 시 항상 휴대해서 이 세션엔 연결
불가).

**연결 과정에서 발견한 것**: 이 M32F에 앱이 **두 개** 설치돼 있었음 —
`com.westinx.yurunavi`(현재 앱)과 **`com.example.winding_road`**(사용자가 4월에
Cursor로 만든 완전히 별개의 초기 프로토타입, 패키지명·프로젝트명 전부 다름). 사용자
확인 후 삭제 완료. **⚠️ 이 발견은 M32F에 한정** — 실주행 테스트는 A34에서 이뤄졌으므로
위 "재확인 결과 2차"의 칩 고정/구버전 칩셋/카페 오염 세 증상을 이걸로 확진하는 건 아님
(정황 강화 정도, 위 정정 참조). A34 접근 가능해지면 같은 방식(완전 삭제 후 재설치)으로
직접 재확인 필요.

**슬라이드7 자체 검증**: `com.westinx.yurunavi`(현재 코드) 클린 재설치 후 평택시
서정동 현지에서(실주행 좌표와 동일 동네) 실제로 목적지 설정 → 코스 선택 →
내비게이션 진입까지 전 과정을 adb 터치 자동화로 재현. 처음엔 폰이 연결된 WiFi
("MAVERIK_5G")가 일시적으로 완전 단절 상태였음(`connectivitycheck.gstatic.com`조차
DNS 실패 — 우리 앱과 무관한 네트워크 자체 문제, logcat으로 확인)이라 내비 화면에 POI
점이 하나도 안 뜸 — **슬라이드7과 동일한 증상 실시간 재현 성공**. WiFi 재연결 후
15초 이내(디바운스 재시도 주기) 별도 조작 없이 POI 점이 정상적으로 나타남 — **코드는
정상 동작하고, 순수 네트워크 단절이 원인이었음을 직접 확인**. 슬라이드7(실주행 중
안 뜸)과 슬라이드12(뜸)의 모순도 이걸로 해소: 실주행 중 특정 구간에서 데이터 연결이
일시적으로 끊겼던 것으로 결론.

**부수 개선**: `PoiService._fetchOne`의 `catch(_) { return []; }`가 네트워크 에러를
완전히 조용히 삼켜서(로그 0줄) 이번 진단이 매우 오래 걸렸음 — `debugPrint('YNAV_POI
fetch failed type=$type error=$e')` 추가해 향후 동일 상황 진단 시간 단축.
`flutter analyze`/`flutter test`(97/97) 통과.

**별도로 확인된 사용자 UX 피드백(버그 아님, 백로그로 기록)**: `SliderStartButton`("Start
your Engine" 슬라이드 버튼)이 `dismissThresholds: 0.75`를 `Dismissible`의 내부 아이템
너비(거의 트랙 전체 폭) 기준으로 계산해서, 실질적으로 **화면 거의 끝까지 밀어야 완료됨**
— 아이폰 슬라이드락처럼 디자인된 트랙 안에서만 끝나는 게 아니라 물리적 화면 끝까지 밀어야
해서 불편하다는 피드백(`lib/core/widgets/slider_start_button.dart`,
`slider_button` 패키지 사용). 다음 UX 정리 세션에서 `dismissThresholds`를 낮추거나
`width`를 유한값으로 바꿔 트랙 안에서 완결되도록 조정 검토.

## 완료: 5. 검색 시트 버그 2건 (슬라이드6)

`main_map_screen.dart`의 `_PoiExploreSheet`("주변 탐색" 검색시트, 지도 헤더 "장소 검색"
버튼으로 진입) 관련 피드백 3개 중 코드로 확인 가능한 것만 처리:

- **"부분문자열 검색 안 됨(앞글자만 매칭)"**: 현재 코드(`_visibleResults` getter)를
  확인해보니 이미 `.contains(query)`로 정상적인 부분문자열 매칭을 하고 있음 —
  **재현 안 됨**. 위 "재확인 결과" 섹션의 다른 증상들과 마찬가지로 실주행 때 구버전/
  별개 앱을 실행했을 가능성이 있는 종류의 항목으로 판단, 손대지 않음.
- **"검색창 포커스 시 키보드에 시트 가려짐"(실제 버그, 수정함)**: `showModalBottomSheet`가
  키보드를 자동으로 피해주지 않아서 발생 — `_PoiExploreSheetState`에 검색
  `TextField`용 `FocusNode` 추가, 포커스 시 시트 `maxHeight`를 기존 75%→거의
  전체화면으로 확장 + `Padding(bottom: MediaQuery.viewInsets.bottom)`으로 키보드
  높이만큼 시트 전체를 밀어올림.
- **"검색 결과가 GPS 위치 중심(화면 중심 아님)"(실제 버그, 수정함)**: `_showPoiExploreSheet()`를
  비동기로 바꿔 시트를 열기 전에 `_mlCtrl.getVisibleRegion()`으로 현재 지도 뷰포트의
  중심 좌표를 구해 그걸 검색 기준점으로 사용(팬 이동 후에도 보고 있는 지역 기준으로
  검색됨) — 실패 시 기존처럼 GPS로 폴백. `nav_screen.dart`의 앰비언트 POI 레이어가
  이미 쓰던 동일 패턴 재사용.
- **작업 중 사고 기록**: 서브에이전트 작업 후 실수로 `dart format`을 파일 전체에
  돌려 무관한 기존 코드까지 787줄 넘게 재포맷되는 사고 발생 → 즉시 되돌리고(`git
  checkout --`) 동일한 두 수정을 Edit 툴로 한 줄씩 수동 재적용해 diff를 43줄로
  축소함. 이 파일은 기존부터 `dart format` 기준과 스타일이 어긋나 있는 상태(포맷팅
  부채)라는 것도 확인됨 — 이번에 손대지 않았고, 별도 정리가 필요하면 전용 세션에서
  진행할 것(수많은 무관한 diff가 생기므로 버그 수정과 섞지 말 것).
- code-auditor PASS(위젯 트리 괄호 정합성, 비동기화로 인한 지연/mounted 체크,
  FocusNode 생명주기, maxHeight 포커스 확장 로직, LatLngBounds 필드명까지 전부 확인).
- `flutter analyze` 0 issues, `flutter test` 97/97, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.
- "로딩 속도 느림, 백그라운드 프리페치 요청"은 손 안 댐 — 별도 기능 추가(스코프 더 큼),
  아래 미착수 항목에 남겨둠.

## 완료: 7. 경로선 레이어가 도로 라벨을 가림 + 지나온 경로 회색 표시 (슬라이드13)

`nav_screen.dart`의 route `addLineLayer` 호출들이 `belowLayerId` 없이 항상 레이어 스택
맨 위에 추가돼 스타일(`osm_liberty_yurunavi.json`)의 모든 도로명/POI/지명 라벨을 덮고
있었음(repo 전체에 `addLayerBelow`/`belowLayerId` 사용례가 이번 수정 전까지 0건이었음).
지나온/남은 구간 구분 로직도 아예 없어서 경로 전체가 항상 단일 코스 색으로만 그려졌음.

**수정** (`lib/features/navigation/presentation/nav_screen.dart`, 전부 이 파일 안에서
완결 — `main_map_screen.dart`엔 동일한 `belowLayerId` 부재 버그가 남아있으나 이번
스코프 밖, 아래 "남은 이슈" 참조):
- `_navRouteTraveledSourceId`/`_navRouteTraveledLayerId` 신규 추가 — 지나온 구간 전용
  회색(`#9E9E9E`, `main_map_screen.dart`의 미선택 코스와 동일 색) 레이어.
- `_initRouteLayer()`/`_recolorNavRouteLayer()`의 `addLineLayer` 호출 전부에
  `belowLayerId: 'waterway-name'` 추가 — 스타일 layers 배열에서 첫 symbol(라벨) 레이어가
  `waterway-name`(index 100/130)이라, 이 아래에 넣으면 모든 폴리곤/라인 레이어(도로,
  건물, 물) 위 + 모든 텍스트 레이어 아래로 정확히 배치됨. `removeLayer`+재추가하는
  recolor 경로에서도 유지되도록 처리(안 하면 코스 재선택 시마다 버그 재발).
- 신규 메서드 `_updateRouteSplit(int snapIdx)` — `route_progress_provider.dart`가 이미
  노출하던 `RouteProgress.snapIdx`(GPS로 갱신되는 폴리라인 세그먼트 인덱스, 단조 증가)를
  이용해 매 progress 업데이트(`_progressSub` 리스너)마다 `_routePoints`를 현재 위치
  기준 지나온/남은 두 구간으로 나눠 각자의 소스에 반영. 두 구간 모두 현재 GPS 위치를
  경계점으로 공유시켜 시각적 gap 없이 이어지도록 함. `_showCourseSheet`(코스 프리뷰
  시트가 열려있는 동안)는 갱신을 건너뛰어 프리뷰 경로를 덮어쓰지 않음(카메라 추적을
  건너뛰는 기존 패턴과 동일 이유).
- code-auditor PASS(1차) — 슬라이싱 인덱스 산수(단조성, 경계값 idx=0/length-1/
  length==2), `pos==null` 방어 분기, `_showCourseSheet` 가드, `belowLayerId` 일관성을
  전부 직접 코드 추적으로 검증받음.
- `flutter analyze` 0 issues, `flutter test` 97/97, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.

**후속 수정(사용자 피드백 반영, 1차 구현 직후)**: 1차 구현은 코스 확정(`_onCourseSheetStart`)
/재탐색(`_reroute`) 시 활성 경로가 통째로 바뀌므로 이전 경로의 회색 구간을 빈 값으로
리셋했었음. 사용자가 이를 지적: "투어링은 집에서부터 목적지 도착까지 이어지는 하루치
기록이고, 재탐색은 좋은 길 따라 마음내키는 대로 달리다 보면 빈번하게 발생하는 것 —
재탐색이 일어나도 그 날의 투어링 궤적이 끊기면 안 됨"(주행 기록 히스토리 기능과도 맞닿는
의미). 단순히 리셋 줄만 지우는 걸로는 해결 안 됨 — 지나온 구간 계산 자체가 활성 경로
폴리라인+`snapIdx`에서만 나오는 구조라 경로가 바뀌면 계산 기반 자체가 사라지기 때문.
- 새 인스턴스 필드 `_traveledTrail`(누적 궤적)과 새 메서드 `_absorbTraveledIntoTrail()`
  추가 — 경로가 통째로 교체되기 **직전**(`_routePoints` 재할당 전, `setState`보다 먼저)에
  그때까지 지나온 구간을 `_traveledTrail`에 흡수. `_updateRouteSplit`의 회색 레이어는
  이제 `_traveledTrail + 현재 활성 경로의 지나온 구간 + 현재 GPS 위치`로 구성 — 재탐색/
  코스 재선택이 몇 번 일어나도 궤적이 계속 이어짐. 코스 프리뷰(`_onCourseCardTap`, 아직
  미확정)는 흡수 대상이 아님 — 그대로 미터치.
- code-auditor PASS(2차) — 흡수 호출이 `_routePoints` 재할당보다 항상 먼저 실행되는지
  (안 그러면 이미 바뀐 경로에서 잘못 흡수함), `_absorbTraveledIntoTrail()`이 읽는
  `routeProgressProvider`의 `snapIdx`가 `setRoute()`의 리셋(post-frame으로 지연)보다
  먼저 읽혀 안전한지, 재탐색 반복 시 좌표 중복/역행 없이 이어지는지 코드 추적으로 검증.
  재탐색 접합부에서 이전 경로 마지막 스냅 지점과 새 경로 시작점 사이에 최대 한 세그먼트
  길이 정도의 미세한 시각적 이음새(gap/kink)가 있을 수 있음을 확인했으나(재탐색 시
  origin을 heading 방향으로 40m 오프셋시키는 기존 설계의 부수 효과, 이번 diff로 생긴
  회귀 아님), 안전/정확성 문제는 아니라 blocking 아님.
- `flutter analyze` 0 issues, `flutter test` 97/97, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.
- **⚠️ 미확인 상태로 남은 것**: MapLibre 레이어 z-order/GeoJSON 소스 갱신, 그리고 이번
  누적 궤적 로직은 정적 코드로는 완전히 검증했지만 실제 렌더링 결과(라벨이 실제로 위에
  보이는지, 회색 궤적이 재탐색을 몇 번 거쳐도 매끄럽게 이어지는지)는 headless 서버라
  실기기 확인 못함. **다음 라이딩에서 확인 필요.**

## 완료: 10. main_map_screen.dart 경로 프리뷰 레이어 라벨 가림 (7번과 동일 원인)

7번과 완전히 동일한 원인 — `main_map_screen.dart`(코스 선택 전 지도 화면)의 route
`addLineLayer` 호출 3곳(`_initRouteLayer()` 배경/선택 레이어 2곳,
`_recolorRouteLayer()` 재색칠 경로 1곳) 모두 `belowLayerId` 없이 추가돼 라벨을 가리고
있었음. nav_screen.dart에서 이미 검증된 것과 동일하게 `belowLayerId: 'waterway-name'`
추가로 해결(커밋 `44a29f4`).

- code-auditor PASS — `waterway-name`이 스타일의 130개 레이어 중 index 100, 전체에서
  첫 symbol(라벨) 레이어임을 스타일 JSON에서 직접 확인해 z-order 논리를 재검증.
  `_recolorRouteLayer`의 `removeLayer`+재추가 경로도 매 호출마다 `belowLayerId`를
  다시 명시하므로 코스 재선택 반복 시 z-order 드리프트 없음. `_initLocationLayer`/POI
  레이어(이 diff로 안 건드림, 여전히 `belowLayerId` 없이 맨 위에 추가되는 puck/POI용
  의도된 동작)에 회귀 없음 확인.
- diff는 3줄 추가만(다른 코드 무변경) — `dart format` 부채 있는 파일이라 전체 재포맷
  사고 재발 안 하도록 이번에도 수동 최소 diff로 처리.
- `flutter analyze` 0 issues, `flutter test` 97/97, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.
- **⚠️ 미확인 상태로 남은 것**: 실제 렌더링 결과(코스 선택 화면에서 라벨이 실제로 경로선
  위에 보이는지)는 headless 서버라 실기기 확인 못함. **다음 실기기 접근 시 확인 필요.**

## 완료: 9. Start your Engine 슬라이드 버튼 드래그 임계값 버그

**원인**: 서드파티 `slider_button` 패키지(v3.1.0)가 내부 `Dismissible` 자식 폭을
`widget.width - (buttonWidth ?? height)`로 계산하는데, 우리 코드가 `width:
double.infinity`를 넘기고 `buttonWidth`는 미설정이라 `infinity - height`가 여전히
`infinity`로 남음 → Flutter의 `BoxConstraints.enforce` 클램핑이 이 안쪽 Dismissible을
"트랙 폭 - 버튼 폭"이 아니라 트랙 전체 폭으로 그대로 resolve해버려서, `dismissThresholds:
0.75`(자기 자신 렌더 폭의 75%)가 사실상 화면 거의 끝까지 드래그해야 충족되는 값이 됨.
패키지는 pub-cache 밖(item 3 flutter_tts와 동일한 제약)이라 패치 불가 — 클라이언트
쪽에서 `width`를 유한값으로 넘기는 방식으로 우회 수정.

**수정** (`lib/core/widgets/slider_start_button.dart`, 커밋 `34fc4fd`):
- `SliderButton` 생성을 `LayoutBuilder`로 감싸 실제 바운딩된 `constraints.maxWidth`를
  획득, `width: double.infinity` → `width: constraints.maxWidth`로 교체(바깥 트랙의
  시각적 전체폭 모양은 기존과 동일하게 유지 — 예전에도 `double.infinity`가 결국 같은
  바운딩 폭으로 클램핑됐던 것과 같은 값이라 외형 변화 없음, 안쪽 Dismissible 계산만
  고쳐짐).
- 기존 `buttonSize: 52`와 맞춰 `buttonWidth: 52` 추가 — 패키지 자체 문서가 "wide,
  non-squared 버튼엔 buttonWidth를 쓰라"고 명시한 대로, 드래그 완료 영역이 실제 버튼
  폭만큼 줄어들도록 정렬.
- 신규 테스트 `test/core/widgets/slider_start_button_test.dart` 추가 — `find.byType
  (SliderButton)`로 생성된 위젯을 찾아 `width`가 유한값인지(다시 `double.infinity`로
  회귀하지 않는지) 검증. 드래그 제스처 자체는 시뮬레이션 안 함(스코프 밖).
- code-auditor PASS — 패키지 소스 직접 재확인으로 constraint 클램핑 추론 검증,
  `course_sheet.dart`/`main_map_screen.dart`/`nav_screen.dart` 호출 체인 전부 확인해
  `LayoutBuilder`가 unbounded width를 받을 위험 없음(모두 `Positioned`+`SafeArea`+
  `Column` 체인, `Row`/가로 `ListView` 없음) 확인, `buttonWidth: 52` 값이 실제 폰 폭
  기준 안전한 양수 범위임을 산수로 검증.
- `flutter analyze` 0 issues, `flutter test` 98/98, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.
- **⚠️ 미확인 상태로 남은 것**: 실제 손가락 드래그 완료 체감(트랙 안에서 자연스럽게
  끝나는지)은 headless 서버라 실기기 확인 못함. **다음 실기기 접근 시 확인 필요.**

## 완료: 6. 검색 로딩 속도 느림, 백그라운드 프리페치 요청 (슬라이드6, 5번에서 분리)

**스코프 확인**: 프리페치 트리거 시점을 "검색 버튼 탭 시점"과 "지도 화면 진입/GPS 확보
시점부터 상시" 두 안 중 사용자에게 확인 — **후자로 결정**(체감 속도가 더 빠름을 우선,
GPS 확보 즉시 백그라운드로 미리 받아두는 쪽).

**원인**: `_PoiExploreSheet`는 사용자가 시트를 열고 카테고리 칩을 고르거나 검색어를
입력해야 그 시점부터 네트워크 요청을 시작하는 구조였음 — 그 사이 대기시간이 "느림"으로
체감됨. 게다가 칩을 여러 개 연속으로 토글하면(예: 카페→편의점 추가) `_effectiveTypes`가
바뀔 때마다 매번 새 네트워크 요청이 발생해 대기가 반복됐음.

**수정** (`lib/features/map/presentation/main_map_screen.dart`):
- 신규 `_maybeFetchSearchPrefetch(LatLng center)` — `_startLocationTracking()`의 GPS
  갱신 경로(캐시된 마지막 위치 도착 시 + `navStateProvider` 매 틱) 양쪽에서
  `unawaited(...)`로 호출. 5종 카테고리 전체를 1500m 반경으로 한 번에 가져와
  `_searchPrefetchPois`/`_searchPrefetchCenter`/`_searchPrefetchAt`에 캐시. 500m 이동
  또는 60초 경과 전엔 재조회하지 않음(기존 ambient 레이어의 200m/15초보다 완화된
  디바운스 — 반경이 넓어 약간의 위치 오차가 결과에 큰 영향 없고, 검색은 ambient만큼
  실시간성이 필요 없음). `_searchPrefetchGen` 카운터로 stale 응답 가드(기존
  `_ambientFetchGen`과 동일 패턴).
- `_showPoiExploreSheet()`가 시트를 열 때 계산한 origin과 `_searchPrefetchCenter`가
  1km 이내면 캐시를 `_PoiExploreSheet`의 신규 `initialPois` 파라미터로 그대로 넘겨
  네트워크 재요청을 완전히 생략. 캐시가 없거나 너무 멀면 시트가 폴백으로 자체 조회.
- `_PoiExploreSheet`/`_PoiExploreSheetState` 구조 변경: 기존엔 칩/검색어가 바뀔 때마다
  그 유효 카테고리 집합만 골라 매번 재조회(`_fetchedTypes`/`_sameTypes`/`_fetch`)했는데,
  이제는 5종 전체를 **딱 한 번**만 가져와(`initState`에서 `initialPois` 즉시 반영 또는
  `_fetchAll()` 단일 호출) `_allPois`에 저장하고, 이후 칩 토글/검색어 입력은 전부
  `_typeFilteredPois`/`_visibleResults`로 클라이언트 필터링만 함 — 재조회 0회. 지도 위
  검색결과 핀(`poiListProvider`)은 `_toggleType`/`_onSearchChanged`/`_fetchAll` 완료
  시점에 `_visibleResults`로 동기화.
- code-auditor PASS — initState에서 `_fetchAll()` 호출이 첫 `await` 전에 `setState`를
  안 써서 build 중 setState 위험 없음(`_loading=true`는 순수 필드 대입), `_searchPrefetchGen`
  가드가 겹치는 GPS 틱 사이 (`pois`, `center`) 불일치 조합을 만들 수 없음, `_fetchAll`이
  네트워크 실패해도 `PoiService.fetchPois`가 예외를 삼키고 `[]`를 반환하므로 `_loading`이
  영구히 멈추는 경로 없음, `poiListProvider`가 카테고리 미선택 상태에서 조기 오염되지
  않음을 전부 코드 추적으로 검증. `initialPois`가 프리페치 중심(최대 1km 오차) 기준으로
  조회된 것이라 실제 origin 기준 1500m 원과 정확히 일치하지 않는 근사치라는 점은 인지된
  트레이드오프로 확인(리스트 표시 거리/정렬은 항상 실제 origin 기준으로 재계산되므로
  화면에 보이는 값 자체는 부정확하지 않음, 후보 집합만 약간 fuzzy).
- `flutter analyze` 0 issues, `flutter test` 98/98, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.
- **⚠️ 미확인 상태로 남은 것**: 실제 GPS 이동 중 프리페치가 매끄럽게 갱신되는지, 시트를
  열었을 때 실제로 "즉시" 뜨는 체감인지는 headless 서버라 실기기 확인 못함. **다음
  실기기 접근 시 확인 필요.**

## 완료: 8. 여러 UX 개선 요청(슬라이드1~6, main_map_screen.dart 홈 지도 화면 전용)

착수 전 사용자에게 두 가지 확인: (1) 오늘 밤 범위 — "전부 순차 진행" 선택(ambient POI
레이어 5개 + 검색시트 목적지 확인카드 2개를 한 세션에서 다 진행), (2) 슬라이드2/5가
요청한 "네이버지도 스타일 아이콘"(가스펌프/그릇/포크나이프 등) — 리포에 에셋이 없어
"Material Icons로 대체"(커스텀 에셋 대기 대신 즉시 구현) 선택. 슬라이드1~6은 전부
`main_map_screen.dart`(코스 선택 전 홈 지도 화면) 소관이라는 걸 재확인 후 5단계
체크포인트로 분해, 각 단계 flutter-coder 구현 → code-auditor 감사 → PASS 시 커밋 순서로
진행(CLAUDE.md TDD 루프).

**1단계(커밋 `9ae2166`) — 우선순위+분포 기반 선택 알고리즘, 개수제한 버그 수정**:
- `PoiService.selectForAmbientDisplay()` 신규(순수 정적 함수, I/O 없음) — 뷰포트를
  gridSize×gridSize(기본 4×4) 격자로 나눠 셀별로 우선순위(주유소>편의점>카페>대형마트>
  식당 — 사용자 원문의 "전통시장"은 API에 대응 카테고리가 없어 스코프 밖, 대신 식당을
  최하위로 둠) + 거리 순 정렬 후 라운드로빈으로 뽑아 최대 20개(기존 10개)로 추린다 —
  화면 중심에만 몰리던 문제와 "우선순위가 랜덤처럼 보임" 문제를 동시에 해소.
- ambient 레이어(`_maybeFetchAmbientPois`, take(10) 단순 거리정렬)를 이 알고리즘으로
  교체.
- **실제 원인 발견**: "번화가에서 10개 제한이 깨지고 수십 개 표시" 버그는 ambient
  레이어(이미 take(10)으로 정상 제한 중이었음)가 아니라 **검색시트("장소 검색")의 지도
  핀 레이어**(`poiListProvider`→`_poiSourceId`)가 애초에 캡이 전혀 없었던 게 원인 —
  스크롤 리스트(`_visibleResults`)는 그대로 무제한 유지하되 지도 핀에 넘기는 값만
  `_mapPinPois`(신규 getter, origin 중심 ±0.02° 근사 bounds로 동일 알고리즘 적용)로
  캡핑.
- 신규 유닛테스트 5개(`test/services/poi_service_test.dart`) — 빈 후보/캡 초과 안 함/
  단일셀 우선순위/멀티셀 라운드로빈 분산/degenerate bounds 폴백.
- code-auditor PASS. 감사에서 나온 사소한 개선 제안(null-origin 폴백 경로가
  `PoiService.displayPriority.indexOf`를 직접 써서 미매핑 타입 방어가 없음, 논블로킹)은
  바로 반영 — `selectForAmbientDisplay`의 degenerate-bounds 경로를 재사용하도록 수정.
- `flutter analyze` 0 issues, `flutter test` 103/103(98+신규5), `flutter build apk
  --debug --dart-define-from-file=env.json` 빌드 성공.

**2단계(커밋 `1c66ce9`) — 아이콘+이름 라벨 렌더링**:
- **제약 확인**: 지도 글리프 서버(`tiles.westinx.com/fonts/...`)는 Noto Sans
  Regular/CJK만 호스팅 — Material Icons 폰트/PUA 코드포인트가 없어 `text-field`로 직접
  렌더링 불가(한글 상호명은 Noto라 문제없음). 따라서 아이콘은 런타임에 `dart:ui`로
  `IconData`+배경원을 PNG로 래스터라이즈해 `controller.addImage()`로 등록하는 방식
  채택(기존 `pointer_red.png` 등 정적 에셋 등록 패턴과 동일한 자리, 다만 에셋이 아니라
  런타임 생성).
- `renderPoiIconPng()` 신규 — 5종 카테고리(주유소=가스펌프/카페=커피컵/편의점=편의점
  아이콘/마트=쇼핑카트/식당=포크나이프) × 기존 CircleLayer와 동일한 5색 배경.
  `onStyleLoadedCallback`(스타일 재주입마다 재실행 필요 — 기존 pointer 아이콘들과 동일
  이유)에서 5개 등록.
- ambient·검색시트 두 POI 레이어 모두 `CircleLayer` → `SymbolLayer`로 전환
  (`iconImage`+`textField`(이름, Noto 폰트)). `belowLayerId`는 기존에도 없었으므로
  유지(최상단 렌더링 유지, 다른 세션의 경로선 라벨가림 수정과는 무관).
- code-auditor 1차 FAIL — `renderPoiIconPng`에서 `ui.Image`가 `dispose()` 없이 leak
  (스타일 재주입마다 5개씩 누적, GC에 의존한 비결정적 해제) → `toByteData()` 직후
  `image.dispose()` 추가해 해소, 2차 확인 후 커밋.
- `flutter analyze` 0 issues, `flutter test` 103/103, `flutter build apk --debug` 빌드
  성공.

**3+4단계(커밋 `7e8b0f2`) — POI 점 탭 + 검색시트 리스트 탭 → 확인카드**:
- 기존 지도 빈 곳 탭 시 쓰던 확인시트(`_showTapConfirmSheet`/`_TapAction`/`_TappedPoi`,
  "여기로 안내"/"경유지 추가"/"닫기")를 재사용 — `_onMapTap`의 꼬리부분(액션 분기+경로
  재조회)을 `_applyTapAction()`으로 순수 추출(기존 동작과 100% 동일, 리팩터만) 후,
  신규 `_handlePoiTap(Poi)`가 이미 알고 있는 이름/카테고리로 같은 시트를 띄우고
  `_applyTapAction`으로 위임.
- 지도 위 POI 점 탭 감지: `controller.onFeatureTapped`(기존 이 리포에서 미사용이던 API)를
  `onMapCreated`(컨트롤러 생애주기당 1회, 스타일 재주입마다 도는 `onStyleLoadedCallback`과
  달리 중복 등록 위험 없음)에서 등록, layerId로 ambient/검색 레이어 구분 후 탭 좌표에서
  가장 가까운 Poi를 haversine으로 찾아 매칭(GeoJSON feature id 왕복 대신 "현재 렌더링
  중인 후보 리스트 중 최근접" 방식 채택 — 헤드리스 서버라 네이티브 feature-id 시맨틱을
  직접 검증할 수 없어 더 안전한 방법 선택).
- 검색시트 리스트 탭: `_PoiExploreSheet.onSelectDest` 시그니처를 `LatLng` → `Poi`로 변경,
  즉시 목적지 확정 대신 `_handlePoiTap(poi)` 경유(확인카드 거침). 즐겨찾기/최근경로
  시트(`_PlacesSheet`, 별개 위젯)는 스코프 아님 — 그대로 즉시 확정 유지.
- code-auditor PASS. 감사 중 실제 회귀 1건 발견(논블로킹으로 분류됐으나 바로 수정) —
  `_handlePoiTap`의 `origin == null` 가드가 `_onMapTap`과 달리 조용히 no-op이었는데,
  ambient POI 레이어는 GPS 확보 전(카메라 뷰포트만으로 동작)에도 뜰 수 있어 실제로
  도달 가능한 데드클릭이었음 → `_onMapTap`과 동일한 "GPS 위치를 기다리는 중입니다…"
  스낵바를 추가해 조용한 무반응 대신 피드백 제공.
- `flutter analyze` 0 issues, `flutter test` 103/103, `flutter build apk --debug` 빌드
  성공.

**5단계(커밋 `dd25dff`) — 목적지/경유지 지도 포인터 이름 라벨**:
- `MapInteractionState`에 `waypointNames`(`List<String?>`, `waypoints`와 index 정렬)
  신규 추가, `addWaypoint(LatLng, {String? name})`/`removeWaypoint`가 두 리스트를 항상
  같이 갱신.
- `_ensureDestMarker`/`_syncWaypointMarkers`에 `textField`(Noto 폰트, 흰 헤일로) 추가해
  목적지/경유지 핀 아래 이름 표시.
- code-auditor 1차 **FAIL — 실사용 경로에서 재현되는 버그 2건 발견**:
  1. **경쟁상태로 목적지 마커 중복 생성**: `_applyDestination`에서 이름을 이미 아는 경우
     (POI 탭 등) `_ensureDestMarker(dest, name: preResolved)`를 unawaited로 던진 직후
     `setDestinationName(preResolved)`가 동기적으로 리스너를 트리거하는데, riverpod의
     `ref.listen` 알림이 `addSymbol`의 플랫폼채널 왕복(진짜 비동기 IPC)보다 먼저
     끝나버려서 `_destMarker`가 아직 null인 상태로 리스너가 또 `_ensureDestMarker`를
     호출 → `addSymbol`이 두 번 발생, 마커 2개가 겹쳐 생성되고 나중에 끝난 쪽만
     `_destMarker`에 남아 다른 하나는 참조를 잃어 영구히 남는 문제. **"POI 탭으로
     목적지 설정"이라는 이 기능의 핵심 경로에서 거의 매번 재현되는 심각도**로 판단돼
     `await`로 전환해 첫 마커 생성이 확정된 뒤에 리스너가 돌게 수정.
  2. **이름 없는 목적지로 갈아탈 때 이전 라벨이 안 지워짐**: `updateSymbol`은 null
     필드를 "변경 없음"으로 처리하는 라이브러리 동작이라(기존 코드가 이미 이 특성에
     의존 중이었음 — geometry만 넘겨도 아이콘이 유지되는 게 그 증거), 이름 있는
     목적지를 찍은 뒤 이름 없는 곳(빈 지도 탭)으로 다시 찍으면 새 위치에 이전 라벨
     텍스트가 그대로 남음 → `_ensureDestMarker`가 `textField: name`을 `textField: name
     ?? ''`로 바꿔 이름 없을 때 빈 문자열을 명시적으로 보내 확실히 지우도록 수정
     (`_syncWaypointMarkers`는 매번 전체 재생성이라 이 문제 없음, 그대로 둠).
  2차 재감사 없이 두 수정을 직접 반영 후 `flutter analyze`/`flutter test` 재실행으로
  회귀 없음 확인(감사자가 제시한 수정안을 그대로 적용한 기계적 수정이라 재감사 생략,
  이후 실기기 확인 시 함께 재검증 필요).
- `flutter analyze` 0 issues, `flutter test` 103/103, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.

**슬라이드1(앱 시작 시 POI 로딩 5초+, 백그라운드 프리로딩 요청)은 별도 구현 불필요**:
6번(검색 프리페치, 이미 완료·커밋됨)이 GPS 확보 시점부터 상시 백그라운드로 5종
카테고리를 미리 받아두는 구조라, 슬라이드1이 요구한 "로딩 체감 단축"을 이미 만족함 —
검색시트를 열 때 캐시가 이미 따뜻하면 네트워크 재요청 자체가 생략됨. 별도 코드 변경
없음.

**⚠️ 8번 전체에서 미확인 상태로 남은 것** (5단계 전부 headless 서버라 실기기 확인 못함,
다음 실기기 접근 시 확인 필요):
- ambient/검색 POI 점이 실제로 아이콘 모양+이름 라벨로 렌더링되는지(스타일 재로드 시
  이미지 등록 타이밍 포함).
- 지도 위 점 탭이 실제 손가락 터치에서 정확히 히트되는지(원 반지름이 작아 오차 여지),
  탭 시 확인카드가 정상적으로 뜨는지.
- 검색시트 리스트 탭 → 확인카드 → 목적지/경유지 확정 흐름 전체.
- 목적지/경유지 핀 아래 이름 라벨이 실제로 보이는지, 이름 있음→없음 전환 시 라벨이
  깨끗이 지워지는지(5단계 감사에서 발견된 두 버그의 실기기 재현 여부 포함).
- ambient 레이어의 20개 상한·우선순위·화면 분포가 실제 번화가에서 체감상 개선됐는지.

## 명시적으로 미룬 것
- **유턴/스위치백 경로 costing 튜닝(슬라이드11)** — 사용자가 "미루고 다른 버그부터"라고
  명시. 먼저 꺼내지 말 것.

## 하지 말 것 / 주의
- `loop/feedback/260712_testDriveFeedback.pdf` 절대 Read 금지 (ECONNRESET 유발 확인됨).
- 이 세션 자체가 반복적으로 ECONNRESET로 끊기고 있음 — 매 단계 완료 시 즉시 이 파일
  갱신할 것.
