# RIDING_QUEUE — 라이딩 검증 대기 브랜치

구현 완료. main 머지 금지. 라이딩 후 결과를 BACKLOG에 기록.

## 대기 중

| 브랜치 | 무엇을 확인 | 어디서 / 방법 |
|---|---|---|
| `debug/fix-rate-probe` | YN_FIX 로그 타임스탬프 간격 = 실제 GPS 전달 주기 | 2~3분 주행 후 `adb logcat -s flutter` 로 YN_FIX 줄 캡처. 간격 5s이면 OS Doze, 1s이면 코드단 정상. 결과를 BACKLOG LOC-UNIFY 선행조건 기록 후 브랜치 폐기. |
