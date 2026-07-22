# YuruNavi RECON/REPORT 인덱스

생성: 2026-07-22 17:03 · 총 문서 수: 152

정렬 기준: 각 문서의 git 최초 커밋일(`git log --follow`로 rename 이력까지 추적한 진짜 생성일).
파일명 앞의 날짜(예: 2026-06-04)가 정찰/보고 시점이다. RECON은 조사, REPORT는 그 조사 이후
실제 구현/수정 결과 — 같은 주제는 보통 RECON_X → REPORT_X 순으로 붙어 있다.

> 이 판은 **날짜순**으로 큐레이션했다(2026-07-22, 마스터 지시). `loop/curate_wiki.sh`를
> 다시 돌리면 스크립트 기본 방식인 **주제 카테고리별**로 재정리되어 이 판을 덮어쓴다.

---

## 2026-06

- **2026-06-04** [RECON_A.md](RECON_A.md) — RECON_A — A묶음 정찰 결과
- **2026-06-04** [RECON_B3.md](RECON_B3.md) — RECON_B3 — 내비 종료 후 깨진 경로탐색창 정찰 결과
- **2026-06-04** [REPORT_A.md](REPORT_A.md) — REPORT_A — A묶음 4건 실행 결과
- **2026-06-04** [REPORT_B3.md](REPORT_B3.md) — REPORT_B3 — 내비 종료 후 경로탐색 상태 정리
- **2026-06-05** [RECON_EXTURL.md](RECON_EXTURL.md) — RECON_EXTURL — 외부 접속 전환 사전조사
- **2026-06-05** [RECON_MARKER.md](RECON_MARKER.md) — RECON_MARKER (B1+B2 마커)
- **2026-06-05** [RECON_NAVIDX.md](RECON_NAVIDX.md) — RECON_NAVIDX (nav_screen 선택코스 무시 버그)
- **2026-06-05** [RECON_NIGHTMODE.md](RECON_NIGHTMODE.md) — RECON_NIGHTMODE (야간모드/일출일몰 버그)
- **2026-06-05** [RECON_PIN.md](RECON_PIN.md) — RECON_PIN (원형→물방울 핀 마커)
- **2026-06-05** [RECON_SUNTIME.md](RECON_SUNTIME.md) — RECON_SUNTIME (박명→일출일몰 기준 전환)
- **2026-06-05** [RECON_WAYPOINT.md](RECON_WAYPOINT.md) — RECON_WAYPOINT (경유지 기능 현황)
- **2026-06-05** [RECON_WPMARKER.md](RECON_WPMARKER.md) — RECON_WPMARKER (경로B 비활성 + 경유지 노랑핀)
- **2026-06-05** [RECON_WPZ.md](RECON_WPZ.md) — RECON_WPZ (목적지핀 최상단 + 겹침 시 적층)
- **2026-06-05** [RECON_ZORDER.md](RECON_ZORDER.md) — RECON_ZORDER — 마커 z-order 버그 사전조사
- **2026-06-05** [REPORT_DESTPIN.md](REPORT_DESTPIN.md) — REPORT_DESTPIN — 목적지 핀 자작 PNG 교체 보고
- **2026-06-05** [REPORT_EXTURL.md](REPORT_EXTURL.md) — REPORT_EXTURL — 타일서버 공개도메인 전환 완료
- **2026-06-05** [REPORT_MARKER.md](REPORT_MARKER.md) — REPORT_MARKER — B1+B2 마커 구현 보고
- **2026-06-05** [REPORT_NIGHTMODE.md](REPORT_NIGHTMODE.md) — REPORT_NIGHTMODE — 야간모드 9시간 오차 수정 보고
- **2026-06-05** [REPORT_PIN.md](REPORT_PIN.md) — REPORT_PIN — 목적지 마커 물방울핀 교체 보고
- **2026-06-05** [REPORT_SUNTIME.md](REPORT_SUNTIME.md) — REPORT_SUNTIME — 박명→일출일몰 전환 보고
- **2026-06-05** [REPORT_WPB.md](REPORT_WPB.md) — REPORT_WPB — 경로B 비활성 (경유지 버튼 제거) 보고
- **2026-06-05** [REPORT_WPMARKER2.md](REPORT_WPMARKER2.md) — REPORT_WPMARKER2 — 경유지 노랑핀 마커 연결 보고
- **2026-06-05** [REPORT_WPZ.md](REPORT_WPZ.md) — REPORT_WPZ — 목적지핀 최상단 + 겹침 적층 구현
- **2026-06-05** [REPORT_ZOOM.md](REPORT_ZOOM.md) — REPORT_ZOOM — 줌맞춤 하단 패딩 보정
- **2026-06-05** [REPORT_ZORDER.md](REPORT_ZORDER.md) — REPORT_ZORDER — 마커 z-order 가림 해결 보고
- **2026-06-07** [REPORT_PATCH2.md](REPORT_PATCH2.md) — REPORT_PATCH2 — Valhalla Fork Patch #2 (곡률/교량/터널 페널티)
- **2026-06-10** [RECON_COURSE_A.md](RECON_COURSE_A.md) — RECON: 코스 차별화 A안 설계 정찰
- **2026-06-10** [RECON_FORK_SIGNALS.md](RECON_FORK_SIGNALS.md) — RECON: 포크 패치 #2 신호
- **2026-06-10** [RECON_KR_ROADCLASS.md](RECON_KR_ROADCLASS.md) — RECON: 한국 OSM 도로등급 ↔ RoadClass 검증
- **2026-06-10** [RECON_PROMPT_course_A.md](RECON_PROMPT_course_A.md) — 정찰 프롬프트 — 코스 차별화 A안(Valhalla FC 인지형 커스텀) 설계용
- **2026-06-10** [RECON_PROMPT_fork_signals.md](RECON_PROMPT_fork_signals.md) — 정찰 프롬프트 — 포크 패치 #2 신호 확정 (속도/직진/고가도로)
- **2026-06-10** [RECON_PROMPT_kr_roadclass.md](RECON_PROMPT_kr_roadclass.md) — 정찰 프롬프트 — 한국 OSM 도로 등급 ↔ RoadClass(0~7) 실데이터 검증
- **2026-06-10** [RECON_PROMPT_valhalla_fork.md](RECON_PROMPT_valhalla_fork.md) — 정찰 프롬프트 — Valhalla 3.7.0 포크 패치 설계 (class_factors 구현)
- **2026-06-10** [RECON_VALHALLA_FORK.md](RECON_VALHALLA_FORK.md) — RECON: Valhalla 3.7.0 포크 패치 설계
- **2026-06-10** [RECON_nav_screen.md](RECON_nav_screen.md) — RECON: nav_screen.dart 현재 상태
- **2026-06-10** [RECON_navlibre.md](RECON_navlibre.md) — RECON: nav_screen MapLibre 이관 정찰
- **2026-06-10** [RECON_navlibre_camera.md](RECON_navlibre_camera.md) — RECON: nav_screen 카메라 이동 불능 원인 격리
- **2026-06-10** [RECON_navlibre_graytile.md](RECON_navlibre_graytile.md) — RECON: nav_screen 회색 지도 원인 격리
- **2026-06-10** [RECON_navlibre_speed_redesign.md](RECON_navlibre_speed_redesign.md) — RECON: GPS 주기 + 속도 재설계 재료
- **2026-06-10** [RECON_navlibre_track_speed.md](RECON_navlibre_track_speed.md) — RECON: nav_screen 카메라 trailing + 속도계 노이즈 원인 격리
- **2026-06-10** [RECON_style_loading.md](RECON_style_loading.md) — RECON: MapLibre 스타일 로딩 방식 (2026-06-08)
- **2026-06-10** [REPORT_311_signals_nobuild.md](REPORT_311_signals_nobuild.md) — REPORT: 311번 동부대로 신호 검증 (무빌드)
- **2026-06-10** [REPORT_FORK_BUILD.md](REPORT_FORK_BUILD.md) — REPORT: Valhalla class_factors 포크 (빌드·검증 완료)
- **2026-06-10** [REPORT_NAVIDX.md](REPORT_NAVIDX.md) — REPORT_NAVIDX — nav_screen 선택코스 유지 버그 수정
- **2026-06-10** [REPORT_PROMPT_fork_build.md](REPORT_PROMPT_fork_build.md) — REPORT 작성 — Valhalla class_factors 포크 빌드/검증 기록
- **2026-06-10** [REPORT_location_rate.md](REPORT_location_rate.md) — REPORT: High-Rate Location Updates
- **2026-06-10** [REPORT_nav_backbutton.md](REPORT_nav_backbutton.md) — REPORT: nav_screen 뒤로가기 인터셉트
- **2026-06-10** [REPORT_nav_eta.md](REPORT_nav_eta.md) — REPORT: nav_screen ETA 실계산
- **2026-06-10** [REPORT_navlibre_1.md](REPORT_navlibre_1.md) — REPORT: nav_screen MapLibre 이관 커밋 ① 골격
- **2026-06-10** [REPORT_navlibre_1fix.md](REPORT_navlibre_1fix.md) — REPORT: nav_screen MapLibre 커밋 ① 핫픽스
- **2026-06-10** [REPORT_navlibre_1fix2.md](REPORT_navlibre_1fix2.md) — REPORT: nav_screen 카메라 추적 복구 (1/4 hotfix2)
- **2026-06-10** [REPORT_navlibre_2.md](REPORT_navlibre_2.md) — REPORT: nav_screen MapLibre 이관 커밋 ② 경로 폴리라인
- **2026-06-10** [REPORT_navlibre_fix_speed.md](REPORT_navlibre_fix_speed.md) — REPORT: 속도계 정지 노이즈 수정 (fix #3)
- **2026-06-10** [REPORT_navlibre_fix_track.md](REPORT_navlibre_fix_track.md) — REPORT: nav_screen 카메라 trailing 수정 (fix #2)
- **2026-06-10** [REPORT_navlibre_speed.md](REPORT_navlibre_speed.md) — REPORT: 속도 재설계 — 위치 윈도우 기반 + 정지 판정
- **2026-06-10** [REPORT_speed_doppler.md](REPORT_speed_doppler.md) — REPORT: Doppler+Hysteresis Speed Gate
- **2026-06-11** [REPORT_location_continuous.md](REPORT_location_continuous.md) — REPORT_location_continuous.md — 위치 연속 수신 + staleness 워치독
- **2026-06-11** [REPORT_onboarding.md](REPORT_onboarding.md) — REPORT — 콜드스타트 로딩표시 + 권한 온보딩 플로우
- **2026-06-11** [REPORT_speed_polish.md](REPORT_speed_polish.md) — REPORT — 보간 복구 + 권한 팝업화 + GPS 선점기동
- **2026-06-11** [REPORT_speedometer_final.md](REPORT_speedometer_final.md) — REPORT — 속도계 종결 통합 (위치설정 복구 + 포그라운드 서비스 + OM 보간 엔진)
- **2026-06-12** [RECON_speed_kalman.md](RECON_speed_kalman.md) — RECON — 칼만 속도융합 도입을 위한 현 속도코드 정찰
- **2026-06-12** [REPORT_faststop.md](REPORT_faststop.md) — REPORT_faststop — 정차 빠른 0 패치
- **2026-06-12** [REPORT_fonts_style.md](REPORT_fonts_style.md) — REPORT: 폰트 Bold/Italic CJK 병합 + osm-bright 스타일 배치
- **2026-06-12** [REPORT_kalman.md](REPORT_kalman.md) — REPORT — GPS+IMU 1D 칼만 속도융합
- **2026-06-12** [REPORT_nav_marker.md](REPORT_nav_marker.md) — REPORT: 내비 화면 현위치 초록점 이식
- **2026-06-16** [RECON_codebase_inventory.md](RECON_codebase_inventory.md) — RECON: 전체 코드베이스 현황 棚卸
- **2026-06-16** [RECON_costing_state.md](RECON_costing_state.md) — RECON N1: Valhalla costing — motorway/motorway_link 배제 여부
- **2026-06-16** [RECON_direction.md](RECON_direction.md) — RECON #2: 안내 방향 오류 추적 결과
- **2026-06-16** [RECON_guidance.md](RECON_guidance.md) — RECON: 안내 거리 미갱신 추적 결과
- **2026-06-16** [RECON_guidance_redesign.md](RECON_guidance_redesign.md) — RECON N4: guidance 현 구조 정리 (2단 카드+다단계 TTS 재설계 전 현황)
- **2026-06-16** [RECON_lanes.md](RECON_lanes.md) — RECON: Valhalla 차선(lanes) 데이터 실제 출력 확인
- **2026-06-16** [RECON_location_dot_regression.md](RECON_location_dot_regression.md) — RECON: 현위치 초록점 소실 회귀
- **2026-06-16** [RECON_map_language.md](RECON_map_language.md) — RECON: 지도 라벨 언어 단일 선택 (한/영/일 택1)
- **2026-06-16** [RECON_mbtiles_langfields.md](RECON_mbtiles_langfields.md) — RECON: Korea/Japan mbtiles 언어 필드 실측
- **2026-06-16** [RECON_route_color_state.md](RECON_route_color_state.md) — RECON N2: 경로 폴리라인 색상 처리 현황
- **2026-06-16** [RECON_settings_phase1.md](RECON_settings_phase1.md) — RECON: 설정 페이지 Phase 1
- **2026-06-16** [RECON_startup_accuracy.md](RECON_startup_accuracy.md) — RECON — 출발 정확성 (Startup Accuracy)
- **2026-06-16** [RECON_zoom_state.md](RECON_zoom_state.md) — RECON N3: 초기 지도 줌 레벨 확인
- **2026-06-16** [REPORT_guidance_debug.md](REPORT_guidance_debug.md) — REPORT: YNAV_GUIDE 디버그 로그 계측
- **2026-06-16** [REPORT_guidance_fix.md](REPORT_guidance_fix.md) — REPORT: guidance-fix (T1~T3)
- **2026-06-16** [REPORT_location_dot_fix.md](REPORT_location_dot_fix.md) — REPORT: 현위치 초록점 소실 회귀 수정
- **2026-06-16** [REPORT_map_language_planB.md](REPORT_map_language_planB.md) — REPORT: 지도 언어 전환 플랜 B (스타일 JSON 재주입)
- **2026-06-16** [REPORT_map_language_spike.md](REPORT_map_language_spike.md) — REPORT: 지도 언어 전환 스파이크 (setLayerProperties 검증)
- **2026-06-16** [REPORT_merge_map_language.md](REPORT_merge_map_language.md) — REPORT: feat/map-language → main 머지
- **2026-06-16** [REPORT_reroute_merge.md](REPORT_reroute_merge.md) — REPORT: reroute maneuver/TTS rebuild 머지 (증상4)
- **2026-06-16** [REPORT_settings_phase1_impl.md](REPORT_settings_phase1_impl.md) — REPORT: 설정 페이지 Phase 1 구현
- **2026-06-16** [REPORT_tts_T1T2.md](REPORT_tts_T1T2.md) — REPORT — T1/T2 TTS 수정 (phase1/startup-accuracy)
- **2026-06-17** [RECON_1hz.md](RECON_1hz.md) — RECON-1hz — 1Hz 요청이 5초 간격으로 전달되는 원인 규명
- **2026-06-17** [RECON_location.md](RECON_location.md) — RECON-location — 위치 업데이트 빈도 진단
- **2026-06-17** [RECON_manifest.md](RECON_manifest.md) — RECON-manifest — Android 위치 전달 제약 진단
- **2026-06-17** [RECON_marker.md](RECON_marker.md) — RECON_marker.md — 목적지 마커 위치 고정 버그 (증상2)
- **2026-06-17** [RECON_reroute.md](RECON_reroute.md) — RECON_reroute.md — 재탐색 heading 미전달 (증상3: 제자리 유턴) *(2026-06-10 더 이른 정찰본은 [archive/duplicate_recon_report_root/RECON_reroute.md](../archive/duplicate_recon_report_root/RECON_reroute.md)에 보존)*
- **2026-06-17** [RECON_tts_pack.md](RECON_tts_pack.md) — RECON_tts_pack — 음성 팩 구조 착수 전 정찰
- **2026-06-23** [RECON_locunify_plan.md](RECON_locunify_plan.md) — RECON-locunify-plan — LOC-UNIFY 실행계획 정찰
- **2026-06-27** [RECON_guidance_p1.md](RECON_guidance_p1.md) — RECON_guidance_p1.md — Layer 1: shape_index 단조 진행추적
- **2026-06-27** [RECON_layer0.md](RECON_layer0.md) — RECON_layer0.md — 단일 실세계 SoT (운동학 상태 추출)
- **2026-06-27** [RECON_perm_halt.md](RECON_perm_halt.md) — RECON_perm_halt.md — 첫 실행 권한 halt (Layer 0 회귀)
- **2026-06-27** [REPORT_guidance_p1.md](REPORT_guidance_p1.md) — REPORT_guidance_p1.md — Layer 1: shape_index 단조 진행추적 구현 완료
- **2026-06-27** [REPORT_layer0.md](REPORT_layer0.md) — REPORT_layer0.md — NavigationState SoT 구현 보고
- **2026-06-27** [REPORT_perm_halt.md](REPORT_perm_halt.md) — REPORT_perm_halt.md — 권한 halt 수정 완료
- **2026-06-30** [RECON_ic_guidance.md](RECON_ic_guidance.md) — RECON_ic_guidance — IC/출구 TTS 조기안내 훅 지점
- **2026-06-30** [RECON_reroute_miss.md](RECON_reroute_miss.md) — RECON — YNAV_REROUTE 로그 0줄 원인 규명
- **2026-06-30** [RECON_underpass.md](RECON_underpass.md) — RECON_underpass — Valhalla fork(:8002) 기능 실측 보고서
- **2026-06-30** [RECON_voice_v2.md](RECON_voice_v2.md) — RECON_voice_v2 — 음성 요구 5건 훅 지점 확정
- **2026-06-30** [REPORT_card_dist.md](REPORT_card_dist.md) — REPORT: 안내카드 거리 숫자 확대
- **2026-06-30** [REPORT_ic_guidance.md](REPORT_ic_guidance.md) — IC 조기안내 구현 리포트
- **2026-06-30** [REPORT_reroute_log.md](REPORT_reroute_log.md) — REPORT — reroute offset 로그 채널 통일 + heading 가시화
- **2026-06-30** [REPORT_voice_v2A.md](REPORT_voice_v2A.md) — REPORT_voice_v2A — 음성 v2 슬라이스 A (R1+R2+R3) 완료 보고

## 2026-07

- **2026-07-02** [RECON_arrival_dialog.md](RECON_arrival_dialog.md) — RECON — 도착 다이얼로그가 재탐색 진입 후에도 안 사라지는 문제
- **2026-07-02** [RECON_gate_avoid_poc.md](RECON_gate_avoid_poc.md) — RECON — gate/access 태깅이 이 Valhalla 빌드에서 관통을 실제로 막는가 (격리 PoC)
- **2026-07-02** [RECON_guidance_engine.md](RECON_guidance_engine.md) — RECON_guidance_engine — TTS tier 엔진 구현 전 실물 확보 (읽기 전용)
- **2026-07-02** [RECON_history_ui.md](RECON_history_ui.md) — RECON_history_ui — 히스토리 표시 (읽기 전용)
- **2026-07-02** [RECON_overlay_pipeline.md](RECON_overlay_pipeline.md) — RECON — 사유지 회피 오버레이, pbf 갱신마다 재현 가능한 파이프라인 설계
- **2026-07-02** [RECON_poi.md](RECON_poi.md) — RECON_poi — POI 지명/히스토리 (읽기 전용)
- **2026-07-02** [RECON_private_avoid.md](RECON_private_avoid.md) — RECON — 사유지(삼성전자 공장) 관통 경로 회피 조사
- **2026-07-02** [RECON_prog_logging.md](RECON_prog_logging.md) — RECON_prog_logging — Layer 1 계측 삽입점 locate (읽기 전용)
- **2026-07-02** [RECON_query.md](RECON_query.md) — RECON_query — queryRenderedFeatures 실측 (읽기 전용)
- **2026-07-02** [RECON_reroute1.md](RECON_reroute1.md) — RECON_reroute — 재탐색 heading 전달 (읽기 전용)
- **2026-07-02** [RECON_roundabout.md](RECON_roundabout.md) — RECON — 회전교차로 안내 무음 (p2/p3)
- **2026-07-02** [RECON_sim_harness.md](RECON_sim_harness.md) — RECON_sim_harness — 합성 좌표 주입점 확보 (읽기 전용)
- **2026-07-02** [RECON_tap_card.md](RECON_tap_card.md) — RECON_tap_card — 탭 확인 카드 (읽기 전용)
- **2026-07-02** [RECON_tts_trigger.md](RECON_tts_trigger.md) — RECON_tts_trigger — TTS 임계 발화 로직 실물 확보 (읽기 전용)
- **2026-07-02** [RECON_tts_volume.md](RECON_tts_volume.md) — RECON — TTS 볼륨/가청성 (고가도로·터널 소음 대비 안 들림)
- **2026-07-02** [REPORT_arrival_dismiss.md](REPORT_arrival_dismiss.md) — REPORT — 도착 다이얼로그 재탐색 시 dismiss (#2)
- **2026-07-02** [REPORT_roundabout.md](REPORT_roundabout.md) — REPORT — 회전교차로 안내 (#4, 슬라이스 1+2+3)
- **2026-07-04** [RECON_arrival_order.md](RECON_arrival_order.md) — RECON: 도착/부근 음성 순서 역전
- **2026-07-04** [RECON_camera_redesign.md](RECON_camera_redesign.md) — RECON_camera_redesign — bottom-anchor 카메라 (C) 필드테스트 문제 조사
- **2026-07-04** [RECON_dest_marker.md](RECON_dest_marker.md) — RECON: destination pin stuck at pre-nav position
- **2026-07-04** [RECON_heading_reroute.md](RECON_heading_reroute.md) — RECON — Reroute U-turn ignores travel heading
- **2026-07-04** [RECON_markers.md](RECON_markers.md) — RECON — pin images (dest/waypoint) + rotating heading-arrow puck
- **2026-07-04** [RECON_nav_ui_redesign.md](RECON_nav_ui_redesign.md) — RECON — nav_screen 네이버식 UI 리디자인 (도착 배너 / 상시 재탐색 버튼 / 하단 앵커 카메라)
- **2026-07-04** [RECON_roundabout_direction.md](RECON_roundabout_direction.md) — RECON — 회전교차로 CW 표시 (방향 왜곡) 원인 조사
- **2026-07-04** [RECON_uturn_costing.md](RECON_uturn_costing.md) — RECON — U턴 강요 근원 (thor 패치 A 타당성)
- **2026-07-05** [RECON_home_ui.md](RECON_home_ui.md) — RECON: Home-screen UI parity + course→color wiring
- **2026-07-05** [RECON_reroute_button.md](RECON_reroute_button.md) — RECON — 재탐색 버튼 (Naver-style) 재배치 + 코스 재선택
- **2026-07-06** [RECON_settings_phase2.md](RECON_settings_phase2.md) — RECON: 설정 페이지 Phase 2
- **2026-07-06** [RECON_sharp_curve.md](RECON_sharp_curve.md) — RECON_sharp_curve — 급커브(45°+) 전용 안내 누락
- **2026-07-06** [RECON_stale_branches.md](RECON_stale_branches.md) — RECON — 4 dangling branches (2026-06-17 ~ 06-26), stale-vs-main audit
- **2026-07-06** [REPORT_tts_audibility.md](REPORT_tts_audibility.md) — REPORT — #5 TTS 가청성 (usage 내비 + focus/덕킹) — 리베이스판
- **2026-07-11** [RECON_costing_national.md](RECON_costing_national.md) — RECON — 국도 코스(index 2) 고속도로/자동차전용도로 미배제 원인
- **2026-07-11** [RECON_exit_landmark.md](RECON_exit_landmark.md) — RECON — EXIT-LANDMARK (2026-07-11 밤)
- **2026-07-11** [REPORT_PATCH3_uturn.md](REPORT_PATCH3_uturn.md) — REPORT_PATCH3 — Valhalla Fork Patch #3 (모터사이클 U턴 페널티)
- **2026-07-11** [REPORT_verify_ride0711.md](REPORT_verify_ride0711.md) — REPORT — verify/ride-0711 합본 검증
- **2026-07-18** [RECON_songtan_paldang_uturn.md](RECON_songtan_paldang_uturn.md) — RECON — 송탄→팔당 실측 "유턴" 재현 및 근본원인 조사 (2026-07-18)
- **2026-07-18** [REPORT_PATCH5_identity.md](REPORT_PATCH5_identity.md) — REPORT_PATCH5 — 3코스(시골길/지방도/국도) 정체성 튜닝 + U턴 허용범위 엔진 패치
- **2026-07-18** [REPORT_voice_wording_0718.md](REPORT_voice_wording_0718.md) — REPORT — 음성/카드 문구 전면 개편 + Valhalla 회전각 재조정 (2026-07-18)
- **2026-07-19** [RECON_tour_history_lost.md](RECON_tour_history_lost.md) — RECON — 투어 기록 완전 유실 (실주행 20-30분+ 라이딩, 저장 0건)
- **2026-07-19** [REPORT_PATCH6_turnangle_headingfix.md](REPORT_PATCH6_turnangle_headingfix.md) — REPORT_PATCH6 — 재탐색 버튼 heading 누락 + 좌/우회전 임계값 재조정
- **2026-07-19** [REPORT_reroute_heading_vgps_verify.md](REPORT_reroute_heading_vgps_verify.md) — REPORT — 자동 재탐색(이탈 감지) heading 버그, M32 가상GPS 실기 검증
- **2026-07-19** [REPORT_structure_turnangle_vgps_verify.md](REPORT_structure_turnangle_vgps_verify.md) — REPORT — 다리/지하차도 분류 + 회전 각도 임계값, M32 가상GPS 실기 검증
- **2026-07-20** [RECON_overlay_pipeline_impossible_turns.md](RECON_overlay_pipeline_impossible_turns.md) — RECON — 불가능한 좌회전 2건, 그래프 레벨 원인 규명 + 로컬 오버레이 파이프라인 (2026-07-20)
- **2026-07-21** [RECON_impossible_left_turns.md](RECON_impossible_left_turns.md) — RECON — 실주행에서 보고된 "좌회전 불가 지점" 2건 (2026-07-19)
