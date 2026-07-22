# REPORT: YNAV_GUIDE 디버그 로그 계측
커밋: 8c61bf2 | 태그: guidance-debug | 브랜치: feat/guidance-fix

---

## 추가한 4개 로그 위치

| # | 태그 이벤트 | file:line | 출력 내용 |
|---|-------------|-----------|-----------|
| ① | `tick` | nav_screen.dart:416 | GPS 틱마다: stepIdx, total, remaining(m), cur(현재 step 레이블), upcoming(다음 step 레이블 or "DEST") |
| ② | `advance` | nav_screen.dart:432 | remaining<50m 자동 진행 후: 새 stepIdx, 새 label |
| ③ | `tts` | nav_screen.dart:523 | _announceStep 발화 직전: idx, text |
| ④ | `reroute` | nav_screen.dart:492 | 재탐색 완료 후: 새 steps 수, 첫 step 레이블 |

---

## 주행 후 로그 수집 명령

### PowerShell (Windows)
```powershell
.\adb logcat -s flutter:* | Select-String "YNAV_GUIDE"
```

### bash (macOS/Linux)
```bash
adb logcat -s flutter:* | grep YNAV_GUIDE
```

### 파일로 저장
```powershell
.\adb logcat -s flutter:* | Select-String "YNAV_GUIDE" | Tee-Object -FilePath ynav_log.txt
```

---

## 로그 해독 가이드

### ① tick (1Hz 간격)
```
YNAV_GUIDE tick stepIdx=0 total=8 remaining=742 cur=출발 upcoming=우회전
```
- `stepIdx=0` — 현재 _stepIdx
- `total=8` — 전체 step 수
- `remaining=742` — 카드에 표시되는 잔여 거리(m)
- `cur=출발` — _steps[stepIdx].label (현재 maneuver)
- `upcoming=우회전` — _steps[stepIdx+1].label (카드에 표시 중인 다음 회전)

**체크포인트:** remaining이 주행하면서 줄어드는가?

### ② advance (step 전환 시)
```
YNAV_GUIDE advance → stepIdx=1 label=우회전
```
- remaining<50m 진입 시 1회 출력
- **체크포인트:** 실제 회전 지점 도달 시 advance가 찍히는가?

### ③ tts (TTS 발화 시)
```
YNAV_GUIDE tts idx=0 text="742m 앞 출발"
YNAV_GUIDE tts idx=1 text="우회전"
```
- **체크포인트:** text가 한국어로 올바른가? idx가 advance와 연동되는가?

### ④ reroute (이탈 재탐색 후)
```
YNAV_GUIDE reroute steps=6 first=출발
```
- **체크포인트:** 재탐색 후 steps 수가 합리적인가? first가 "출발" 또는 첫 회전인가?

---

## 검증 판정 기준

| 현상 | 정상 | 이상 |
|------|------|------|
| remaining | 주행할수록 감소 | 고정 or 음수 |
| advance | 회전 지점 ~50m 전 | 안 찍히거나 멀리서 찍힘 |
| upcoming | 카드 텍스트와 일치 | 불일치 |
| tts text | 실제 들리는 음성과 일치 | 불일치 |
| reroute first | "출발" or 첫 실질 회전 | "none" or 비어있음 |
