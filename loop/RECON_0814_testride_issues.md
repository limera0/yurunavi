GOAL: 2026-08-14 단거리 실주행(VERIFY_0806_S3_master_device_check.md 작성 시점) 중 마스터가
보고한 5개 문제의 원인을 로그(loop/testride_result/log/ynav_2026-08-14T*.log 3개)와 코드로
조사한다. 이 세션은 조사만 하고 코드는 건드리지 않았다 — 다음 세션 착수 시 이 문서부터 읽을 것.

# RECON — 0814 실주행 5대 문제 원인 조사

- 작성 2026-08-14 · 브랜치 `verify/ride-0711`
- 근거: `loop/VERIFY_0806_S3_master_device_check.md` §9(S4a)·§16(S15)·§18(S17) 마스터 기재분,
  오늘 대화에서 마스터가 제기한 5개 항목, `loop/testride_result/log/ynav_2026-08-14T{17-10-43,
  17-33-06,18-26-00}.log`, 스크린샷 2장(`Screenshot_20260814_182523_Yurunavi.jpg`,
  `Screenshot_20260814_182838_Yurunavi.jpg`)
- **중요 전제**: 오늘 3개 세션 전부 `YNAV_SESSION ... release=false` — **디버그 빌드로 주행**
  (`lib/core/logging/file_logger.dart:38` `release=$kReleaseMode`). `CLAUDE.md` "헤드리스 서버:
  flutter build apk --debug"가 표준 빌드 경로라 특이사항은 아니지만, 렌더링/GPU 계열 결함(§1)은
  release 빌드에서 재현되는지 별도 확인이 필요하다 — 로드맵 10번("실제 release build 검증")이
  아직 미완료인 이유와 직결된다.

## 로그 세션 개요

| 파일 | 시작 | 끝 | 비고 |
|---|---|---|---|
| ynav_2026-08-14T17-10-43.log | 17:10:43 | 17:27:30 | 초반 주행 |
| ynav_2026-08-14T17-33-06.log | 17:33:06 | 18:25:56(background) | 메인 주행, 도착 없이 background로 종료 |
| ynav_2026-08-14T18-26-00.log | 18:26:01 | 18:30:04 | **17-33 세션 종료 5초 뒤 완전 재기동.** S15 TOUR_RECOVERY(18:26:09) → 도착(18:27:59) → §1 블랙스크린 발생 구간 |

---

## 1. 내비 종료 후 블랙스크린 — 원인 강하게 특정됨 (§VERIFY-2 연장선)

**결론(쉬운 설명)**: 도착 처리 직후 앱이 "포그라운드 ↔ 백그라운드"를 짧은 시간에 두 번 왔다갔다
했고, 그 과정에서 화면을 그리는 창(Surface)이 파괴된 뒤 다시 만들어지지 않았다. 앱은 살아있고
뒤로가기 입력도 받지만(그래서 뒤로가기 연타로 탈출 가능), 화면에 아무것도 그리지 못해 까맣게
보인 것으로 보인다. 이 자체가 8/6에 이미 미해결로 남아있던 "내비 종료 후 오버레이가 앱 위에
잔존" 버그(`VERIFY_0806...md` §2 마지막 항목, 그때도 X)와 같은 계열일 가능성이 높다.

**로그 타임라인** (`ynav_2026-08-14T18-26-00.log`):
- `18:28:10.354` `MapLibreGLSurfaceView` → `onWindowVisibilityChanged(8) false` → `surfaceDestroyed`
  (지도 레이어만 파괴 — `YNAV_TOUR saved`가 0.5초 뒤인 것과 맞물려, nav_screen에서 다른 화면으로
  전환되며 지도 위젯이 언마운트되는 정상 흐름으로 추정)
- `18:28:28.267` **`FlutterSurfaceView`**(앱 전체 렌더링 표면, bounds `0,0-1080,2340` = 전체 화면)
  → `onWindowVisibilityChanged(8) false` → `surfaceDestroyed`. 같은 시각
  `YNAV_MEMPRESSURE onTrimMemory` + `background imageCache cleared` 동시 발생 — 진짜 백그라운드
  전환으로 확인됨.
