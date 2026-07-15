# HANDOFF — POI 데이터소스 아키텍처 결함 (2026-07-15, Claude Code for VS Code 세션)

> **새 세션은 이 문서부터 읽고 바로 착수할 것.** `RELEASE_ROADMAP.md`에도 15번 항목으로
> 등록해뒀지만 상세 설계 근거는 전부 여기 있음.

## 배경 — 어떻게 발견했는가

`RIDE_RESULTS_0715.md`(오늘 새벽 실주행)에서 "POI가 홈/내비 화면 둘 다 안 뜸"이 확진된 원인은
**빌드 시 `--dart-define-from-file=env.json` 플래그 누락**(`SEMAS_SERVICE_KEY`가 빈 문자열로
컴파일되어 API가 401)이었음. 이 세션에서 기존 debug APK를 지우고 플래그를 넣어 재빌드,
M32F(westinx 서버 상시 연결 테스트폰)에 재설치까지 완료했는데도 **사용자가 A34(실주행폰)에서
같은 증상을 재현 보고**함 — 앱 삭제 후 재설치했는데도 POI가 전혀 안 뜸.

원인을 다시 추적하기 위해 서비스키로 실제 API를 직접 curl 호출:

```
GET https://apis.data.go.kr/B553077/api/open/sdsc2/storeListInRadius?serviceKey=...
→ HTTP 429, body: "API token quota exceeded"
```

**빌드 문제가 아니라 일일 트래픽 쿼터(개발계정 10,000건/일, [[project_poi_datasource]] 참조)
소진.** 확인 시각 2026-07-15 16:23 KST, 리셋은 자정(KST) 기준 예상.

## 왜 이게 "오늘 재테스트하면 끝"이 아니라 근본 문제인가

**서비스키가 클라이언트(APK)에 그대로 박혀 있고(`String.fromEnvironment('SEMAS_SERVICE_KEY')`,
`lib/services/poi_service.dart:18`), 쿼터는 이 키 하나에 걸려있다.** 즉 전체 사용자가 쿼터
하나를 공유하는 구조. 지금은 개발자 1인 + 코드 감사 중 반복한 라이브 curl 검증만으로도
소진됐는데, 실사용자가 수백~수천 명으로 늘면 각자 이동하면서 발생하는 폴링(현재 앱에 최소
3개 독립 폴링 경로 존재 — 홈 ambient 레이어, 내비 ambient 레이어, 검색 프리페치, 각각
`fetchPois` 1회 = 5개 카테고리 병렬요청)이 무조건 하루 안에 쿼터를 소진시킨다. **운영계정
전환으로 쿼터를 늘려도 사용자 수가 늘면 다시 막히는 구조 자체는 그대로** — 이건 "쿼터가
작다"가 아니라 "사용자 요청이 매번 외부 API를 직접 때리는 아키텍처"가 문제.

## 근본 해결책 — 분기별 벌크 CSV 자체 호스팅

