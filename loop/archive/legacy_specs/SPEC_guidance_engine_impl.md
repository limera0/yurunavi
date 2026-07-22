# SPEC_guidance_engine_impl — TTS tier 엔진 구현 (프로덕션)

작성: 2026-06-29
브랜치: `feat/guidance-engine` (main에서 분기)
선행: RECON_guidance_engine FINDINGS, 설계 SPEC_guidance_config.
RECON 반영 조정: **type→event 매핑은 config 아닌 코드(`_eventForType`)**. config는 타이밍+문구만.

## ⛔ 범위·규율
- **커밋 5개, 파일 1개 = 커밋 1개.** 각 `flutter analyze` 신규 에러 0. 한 곳 → analyze → 다음.
- distToNextTurnM/snap/route 계산부 **불변**. 계측 로그(YNAV_*) 유지·확장만.
- **머지 금지.** 데스크 재확인 → 라이딩 검증 후 별도.
- 모호하면 **중단·보고**. 특히 §C5의 `next`↔`step+1` 정합(아래) 불일치 시 즉시 halt.

---

## C1 — config 자산: `assets/config/guidance_profile.json` + pubspec 등록
```json
{
  "schema_version": 1,
  "profile_id": "default",
  "imminent_m": 5,
  "tiers": [
    { "min_entry_m": 500, "points_m": [500, 300, 50] },
    { "min_entry_m": 150, "points_m": [300, 50] },
    { "min_entry_m": 30,  "points_m": [100, 50] },
    { "min_entry_m": 0,   "points_m": [] }
  ],
  "events": {
    "turn_left":   { "enabled": true },
    "turn_right":  { "enabled": true },
    "uturn":       { "enabled": true },
    "ramp":        { "enabled": true },
    "exit":        { "enabled": true },
    "keep":        { "enabled": true },
    "merge":       { "enabled": true },
    "roundabout":  { "enabled": true },
    "continue":    { "enabled": false },
    "destination": { "enabled": true }
  }
}
```
- `pubspec.yaml` flutter assets에 `assets/config/guidance_profile.json` 추가(default_ko.json 등록 라인 옆).
- depart는 엔진 발화 대상 아님(`_announceStep`이 '출발합니다' 단독 — 기존 유지). config events에 미포함.

## C2 — `GuidanceProfile` 모델 + 로더 (신규 `lib/.../guidance_profile.dart`)
```dart
class GuidanceTier { final double minEntryM; final List<double> pointsM; ... }
class GuidanceProfile {
  final double imminentM;
  final List<GuidanceTier> tiers;            // minEntryM desc 정렬 보장
  final Set<String> enabledEvents;

  static Future<GuidanceProfile> load(String assetPath) async { /* rootBundle.loadString → jsonDecode, default_ko.json 로드 패턴 그대로 */ }

  GuidanceTier tierFor(double entryD) =>
      tiers.firstWhere((t) => entryD >= t.minEntryM);   // desc라 첫 매치
  bool isEnabled(String event) => enabledEvents.contains(event);
}
```
- 로드 실패 시 안전한 하드코딩 기본값으로 폴백(앱 무음화 방지). 폴백값 = 위 JSON과 동일.
- `_initTts()` 부근에서 `_profile = await GuidanceProfile.load(...)` (fire-and-forget 아님, await 후 구독 보장 권장 — 불가 시 null-guard).

## C3 — 음성팩 `default_ko.json` 이벤트 기반 재구조 (flat 유지, {dist} 주입)
speak(key,vars)가 일반 `{key}` 치환(FINDINGS A)이므로 **flat 키 + 이벤트 접두**:
```json
{
  "depart": "출발합니다",
  "turn_left_approach": "{dist}미터 앞 좌회전",
  "turn_left_imminent": "좌회전입니다",
  "turn_right_approach": "{dist}미터 앞 우회전",
  "turn_right_imminent": "우회전입니다",
  "uturn_approach": "{dist}미터 앞 유턴",
  "uturn_imminent": "유턴입니다",
  "ramp_approach": "{dist}미터 앞 진입",
  "ramp_imminent": "진입입니다",
  "exit_approach": "{dist}미터 앞 진출",
  "exit_imminent": "진출입니다",
  "keep_approach": "{dist}미터 앞 차선 유지",
  "keep_imminent": "차선 유지",
  "merge_approach": "{dist}미터 앞 합류",
  "merge_imminent": "합류 구간",
  "roundabout_approach": "{dist}미터 앞 회전교차로",
  "roundabout_imminent": "회전교차로",
  "destination_approach": "{dist}미터 앞 목적지",
  "destination_imminent": "목적지 도착"
}
```
- 구 키(`approach_500`/`approach_300`/`approach_50`) **제거**. '항상 300m' 템플릿 근본 소멸.