- `18:28:32.404~496` `FlutterSurfaceView` 재생성 (`BLASTBufferQueue` new → `surfaceCreated`) — 4초
  만에 복귀.
- **`18:28:38` — 마스터가 블랙스크린 스크린샷을 찍은 시각.** 직전 재생성(18:28:32)으로부터 6초
  지난 시점인데도 화면이 까맣다 — 표면은 "생성"됐지만 실제로 프레임이 그려지지 않은 상태로 추정.
- `18:28:44.623` `FlutterSurfaceView` **다시** `surfaceDestroyed`. 같은 시각 다시
  `onTrimMemory`+`background` 동시 발생(16초 만에 재발 — 정상적인 단일 백그라운드 전환이라면
  이렇게 반복되지 않아야 함).
- 로그 캡처 종료(18:30:04)까지 **이 두 번째 파괴 이후 재생성 로그가 없음** — 즉 마스터가 실제
  탈출(뒤로가기 연타)할 때까지 화면이 계속 안 그려졌을 가능성과 부합.
- `YNAV_GPUMEM`: 18:27:01 graphics≈160MB → 18:28:01 graphics≈182MB → **18:29:09 graphics≈13MB**로
  급락(같은 구간에서 GPU 리소스가 강제로 반납된 정황). `YNAV_CRASH` 0건 — 하드 크래시는 아님.

**미확정 부분**: 왜 도착 직후 40초 사이에 background 전환이 두 번이나 발생했는지는 로그만으로는
단정 못 함. 유력 후보는 `nav_screen.dart:504-516`의 `didChangeAppLifecycleState`가 paused/hidden
마다 `NavFloatingOverlay.show()`를 호출하는 구조 — 도착 후 화면 전환과 오버레이 표시/해제 요청이
겹치면서 포커스가 흔들렸을 가능성. `FloatingOverlayService.kt`의 show/hide는 서로 다른 Intent
액션(ACTION_SHOW/HIDE)으로 각각 비동기 처리되고 `overlayView` 참조를 1개만 추적하므로
(`FloatingOverlayService.kt:49-50,79-133,148-155`), 겹쳐 호출되면 좀비 뷰가 남을 수 있는 구조라는
점은 코드로 확인됨(§VERIFY-2 8/6 기록과 일치). 다음 재현 시 `adb logcat`을 동시에 띄워
`FlutterSurfaceView`/`WindowManager` 라인이 어떤 호출과 겹치는지 대조하면 확정 가능.

## 2. 좌회전 TTS 미발화 — "생성은 됐는데 실제로 안 들림" 쪽에 가까움

**결론(쉬운 설명)**: 로그상으로는 좌회전 안내가 6번이나 "말하라"는 명령까지는 내려갔다. 그런데
그 중 처음 두 개(급커브용 안내, 일반 좌회전 안내)가 **같은 지점을 놓고 서로 다른 두 엔진이
각자 감지해서 4초 간격으로 거의 동시에** 발화 명령을 냈다. 이 앱의 TTS는 겹치는 호출을 한 줄로
순서대로 재생하도록 큐를 걸어놨는데, 그 큐 코드 자체에 "특정 상황(TTS 엔진 콜백 오류)에서 최대
8초간 큐가 완전히 막혀 이후 안내가 조용히 먹통이 된다"는 알려진 결함이 주석으로 이미 적혀있다.
오늘 좌회전에서 겪은 "이중 발화 요청"이 바로 그 결함을 건드릴 조건과 정확히 일치한다.

