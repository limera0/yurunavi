# RIDING_QUEUE — 라이딩 검증 대기 브랜치

구현 완료. main 머지 금지. 라이딩 후 결과를 BACKLOG에 기록.

## 대기 중

| 브랜치 | 무엇을 확인 | 어디서 / 방법 |
|---|---|---|
| `debug/fix-rate-probe` | YN_FIX 로그 타임스탬프 간격 = 실제 GPS 전달 주기 | 2~3분 주행 후 `adb logcat -s flutter` 로 YN_FIX 줄 캡처. 간격 5s이면 OS Doze, 1s이면 코드단 정상. 결과를 BACKLOG LOC-UNIFY 선행조건 기록 후 브랜치 폐기. |
| `phase2/marker-fix` | 주행 중 목적지·경유지 마커가 지도 좌표에 고정 추종 (화면 고정 아님) | 내비 진입 후 카메라 이동 시 목적지 핀이 지도와 함께 움직이는지 확인. PASS 시 main 머지. |
| `feat/arrival-fix` | 마지막 회전 후 20m 이내→상단카드 '목적지 도착' 전환, 정차 2초 후 카운트다운 10→0 자동종료 또는 '지금 종료' 버튼 동작 | 목적지 근처 실주행. C1 도착 판정→C2 카드→C3 카운트다운→C4 TTS 순차 확인. PASS 시 main 머지. |
