# SPEC_sim_harness — VoiceEngine 추출 + 순수 unit 하니스

작성: 2026-06-29
브랜치: `feat/guidance-engine`
선행: RECON_sim_harness FINDINGS (voice 로직이 `_NavScreenState`에 갇힘 → widget test 필요로 판정).
방침 전환: widget test(MapLibre/TTS 플러그인 채널 함정) 회피 → **엔진을 순수 클래스로 추출해 unit test**.
목표: 라이딩 전 엔진 로직(티어/pending/방향 step+1/type→event/도착)을 **`flutter test` 단독**으로 전수 검사.

## ⛔ 범위·규율
- 커밋 3개, 파일 1개 = 커밋 1개. 각 `flutter analyze` 신규 에러 0.
- **거동 불변 리팩터** — 발화 결과·YNAV_TTS 로그 포맷 그대로. 추출만, 로직 변경 금지.
- 머지 금지. 하니스 녹색 → 라이딩(GPS 거동) 후 별도.
- 모호하면 중단·보고. 특히 §C1 halt 가드.

---

## C1 — `VoiceEngine` 순수 클래스 추출 (신규 `lib/.../voice_engine.dart`)

`_handleVoice`(현 nav_screen.dart:237)의 엔진 로직을 **위젯 무의존 클래스**로 이전.

```dart
class SpeakIntent {
  final String key;                 // 예: 'turn_right_approach'
  final Map<String, String> vars;   // 예: {'dist': '300'}
  const SpeakIntent(this.key, this.vars);
}

class VoiceEngine {
  final GuidanceProfile profile;
  VoiceEngine(this.profile);

  int _voiceStepIdx = -1;
  List<double> _pendingPoints = [];

  /// 매 progress tick 호출. 발화할 의도 목록 반환(보통 빈 리스트).
  /// steps: ManeuverStep 리스트(.type 필요). step: activeStepIdx. d: distToNextTurnM.
  List<SpeakIntent> onProgress(int step, double d, List<ManeuverStep> steps) {
    final turnIdx = step + 1;                 // ★ off-by-one 수정 유지
    if (turnIdx >= steps.length) return const [];
    final event = _eventForType(steps[turnIdx].type);   // C4에서 옮겨오거나 참조
    if (event == null) return const [];

    if (step != _voiceStepIdx) {
      _voiceStepIdx = step;
      final entryD = d;
      final tier = profile.tierFor(entryD);
      final pts = [...tier.pointsM, profile.imminentM];
      _pendingPoints = pts.where((p) => p < entryD).toList()..sort((a, b) => b.compareTo(a));
    }

    final out = <SpeakIntent>[];
    while (_pendingPoints.isNotEmpty && d <= _pendingPoints.first) {
      final point = _pendingPoints.removeAt(0);
      final isImminent = point == profile.imminentM;
      if (profile.isEnabled(event)) {
        out.add(SpeakIntent(
          '${event}_${isImminent ? 'imminent' : 'approach'}',
          {'dist': point.toStringAsFixed(0)},
        ));
      }
    }
    return out;
  }
}
```

### halt 가드
- `_eventForType`가 현재 `_TurnStep` 내부 static(C4 note)이면, **`VoiceEngine`에서 접근 가능한 위치**
  (top-level 함수 또는 `ManeuverStep` 확장)로 옮길지 결정 필요. 옮기면 그 사용처(카드)도 영향 →
  **사용처 1곳뿐이면 옮기고, 다곳이면 중단·보고**(추측 이동 금지).
- `_handleVoice`가 위 4입력(step,d,steps,profile) 외 **위젯 state에 더 의존**하면(예: 별도 플래그/타이머),
  그 의존 항목 verbatim 보고 후 중단. 순수 추출이 안 되면 설계 재논의.

## C2 — `_handleVoice` 어댑터화 (nav_screen.dart)

```dart
late final VoiceEngine _voiceEngine;   // _profile 로드 후 생성
// initState/프로파일 로드 직후: _voiceEngine = VoiceEngine(_profile!);

void _handleVoice(RouteProgress prog) {
  if (_profile == null) return;
  final intents = _voiceEngine.onProgress(prog.activeStepIdx, prog.distToNextTurnM, _steps);
  for (final it in intents) {
    _vps?.speak(it.key, vars: it.vars);
    debugPrint('YNAV_TTS key=${it.key} dist=${it.vars['dist']} step=${prog.activeStepIdx}');
  }
}
```
- 구 `_voiceStepIdx`/`_pendingPoints` state 필드 **제거**(엔진으로 이전).
- YNAV_TTS 로그 유지(필드명만 key= 로 — 라이딩 분석 호환되게 event/point 포함).

## C3 — 하니스: `test/voice_engine_test.dart`

`ManeuverStep` 리터럴 + 합성 (step, d) 시퀀스로 `VoiceEngine.onProgress`를 구동, 발화 의도 검증.
플러그인·위젯·provider 불필요.

### 시나리오 (각 group)
| # | 상황 | 진입 d | steps[step+1].type | 기대 발화(순서) |
|---|------|--------|--------------------|-----------------|
| A 먼턴 | 우회전 | 600 | 10 | 500→300→50 approach, 5 imminent (turn_right) |
| B 중턴-상 | 좌회전 | 450 | 15 | 300→50 approach, imminent |
| C 중턴-하 | 좌회전 | 200 | 15 | 50 approach, imminent (300 스킵: 200<300) |
| D 근턴 | 좌회전 | 120 | 15 | 100→50 approach, imminent |
| E 근턴-진입내 | 좌회전 | 80 | 15 | 50 approach, imminent (100 스킵) |
| F 초근접 | 우회전 | 25 | 10 | imminent만 (직전 5m) |
| G 방향정확 | — | 600 | step+1=우(10), step=좌(15) | 발화 event=**turn_right**(step+1), step 좌 아님 |
| H type=0 | — | 600 | 0(kNone) | **무발화**(continue→null) |
| I 도착 | — | — | turnIdx>=len | 무발화(엔진 빈 리스트), 크래시 없음 |

- 각 시나리오: 진입 tick 1회 + d를 점들 아래로 단조 감소시키며 tick → 누적 SpeakIntent의 key/dist 검증.
- 핵심 단언:
  - **C/E**: 진입 시 이미 안쪽인 상위 점(300/100)이 **안 나옴**("174m 앞" 류 차단 증명).
  - **F**: close-turn에 **imminent 발화**(지난 라이딩 무음 갭 해소 증명).
  - **G**: event가 step+1 턴 — off-by-one 회귀 차단.
  - **H**: type=0 폴백 무발화.

## 실행 (라이딩 불요)
```bash
cd /data/projects/yurunavi
flutter test test/voice_engine_test.dart
```
- 전 시나리오 녹색 → 엔진 로직 전수 통과. 그 다음 라이딩은 **GPS 거동만** 1회.
- 실패 시 케이스별 기대/실제 보고 → 로직 수정 SPEC.

## 산출
- C1~C3, 각 analyze 클린, `flutter test` 녹색, push. **머지 금지.**
- 녹색 후: 라이딩 1회(close-turn 포함 경로)로 GPS·타이밍 최종 확인 → 머지.
