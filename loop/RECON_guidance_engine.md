# RECON_guidance_engine — TTS tier 엔진 구현 전 실물 확보 (읽기 전용)

작성: 2026-06-29
브랜치: `main` (Layer 1 머지 후 최신)
목적: `SPEC_guidance_config`(설계)를 프로덕션 구현 SPEC으로 떨구기 위해 실물 5개 확정.
산출물: 이 파일 `## FINDINGS`에 항목별 `file:line` + verbatim.

## ⛔ 범위·금지
- **읽기 전용.** 수정·커밋·fix 금지. 코드 덤프·구조 보고만.
- 모든 답 `file:line` + 코드 발췌. **추측 금지** — enum 정수는 소스/응답 실측만.
- 모호하면 중단·보고.

---

## A. VoicePackService API (`voice_pack_service.dart`)
```bash
cd /data/projects/yurunavi
sed -n '1,80p' $(grep -rl "class VoicePackService" lib)
```
- `load(...)` 시그니처·반환형. TTS인지 오디오파일 재생인지 둘 다인지.
- `speak(key, {vars})` — 템플릿 **조회 방식**, **변수 치환 방식**(현재 `{direction}` 어떻게 박나).
  → 엔진은 여기에 **`{dist}` 주입**이 필요. 치환이 일반 `{key}` 패턴인지, `direction` 하드코딩인지 확인.
- 기대하는 JSON 구조(현재 flat: `approach_500`/`approach_300`/`approach_50`/`departure`).
  이벤트 기반(`turn_left.approach`/`.imminent`)으로 재구조화 가능한지.

## B. Step / maneuver 모델 (`routing_service.dart` 등)
```bash
grep -rn "class ManeuverStep\|maneuver\|beginShapeIdx\|endShapeIdx\|\.type\|\.label\|leg" lib/ | grep -vi test | head -40
```
- maneuver **type 정수 필드** 노출 경로(이름).
- `label`(한글 방향어) **출처** — type→label 하드코딩 매핑 있나(메모리: `nav_screen _TurnStep._labelForType` 의심). verbatim.
- beginShapeIdx/endShapeIdx (Layer 1 추가분) 확인.
- **leg 경계(경유지) 식별 방법** — multi-leg 응답에서 waypoint 지점 어떻게 아나.
- `street_names`/`verbal_*` 파싱 여부(현재 폐기 중인지 — Layer 2 소재 확인).

## C. Valhalla maneuver type enum 정수 실측 (★ 추측 금지)
```bash
# fork 소스 enum
grep -rn "kRight\|kLeft\|kStart\|Maneuver_Type\|DirectionsLeg" /data/projects/valhalla-src/valhalla/proto/*.proto /data/projects/valhalla-src --include=*.h 2>/dev/null | grep -i "= [0-9]" | head -60
# 실응답 확인 (localhost)
curl -s "http://localhost:8002/route" -d '{"locations":[...],"costing":"motorcycle"}' | python3 -m json.tool | grep -A1 '"type"' | head
```
- `SPEC_guidance_config §3`의 `valhalla_types` 정수 배열을 **fork enum과 1:1 대조**해 확정.
- 로그 기지칭: 1=start, 2=start_right, 10=right, 15=left (실측 일치 확인분). 나머지 전부 채울 것.

## D. _handleVoice 현 구조 (`nav_screen.dart`, 엔진 삽입점)
```bash
sed -n '225,265p' $(grep -rl "_handleVoice\|YNAV_TTS" lib)
```
- seed-fix 후 현재 임계 블록(`if (d<=500 && !_said500)...` + seed 블록 + step 변경 감지) verbatim.
- 엔진(티어 선택+pending 소비)이 **이 블록을 통째로 대체**할 경계 확정.
- `_said500/300/50` 외 엔진이 흡수할 상태 변수 목록.

## E. ★ 발화 방향 소스 off-by-one (최우선 — 정확성)
- speak 호출의 `direction`(=`dir`)이 **어느 maneuver의 label**인가: `maneuvers[step]`? `[step+1]`?
  `[step-1]`? snap 기준 다음 vertex 기준?
- **교차검증**: 실주행 로그 사실 — step=N으로 전환 시 `YNAV_STEP ... maneuver=X`의 X는
  `maneuvers[step].type`. route1에서 `maneuvers[0]=start, [1]=우(10), [2]=좌(15), [3]=우(10)`.
  activeStep=0일 때 **다가오는 첫 턴 = maneuvers[1]=우회전**.
  → `dir`이 `maneuvers[step]`(=start)을 쓰면 **오방향**(원래 ③의 "좌회전" 오발화 뿌리).
- **확정해야 할 것**: "다가오는 턴"의 올바른 인덱스(=step? step+1?)와, 현재 `dir`이 그걸 쓰는지.
  step/snap 의미론(activeStep = 향하는 maneuver인가, 올라탄 세그먼트인가)을 `route_progress_provider`
  에서 file:line으로 확정.

## C/E 보조 — config 로드 패턴 (`guidance_profile.json` 배치용)
- `default_ko.json`을 자산으로 읽는 방식(`rootBundle.loadString` 등) + `pubspec.yaml` 자산 등록 file:line.
  → 엔진 config 로더가 같은 패턴 따르게.

