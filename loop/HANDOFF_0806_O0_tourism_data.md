GOAL: OSM PBF + data.go.kr 표준데이터에서 관광지/전망대 POI(약 2.8만건)를 추출해 `tourism.db`로 별도 배포하고, 앱에 `PoiType.touristSpot`/`PoiType.viewpoint` 2종을 신규 추가한다.

# HANDOFF — O0 · 관광지 데이터 파이프라인

- 작성 2026-08-06 · 브랜치 `verify/ride-0711` · HEAD `a9589f8`
- 대장: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §O (507~568행)
- 근거: [RECON_0805_offline_first_architecture.md](RECON_0805_offline_first_architecture.md) §7(O0 정의) · §9(데이터 소스 조사)
- **오프라인 트랙(O0~O5) 중 이번 세션은 O0만.** O1~O5는 스코프 밖 — 손대지 말 것.
- O0은 오프라인 전환과 독립적으로 값어치 있음 — 완성되면 서버 `tourism.db`에 얹어 **온라인 경로에서도 바로 사용**.

---

## 0. 마스터 확인 완료 사항 (2026-08-06, 착수 전 4문항 회신)

| # | 질문 | 결정 |
|---|---|---|
| 1 | 착수 범위 | **O0만.** P1(S4~S8)·O1~O5는 이번 세션 대상 아님 |
| 2 | PoiType 분리 | **관광지 / 전망대 2종 분리** (RECON §9-3 권고 채택) |
| 3 | data.go.kr 15021141 인증키 | **이미 발급받아 바로 다운로드 가능.** 포맷은 **CSV** — 기존 `native/src/bin/ingest_poi.rs`가 `csv` crate로 상권 POI를 읽는 파이프라인과 동일하게 맞춤(신규 XML/RDF 파서 의존성 불필요) |
| 4 | TourAPI(26만건, 15101578) | **이번엔 제외.** 과거 공공데이터포털 쿼터 공유 결함 재발 이력(memory `project_poi_datasource`) 반복 방지 |

---

## 1. 데이터 소스 (RECON §9 실측 요약)

### 1-1. OSM — 1순위, 서버에 이미 있음

`/data/valhalla/staging_impossible_turns/korea_patched.osm.pbf`(267MB)에서 `osmium`으로 추출(실측 4초).

| OSM 태그 | 건수 | 매핑할 신규 PoiType |
|---|---|---|
| `tourism=viewpoint` | 2,277 | **viewpoint** (전망대 — 라이더 최고가치) |
| `boundary=national_park` | 24 | touristSpot |
| `tourism=attraction` | 1,676 | touristSpot |
| `tourism=museum` | 1,550 | touristSpot |
| `historic=*` | 5,309 | touristSpot |
| `leisure=nature_reserve` | 46 | touristSpot |
| `natural=peak` (이름 있는 것만) | 16,548 중 일부 | touristSpot (무명 봉우리는 제외 — 이름 필터링 필수) |

라이선스 **ODbL**. `© OpenStreetMap contributors` 표기는 앱에 이미 있음(`main_map_screen.dart` LAYER 1b) — 추가 표기 불필요, 단 §3의 분리 배포 원칙은 지킬 것.

### 1-2. data.go.kr 전국관광지정보표준데이터 — 2순위, 한글 명칭 보강용

