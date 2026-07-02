# RECON_tts_trigger — TTS 임계 발화 로직 실물 확보 (읽기 전용)

작성: 2026-06-28
브랜치: `feat/layer1-progress`
목적: 계측 로그가 ③/② 근본을 **TTS 임계 level-발화 + step 진입 동시 다발**로 확정했다.
edge(하향 통과)로 수술하려면 현재 조건문·플래그·리셋 코드의 **실물 verbatim**이 필요하다.

## ⛔ 범위·금지
- **읽기 전용.** 수정·커밋·fix 금지. 코드 덤프와 구조 보고만.
- 모든 답은 `file:line` + verbatim 코드 발췌. 모호하면 중단·보고.

## 확정된 증거 (배경)
```
YNAV_TTS thr=500 next=16.0 step=0   ┐ 1ms 안에
YNAV_TTS thr=300 next=16.0 step=0   ┤ 3발 동시
YNAV_TTS thr=50  next=16.0 step=0   ┘ (next=16인데 500/300 발화)
```
→ 발화 조건이 `next < thr` level일 가능성 높음. 확인 필요.

## 덤프 항목 (verbatim)

### A. 임계 발화 블록 전체
`nav_screen.dart` 244-246 speak() 포함 **위아래 맥락**까지:
```bash
cd /data/projects/yurunavi
sed -n '210,290p' lib/**/nav_screen.dart 2>/dev/null || \
  awk 'NR>=210 && NR<=290' $(grep -rl "YNAV_TTS\|thr=500\|speak(" lib | head -1)
```
- 각 임계(500/300/50)의 **발화 조건문 정확히**: `next < thr`(level)인가, `prev >= thr && next < thr`(edge)인가, baseline(prevNext) 존재하는가.

### B. spoken 플래그 정의·리셋
```bash
grep -rn "spoken\|_said\|announced\|_tts\|lastSpokenStep\|prevNext\|_lastNext" lib/ | grep -vi test
```
- 플래그 선언 위치, **리셋 트리거**(step 전환 시? 어디서?), 리셋 시점이 새 next 평가보다 **앞인지 뒤인지**.

### C. depart/출발 멘트 처리
- "출발"/depart 발화가 임계 로직과 **같은 경로**인지 별개인지 file:line.
  (현재 출발 시점에 500/300/50가 같이 터지는 게 이 때문인지 확인)

### D. step 전환 ↔ TTS 동기
- step 증가를 TTS 쪽이 어떻게 감지하는가(현재 step 저장? 비교?). 새 step 첫 평가 때 next가 이미
  임계 안쪽이면 어떤 분기를 타는지.

## FINDINGS (Claude Code가 채움)

### A 발화 조건 — **level 판정 (edge 없음)**

`nav_screen.dart:244-258` verbatim:
```dart
if (d <= 500 && !_said500) {
  _said500 = true;
  debugPrint('YNAV_TTS thr=500 next=${d.toStringAsFixed(1)} step=$step ...');
  _vps?.speak('approach_500', vars: {'direction': dir});
}
if (d <= 300 && !_said300) {
  _said300 = true;
  debugPrint('YNAV_TTS thr=300 next=${d.toStringAsFixed(1)} step=$step ...');
  _vps?.speak('approach_300', vars: {'direction': dir});
}
if (d <=  50 && !_said50) {
  _said50  = true;
  debugPrint('YNAV_TTS thr=50 next=${d.toStringAsFixed(1)} step=$step ...');
  _vps?.speak('approach_50',  vars: {'direction': dir});
}
```
→ `d <= thr` **level 조건**. `prev >= thr && next < thr` 형태의 edge 검사 없음.  
→ 새 step 첫 평가 시 d가 이미 500 이하이면 3개 if 모두 통과 = **3발 동시 발화** (로그 증거와 일치).

### B 플래그 선언·리셋

- **선언** `nav_screen.dart:83`
  ```dart
  bool _said500 = false, _said300 = false, _said50 = false;
  ```
- **리셋** `nav_screen.dart:237-239` — `_handleVoice` 내부, step 변경 감지 직후 즉시:
  ```dart
  if (step != _voiceStepIdx) {
    _voiceStepIdx = step;
    _said500 = _said300 = _said50 = false;   // ← 리셋
  }
  // 바로 아래 244행에서 d <= 500 평가
  ```
- **리셋 순서**: 리셋(239행) → 임계 평가(244행) — 동일 함수 호출 사이클 내 연속 실행.  
  새 step 진입과 동시에 d가 임계 이하이면 리셋 직후 전 임계가 통과됨.

### C depart/출발 멘트 경로 — **임계 로직과 별개 경로**

`_announceStep(int idx)` `nav_screen.dart:340-351`:
```dart
void _announceStep(int idx) {
  if (idx < 0 || idx >= _steps.length) return;
  if (idx == _lastAnnouncedIdx) return;
  _lastAnnouncedIdx = idx;
  final step = _steps[idx];
  if (step.label == '출발') {
    _vps?.speak('departure');
    return;                    // ← 임계 블록 진입 없이 종료
  }
  _vps?.speak('approach_300', vars: {'direction': step.label});
}
```
- 호출 경로:
  1. `_initTts()` 완료 후 `_announceStep(0)` (`nav_screen.dart:337`)
  2. 수동 버튼 → `_announceStep(_stepIdx)` (`nav_screen.dart:706`)
- `_handleVoice`의 임계 블록(`_said500/300/50`)과 **코드 경로 분리**.  
  그러나 `_initTts` 완료 타이밍에 `routeProgressProvider` 구독이 이미 active이면  
  `_announceStep(0)` (departure) + `_handleVoice` 임계 발화가 **동시에** 트리거될 수 있음.

### D step 전환 감지 방식

- TTS 전용 `_voiceStepIdx` 필드 (`nav_screen.dart:82`, 초기값 `-1`):
  ```dart
  int _voiceStepIdx = -1;
  ```
- `_handleVoice(prog)` 매 호출마다 `prog.activeStepIdx`와 비교:
  ```dart
  final step = prog.activeStepIdx;          // nav_screen.dart:236
  if (step != _voiceStepIdx) {             // 237: 새 step 감지
    _voiceStepIdx = step;                  // 238
    _said500 = _said300 = _said50 = false; // 239: 플래그 리셋
  }
  if (step + 1 >= _steps.length) return;  // 241: 마지막 step 방어
  final d = prog.distToNextTurnM;          // 243
  // 244~258: 임계 평가
  ```
- `_stepIdx`(UI 카드, setState 내부)와 `_voiceStepIdx`(TTS, handleVoice 내부)는 **별개 필드**.  
  새 step 첫 평가에서 d < 500이면 리셋 직후 3 if 블록 연속 통과 — **동일 tick에 3발**.

- (fix 제안 금지 — SPEC에서)