## FINDINGS (Claude Code가 채움)

### A VoicePackService (load/speak/치환/JSON구조)
`lib/services/voice_pack_service.dart:11-25`

```dart
static Future<VoicePackService> load(String assetPath, FlutterTts tts) async {
  final raw = await rootBundle.loadString(assetPath);
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final templates = (data['templates'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, v as String));
  return VoicePackService._(templates, tts);
}

Future<void> speak(String key, {Map<String, String> vars = const {}}) async {
  final template = _templates[key];
  if (template == null) return;
  var text = template;
  for (final entry in vars.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value);
  }
  await _tts.speak(text);
}
```

- `load(String assetPath, FlutterTts tts) → Future<VoicePackService>`. 반환형 자기 자신. TTS 재생 전용(오디오 파일 아님).
- `speak(key, {vars})`: template을 `_templates[key]`로 조회, `text.replaceAll('{${entry.key}}', entry.value)` 일반 패턴. `{direction}` 하드코딩 없음 — vars Map의 키 이름이 `{key}` 자리를 채움.
- JSON 구조: `{ "templates": { "approach_500": "...", "approach_300": "...", "approach_50": "...", "departure": "...", "arrival": "..." } }` flat.
- `{dist}` 주입 가능: `vars: {'direction': dir, 'dist': '500m'}` 동일 패턴으로 확장 가능.

---

### B Step·maneuver (type/label출처/leg경계/verbal)
`lib/services/routing_service.dart:31-46`

```dart
class ManeuverStep {
  /// Valhalla maneuver type integer (e.g. 10=우회전, 15=좌회전, 4=도착).
  final int type;
  /// Valhalla가 반환한 영문 instruction.
  final String instruction;
  /// 이 구간 거리 (km).
  final double distanceKm;
  final int beginShapeIdx;   // 전역 인덱스 (leg 오프셋 적용 후)
  final int endShapeIdx;     // 전역 인덱스
  const ManeuverStep({
    required this.type,
    required this.instruction,
    required this.distanceKm,
    this.beginShapeIdx = 0,
    this.endShapeIdx = 0,
  });
}
```

- `label` 필드 없음. label 출처: `nav_screen.dart:1044 _labelForType(int type)` — type 정수 switch 한글 하드코딩. `_TurnStep.fromManeuver(m)` (nav_screen.dart:1018)에서 `_labelForType(m.type)` 호출.
- `beginShapeIdx`/`endShapeIdx`: leg 오프셋 적용 후 전역 인덱스. `routing_service.dart:428-429`:
  ```dart
  beginShapeIdx: shapeOffset + b,
  endShapeIdx:   shapeOffset + e,
  ```
- **leg 경계 식별**: `_collectManeuvers` (routing_service.dart:417)에서 legs 루프 순회 + `shapeOffset += legPts.length - 1` 누적. ManeuverStep에 leg boundary 마커 필드 없음. RouteResult에도 leg 경계 리스트 없음.
- `street_names`, `verbal_*`: 파싱 안 함. 수집 필드: `type`, `instruction`(영문, 현재 미사용), `length`, `begin_shape_index`, `end_shape_index`만. Layer 2 소재 미정.

---

### C Valhalla type enum 정수표
소스: `/data/projects/valhalla-src/proto/descriptors/directions.proto:42-85`

```
0  = kNone
1  = kStart
2  = kStartRight
3  = kStartLeft
4  = kDestination
5  = kDestinationRight
6  = kDestinationLeft
7  = kBecomes
8  = kContinue
9  = kSlightRight
10 = kRight
11 = kSharpRight
12 = kUturnRight
13 = kUturnLeft
14 = kSharpLeft
15 = kLeft
16 = kSlightLeft
17 = kRampStraight
18 = kRampRight
19 = kRampLeft
20 = kExitRight
21 = kExitLeft
22 = kStayStraight
23 = kStayRight
24 = kStayLeft
25 = kMerge
26 = kRoundaboutEnter
27 = kRoundaboutExit
28 = kFerryEnter
29 = kFerryExit
30 = kTransit
31 = kTransitTransfer
32 = kTransitRemainOn
33 = kTransitConnectionStart
34 = kTransitConnectionTransfer
35 = kTransitConnectionDestination
36 = kPostTransitConnectionDestination
37 = kMergeRight
38 = kMergeLeft
39 = kElevatorEnter
40 = kStepsEnter
41 = kEscalatorEnter
42 = kBuildingEnter
43 = kBuildingExit
44 = kLevelChange
45 = kParkVehicle
```

`_labelForType` 대조: 1→'출발' ✓, 2→'출발' ✓, 3→'출발' ✓, 4→'목적지 도착' ✓, 8→'직진'(kContinue) ✓, 9→'약간 우회전' ✓, 10→'우회전' ✓, 11→'급우회전' ✓, 12→'유턴'(kUturnRight) ✓, 13→'유턴'(kUturnLeft) ✓, 14→'급좌회전' ✓, 15→'좌회전' ✓, 16→'약간 좌회전' ✓, 22→'직진'(kStayStraight) ✓, 25→'합류'(kMerge) ✓, 26→'회전교차로 진입' ✓, 27→'회전교차로 진출' ✓, 28→'도선 탑승' ✓, 29→'도선 하차' ✓. 전체 일치 확인.

