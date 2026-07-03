# SPEC_tts_edge_fix — TTS 임계 다발 + _announceStep 잡음 수술

작성: 2026-06-28
브랜치: `feat/layer1-progress`
선행: RECON_tts_trigger FINDINGS (실물 verbatim 확보).
근본(확정):

- 버그1 `nav_screen.dart:237-239` step 변경 시 `_saidXXX=false` 리셋 + `:244` `d<=thr` level → 동시 다발.
- 버그2 `nav_screen.dart:350` `_announceStep` 비-출발 분기가 `approach_300` 하드코딩 발화.

## ⛔ 범위·규율

- nav_screen.dart **로직 수술**. distToNextTurnM/snap/route 계산 **불변**. 계측 로그문 **그대로 유지**.
- **커밋 2개** (둘 다 nav_screen.dart, 논리 분리):
  - C1: 버그1 seed 수정
  - C2: 버그2 _announceStep 출발 전용화
  - 각 `flutter analyze` 새 에러 0.
- 한 곳 고치고 → analyze → 다음. 동시 편집 금지(직전 중괄호 붕괴 교훈).
- **머지 금지.** fix 후 검증은 별도.
- 모호하면 **중단·보고** (특히 C1 변수 스코프).

---

## C1 — step 진입 시 플래그 seed (버그1)

### 현재 (`:237-239` 부근, 리셋 블록)

```dart
_voiceStepIdx = prog.activeStepIdx;   // (대략 — 실물 확인)
_said500 = false;
_said300 = false;
_said50  = false;
```

### 변경 — `false` → level seed

```dart
_voiceStepIdx = prog.activeStepIdx;
_said500 = d <= 500;   // 이미 안쪽이면 '지나친 것'으로 처리 → 재안내 금지
_said300 = d <= 300;
_said50  = d <=  50;
```

### 제약·가드 (엄수)

- `d`는 `:244`의 `if (d <= 500 ...)`에서 쓰는 **그 거리 변수**여야 한다(= distToNextTurnM).
- **스코프 확인**: `d`가 리셋 블록(237-239) 시점에 이미 계산돼 있어야 함.
  - 계산이 리셋 **뒤**라면, seed 3줄을 **`d`가 확정된 직후·step 변경 분기 내부**로 옮긴다(같은 tick, 같은 분기).
  - 구조상 깔끔히 안 되면 **중단하고 `:230-245` verbatim 보고.** 추측 이동 금지.
- 의미: step 내부 단조 감소 보장 → `level + 1회 플래그`는 이미 edge 동치. seed만으로 진입-다발 제거.

### C1 검증 (라이딩 불요 — 책상 재확인)

빌드·설치 후 **타지 말고** 동일하게 목적지만 찍어 route_check 재취득:

```cmd
cmd /c "adb logcat -d -s flutter:I > route_check2.log"
```

- **기대**: 진입 시 `YNAV_TTS` **0줄**(step0 d=16 → 셋 다 seed=true → 침묵). 출발은 `_announceStep`이 담당.
- 진입 다발이 사라지면 C1 데스크 확정.

---

## C2 — `_announceStep` 출발 전용화 (버그2)

### 현재 (`:340-351` verbatim)

```dart
void _announceStep(int idx) {
  if (idx < 0 || idx >= _steps.length) return;
  if (idx == _lastAnnouncedIdx) return;
  _lastAnnouncedIdx = idx;
  final step = _steps[idx];
  if (step.label == '출발') {
    _vps?.speak('departure');
    return;
  }
  debugPrint('YNAV_GUIDE tts idx=$idx direction="${step.label}"');
  _vps?.speak('approach_300', vars: {'direction': step.label});
}
```

### 변경 — 비-출발 분기의 `approach_300` 발화 제거 (접근 안내는 `_handleVoice`가 단독 소유)

```dart
void _announceStep(int idx) {
  if (idx < 0 || idx >= _steps.length) return;
  if (idx == _lastAnnouncedIdx) return;
  _lastAnnouncedIdx = idx;
  final step = _steps[idx];
  if (step.label == '출발') {
    _vps?.speak('departure');
  }
  // 비-출발 접근 안내는 임계 경로(_handleVoice)가 담당 — 여기서 발화하지 않음
  debugPrint('YNAV_GUIDE announceStep idx=$idx label="${step.label}"');
}
```

- `approach_300` 하드코딩 발화 라인 **삭제**. departure만 발화.
- 영향: 수동 버튼 핸들러(`:704-706` `_announceStep(_stepIdx)`)는 더 이상 임의 step을 음성 안내하지 않음
  (디버그 스킵 버튼으로 추정 — 음성은 임계 경로가 처리). **이 거동 변화 OK인지 확인**, 아니면 보고.

---

## 범위 외 (이번엔 손대지 않음)

- init 경쟁조건(`_initTts`/`_startLocation` fire-and-forget): C1 적용 후 step0가 침묵하므로
  **가청 충돌 소멸**(출발 멘트만 남음). 라이딩에서 출발 멘트 타이밍 이상 없으면 그대로 둔다.
- distToNextTurnM 계산부: offset 정상 확인됨. 불변.

## 산출·다음

- C1, C2 2커밋, analyze 클린, push. **머지 금지.**
- 1차: route_check2(데스크)로 진입 다발 소멸 확인.
- 2차: 한 바퀴 라이딩 → `ride.log`로 **TTS 1회 정상 + ①(next 단조) + ②(step 전환) + ⑤(도착)** 동시 검증.
  (정지 로그로 미검증이던 항목들을 이 주행에서 묶어 확인)
