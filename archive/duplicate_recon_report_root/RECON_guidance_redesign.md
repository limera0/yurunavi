# RECON N4: guidance 현 구조 정리 (2단 카드+다단계 TTS 재설계 전 현황)

대상: `lib/features/navigation/presentation/nav_screen.dart`  
※ 설계안 작성 금지. 현황 인용만.

---

## 현재 상단 안내 카드 위젯 트리

```
build() :795
  step    = _steps[_stepIdx]          // 현재 maneuver (거리 폴백용)
  upcoming = _steps[_stepIdx+1] ?? step  // 다가오는 회전 (카드에 표시)

Positioned(top:0, left:0, right:0)  :910
  SafeArea(bottom:false)             :914
    GestureDetector(onTap=수동진행)   :916
      Container(margin:LRTB 12,8,12,0 / borderRadius:20 / shadow)  :923
        ClipRRect(borderRadius:20)   :936
          Column(mainAxisSize:min)   :938
            LinearProgressIndicator  :941   ← (_stepIdx+1)/_steps.length
            Padding(h:16, v:14)      :947
              Row                    :949
                Container(58×58)     :951   ← 아이콘 박스
                  Icon(upcoming.icon, size:30)   :958
                SizedBox(width:14)   :960
                Expanded             :961
                  Column(crossStart) :962
                    Text(거리)        :966   ← _cardRemainingM or step.dist, fontSize:13 tertiary
                    Text(upcoming.label)  :976  ← fontSize:20 bold onSurface
```

**현재 카드는 1단 (아이콘 + 거리/레이블 1쌍).**

---

## TTS 발화 지점 file:line

### 1. 초기 발화 (라우트 로드 직후)
- `_initTts()` → `_announceStep(0)` — nav_screen.dart:505
- `_applyRouteGuidance()` 호출 직후 (재탐색 시) → `_announceStep(0)` — nav_screen.dart:492 (debugPrint 바로 뒤)

### 2. 400m 예비 발화 — nav_screen.dart:421-426
```dart
if (remaining < 400 && !_preAnnounced && _stepIdx + 1 < _steps.length) {
  _preAnnounced = true;
  final next = _steps[_stepIdx + 1];           // ← 다가오는 회전 (T3 적용 후 카드와 일치)
  final distStr = '${remaining.toStringAsFixed(0)}미터 앞';
  _tts?.speak('$distStr ${next.label}');        // e.g. "350미터 앞 우회전"
}
```
조건: `remaining < 400m` & `_preAnnounced == false` → **1회만** 발화.

### 3. 50m 자동 진행 TTS — nav_screen.dart:430-433
```dart
if (remaining < 50) {
  _preAnnounced = false;
  setState(() => _stepIdx++);
  _announceStep(_stepIdx);                      // 진행 후 새 current step 발화
}
```

### 4. `_announceStep(idx)` 공통 로직 — nav_screen.dart:508-524
```dart
void _announceStep(int idx) {
  if (idx < 0 || idx >= _steps.length) return;
  if (idx == _lastAnnouncedIdx) return;         // 중복 방지
  _lastAnnouncedIdx = idx;
  final step = _steps[idx];
  final text = step.dist.isNotEmpty
      ? '${step.dist} 앞 ${step.label}'        // e.g. "2.3km 앞 우회전"
      : step.label;                            // e.g. "목적지 도착"
  debugPrint('YNAV_GUIDE tts idx=$idx text="$text"');
  _tts?.speak(text);
}
```
- `step.dist` = **정적 Valhalla 거리 문자열** (카드 표시와 달리 live remaining 미반영)
- 호출처: _initTts(:505), 재탐색(:492), GPS진행(:433), 수동탭(:920)

---

## 현재 TTS 거리 vs 카드 거리 불일치

| 항목 | 소스 |
|------|------|
| 카드 거리 텍스트 | `_cardRemainingM` (GPS 실시간) |
| `_announceStep` 거리 | `step.dist` (정적 Valhalla) |
| 400m 예비 TTS 거리 | `remaining.toStringAsFixed(0)` (GPS 실시간) |

→ 일반 step TTS(`_announceStep`)만 정적 거리 사용.

---

## 2단 카드 얹을 지점

현재 `Expanded > Column` (:961-984) 내부에 `Text(거리)` + `Text(레이블)` 2개가 있음.  
카드를 2단으로 확장하려면 이 Column에 추가 위젯을 삽입하거나,  
`Row(:949)` 아래에 두 번째 `Row`를 추가하는 방식이 가장 자연스러운 삽입점.