---

### D _handleVoice 현 블록 + 대체 경계
`lib/features/navigation/presentation/nav_screen.dart:235-262` verbatim:

```dart
void _handleVoice(RouteProgress prog) {
  final step = prog.activeStepIdx;
  final stepChanged = step != _voiceStepIdx;
  if (stepChanged) _voiceStepIdx = step;
  if (step + 1 >= _steps.length) return; // 마지막 = 도착, 턴 발화 없음
  final dir = _steps[step].label;
  final d = prog.distToNextTurnM;
  if (stepChanged) {
    _said500 = d <= 500;
    _said300 = d <= 300;
    _said50  = d <=  50;
  }
  if (d <= 500 && !_said500) {
    _said500 = true;
    debugPrint('YNAV_TTS thr=500 next=${d.toStringAsFixed(1)} step=$step maneuver=${step < widget.maneuvers.length ? widget.maneuvers[step].type : -1}');
    _vps?.speak('approach_500', vars: {'direction': dir});
  }
  if (d <= 300 && !_said300) {
    _said300 = true;
    debugPrint('YNAV_TTS thr=300 next=${d.toStringAsFixed(1)} step=$step maneuver=${step < widget.maneuvers.length ? widget.maneuvers[step].type : -1}');
    _vps?.speak('approach_300', vars: {'direction': dir});
  }
  if (d <=  50 && !_said50) {
    _said50  = true;
    debugPrint('YNAV_TTS thr=50 next=${d.toStringAsFixed(1)} step=$step maneuver=${step < widget.maneuvers.length ? widget.maneuvers[step].type : -1}');
    _vps?.speak('approach_50',  vars: {'direction': dir});
  }
}
```

- 호출 사이트: nav_screen.dart:217 `_handleVoice(prog);`
- 엔진이 흡수할 상태 변수: `_voiceStepIdx` (nav_screen.dart:82), `_said500`, `_said300`, `_said50` (nav_screen.dart:83).
- 엔진 대체 경계: `_handleVoice` 메소드 전체(:235-262) + 호출 사이트(:217). 선언 변수 4개 제거 대상.

---

### E ★ direction 소스 + 올바른 "다가오는 턴" 인덱스 (off-by-one 판정)

`nav_screen.dart:240`: `final dir = _steps[step].label;`  
`nav_screen.dart:236`: `final step = prog.activeStepIdx;`

`activeStepIdx` 산출: `route_progress_provider.dart:169-174`

```dart
int _activeStepFor(int seg) {
  for (int s = 0; s < _maneuvers.length; s++) {
    if (_maneuvers[s].endShapeIdx > seg) return s;
  }
  return _maneuvers.isEmpty ? 0 : _maneuvers.length - 1;
}
```

의미: "현재 snap seg가 아직 지나지 않은(endShapeIdx > seg) **첫 번째** maneuver 인덱스" = 현재 진행 중인 구간의 maneuver.

`_nextTurnShapeIdx` (route_progress_provider.dart:177-183):

```dart
int _nextTurnShapeIdx(int seg) {
  final s = _activeStepFor(seg);
  if (s >= _maneuvers.length) return _pts.length - 1;
  // 다음 턴 지점 = 현재 active maneuver의 종료 shape(그 지점에서 회전)
  return _clampIdx(_maneuvers[s].endShapeIdx);
}
```

`distToNextTurnM` = snap → `maneuvers[activeStep].endShapeIdx` 까지 거리.  
즉, **`activeStep` maneuver의 endShape에서 실행되는 턴 = `maneuvers[activeStep+1]`의 type/label**.

**판정: `dir = _steps[step].label` 은 activeStep(현재 진행 구간)의 label 사용 → off-by-one 버그 확정.**

- activeStep=0(출발 구간)이면 `dir='출발'` → approach_500에 "출발 방향" 오발화.
- 올바른 인덱스: `step + 1` (`_steps[step + 1].label`).
- guard 조건 `if (step + 1 >= _steps.length) return;` (nav_screen.dart:239) 이미 존재 — step+1 접근 안전.
- `distToNextTurnM` 타이밍 자체는 올바름(activeStep.endShape까지 측정).

---

### config 로드 패턴

- `rootBundle.loadString(assetPath)` — `lib/services/voice_pack_service.dart:12`
- 현재 경로: `'assets/voice_packs/default_ko.json'` — `nav_screen.dart:339`
  ```dart
  _vps = await VoicePackService.load('assets/voice_packs/default_ko.json', _tts!);
  ```
- pubspec.yaml:47 자산 등록:
  ```yaml
  assets:
    - assets/images/
    - assets/voice_packs/
  ```
- 엔진 config 로더는 동일 `rootBundle.loadString` + 동일 `assets/voice_packs/` 경로 패턴을 따를 것.

---

- (fix·재구조화 제안 금지 — 구현 SPEC에서)
