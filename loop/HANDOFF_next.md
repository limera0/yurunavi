# HANDOFF — 다음 세션 인수인계 (2026-06-25 작성)

## 프로젝트
유루나비: 경치 좋은 와인딩 우선 오토바이 투어링 내비(한국→일본). 비개발자 마스터,
12시간 교대 근무로 시간 제약. 폰 실측(Galaxy A34)만이 유효 검증.
서버 westinx(192.168.0.57), 저장소 github.com/limera0/yurunavi.

## 루프 작업 방식 (이게 핵심 — 새 세션이 따를 것)
- Claude Code를 `claude -p "$(cat loop/tick.md)" --permission-mode auto --verbose --output-format stream-json` 로 구동.
  (claude-auto-retry는 설치 후 자동 구동되므로 명령에 쓰지 말 것 — 그냥 claude)
- tick.md = 1틱 1작업 후 종료. 큰 작업은 "추가 지시:"로 커밋 단위를 좁혀 던짐.
- 상태 스파인: loop/BACKLOG.md / SPEC_*.md / RECON_*.md / REPORT_*.md.
- 게이트: 1커밋=1논리=단일파일. analyze는 객관검증, 폰 실측만 진짜 증명.
- T1/T2(객관검증 가능)=auto-merge 가능 / T3(라이딩 필요)=브랜치에 쌓고 라이딩 후 main 머지.
- 모호하면 중단·보고. grep 없이 추측 금지, file:line 인용.
- analyze 상시 경고 2개(settings_screen.dart:73 onChanged deprecated)는 무관 — 무시.

## 완료 (main 반영)
- LOC-UNIFY (abced22 머지): 위치 스트림 단일화(map_providers locationStreamProvider)
  + splash 워밍업 + WAKE_LOCK 권한. 라이딩 검증 완료 — GPS 1Hz 빠릿, 콜드스타트 0km/h 소멸.
  ★교훈: "GPS 5초=하드웨어 한계"는 오진. geolocator _positionStream 캐시충돌이 원인이었고,
    최종 회귀는 AndroidManifest WAKE_LOCK 누락(enableWakeLock:true가 권한 요구)이었음.

## 코드 완성·라이딩 검증 대기 (브랜치에 있음, main 머지 전)
- phase2/heading-fix (3커밋): 재탐색 시 _currentHeading을 Valhalla fetchRoutes(heading:)로 전달.
  증상: 경로이탈 후 재탐색이 무조건 불법유턴 안내. 원인: heading 미전송(RECON_reroute.md).
  검증법: 주행 중 일부러 경로 이탈 → 재탐색이 유턴 말고 진행방향 경로 주는지.
- phase2/marker-fix (커밋1): nav 목적지/경유지 마커를 FlutterMap 오버레이→MapLibre Symbol 전환.
  증상: 목적지 마커가 화면 좌상단 고정, 카메라 안 따라옴. 원인: FlutterMap initialCenter 고정(RECON_marker.md).
  검증법: 주행 중 목적지 빨간 마커가 지도에 붙어 따라오는지.
  남은 곁다리(커밋2 미착수): main_map 스타일 재주입 후 _ensureDestMarker 재호출 누락(RECON_marker §C).

## 다음 할 일 (우선순위)
1. [최우선·미진단] 도착/종료 버그 — 2026-06-24 라이딩 발견. 치명적.
   - 증상A: 목적지 30m 전인데 "도착" 처리하고 내비 일방 종료(좌회전 남았는데 끊김).
   - 증상B: 목적지 지나쳐 다시 돌아가야 할 때도 칼같이 종료해버림.
   - 마스터 해법: 도착 시 상단 카드 안내만 띄우고, 안내는 유지. 완전 정차 후에야 종료버튼 표시,
     종료버튼에 10초 카운트다운(수동 즉시 종료 or 10초 후 자동종료).
   - 진행: RECON으로 도착 판정 반경·종료 트리거 file:line부터. (코드 변경 0)
2. [진단완료] HANDOFF_tts_arrival.md 참조 — 음성 거리적응 안내 2건:
   - 코너가 300m 미만이어도 무조건 "300m 앞 회전" 거짓 안내 → 동적 임계(150/50/직전).
   - 골목 연속 좌우회전 시 무음. 둘 다 SPEC_tts 거리임계 로직 확장 필요.
3. [라이딩 후] heading-fix / marker-fix main 머지.

## 미해결 라이딩 검증 큐
- heading-fix, marker-fix (위)
- (참고) RIDING_QUEUE.md에 이전 항목들 있음

작성 시점 브랜치 상태: main에 LOC-UNIFY 머지됨. phase2/heading-fix, phase2/marker-fix 원격 push됨.
