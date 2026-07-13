# 실주행 피드백 버그 수정 진행 상황 (2026-07-12, ANALYSIS_progress.md 이후 이어감)

이 세션에서도 API 에러(ECONNRESET)로 재차 끊길 가능성 있어 여기 기록하며 진행.
**16장 PNG 분석은 완료됨** (`ANALYSIS_progress.md` 참조).

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

## 진행 중: 2. Y자 삼거리 좌회전 오안내 (슬라이드16)

좌표 (37.07016, 127.04945). 실제로는 우측(서정로, 직진처럼 보이는 완만한 각도)이 도로명
유지, 좌측(서정북로)이 더 큰 각도로 분기하는 갈림길인데, 앱이 좌회전(좌측/서정북로) 상황
에서 "직진입니다. 차선을 유지하세요" 오안내.

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
- **결론**: 위 세 증상(칩 고정, 구버전 칩셋, 카페 오염)은 전부 **같은 원인 하나**로
  수렴함 — 사용자가 테스트한 APK가 `0ab27b2`+`2d91e4d`보다 오래된 빌드였을 가능성이
  매우 높음. `adb install -r`은 앱 데이터(SharedPreferences 등)를 지우지 않으므로,
  기존 APK를 완전 삭제(uninstall) 후 재설치를 권장. `flutter clean` 후 클린 리빌드한
  새 debug APK 준비 완료 — **사용자가 완전 삭제 후 이 새 APK로 재테스트 필요**.
- 슬라이드7 vs 슬라이드12 모순(내비 화면 POI 표시 여부)은 여전히 미해결 — 아래 "내비
  화면 POI 시뮬레이션 검증" 항목 참조.

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

실물 폰(Galaxy M32, `RZ8RC1N3V9W`)을 adb로 westinx 서버에 USB 연결해 직접 검증함.

**연결 과정에서 발견한 것(중요, 다른 미스터리들과 직결)**: 폰에 앱이 **두 개** 설치돼
있었음 — `com.westinx.yurunavi`(현재 앱)과 **`com.example.winding_road`**(사용자가
4월에 Cursor로 만든 완전히 별개의 초기 프로토타입, 패키지명·프로젝트명 전부 다름).
사용자가 실주행 테스트 때 홈 화면 아이콘을 헷갈려 이 구버전 별개 앱을 실행했을 가능성이
매우 높음 — 위 "재확인 결과 2차"의 칩 고정/구버전 칩셋/카페 오염 세 증상 전부 이걸로
설명됨(별도 코드 버그 아님). 사용자 확인 후 `com.example.winding_road` 삭제 완료.

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

## 아직 안 건드린 나머지 항목 (우선순위 순, HANDOFF_0712_ridefeedback2.md §3 기반)
5. 검색 부분문자열 매칭 안 됨(앞글자만), 검색창 포커스 시 바텀시트 가려짐, 검색결과가
   화면중심 아닌 GPS위치 중심 (슬라이드6)
6. 경로선 레이어가 도로 라벨을 가림, 지나온 경로 회색 표시 요청 (슬라이드13)
7. 여러 UX 개선 요청(POI 프리로딩, 점 아이콘/터치, 목적지 확인 카드 등, 슬라이드1~6)
8. **신규**: "Start your Engine" 슬라이드 버튼이 화면 끝까지 밀어야 완료됨 — 트랙
   디자인 안에서 끝나도록 UX 정리 필요 (이번 세션 실기기 검증 중 발견)

## 명시적으로 미룬 것
- **유턴/스위치백 경로 costing 튜닝(슬라이드11)** — 사용자가 "미루고 다른 버그부터"라고
  명시. 먼저 꺼내지 말 것.

## 하지 말 것 / 주의
- `loop/feedback/260712_testDriveFeedback.pdf` 절대 Read 금지 (ECONNRESET 유발 확인됨).
- 이 세션 자체가 반복적으로 ECONNRESET로 끊기고 있음 — 매 단계 완료 시 즉시 이 파일
  갱신할 것.
