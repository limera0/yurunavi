# 유루나비 ROADMAP v2 (Night 10 이후)
# 완료 기준: [AUTO] = Claude Code 자율 수행 가능 / [HUMAN] = 마스터 직접 확인 필요
# 작업 방향: 핵심 가치(재미있는 시골길 탐색) → 완성도 → 배포 준비 순

**⚠️ 2026-07-17 확인**: 이 파일 전체가 상당히 stale함 — 아래 "미완료" 항목 중 최소
1/3/4/6/9번은 스팟체크 결과 이미 코드에 구현돼 있었음(상세는 각 항목 옆 표시). 지금
릴리스 준비의 단일 소스는 `loop/RELEASE_ROADMAP.md`, 라이딩 품질 이슈는
`loop/feedback/RIDE_RESULTS_0716.md`다 — 이 파일은 전수 재검증 안 했으니 "미완료"
표시를 그대로 믿지 말고 착수 전 코드로 재확인할 것(BACKLOG.md와 동일한 함정).

## 완료 ✅ (Night 1~10, 항목 1~27)
[생략 — git log 참조]

## 미완료 항목 (위에서부터 처리) — ⚠️ 위 경고 참조, 아래 [ ]는 미검증 표시 그대로임

### 🔴 핵심 가치 (앱 존재 이유)
- [x] 1. [AUTO] fun-road costing 실제 구현 — **2026-07-17 스팟체크: 이미 구현됨**. Valhalla 포크(`/data/projects/valhalla-src/src/sif/motorcyclecost.cc`)에 실제 커스텀 코스팅 존재, `native/src/api.rs`의 `fun_score_v1/v2`와 별개로 라우팅 엔진 자체가 곡률 기반 차별화(+7.8% 우회 실측, `docker/REPORT_PATCH2.md`). 메모리 `project_yurunavi.md` 참조.
- [ ] 2. [AUTO] 고속도로·자동차전용도로 완전 배제 검증: `motorcyclecost.cc`에 `highway_factor_`/`use_highways` 기반 가중치 로직은 있음(스팟체크 확인) — 다만 "완전 배제(use=0)"인지 "패널티 가중치"인지까지는 이번엔 안 봄, 필요시 재확인.
- [x] 3. [AUTO] fun_score 구성요소 확장 — 도로 등급 가중치 — **이미 구현됨**: `native/src/api.rs`의 `road_class_score`/`fun_score_v2`.
- [x] 4. [AUTO] fun_score 구성요소 확장 — 커브 밀도 — **이미 구현됨**: `native/src/api.rs`의 `calc_tortuosity`/`curvature_tau`(`fun_score_v1` 기반).

### 🟠 내비게이션 완성도
- [ ] 5. [AUTO] 경로 카드 선택/미선택 색상 구분 — 미검증(이번엔 안 봄).
- [x] 6. [AUTO] 음성 안내 거리 정확도 — **이미 구현됨, ROADMAP 요청보다 더 발전된 형태**: `GuidanceProfile`의 티어 시스템(`500/300/50m` 등)으로 이벤트별 거리 기반 발화(`lib/features/navigation/guidance_profile.dart`, `voice_engine.dart`).
- [ ] 7. [AUTO] 도착지 주변 POI 표시 — 미검증. `nav_screen.dart`에 `_arrivalPois` 상태가 존재하는 건 확인했으나 요청 스펙(반경 500m·3개·마커)과 정확히 일치하는지는 안 봄.
- [ ] 8. [AUTO] 경유지 추가 버튼 상태 버그 수정 — 미검증(이번엔 안 봄, `main_map_screen.dart`에 경유지 추가 UI 자체는 존재).

### 🟡 지도 표시 완성도
- [x] 9. [AUTO] OSM 스타일 실제 적용 확인 — **이미 완료됨**: `pubspec.yaml`에 `maplibre_gl: ^0.26.1`, CLAUDE.md "지도 타일 인프라" 섹션에 타일서버/스타일 전환 완료 기록. flutter_map은 이미 대체됨.
- [ ] 10. [AUTO] 지도 초기 줌 레벨 z16 고정 — 미검증.
- [ ] 11. [AUTO] 내비 중 지도 줌 속도 연동 튜닝 — 미검증(단, `RIDE_RESULTS_0716.md`가 다른 줌/자동추종 이슈를 다루는 걸 보면 이 영역이 계속 튜닝 중인 건 맞음).

### 🟢 인프라·안정성
- [ ] 12. [AUTO] Rust 서버 systemd 자동 재시작 확인 — 미검증. 참고: `loop/RELEASE_ROADMAP.md` 12번에 따르면 navi 백엔드는 이제 systemd가 아니라 Docker compose로 전환 완료(`docker restart=always` 정책 여부는 미확인).
- [x] 13. [AUTO] scripts/check_all.sh 확장 — **이미 구현됨**: `scripts/check_all.sh`에 valhalla `/status`·navi `/health` curl 체크 둘 다 존재.
- [x] 14. [AUTO] APK 서명 키 설정 — **이미 완료됨**(`loop/RELEASE_ROADMAP.md` 2번과 동일 항목, DONE).

### 🔵 배포 준비
- [ ] 15. [HUMAN] 앱 아이콘 + 스플래시 이미지 교체 — **미완료, 실제로 남아있는 항목**(`loop/RELEASE_ROADMAP.md` 9번과 동일, 8번 브랜드 방향 확정 대기 중).
- [~] 16. [AUTO] 앱 버전 관리 자동화 — 부분: `pubspec.yaml`이 `version: 1.0.1+2` 체계는 쓰고 있음(수동), "완료 시 자동 bump 스크립트"까지 있는지는 미검증.
- [ ] 17. [AUTO] 릴리즈 APK 빌드 + 파일명 자동화 — 미검증(`loop/RELEASE_ROADMAP.md` 10번 "실제 release build 검증"과 사실상 같은 항목, 거긴 DEFERRED 상태).
- [ ] 18. [HUMAN] Google Play 내부 테스트 트랙 첫 업로드: APK → AAB 전환, Play Console 앱 생성, 내부 테스트 등록. 마스터가 Play Console 계정 필요.

### ⚪ 일본 시장 확장 (MVP 이후)
- [ ] 19. [AUTO] 일본 OSM 타일 빌드: Geofabrik japan-latest.osm.pbf → Valhalla 타일 빌드. valhalla.westinx.com이 한국/일본 타일 모두 서비스하도록 config 분기.
- [ ] 20. [AUTO] 언어 다국어 지원 기반: flutter_localizations 추가, ko/ja ARB 파일 구조 생성. 현재 하드코딩된 한국어 문자열 추출 (l10n.dart 자동 생성).
