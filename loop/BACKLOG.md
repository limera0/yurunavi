# 유루나비 루프 백로그 (단일 상태 소스)

tick은 READY 맨 위부터 선행조건 충족된 작업 1개를 집는다.
유형: RECON(읽기전용) / T1·T2(객관 검증→auto-merge) / T3(라이딩 검증 필요→머지 금지)
작업 전 관련 SPEC_*.md를 읽고 RECON과 대조. 충돌 시 SPEC 우선.

## READY
- [ ] **ARRIVAL-C1+C2** (T3) 도착 판정 조건 교체 + _ArrivalPhase enum + 도착카드 골격 ← **라이딩 대기** (branch: feat/arrival-fix)
  - C1(363efb0): _checkArrival 경로잔여거리+마지막step 복합조건으로 교체, _kArrivalM=20.0, 더미폴백 직선20m
  - C2(7883569): _ArrivalPhase {guiding,arrivedHold,stopReady} 도입, _arrived→_phase 전환, _showArrivalDialog 호출 제거, 상단카드 arrivedHold 분기('목적지 도착' 골격), analyze No issues
  - 라이딩검증: 마지막 회전 후 20m 이내 → 상단카드 '목적지 도착' 전환 + 정차 2초 후 카운트다운 10→0 자동종료 or '지금 종료' 버튼 확인 → PASS 시 main 머지
  - C3(✓ 3de7887): 정차게이트/카운트다운/종료버튼 — analyze PASS, auditor 7/7 PASS
  - C4(✓ 9a8b11c): TTS _arrivalAnnounced 1회 가드 + _arrivalPois POI 바인딩 — analyze PASS, auditor 7/7 PASS, 라이딩 대기
  - RIDING_QUEUE 등록: feat/arrival-fix (2026-06-26)
- [ ] **MARKER-FIX** (T3) nav 목적지 마커 화면고정 버그(증상2) ← **라이딩 대기** (커밋1: 6af8d7b, branch: phase2/marker-fix)
  - 근거: RECON_marker.md — nav가 MapLibre 위 FlutterMap 오버레이(initialCenter 고정)에 마커를 얹어 카메라 미추종
  - 커밋1 완료: FlutterMap 오버레이 제거 → 목적지·경유지를 MapLibre 네이티브 Symbol로 전환 (analyze PASS, code-auditor PASS)
  - 라이딩검증: 주행 중 목적지 마커가 지도에 고정 추종 (화면 고정 아님) → PASS 시 main 머지
  - 곁다리(커밋2): main_map 스타일 재주입 후 _ensureDestMarker 미호출로 목적지 마커 소멸 — 라이딩 후 별도 커밋

- [x] **RECON-locunify-plan** (RECON) LOC-UNIFY 실행계획 정찰 ✓ 2026-06-17
  - 산출물: loop/RECON_locunify_plan.md 생성 완료
  - locationStreamProvider → map_providers.dart (currentLocationProvider 위)
  - main_map_screen.dart:193 / nav_screen.dart:232 → streamProvider 구독 전환
  - 워밍업: main_map_screen initState 구독으로 자연 충족 (별도 커밋 불필요)
  - 커밋 분할: 3커밋 (map_providers 추가 → main_map 전환 → nav 전환), 전부 analyze 객관검증
  - LOC-UNIFY 전체 유형: T3 (라이딩 후 main 머지)
- [x] **RECON-marker** (RECON) 목적지 마커 위치 고정 버그(증상2) ✓ 2026-06-17
  - 산출물: loop/RECON_marker.md 생성 완료
  - nav_screen:898 FlutterMap Marker(point: widget.destination!) — 카메라 미동기화 → 화면좌표 고정
  - main_map_screen:315–329 MapLibre Symbol — 스타일 재주입 시 onStyleLoadedCallback:809 _destMarker=null 후 미복구
  - 수정 방향: nav_screen→MapLibre 네이티브 Symbol 교체(옵션A); main_map_screen→onStyleLoadedCallback에 _ensureDestMarker 재호출 추가
- [x] **RECON-1hz** (RECON) 1Hz 요청이 5초로 전달되는 코드 원인 규명 ✓ 2026-06-17
  - 산출물: loop/RECON_1hz.md 생성 완료
  - 원인: geolocator_android-5.0.2 싱글턴 캐시 (`_positionStream != null` → settings 무시)
    main_map_screen(:193) 이 먼저 `LocationSettings(distanceFilter:10, timeInterval:null=5000ms)` 로 스트림 생성
    nav_screen(:232) 의 `AndroidSettings(intervalDuration:1000ms)` 는 캐시 히트로 완전히 무시됨
  - 수정 방향: _startNavigation() 에서 NavScreen push 직전 main_map 구독 해제 (옵션A) + LOC-UNIFY (옵션B)
- [x] **RECON-manifest** (RECON) Android 위치 전달 제약 진단 ✓ 2026-06-17
  - 산출물: loop/RECON_manifest.md 생성 완료
  - ACCESS_FINE_LOCATION ✅ manifest:4, FOREGROUND_SERVICE_LOCATION ✅ manifest:7
  - foregroundServiceType="location" → geolocator 플러그인 제공, APK 머지 확인 (targetSdk=36)
  - DrivingScreen: 라우팅 진입 없는 Dead Code 확정
  - 결론: 매니페스트 이상 없음. INSTR-fixrate 선행조건 해소.