**로그 근거** (`ynav_2026-08-14T17-33-06.log`):
```
17:36:44.133  sharp_turn_left_approach dist=오백오십  (CurveVoiceEngine — 지오메트리 기반 급커브 감지)
17:36:48.147  turn_left_approach       dist=오백오십  (VoiceEngine — Valhalla maneuver 기반, 불과 4초 뒤)
17:36:59.165  sharp_turn_left_approach dist=삼백오십
17:37:14.151  sharp_turn_left_approach dist=백
17:37:20.149  turn_left_imminent       dist=오십
```
같은 시간대 우회전(예: 18:14:24~18:15:26 `turn_right_approach`→`turn_right_imminent`)은 단일
계열로만 깔끔하게 발화됨 — 오늘 이 특정 좌회전만 유독 지오메트리 급커브 판정과 Valhalla
maneuver 판정이 동시에 걸린 것으로 보인다.

**코드 근거**:
- [voice_engine.dart:16-17](lib/features/navigation/voice_engine.dart#L16-L17) — Valhalla
  maneuver type 14/15/16이 `turn_left`/`sharp_turn_left`로 매핑
- [voice_engine.dart:366-368](lib/features/navigation/voice_engine.dart#L366-L368) —
  `CurveVoiceEngine`은 별도로 지오메트리만 보고 `sharp_turn_left`를 독립적으로 판정(위 maneuver
  판정과 무관하게 항상 켜져 있음)
- [guidance_arbiter.dart:9](lib/features/navigation/guidance_arbiter.dart#L9) — 우선순위
  `voice > structure > curve`, 최소 간격 4초. 오늘 로그의 두 발화는 정확히 4.0초 차이라 간격
  체크는 통과했지만, 그 다음 레이어인 TTS 재생 자체에서 문제가 났을 가능성.
- [voice_pack_service.dart:30-52](lib/services/voice_pack_service.dart#L30-L52) — 주석 원문:
  "flutter_tts 4.2.5 네이티브 결함... 큐가 영구히 막혀 이후 모든 발화가 조용히 먹통이 된다 —
  8초로 강제 settle". **이 결함 자체를 로그로 확증할 방법이 현재 없다** — speak() 호출(큐 투입)
  시점만 `YNAV_TTS`로 남고, 실제 재생 성공/실패(onDone/onError)는 로깅되지 않음.

**다음 세션 확인용 제안**: `voice_pack_service.dart`의 `_tts.speak()` 호출부에
`onError`/`onDone`/타임아웃 발동 여부를 `YNAV_TTS_RESULT` 같은 새 로그 줄로 남기면, 다음 실주행
때 "발화 요청은 갔는데 실제로 안 들렸다"를 로그만으로 확정할 수 있다.

**2026-08-14 저녁 — 마스터 확인 + 조치**: 마스터가 별도로 "회전교차로(로터리) 통과 중에도 급회전
안내가 자꾸 끼어들어 중복됐다"고 확인 — `CurveVoiceEngine`(지오메트리 기반)이 로터리 진입/진출
곡선 구간에서도 오탐 발화하는 것으로 보이며, 위에서 분석한 좌회전 이중발화와 같은 계열(같은
지점을 Valhalla maneuver 판정과 지오메트리 판정이 각각 독립적으로 잡아 충돌)로 판단됨.
**조치**: `sharp_turn_left`/`sharp_turn_right` 안내를 `assets/config/guidance_profile.json`의
`enabled: false`로 완전 비활성화(커밋 예정) — `VoiceEngine`(maneuver 기반)과
`CurveVoiceEngine`(지오메트리 기반) 양쪽 다 이 플래그 하나로 억제됨
([voice_engine.dart:218](lib/features/navigation/voice_engine.dart#L218),
[voice_engine.dart:397](lib/features/navigation/voice_engine.dart#L397) 둘 다
`profile.isEnabled(event)` 게이트를 거침). `RoutingService.detectSharpCurves()` 자체(지오메트리
탐지 로직)는 건드리지 않았다 — 다음에 재활성화할 때는 이 탐지가 로터리 곡선을 오인하지 않도록
억제 조건을 먼저 손봐야 한다(§VERIFY 검단회전교차로 프로브 참고). 마스터가 이 상태로 재검증
주행 후 좌회전/우회전 안내가 정상인지 판단할 예정 — 재검증 결과 전까지 이 flag를 되돌리지 말 것.

## 3. 거리 안내 반올림(550→"오백오십", 350→"삼백오십") — 원인 확정

**결론**: 550m·350m 지점은 "50m 단위로 반올림"해도 원래 50의 배수라 반올림이 아무 효과가 없다.
그래서 "조금 일찍 트리거하되 깔끔한 숫자로 말한다"는 원래 의도(550 트리거 → "500m 앞" 발화)가
실제로는 트리거 값을 그대로 읽는 것으로 끝나버린다. 70m(임박 안내) 케이스는 70이 50의 배수가
아니라서 반올림이 우연히 의도대로 50으로 떨어져 정상 작동 중 — 8/6 VERIFY엔 이것도 불량이라고
적혀 있었는데 오늘 로그(`turn_right_imminent dist=오십`)를 보면 그 부분은 이미 고쳐진 상태.
**남은 문제는 550/350 두 트리거뿐.**

**코드 근거**:
- [voice_engine.dart:52-65](lib/features/navigation/voice_engine.dart#L52-L65) `_distToKorean()` —
  `(distM/50).round()*50`로 "가장 가까운 50m"만 계산, 550/350처럼 이미 50의 배수인 값은 그대로
  통과.
- [guidance_profile.json:7,17,27](assets/config/guidance_profile.json#L7) — `turn_left`/
  `turn_right`/기본 tier의 접근 포인트가 `[550, 350, ...]`으로 박혀 있음. 트리거 시점(조금
  일찍 울리기)과 발화 문구(깔끔한 숫자)가 값 하나로 묶여 있어 분리가 안 된 구조.

**고치는 방법(제안, 미착수)**: 70m→50m가 이미 "50의 배수가 아닌 트리거값을 넣으면 자동으로
깔끔한 숫자로 반올림된다"는 패턴으로 우연히 작동 중이므로, 같은 패턴을 550/350에도 적용 —
예: JSON의 트리거값을 550/350 대신 500~524·300~324 범위의 비50배수 값(예 520/320)으로 바꾸면
기존 `_distToKorean` 로직 그대로 "500m"/"300m"로 떨어진다. 코드 변경 없이 설정값만 조정하는
가장 작은 수정.

**2026-08-14 저녁 — 적용 완료**: 위 제안대로 `guidance_profile.json`의 `tiers`(전역)·
`turn_left`·`turn_right`·`roundabout_enter` 4곳의 550→520, 350→320 전부 치환(커밋 예정).
`_distToKorean` 함수 자체는 변경하지 않음(테스트 `voice_engine_test.dart` N4가 "550→오백오십"을
함수 고유 동작으로 정확히 검증하고 있어 그대로 둠 — 버그는 함수가 아니라 JSON 트리거값에
있었다는 진단과 일치). `flutter test`로 관련 6개 테스트 파일(64건) 전부 통과 확인 — 어떤 테스트도
실제 JSON 파일을 로드하지 않아(전부 자체 fixture 사용) 회귀 없음.

## 4. 플로팅 오버레이 — 마스터 확인 결과, 오독 정정 (2026-08-14 저녁 대화)

**최초 조사에서 오독함** — 이 세션 초반엔 스크린샷 속 큰 박스가 72dp 코드와 안 맞아서
"유루나비 자체 화면을 착각한 것 아니냐"고 추측했으나, **마스터가 직접 정정**: 그 스크린샷은
**유루나비가 백그라운드로 간 상태에서 네이버지도가 전경에 떠 있고, 그 네이버지도 화면 위에
네이버지도 자신의 플로팅 위젯이 떠 있는 장면**이다. 즉 스크린샷 속 나머지 UI(속도계·컴퍼스·
주유소 버튼 등)는 유루나비가 아니라 네이버지도 자체 화면이고, "843m/169m" 박스가 네이버지도의
자체 플로팅 내비 위젯 — **이것이 마스터가 제시한 모범사례(참고 기준)**다.

**결론**: 유루나비의 현재 오버레이(72dp 정사각형, 아이콘 1개+거리 텍스트 1줄만,
`FloatingOverlayService.kt`+`floating_nav.xml` 기준, 우측 하단 고정, 드래그 이동 없음)를
네이버지도의 이 스타일 — **더 큰 카드, 2줄(현재 안내+다음 안내 동시 표시), 이동 가능** —
을 기준으로 재설계해야 한다. 후속 작업 지시서:
[HANDOFF_0814_S21_floating_overlay_redesign.md](HANDOFF_0814_S21_floating_overlay_redesign.md).

## 5. 투어 기록 병합 미구현 + 공유 화면 스코프 오류 — 둘 다 재확인됨, 미착수 그대로

**5-a. 병합 미구현**: 오늘 로그로 실제 재현됨.
- `18:26:09` `YNAV_TOUR_RECOVERY recovered id=1786697959328 distanceM=10486 ...` — S15가 중단된
  투어(10.486km)를 감지해 별도 기록으로 확정 저장
- `18:28:10` `YNAV_TOUR saved id=1786699574685 distanceM=1017 ...` — 재개 후 도착까지 달린
  구간(1.017km)이 **완전히 다른 id로 또 저장됨**
- [tour_recovery_service.dart:224-247](lib/services/tour_recovery_service.dart#L224-L247)
  `finalizeAsInterrupted()` 주석 원문: "재개를 수락해도... 거절해도... 동일하게 이 메서드로
  마무리" — 즉 재개를 수락하는 경로 자체가 설계상 원본 투어를 "비정상 종료로 자동 복구됨" 메모와
  함께 독립 기록으로 확정하고, 재개 구간은 처음부터 별개의 새 투어로 시작한다. 두 기록을 하나로
  합치는 코드는 프로젝트 전체에 없음(`merge` 키워드 검색 결과 tour 관련 서비스 파일에 매치 0건).
  `VERIFY_0806...md` §16에서 마스터가 이미 X로 남긴 항목("병합하는 기능이 없음")과 정확히 일치 —
  8/10 구현 때부터 스코프에서 빠진 채 8/14까지 그대로.

**5-b. 공유 화면**: `git log --since=2026-08-11 -- lib/features/route lib/services/route_share*`
결과 0건, `lib/features/route/`·`nav_screen.dart` 전체에서 "공유"/"RouteShare" 매치 0건 — 8/11에
마스터가 "투어 완료 후가 아니라 출발 전 코스 선택/내비 화면에 공유 버튼이 있어야 한다"고 스코프
정정을 남긴(`VERIFY_0806...md` §18) 이후 **관련 코드가 전혀 손대지지 않음**. 현재도 공유 진입점은
투어 완료 후 상세 화면에만 있는 8/10 원안 그대로.

---

## 세션 결과 (2026-08-14 저녁 대화에서 확정)

- **§1 블랙스크린** — 내일 아침(무인 낮 루프)에 착수. 목표 고정:
  [HANDOFF_0814_S20_nav_end_blackscreen.md](HANDOFF_0814_S20_nav_end_blackscreen.md)
- **§2 좌회전/급회전 중복** — 오늘 밤 조치 완료: `sharp_turn_left`/`sharp_turn_right` 비활성화
  (위 §2 "적용 완료" 참고). 마스터가 다음 실주행에서 좌/우회전·로터리 안내가 정상인지
  재검증할 예정 — 결과 나오기 전까지 이 상태 유지.
- **§3 거리 반올림** — 오늘 밤 수정 완료(위 §3 "적용 완료" 참고).
- **§4 오버레이 UX** — 네이버지도 기준으로 재설계 필요하다고 스코프 확정, 후속 세션용 지시서:
  [HANDOFF_0814_S21_floating_overlay_redesign.md](HANDOFF_0814_S21_floating_overlay_redesign.md).
  착수 시점은 미정 — §1과 같은 파일(`FloatingOverlayService.kt`)을 건드리므로 §1 완료 후가
  안전.
- **§5 투어 병합 + 공유 화면** — 아직 착수 시점 미정, 이 세션에서 결정 안 됨. 다음 저녁 대화에서
  확인 필요.
