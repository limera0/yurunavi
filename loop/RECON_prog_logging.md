# RECON_prog_logging — Layer 1 계측 삽입점 locate (읽기 전용)

작성: 2026-06-28
브랜치: `feat/layer1-progress` (체크아웃 상태로 조사, 변경·커밋 금지)
목적: ②③ TTS 증상을 **코드 읽기로 추측하지 않고 로그 숫자로 판정**하기 위해,
구조화 로그 4종을 삽입할 **정확한 file:line**과 현재 코드를 확보한다.

## ⛔ 범위·금지 (엄수)

- **읽기 전용.** 코드 수정·커밋·fix·로그 삽입 전부 금지. 이번 단계는 "어디에 넣을지" 확정만.
- 산출물: 이 파일 하단 `## FINDINGS`에 항목별 `file:line` + 현재 코드 3~8줄 발췌.
- 인용 없는 추정 금지. 모호하면 중단·보고.

## 배경

- 라이딩 결과: ① 카드 단조 OK(절대값 미검증), ② TTS 비정상, ③ 실거리<100m에 "300m 앞 좌회전".
- 다음 단계에서 아래 로그 4종을 삽입 → 1회 주행 → 로그로 H1(템플릿 하드코딩)/H2(거리 과대) 판정.

## 삽입할 로그 4종 (이번엔 넣지 말 것 — 위치만 찾기)

```
YNAV_PROG snap=<int> step=<int> next=<m.1f> dest=<m.1f> off=<bool> perp=<m.1f>
YNAV_STEP from=<int> to=<int> maneuver=<en> beginShape=<int> endShape=<int>
YNAV_TTS  thr=<500|300|50> next=<m.1f> step=<int> maneuver=<en> txt="<발화>"
YNAV_ARR  dest=<m.1f> snap=<int> lastShape=<int>
```

## 조사 항목 (각 file:line + 코드 발췌)

### A. YNAV_PROG 삽입점 — routeProgressProvider 갱신 지점

```bash
cd /data/projects/yurunavi && git rev-parse --abbrev-ref HEAD
sed -n '1,200p' lib/**/route_progress_provider.dart 2>/dev/null || \
  grep -rln "routeProgressProvider\|distToNextTurnM\|snapIdx" lib/
```

- snapIdx / distToNextTurnM / distToDestM / offRoute가 **계산 완료되어 노출되는 한 지점** 특정.
- `perp`(경로까지 수직거리)가 이미 계산되는가? 안 되면 어느 변수에서 파생 가능한지(스냅 세그먼트 투영 잔차) 위치만.
- 이 provider가 값을 emit하는 build/return 라인 = YNAV_PROG 한 줄 들어갈 자리.

### B. YNAV_TTS 삽입점 — 발화 직전 (★③ 결정타 라인)

```bash
grep -rn "speak(\|TtsService\|flutterTts\|voice_pack\|default_ko\|앞 " lib/ | grep -vi test
```

- 실제 `speak()` 호출 지점 file:line.
- 그 지점에서 **이미 손에 있는 값**: 트리거 임계값(thr), 그 순간 distToNextTurnM(next), step, maneuver, 발화 문자열(txt).
- 임계값 비교 조건문(500/300/50) file:line — `thr`로 찍을 값이 거기 있음.

### C. 거리 소스 — 카드 vs TTS (H1/H2 사전 단서)

- 턴 카드 잔여거리 표시 소스 file:line.
- TTS 거리 소스 file:line.
- 둘이 같은 `distToNextTurnM`인가 다른가. (같은데 카드만 맞으면 H1 강함)

### D. 발화 문자열 생성 — 템플릿 실체

```bash
sed -n '1,40p' assets/voice_packs/default_ko.json
```

- 거리 토큰이 하드코딩("300m")인지 플레이스홀더(`{dist}`)인지, maneuver 토큰도. 9-10행 그대로 인용.
- 문자열 빌더가 live `next`를 주입하는 라인 vs 템플릿 그대로 읽는 라인.

### E. YNAV_STEP / YNAV_ARR 삽입점

- step 전환(증가)이 일어나는 file:line. from/to/maneuver/beginShape/endShape가 그 자리에 있나.
- 도착 판정(arrived=true) file:line. dest/snap/lastShape 접근 가능 여부.

## FINDINGS (Claude Code가 채움)

### A. YNAV_PROG 삽입점

**파일:** `lib/features/navigation/providers/route_progress_provider.dart:142`
`state = RouteProgress(...)` 바로 직전 (line 141 다음, line 142 앞).

그 시점의 로컬 변수:
```dart
// route_progress_provider.dart:120-141
final offRoute = bestPerp > _kOffRouteM;           // offRoute
// ...
_snapIdx = bestSeg;                                 // snap
final traveledM = _cumFromStartM[bestSeg] + bestAlongM;
final activeStep = _activeStepFor(bestSeg);         // step
final nextTurnShape = _nextTurnShapeIdx(bestSeg);
final distToNext = ...clamp(0.0, ...);              // next
final distToDest = (_totalM - traveledM).clamp(...);// dest
final arrived = distToDest <= _kArrivalM;
// ← YNAV_PROG 삽입 지점
state = RouteProgress(
  snapIdx: bestSeg,
  activeStepIdx: activeStep,
  distToNextTurnM: distToNext,
  distToDestM: distToDest,
  arrived: arrived,
  offRoute: offRoute,
);
```

### B. YNAV_TTS 삽입점 (+ thr 비교 조건)