## C4 — `_eventForType(int type)` (nav_screen, type→event 카테고리)
- `_labelForType`(:1044)의 **동일 type 그룹핑**을 mirror해 영문 카테고리 반환:
  좌(14,15,16)→`turn_left`, 우(9,10,11)→`turn_right`, 유턴(12,13)→`uturn`,
  ramp(17,18,19)→`ramp`, exit(20,21)→`exit`, keep(22,23,24)→`keep`,
  merge(25,37,38)→`merge`, roundabout(26,27)→`roundabout`, destination(4,5,6)→`destination`,
  그 외(continue 등)→`continue`(또는 null=무발화).
- `_labelForType`는 UI 카드용으로 **유지**(건드리지 않음). `_eventForType`는 음성 전용 신설.

## C5 — tier 엔진: `_handleVoice` 교체 (`:235-262`) + 방향 off-by-one 수정 (★ 엔진 본체)

### 상태 (구 `_voiceStepIdx`,`_said500/300/50` 4개 → 2개로)
```dart
int _voiceStepIdx = -1;
List<double> _pendingPoints = [];   // 현재 step 잔여 안내점, desc
```

### 로직 (`:235-262` 블록 통째 대체)
```dart
void _handleVoice(RouteProgress prog) {
  if (_profile == null) return;
  final step = prog.activeStepIdx;
  final d = prog.distToNextTurnM;

  // ★ off-by-one 수정: 다가오는 턴 = step+1 (가드 기존 존재)
  final turnIdx = step + 1;
  if (turnIdx >= _steps.length) return;   // 마지막 구간 후속 턴 없음 → 도착은 YNAV_ARR/도착UX 담당
  final event = _eventForType(_steps[turnIdx].type);
  if (event == null) return;

  if (step != _voiceStepIdx) {                 // step 진입
    _voiceStepIdx = step;
    final entryD = d;
    final tier = _profile!.tierFor(entryD);
    final pts = [...tier.pointsM, _profile!.imminentM];
    _pendingPoints = pts.where((p) => p < entryD).toList()..sort((a, b) => b.compareTo(a));
  }

  while (_pendingPoints.isNotEmpty && d <= _pendingPoints.first) {
    final point = _pendingPoints.removeAt(0);
    final isImminent = point == _profile!.imminentM;
    if (_profile!.isEnabled(event)) {
      final key = '${event}_${isImminent ? 'imminent' : 'approach'}';
      _vps?.speak(key, vars: {'dist': point.toStringAsFixed(0)});
    }
    debugPrint('YNAV_TTS point=${point.toStringAsFixed(0)} d=${d.toStringAsFixed(1)} step=$step turnIdx=$turnIdx event=$event');
  }
}
```

### ★ halt 가드 (구현 전 필수 확인)
- `distToNextTurnM`(=`next`)이 **`_steps[step+1]`의 턴까지의 거리**가 맞는지 `route_progress_provider`
  에서 file:line 확인. 만약 `next`가 `_steps[step]` 기준이면 방향만 step+1로 고치면 **거리·방향 불일치**.
  → **불일치 시 중단·보고.** (FINDINGS E는 dir=step+1이 옳다 했으니 next도 step+1 정합일 것으로 기대,
  그러나 실코드로 확인 후 진행. 추측 금지.)
- imminent(5m)는 `p < entryD` 필터를 거의 항상 통과 → **close-turn 무음 해소**(원래 라이딩 갭).

---

## 검증 절차

### 1. 데스크 재확인 (라이딩 불요) — `route_check3.log`
목적지 설정 → 내비 개시 → 정차 10초:
```powershell
.\adb logcat -G 16M; .\adb logcat -c
# (개시 후) 
.\adb logcat -d | Select-String "YNAV_" | Out-File -Encoding utf8 route_check3.log
```
- 기대: step0 침묵(depart는 '출발합니다' 단독), 거짓 안내 0, `event=` 라벨이 다가오는 턴과 일치.

### 2. 라이딩 — `ride.log` (close-turn 포함 경로)
- **신규 합격**: 50m 안쪽 진입 턴도 **직전 cue 발화**("좌회전입니다"), **방향 정확**(step+1).
- **무회귀**: 거짓 300m 없음, 각 점 1회, 먼 턴은 티어 점(500/300/100/50)에서만, 도착 정상.
- `YNAV_TTS`의 `event=`/`point=`로 항목 대조.

## 산출
- C1~C5, 각 analyze 클린, push. **머지 금지.** 데스크 → 라이딩 통과 후 머지.
- v2(터널/교량/연속회전/N시방향)는 config events에 자리만, 코드 미구현 — 별도.