**핵심 발견**: 이 API는 실시간 조회 엔드포인트와 별개로, **같은 데이터를 분기별 전국 단위
CSV로도 무료 배포**한다 — [소상공인시장진흥공단_상가(상권)정보_20260331](https://www.data.go.kr/data/15083033/fileData.do)
(공공데이터포털 파일데이터 탭). 확인된 사실(WebFetch로 직접 확인, 2026-07-15):
- **전국 단위 한 파일**, 지역별로 안 나뉨.
- **로그인/인증키 불필요** — 그냥 다운로드.
- **갱신주기 분기, 다음 갱신 예정일 2026-08-01.** 중요: 실시간 API도 "분기별 갱신"이라고
  이미 메모리에 기록돼 있었음([[project_poi_datasource]]) — 즉 **파일이 실시간 API보다
  데이터가 더 오래된 게 아니다.** 이 전환에 신선도 손실이 전혀 없음.
- **"이용허락범위 제한없음"** — 상업적 이용/재배포/재가공 전부 허용.

### 제안 아키텍처

```
[분기별 1회] data.go.kr CSV 다운로드 → navi 서버 로컬 DB 적재 (cron)
[사용자 요청마다] Flutter 클라이언트 → navi.westinx.com/poi/nearby → 로컬 DB 조회 (외부 호출 0)
```

이러면 사용자가 몇 명이든 외부 쿼터에 걸릴 일이 원천적으로 없어짐 — 서버 자체 처리량
문제로 바뀔 뿐인데, 좌표 반경조회는 로컬 인덱스 DB로는 사실상 무시할 수준.

### 기존 인프라와 어떻게 맞물리는가 (이번 세션에 확인한 실제 코드 기준)

- **`native/`가 이미 axum 기반 Rust 서버**(`native/src/main.rs`, `yurunavi_server` 바이너리,
  포트 8003, `docker compose`로 이미 `navi` 서비스로 떠 있음 — 12번 인프라 작업에서 완료).
  기존 라우팅 패턴 그대로 따라가면 됨: `Router::new().route("/poi/nearby", get(handler))`
  식으로 추가, 순수 로직은 `native/src/api.rs`(flutter_rust_bridge 겸용 모듈, DB 접근은
  여기 넣지 말고 `main.rs`나 신규 모듈에 두는 게 기존 구조와 일관적 — `api.rs`는 지금
  I/O 없는 순수 함수만 있음).
- **`Cargo.toml`엔 아직 DB 크레이트가 없음**(`axum`/`tokio`/`serde`/`reqwest`뿐) — 신규
  추가 필요. 이 앱 규모(단일 개발자, 전국 데이터 한 번 로드 후 읽기 전용 조회 위주)엔
  PostgreSQL+PostGIS 같은 별도 DB 서버보다 **SQLite + R-tree 확장(`rusqlite` 크레이트,
  `bundled` feature로 R-tree 포함 가능)** 이 운영 부담이 훨씬 적음 — 별도 DB 서버 프로세스
  불필요, 파일 하나로 백업/배포 가능(`docker/backup.sh`의 기존 하드링크 스냅샷 패턴에
  자연스럽게 편입 가능). 데이터 규모가 실제로 커서(CSV를 받아봐야 정확한 행수 확인 가능,
  이번 세션엔 페이지 메타데이터만 확인함 — 누적 다운로드 41만+회라는 것만 확인, 정확한
  용량/행수 미확인) SQLite로 부족하면 그때 Postgres로 격상 검토.
- **분기 동기화 cron**: `docker/backup.sh`가 이미 매일 03:00 크론으로 등록되어 있는 패턴
  (`docker/INFRA.md` 참조) — 같은 자리에 분기 1회(다음 갱신 2026-08-01 기준) CSV
  재다운로드+재적재 스크립트를 추가하면 기존 운영 패턴과 일관적.
- **클라이언트 쪽 변경**: `lib/services/poi_service.dart`가 지금 `_semasBaseUrl =
  'https://apis.data.go.kr/...'`로 data.go.kr을 직접 호출 중(`_serviceKey =
  String.fromEnvironment('SEMAS_SERVICE_KEY')`, L13-18) — 이걸
  `https://navi.westinx.com/poi/nearby`로 교체. `routing_service.dart`/`native_engine.dart`가
  이미 이 패턴(자체 백엔드 호출)을 쓰고 있음(CLAUDE.md에 기록된 구조) — POI만 예외적으로
  외부 API 직호출이었던 것. 이 교체가 끝나면 **`SEMAS_SERVICE_KEY`를 클라이언트 빌드에서
  완전히 제거 가능**(env.json 의존성 자체가 사라짐, 부수적으로 APK 디컴파일로 키가
  추출되던 보안 리스크도 같이 해소).
- **카테고리 필터링/오분류 휴리스틱 이관 여부 결정 필요**: 현재 `poi_service.dart`에
  카테고리 코드 매핑(`_categoryCodes`)과 오분류 업소명 키워드 필터(`looksMisclassified`,
  `_nonStorefrontKeywords`/`_cafeRestaurantKeywords`)가 Dart 쪽에 있음. 새 아키텍처에서
  이 로직을 Rust 쪽(서버, 전 사용자 공용)으로 옮길지 그대로 Dart에 남겨 서버는 원본
  row만 반환할지는 새 세션에서 설계 시 결정 — 서버로 옮기면 유지보수 지점이 하나로
  줄어드는 대신 Rust 재작성 필요. CSV 컬럼명이 실제로 API JSON 필드(`indsLclsCd`,
  `indsMclsCd`, `indsSclsCd`, `bizesNm`, `lat`, `lon`, `rdnmAdr`, `lnoAdr`, `bizesId`)와
  동일한지도 다운로드 직후 반드시 확인할 것(공공데이터포털 파일/API가 컬럼명이 미묘하게
  다른 경우가 종종 있음).

### 진행 순서 제안 (CLAUDE.md TDD 루프대로, 체크포인트 커밋 매 단계)

1. CSV 실제 다운로드 + 스키마/행수/용량 확인 (컬럼명이 API JSON 필드와 일치하는지 직접 대조)
2. DB 스키마 설계 + rusqlite/R-tree 적재 스크립트 (rust-coder)
3. `native/src/main.rs`에 `/poi/nearby` 엔드포인트 추가 (rust-coder) — 기존
   `handle_off_route` 등과 동일한 axum 패턴
4. `poi_service.dart`를 새 엔드포인트로 교체, `SEMAS_SERVICE_KEY`/env.json 의존성 제거
   (flutter-coder)
5. code-auditor 감사 (반경 계산 정확성, 빈 결과/에러 처리, 기존 5종 카테고리 결과가
   실제 API와 동등한지 표본 비교)
6. `docker/backup.sh` 인근에 분기 동기화 cron 추가, `docker/INFRA.md` 갱신
7. `flutter analyze`/`flutter test`/`flutter build apk --debug` 확인 (이제
   `--dart-define-from-file` 불필요해짐 — 그것도 확인 포인트)
8. `RELEASE_ROADMAP.md` 15번 상태 갱신 + 커밋 해시 기록

## 오늘 밤 당장 라이딩 재검증이 급하다면 (임시방편, 근본 해결 아님)

자정(KST) 쿼터 리셋 후에는 지금 M32F에 설치된 빌드(플래그 포함, 이미 정상) 그대로 재테스트
가능 — 단 이건 이 세션에서 다루는 근본 수정과 무관한 임시방편이니 위 8단계 작업과 섞지 말 것.

## 참고 문서
- `loop/feedback/RIDE_RESULTS_0715.md` — 오늘 실주행 체크리스트 전체(P0 POI 포함 4건)
- `~/.claude memory`의 `project_poi_datasource.md` — API 사양·카테고리 코드·계정 상태
- `native/src/main.rs`, `native/src/api.rs`, `native/Cargo.toml` — 기존 백엔드 구조
- `docker/INFRA.md` — 기존 cron/백업 패턴