- [x] **INSTR-fixrate** (계측·폐기용) 실제 fix 도착 간격 측정 ✓ 2026-06-17
  - 산출물: debug/fix-rate-probe 브랜치 (2991a68). main 머지 절대 금지.
  - nav_screen.dart:306 YN_FIX debugPrint 삽입, analyze No issues, code-auditor PASS
  - 다음 단계: `flutter build apk --debug` → adb install → 2~3분 주행 → `adb logcat -s flutter | grep YN_FIX` 간격 측정 → 브랜치 폐기
  - 라이딩 대기: loop/RIDING_QUEUE.md 참조
- [x] **RECON-location** (RECON) 위치 업데이트 빈도 진단 ✓ 2026-06-17
  - 산출물: loop/RECON_location.md 생성 완료
  - GPS 요청: nav_screen.dart:235 intervalDuration=1000ms(1Hz 요청, OS 보장 아님)
  - "5초 갱신" 코드값 없음 — Android Doze/배터리 절약으로 OS가 임의 연장이 유력
  - 1Hz 강제: 현재 이미 1Hz 요청. OS 보장은 배터리 최적화 제외·매니페스트 foregroundServiceType으로 해결
  - 적응 throttle: nav_screen.dart:317 (≤10km/h→500ms, 나머지→1000ms)
- [x] **RECON-marker** (RECON) 목적지 마커 위치 고정 버그 ✓ 2026-06-17 (중복항목 — 위 항목 참조)
- [x] **RECON-tts-pack** (RECON) 팩 구조 착수 전 정찰 ✓ 2026-06-16
  - 산출물: loop/RECON_tts_pack.md 생성 완료
  - 발화 지점 8개 전수, 변경 파일 1개(nav_screen.dart) + 신규 2개, 단일커밋 불가(2커밋 권장)
- [x] **TTS-PACK** (T2/설계) 음성안내 팩 구조 모듈화 ✓ 2026-06-16
  - 산출물: VoicePackService + default_ko.json, nav_screen 8곳 재배선, main 머지 완료
  - SPEC §4 전 항목 PASS + analyze No issues
## RIDING_QUEUE (구현 완료 · 라이딩 검증 대기 · main 머지 금지)
phase1/startup-accuracy / feat/guidance-fix 에 존재. main 미반영(2026-06-17 확인).
- [ ] type18 아이콘 반전 + type17 불일치 (65528b7) — 카드 아이콘 방향 육안 확인
- [ ] 카드 off-by-one (2048379) — 접근 중 교차로 표시 맞는지
- [ ] 카드 거리 live remaining (0195e6d) — 틱마다 갱신되는지
- [ ] Seoul 카메라 flicker (initState 162-167) — 진입 시 떨림 없는지
- [ ] _lastAnnouncedIdx=0 회귀 점검 (903715f) — 재탐색 후 카드·TTS 리빌드 정상? (06-15 증상4 회귀 여부)
- [ ] T3 2단 안내 카드 재설계 — 미착수, 라이딩 가능 세션에서

## DONE (main 반영 완료)
- **LOC-UNIFY** (T3) ✓ 2026-06-24 (merge abced22) — 위치 파이프라인 통합 + 워밍업 + WAKE_LOCK
  - 커밋: f3ae69b/dcf6019/7aae78a/b1fefc1/c39c5d6/a9b859a/e875da5/a9ba52f → merge abced22
  - locationStreamProvider(map_providers.dart) 단일 소스, listenManual 전환, 권한 게이트, WAKE_LOCK 추가
  - 라이딩검증 완료(merge 시 확인): 콜드 0km/h 소멸, 마커 1~2초 추종
- **RECON-locunify-plan** (RECON) ✓ 2026-06-17 — loop/RECON_locunify_plan.md
  - locationStreamProvider 위치(map_providers.dart), 전환 file:line, 3커밋 분할안, T3 확정
- **RECON-heading** (RECON) ✓ 2026-06-17 — loop/RECON_reroute.md §D
  - Valhalla 포크 heading 수용 ✅ (curl B HTTP 200, heading 에코 확인)
  - Flutter 코드 heading 미전달 확인: routing_service.dart:128–133 (lon/lat만), nav_screen.dart:68 (_currentHeading 없음), nav_screen.dart:493 (_reroute(LatLng) — heading 인자 없음)
  - 제자리 유턴 원인: Valhalla가 진행 방향을 모르므로 유턴이 거리상 유리할 경우 선택됨
  - 수정 방향: LOC-UNIFY 시 _currentHeading 상태 추가 + fetchRoutes(heading:) 전달 권장
- **RECON-marker** (RECON) ✓ 2026-06-17 — loop/RECON_marker.md
  - nav_screen:898 FlutterMap Marker — FlutterMap 카메라 미동기화 → 화면좌표 고정
  - main_map_screen:315–329 MapLibre Symbol — 스타일 재주입(onStyleLoadedCallback:809) 시 _destMarker 미복구
- **RECON-1hz** (RECON) ✓ 2026-06-17 — loop/RECON_1hz.md
- **RECON-manifest** (RECON) ✓ 2026-06-17 — loop/RECON_manifest.md
- **RECON-location** (RECON) ✓ 2026-06-17 — loop/RECON_location.md
- **RECON-tts-pack** (RECON) ✓ 2026-06-16 — loop/RECON_tts_pack.md
- **TTS-PACK** (T2/설계) ✓ 2026-06-16 — VoicePackService + default_ko.json + nav_screen 재배선