[15021141](https://www.data.go.kr/data/15021141/standard.do) — 관광지명·관광지구분·소재지주소·위도·경도·면적·주차가능수·관광지소개·관리기관. CSV. 소관 문화체육관광부, 갱신 연 1회.

- 인증키는 확보돼 있다(§0-3). CSV로 다운로드.
- ⚠️ **그리드 다운로드 5만건 제한** — 전체가 5만 건을 넘으면 페이지네이션/그리드 분할 필요(RECON §9-2). 실제 건수 먼저 확인할 것.
- 좌표 근접 매칭(예: 50~100m 반경)으로 OSM 추출분과 중복 제거 + 한국어 공식 명칭 보강. 매칭 안 되는 표준데이터 항목은 그대로 추가(법적 지정 관광지라 OSM에 없는 것도 있음).
- "관광지구분" 필드로 touristSpot/viewpoint 중 어디로 갈지 분류(전망대성 구분이 있으면 viewpoint로, 없으면 touristSpot 기본).

---

## 2. 구현 항목

### 2-1. 추출 스크립트 (서버/CI, Rust 또는 쉘+osmium)

- [ ] osmium으로 위 태그 필터 추출 → 중간 GeoJSON 또는 CSV
- [ ] `natural=peak`은 `name` 태그 없는 것 제외
- [ ] data.go.kr CSV 다운로드 + 파싱(`native/src/bin/ingest_poi.rs`의 `csv::ReaderBuilder` 패턴 재사용)
- [ ] 좌표 근접 매칭으로 병합, 중복 제거 로직에 단위테스트

### 2-2. `tourism.db` — poi.db와 **별도 파일**

> ⚠️ **라이선스 필수 조건 (RECON §9-3).** 현 `poi.db`는 공공누리 데이터. OSM(ODbL)을 같은 DB에 병합해 배포하면 그 DB가 ODbL "파생 데이터베이스"가 되어 share-alike가 걸릴 수 있다. **반드시 `tourism.db`로 분리 배포**(collective database로 유지) — 병합 금지. 출처 표기는 관광지 항목에 OSM/공공데이터 출처를 개별 표기.

- [ ] `tourism.db` 스키마 설계 — `poi.db`의 R-tree 인덱스 패턴 재사용
- [ ] 서버 배포 경로 확정 (poi.db와 동일 호스팅 위치, 파일만 분리)

### 2-3. `PoiType` 신규 (`lib/models/poi.dart:3`)

현재 5종(`cafe`, `convenienceStore`, `gasStation`, `supermarket`, `restaurant`)에 이어:

- [ ] `PoiType.touristSpot`, `PoiType.viewpoint` 추가
- [ ] 아이콘 매핑 추가 (기존 SVG 아이콘 패턴 — memory `project_nav_svg_icons` 참고, `assets/images/nav_icons/`)
- [ ] `minZoomLevel`·`displayPriority` 값 결정 — 전망대는 라이더 핵심 가치이므로 restaurant보다 표시 우선순위 높게 검토(현재 restaurant가 최하위인 것과 대비, RECON §1 지적)
- [ ] `_label`/`_color`/`displayPriority` 등 기존 switch문 전수 반영 (컴파일러가 `case` 누락을 잡아줌 — exhaustive switch 확인)

### 2-4. 서버 통합 (온라인 경로)

- [ ] `tourism.db`를 기존 POI 조회 서버(`native/`)에서 함께 질의하도록 통합 — 단, **poi.db와 물리적으로는 별도 파일 유지**, 응답 스키마에서만 합쳐서 반환
- [ ] 기존 5종 카테고리 필터 API에 `touristSpot`/`viewpoint` 추가

---

## 3. 스코프 밖 (이번 세션에서 하지 말 것)

- [-] TourAPI 통합 — §0-4 결정
- [-] 온디바이스(sqflite) 오프라인 다운로드 — O3 항목, 이번 세션 아님
- [-] 타일 오프라인·스타일 로컬화 — O1/O2, 이번 세션 아님
- [-] Rust 이관 판단 — O4, 이번 세션 아님

---

## 4. 검증

- [ ] `flutter analyze` 0 · `flutter test` 전건 통과 (신규 PoiType 관련 테스트 포함)
- [ ] 추출 건수 실측이 RECON §9-1 표(전망대 2,277·국립공원 24 등)와 자릿수가 맞는지 확인
- [ ] `tourism.db`가 `poi.db`와 물리적으로 분리된 별도 파일인지, 배포 스크립트에서 병합되지 않는지 확인
- [ ] 좌표 근접 매칭 중복 제거가 실제로 동작하는지(같은 지점이 OSM+표준데이터 양쪽에 다 있는 국립공원 등 샘플로 확인)

## 5. 완료 후

- [ ] `CHECKLIST_0805_testride0802.md` §O0 항목 `[x]`로 갱신, 커밋 메시지에 "O0" 명시
- [ ] O1(스타일 로컬화)이 다음 후보 — 다만 착수는 마스터 재확인 후