**파일:** `lib/features/navigation/presentation/nav_screen.dart:244-246`
`_handleVoice()` 내부, 각 `_vps?.speak(...)` 직전.

```dart
// nav_screen.dart:235-246
void _handleVoice(RouteProgress prog) {
  final step = prog.activeStepIdx;               // step
  if (step != _voiceStepIdx) { ... }
  if (step + 1 >= _steps.length) return;
  final dir = _steps[step].label;                // maneuver
  final d = prog.distToNextTurnM;                // next
  if (d <= 500 && !_said500) { _said500 = true; _vps?.speak('approach_500', ...); } // thr=500
  if (d <= 300 && !_said300) { _said300 = true; _vps?.speak('approach_300', ...); } // thr=300
  if (d <=  50 && !_said50)  { _said50  = true; _vps?.speak('approach_50',  ...); } // thr=50
}
```

**thr 비교 조건:** `d <= 500`, `d <= 300`, `d <= 50` (각 라인에 threshold 값 명시적).

**`txt` 렌더링 위치:** `lib/services/voice_pack_service.dart:22-26`
```dart
var text = template;
for (final entry in vars.entries) {
  text = text.replaceAll('{${entry.key}}', entry.value);
}
await _tts.speak(text);  // ← 여기서 txt 확정
```
`txt`는 speak() 내부에서만 렌더링됨. YNAV_TTS 한 줄에 모두 넣으려면
call site(nav_screen.dart:244-246)에서 template을 미리 render하거나,
speak() 반환값/파라미터를 추가해야 함 → SPEC 단계에서 결정.

### C. 카드/TTS 거리 소스 동일 여부

**동일 소스.** 두 곳 모두 동일한 `prog.distToNextTurnM`을 읽음:

- 카드: `nav_screen.dart:214` → `_cardRemainingM = prog.distToNextTurnM;`
- TTS:  `nav_screen.dart:243` → `final d = prog.distToNextTurnM;`

`_progressSub` 콜백 (nav_screen.dart:210-232)에서 `setState()` → `_handleVoice(prog)` 순으로
**같은 prog 객체**를 사용. 카드값과 TTS 트리거값은 항상 동일.

결론: 카드가 맞는 거리를 표시하면서 TTS가 늦게 발화된다면 → H2(거리 과대) 방향이 아니라
`_said300` 플래그 리셋 타이밍 / `_voiceStepIdx` 동기화 문제 가능성.
카드도 과대라면 → H2(distToNextTurnM 자체 과대). 로그로 확인 필요.

### D. 템플릿 하드코딩 여부 (9-10행 인용)

`assets/voice_packs/default_ko.json` 9-10행:
```json
    "approach_300": "300m 앞 {direction}",
    "approach_50":  "곧 {direction}",
```

- **거리 문자열("300m", "500m")은 템플릿에 고정.** `{dist}` 플레이스홀더 없음.
- `{direction}` 만 동적 치환 (`voice_pack_service.dart:23-24`).
- 의도: threshold 도달 시 해당 거리 문구 발화 (300m 임계 → "300m 앞 X").
- 따라서 H1(하드코딩 버그)은 해당 없음 — 설계된 동작.
- 증상 ③("실거리<100m에 '300m 앞 좌회전'")은 `d <= 300` 조건이
  실제로 100m 미만일 때 처음 충족되는 것 → **H2(distToNextTurnM 과대)** 강함.

문자열 빌더: `voice_pack_service.dart:19-27` (live `next` 주입 없음, dir만 주입).

### E. YNAV_STEP / YNAV_ARR 삽입점

**YNAV_STEP:**
`lib/features/navigation/providers/route_progress_provider.dart:134-141`
`activeStep`이 계산된 직후, `state = RouteProgress(...)` 직전.
```dart
// line 134
final activeStep = _activeStepFor(bestSeg);
// ← if (activeStep != (state?.activeStepIdx ?? -1)) → YNAV_STEP 삽입
```
그 시점에서 접근 가능:
- `from` = `state?.activeStepIdx ?? -1`
- `to` = `activeStep`
- `maneuver` = `_maneuvers[activeStep].type` (int) + `.instruction` (영문)
- `beginShape` = `_maneuvers[activeStep].beginShapeIdx`
- `endShape` = `_maneuvers[activeStep].endShapeIdx`
(단, bounds 체크 `activeStep < _maneuvers.length` 필요)

**YNAV_ARR:**
`lib/features/navigation/providers/route_progress_provider.dart:140-141`
```dart
final arrived = distToDest <= _kArrivalM;   // line 140
// ← if (arrived && !(state?.arrived ?? false)) → YNAV_ARR 삽입
```
그 시점에서 접근 가능:
- `dest` = `distToDest`
- `snap` = `bestSeg`
- `lastShape` = `_pts.length - 1`

### perp 계산 가능 경로

**있음. 이미 `_advance()` 내부에서 계산됨.**

`route_progress_provider.dart:106-116`:
```dart
double bestPerp = double.maxFinite;
for (int i = start; i <= end; i++) {
  final r = _projectOntoSegment(pos, _pts[i], _pts[i + 1]);
  if (r.perpM < bestPerp) {
    bestPerp = r.perpM;
    ...
  }
}
```
`bestPerp`는 `state = RouteProgress(...)` 이전에 로컬 변수로 존재.
`RouteProgress`에 필드는 없지만 **로그용으로 직접 사용 가능** (추가 연산 불필요).

---
- (수정·삽입은 다음 SPEC 단계 — 여기선 위치 보고만)
