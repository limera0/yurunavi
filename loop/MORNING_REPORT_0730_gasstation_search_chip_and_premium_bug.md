# 세션 보고 — 19번 후속: 고급휘발유 99999 버그 수정 + 지도 검색창 진입점 추가 (2026-07-30)

핸드오프: `HANDOFF_0730_gasstation_search_chip_and_premium_bug.md`. 마스터가 진행 중 스코프를
한 가지 명시적으로 확장함: **휘발유 탭과 고급휘발유 탭이 완전히 동일한 목록일 필요는 없다 —
고급휘발유 탭 선택 시 그 유종을 취급하지 않는 주유소는 목록에서 아예 제외**. 이 지시를
반영해 원래 핸드오프의 "premium_price: null로 두고 프론트에서 '정보 없음' 표시" 계획 대신
서버 단에서 완전히 제외하도록 구현했다.

## Phase A — 고급휘발유 99999 센티널 버그 (완료)

- `native/src/main.rs`: `parse_opinet_price()`에 `p != 99999` 필터 추가. 신규 헬퍼
  `should_include_for_fuel(fuel, gasoline, premium)` 추가해 B034 요청 시 `premium.is_none()`인
  주유소를 `handle_gasstations_nearby`의 `filter_map`에서 완전히 드롭.
- 단위테스트 6종 신설(`parse_opinet_price` sentinel/정상값/영·음수·빈값, `should_include_for_fuel`
  3케이스). `cargo test` 148 passed, 0 failed.
- rust-coder 구현 → code-auditor PASS(빈 findings) → `docker compose build navi` +
  `up -d navi`로 재배포 → healthy 확인.
- 배포 후 curl 재검증(운영 컨테이너, 8003 포트, 실제 오피넷 라이브 데이터):
  - 울릉군 좌표 B034(반경 10km) → `[]` (3개 주유소 전부 고급휘발유 미취급, 전체 제외 확인)
  - 울릉군 좌표 B027 → 정상 3건(2059/2079/2079원)
  - 서울 중구 B034(혼재 지역) → 6건, premium_price 전부 2369~3240원 정상 범위, 99999 없음
- 커밋 `5353305`.

## Phase B — 지도 검색창("주변 탐색") "주유소" 단독 선택 시 오피넷 경로 전환 (코드 완료, 실기기 시각 확인은 마스터 예정)

- **핸드오프 문서 정정**: 핸드오프가 지목한 `_PlacesSheet`(3160줄대)는 실제로는 즐겨찾기/최근
  경로 전용 위젯이라 카테고리 칩이 없음 — 진짜 대상은 `_PoiExploreSheetState`
  (`main_map_screen.dart`, "주변 탐색" 시트, 카테고리 필터칩 보유, 2882줄~). 코딩 전 실제
  파일을 읽고 확인 후 정정해서 진행.
- `_isGasStationOnly`(주유소 칩 단독 선택 — 검색어로 5종 확장되는 `_effectiveTypes`와는 별개
  조건) 상태일 때만 `GasStationService.fetchNearby(fuel: 'B027')`로 전환, 그 외 조합은 기존
  소상공인 DB(`/poi/nearby`) 경로 완전히 그대로(byte-identical, 코드리뷰로 확인).
- 유종은 B027 고정(스코프 최소화, 토글칩은 후속 과제).
- 리스트 아이템은 `nav_screen.dart`의 `_GasStationSheet` 스타일 재사용. 탭 시 `GasStation`을
  합성 `Poi`로 감싸 기존 `onSelectDest` 콜백 경로 그대로 재사용 — 부모 위젯
  (`_showPoiExploreSheet` 호출부)은 무변경.
- flutter-coder 구현 → code-auditor PASS(빈 findings, `flutter analyze` 재확인 포함) → 커밋
  `0decff2`.
- `flutter build apk --debug` + `adb install`로 연결된 실기기(M32, `RZ8RC1N3V9W`)에 설치까지
  이 세션에서 완료. "주변 탐색" 시트를 열고 "주유소" 칩을 누르는 조작까지 시도했으나 스크린샷
  좌표 스케일링(표시 900x2000 vs 실제 1080x2400, 1.2배) 실수로 다른 칩(주소 모드 토글)을
  잘못 누름 — 마스터가 "M32 응답 느리면 건너뛰고 진행, 실기기 테스트는 직접 하겠다"고 해서
  이 지점에서 자동화 검증을 중단함. **주유소 칩 단독 선택 시 오피넷 목록이 실제로 뜨는지는
  아직 육안 미확인.**

## 남은 것 / 다음 세션 확인 필요

- Phase B 실기기 시각 확인(마스터 예정) — 결과에 따라 `RELEASE_ROADMAP.md` 19번 후속 섹션과
  이 보고서에 반영 필요.
- 유종 토글칩(B027/B034)을 지도 검색창 쪽에도 추가할지는 마스터 판단 대기(핸드오프 원문
  지시, 미착수).

## 커밋

- `5353305` fix(navi): 오피넷 99999 센티널 필터 + B034 미취급 주유소 목록 제외
- `0decff2` feat(map): 검색창 주유소 단독선택 시 오피넷 가격순 목록으로 전환

**목표 달성 판정:** 원래 목표: 지도 검색창 주유소 단독 선택 시 오피넷 가격순 전환 + 고급휘발유
99999 버그 수정(마스터 추가 지시: 고급휘발유 탭은 미취급 주유소를 목록에서 제외) / 달성: 부분 —
Phase A(버그 수정+배포+실측 재검증)는 완전히 끝나 달성. Phase B는 코드·code-auditor PASS·빌드·
기기 설치까지 끝났으나 시트에서 칩을 눌러 목록이 실제로 뜨는 육안 확인이 아직 없음(좌표 스케일링
실수로 자동 검증 중단, 마스터가 직접 확인하기로 함) — 그 결과가 나와야 전체 done으로 닫힌다.
