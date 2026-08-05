# RECON — 오프라인 우선(offline-first) 전환 검토: POI·타일 사전 다운로드 + 온디바이스 조회

- 작성 2026-08-05 · 브랜치 `verify/ride-0711`
- 발단: 마스터 제안 — "POI 전체를 폰에 미리(가급적 WiFi에서) 받아두고 GPS 기준으로
  폰에서 바로 읽자. Rust로 만들자. 지도 타일도 미리 받아두자. 주행 중 네트워크·CPU
  사용을 최소화하자."
- 선행: [RECON_0805_testride0802_master_plan.md](RECON_0805_testride0802_master_plan.md) §3(근본원인 B),
  [MORNING_REPORT_0805_S2_network_flood.md](MORNING_REPORT_0805_S2_network_flood.md)
- 체크리스트 P3 기존 항목: "오프라인 지도 다운로드(도 단위, WiFi 전용 옵션)",
  "OSMAND / Organic Maps 벤치마킹 조사" — **이 문서가 그 조사에 해당한다.**
- **정찰 전용. 코드 변경 없음.**

---

## 0. 결론 먼저

**방향은 옳다. 다만 순서와 도구 선택은 조정을 권한다.**

| 마스터 제안 | 판정 | 이유 |
|---|---|---|
| POI를 폰에 미리 받아 온디바이스 조회 | **채택 권고** | OSMAnd·Organic Maps 둘 다 이 구조. 우리 데이터는 154MB로 충분히 작다 |
| 타일 미리 다운로드 | **최우선 채택 권고** | **이미 쓰는 `maplibre_gl 0.26.1`에 오프라인 API가 통째로 들어있다.** 새로 만들 게 거의 없다 |
| WiFi일 때 백그라운드 다운로드 | **채택** | 450MB급이라 필수 조건 |
| POI 조회를 **Rust**로 구현 | **1단계에서는 비권고 → 2단계 선택지** | 조회 자체가 병목이 아니다. `sqflite` + 기존 R-tree로 충분. Rust는 NDK·3-ABI 빌드 비용을 새로 지는데 얻는 게 측정되지 않았다 |
| "CPU 의존성을 줄인다" | **부분 정정 필요** | 실측된 CPU·배터리 주범은 POI 조회가 아니었다 (§2) |

**가장 중요한 발견 하나만 고른다면**: 타일 오프라인은 **개발이 아니라 통합 작업**이다.
`maplibre_gl 0.26.1`이 `downloadOfflineRegion` · `installOfflineMapTiles`(mbtiles 통째
사이드로드) · `pauseOfflineRegionDownload` · `setOfflineTileCountLimit` ·
`setOfflineMaxConcurrentRequests` · `setOffline(true)`를 전부 제공한다. 앱 코드에서
**현재 단 한 곳도 안 쓰고 있다**(`grep -rn "OfflineRegion" lib/` → 0건).

---

## 1. 실측 숫자 — 우리 데이터 규모

이 검토의 모든 판단은 아래 실측치에서 나왔다.

| 대상 | 크기 | 상세 |
|---|---|---|
| **타일** `/data/tiles/data/korea.mbtiles` | **382 MB** | z0–14, pbf/gzip, OpenMapTiles 3.16.0, bounds 124.3–132.3 / 32.4–38.6 (**남한 전역**) |
| **POI** `/data/poi/poi.db` | **154 MB** | SQLite, **696,255행**, `poi` 테이블 + **`poi_rtree` R-tree 인덱스 이미 존재** |
| 참고: 일본 타일 | 1.7 GB | 현재 앱 스코프 밖 |

POI 카테고리 분포:

| 카테고리 | 행 수 | 비중 |
|---|---|---|
| restaurant | 452,778 | **65.0%** |
| cafe | 115,173 | 16.5% |
| supermarket | 60,248 | 8.7% |
| convenience_store | 55,109 | 7.9% |
| gas_station | 12,947 | 1.9% |

> **주목**: 식당이 전체의 3분의 2다. 그런데 `PoiService.displayPriority`에서 식당은
> **최하위**이고, 라이더에게 실제로 중요한 주유소는 1.9%(12,947건)뿐이다.
> 카테고리 선택 다운로드만으로 용량이 크게 갈린다(§5-2).

**전국 통짜 패키지 = 타일 382MB + POI 154MB ≈ 536MB.**
OSMAnd 한국 `.obf`(라우팅·주소 포함)나 Geofabrik 한국 PBF(289MB)와 같은 자릿수로,
이 카테고리 앱에서는 지극히 정상적인 크기다. 다만 **도 단위 분할은 필수**다.

---

## 2. 먼저 정정 — "CPU 의존성"의 실체

마스터 제안의 목표 중 "CPU 사용량 최소화"는 방향은 맞지만, **실주행 로그에서 측정된
CPU·배터리 주범은 POI 조회가 아니었다.** 정확히 하고 가야 우선순위를 안 틀린다.

| 실측 주범 | 상태 |
|---|---|
| `clamp` 예외 56,789건 → 스택트레이스 + 디스크 append + Crashlytics 업로드 | **S1에서 해결** |
| POI 요청 69,875건(전부 429) → TLS 핸드셰이크 + 라디오 상시 점유 + 실패 로그 | **S2에서 해결** |
| GPS `bestForNavigation` 1Hz + `distanceFilter: 0` 상시 (`keepAlive()`로 홈/설정 화면에서도) | S5 예정 |
| 음성 엔진 4개가 서로 모른 채 각자 발화 | S4b 예정 |
| 렌더링 자원 고갈(내용물 소실) | S1b 조사 예정 |

**POI를 SQLite R-tree에서 읽는 비용 자체는 원래도 무시할 만하다** — 69만 행 R-tree
질의는 밀리초 이하다. 서버에서 읽든 폰에서 읽든 그 계산 자체는 싸다.

그러면 오프라인 전환의 진짜 이득은 무엇인가:

1. **네트워크 왕복 제거** — TLS 핸드셰이크, 라디오 wake, JSON 파싱, 타임아웃 대기.
   이건 CPU보다 **배터리·발열**에 직접 온다. 실질 이득 크다.
2. **신호 없는 곳에서도 동작** — ⭐ **이게 진짜 이유다.** 산길·터널·시골은 투어러의
   주 무대인데 지금은 거기서 POI도 타일도 안 나온다. 기능 결손이지 최적화가 아니다.
3. **서버 부하·비용 제거** — 429를 뱉던 게 Cloudflare 터널이다. 사용자가 늘수록
   이 병목은 다시 온다. 근본적으로 없애는 게 맞다.
4. **429 계열 장애의 구조적 소멸** — S2는 폭주를 "막았"지만, 오프라인은 원인을 "없앤다".

> 즉 **"CPU 절감"보다 "네트워크 비의존 + 배터리 + 서버비용"으로 이유를 잡는 게
> 정확하다.** 어차피 결론(하자)은 같지만, 이유가 정확해야 나중에 성능이 기대만큼
> 안 나왔을 때 엉뚱한 데를 파지 않는다.

---

## 3. 벤치마킹 — OSMAnd · Organic Maps는 어떻게 하나

### 3-1. Organic Maps — `.mwm`, 완전 오프라인

- 지역별 **`.mwm` 바이너리 한 파일**에 지오메트리·POI·**검색 인덱스**·라우팅이
  전부 들어간다. 서버 질의가 **아예 없다**.
- 저장소 구조(`docs/STRUCTURE.md` 실측):
  `indexer/`("processor for map files, classificator, styles") ·
  `search/`("ranking and searching classes") · `routing/`("in-app routing engine") ·
  `drape/`("the new graphics library core") + `drape_frontend/` + `shaders/`.
- 렌더링은 자체 **Drape**(C++ GPU 렌더러). 검색·라우팅도 C++로 온디바이스.
- 홍보 문구 그대로 "100% offline — including search and navigation".

### 3-2. OsmAnd — `.obf`, 프로토버프 섹션 구조

- `.obf` 한 파일에 **Map / Routing / POI / Address / Transport** 섹션이 들어가고,
  각 섹션이 여러 개일 수 있다. 파일당 **2GB 미만 권장**.
- **POI 공간 인덱싱이 우리에게 가장 참고가 된다** (`OBF.proto` 실측):
  - `OsmAndPoiBox` — `zoom`, `left`, `top`을 **부모 대비 델타 인코딩**, `subBoxes`로
    재귀 → **줌 레벨별 타일 박스 트리**
  - `OsmAndPoiBoxData` — 리프에 `zoom`/`x`/`y` 타일과 실제 POI 목록
  - `OsmAndPoiBoxDataAtom` — 개별 POI. 좌표를 **zoom 24 기준 `dx`/`dy` 델타**로 저장
  - `OsmAndPoiNameIndex` — 이름 검색용 프리픽스 트리
  - `OsmAndCategoryTable` — 카테고리/서브카테고리 계층
- 요컨대 **"공간 타일 트리 + 델타 인코딩 + 파일 내장 인덱스"**로 용량과 조회를 함께 잡는다.

### 3-3. 우리에게 주는 시사점

| 그들 | 우리 | 판단 |
|---|---|---|
| 지역별 단일 파일에 인덱스 내장 | `poi.db`(SQLite + R-tree) | **R-tree가 이미 같은 일을 한다.** 자체 바이너리 포맷을 새로 발명할 이유 없음 |
| 델타 인코딩으로 용량 압축 | 154MB 원본 | 필요해지면 그때. 우선은 **카테고리·지역 선택**으로 줄이는 게 훨씬 싸다 |
| 온디바이스 라우팅(C++) | Valhalla **서버** | ⚠️ **우리는 라우팅이 오프라인이 안 된다** (§6) |
| 자체 GPU 렌더러(Drape) | MapLibre Native(C++ GPU) | **이미 동급이다.** Gemini 권고가 틀렸던 지점(RECON §0)과 동일 |
| 이름 검색 프리픽스 트리 | 서버 `/geocode/search`(V-World 프록시) | 오프라인 상호 검색은 별도 과제 |

**결론: 우리는 두 앱의 아키텍처 중 "데이터를 폰에 두는 부분"만 가져오면 되고,
렌더러는 이미 같은 급이며, 라우팅은 서버로 남는다.**

---

## 4. 타일 오프라인 — 이미 있는 API로 대부분 해결된다

`maplibre_gl 0.26.1`(현 `pubspec.yaml:35` 의존성)의 `lib/src/global.dart` 실측 API:

| API | 용도 |
|---|---|
| `downloadOfflineRegion(definition, metadata, onEvent)` | bbox + 스타일 + min/max zoom 지정 다운로드 |
| **`installOfflineMapTiles(tilesDb)`** | **mbtiles 파일을 통째로 사이드로드** ("Copy tiles db file passed in to the tiles cache directory") |
| `pauseOfflineRegionDownload` / `resumeOfflineRegionDownload` | 일시정지·재개 (WiFi 끊기면 정지) |
| `getOfflineRegionStatus` / `getListOfRegions` / `deleteOfflineRegion` | 진행률·목록·삭제 |
| **`setOfflineTileCountLimit(limit)`** | ⚠️ **MapLibre 기본 상한이 낮다. 안 올리면 도 단위 다운로드가 조용히 끊긴다** |
| **`setOfflineMaxConcurrentRequests(...)`** | 문서 원문: *"Lowering these values can help avoid rate limiting from tile servers (e.g. Cloudflare)"* — **우리 429 문제와 정확히 같은 이야기** |
| `setOffline(true)` | 강제 오프라인. "데이터 절약 모드" + **주행 중 네트워크 0을 검증하는 수단** |
| `clearAmbientCache` / `resetOfflineDatabase` | 정리 |

### 4-1. 두 갈래 방식 — 사이드로드가 유리하다

| 방식 | 내용 | 평가 |
|---|---|---|
| **A. mbtiles 사이드로드** (`installOfflineMapTiles`) | 서버에서 `korea.mbtiles`(382MB) 또는 도 단위로 자른 mbtiles를 **HTTP 한 번**에 받아 설치 | **권고.** 서버 부하 최소(정적 파일 1개), 재개 가능(HTTP Range), 타일 개수 상한 무관, 우리가 이미 mbtiles를 갖고 있다 |
| B. `downloadOfflineRegion` 크롤 | 앱이 bbox 안 타일을 하나씩 요청 | 수만~수십만 요청 → **Cloudflare가 또 429를 뱉는다.** 사용자별 반복 부하. 상한 설정도 필요 |

> B는 "우리 서버가 안 죽을 만큼 천천히" 받아야 해서 오래 걸리고, 그 과정이 정확히
> 우리가 방금 S2에서 막은 폭주와 같은 모양이다. **A를 기본으로, B는 소규모 보정용.**

### 4-2. ⚠️ 빠지기 쉬운 함정 — 스타일 에셋도 오프라인이어야 한다

`assets/images/osm_liberty_yurunavi.json` 실측:

```
"glyphs":  "https://tiles.westinx.com/fonts/{fontstack}/{range}.pbf"
"sprite":  "https://tiles.westinx.com/styles/yurunavi/sprite"
"url":     "https://tiles.westinx.com/data/v3.json"
```

타일만 받아두고 이걸 그대로 두면 **글리프(한글 폰트!)와 스프라이트를 계속 네트워크로
가져간다.** 한국어 라벨은 CJK 글리프 range가 많아 요청 수가 적지 않다.
→ 폰트 pbf·스프라이트를 **앱 에셋으로 동봉**하고 스타일을 로컬 경로로 바꿔야 진짜
오프라인이 된다. Noto Sans + Noto Sans CJK TC(현 타일서버 설정) 기준으로 용량 확인 필요.

---

## 5. POI 오프라인 — 설계안

### 5-1. 데이터 전달 방식

`poi.db`는 이미 **SQLite + R-tree**다. 그대로 폰에 내려서 그대로 읽으면 된다.
포맷 변환·재설계 불필요(memory `feedback_prefer_simple_reuse`).

- 서버: `/poi/download?region=<코드>&categories=<...>` — 미리 잘라둔 `.db`를 정적 제공
  (gzip 전송). 매니페스트(`version`, `built_at`, `sha256`, `size`)를 함께 둔다.
- 앱: 받아서 앱 전용 디렉터리에 저장 → 기존 `/poi/nearby` 호출을 **로컬 질의로 대체**.
- 갱신: 월 1회 매니페스트 확인 → 버전 다르면 WiFi에서 재다운로드(OSMAnd도 월 1회 갱신).

### 5-2. 용량 줄이기 — 선택지 (마스터 결정 필요)

| 안 | 내용 | 예상 용량 | 비고 |
|---|---|---|---|
| a | 전국 5종 전부 | ~154MB | 단순, 가장 안전 |
| b | **전국, 식당 제외** | ~50MB 내외 | 식당이 65%. 라이더 우선순위 최하위 |
| c | 전국, 주유소+편의점만 | ~15MB 내외 | 12,947 + 55,109 = 68,056행. **투어 필수 2종** |
| d | 도 단위 선택 다운로드 | 지역별 | 타일과 같은 단위로 묶으면 UX 일관 |

> **소견**: 기본값 **c 또는 b**(주유소·편의점은 항상 포함), 나머지는 사용자가 켜면
> 추가 다운로드. 식당·카페는 온라인일 때만 서버 조회로 보완해도 실용상 문제없다.
> — 다만 이건 제품 판단이라 마스터가 정해야 한다.

### 5-3. 조회 계층 — **Rust vs Dart, 솔직한 평가**

마스터 제안의 핵심 질문이다. 현재 상태부터 정확히:

- `pubspec.yaml:25` `flutter_rust_bridge: ^2.12.0` **있음**
- `native/Cargo.toml` `crate-type = ["cdylib", "staticlib"]`, `rusqlite`(bundled) **있음**
- **그러나 `native/src/lib.rs`는 9바이트(`mod api;`)뿐이고, `android/`에 Rust 빌드
  연동(cargo-ndk, jniLibs)이 **전혀 없다.** `.so` 파일 0개.**
- `abiFilters = ["armeabi-v7a", "arm64-v8a", "x86_64"]` → **3개 ABI 크로스컴파일 필요**

즉 **온디바이스 Rust는 "설정만 깔려 있고 한 번도 검증된 적 없는 경로"**다.
`native/`의 실체는 서버 바이너리(`main.rs` 98KB, axum)다.

| | Rust(flutter_rust_bridge) | Dart(`sqflite`) |
|---|---|---|
| R-tree 69만행 질의 성능 | 빠름 | **역시 빠름** (밀리초 이하, 병목 아님) |
| 신규 빌드 인프라 | **NDK 크로스컴파일 × 3 ABI, cargo-ndk, gradle 연동, CI, frb codegen** | 없음 |
| APK 증가 | ABI당 수 MB | ~0 |
| 서버 코드 재사용 | ⭕ `/poi/nearby` 질의 로직을 한 벌로 유지 가능 | ❌ Dart로 한 번 더 구현(로직 이중화) |
| 실패 시 리스크 | 네이티브 크래시(디버깅 난이도 높음) | 예외로 잡힘 |
| 첫 성과까지 | 김 | 짧음 |

**권고: 2단계로 나눈다.**

- **1단계 — Dart + `sqflite`.** 오프라인 데이터 파이프라인(다운로드·설치·버전관리·
  로컬 질의 전환)을 **새 툴체인 리스크 없이** 먼저 완성해 실제 효과를 측정한다.
  이 단계에서 이미 네트워크 의존은 사라진다.
- **2단계 — 측정 후 판단.** 1단계에서 POI 질의가 실제로 프레임을 먹는 게 **측정되면**
  그때 Rust로 내린다. 서버 질의 로직 공유가 목적이라면 그것만으로도 정당하다.

> **근거**: RECON §0의 결론과 같은 원칙이다 — *"P0~P2 완료 후 재측정하고 나서 판단.
> 지금 착수하면 실측 없는 최적화가 된다."* 이번 실주행 결함 중 언어·아키텍처가
> 원인인 건 하나도 없었다.
>
> **Rust가 진짜로 값어치 있는 지점은 따로 있다.** POI 조회(가벼움)가 아니라
> ① 온디바이스 라우팅/재탐색, ② fun-road 곡률 스코어링을 폰에서 돌리는 경우,
> ③ 추측항법(S7) 같은 연속 수치계산 — 이쪽은 계산량이 자릿수로 다르다.
> **오프라인 POI를 Rust 도입의 명분으로 삼기보다, 위 셋 중 하나를 할 때 함께
> 도입하는 편이 투자 대비가 맞다.**

### 5-4. 온디바이스 조회로 바뀌면 좋아지는 것

S2에서 만든 방어장치 상당수가 **불필요해진다** — 이것도 이득이다.
429 서킷브레이커, 지수 백오프, in-flight 취소, 실패 캐싱 방지, bbox 그리드 스냅…
전부 "네트워크가 있어서" 필요했던 것들이다. 로컬 질의는 15초 디바운스도 필요 없이
매 틱 조회해도 된다(오히려 POI 표시가 지금보다 부드러워진다).

---

## 6. ⚠️ 한계 — 이걸 해도 "완전 오프라인"은 아니다

정직하게 남긴다.

| 기능 | 오프라인 전환 후 |
|---|---|
| 지도 렌더링 | ⭕ 완전 오프라인 |
| POI 표시·주변 검색 | ⭕ 완전 오프라인 |
| **경로 탐색 / 재탐색** | ❌ **여전히 서버(Valhalla) 필요** |
| 주소·상호 검색 | ❌ 서버(`/geocode/search`) 필요 |
| 주유소 실시간 유가(오피넷) | ❌ 본질적으로 온라인 데이터 |

**신호 없는 산길에서 경로를 벗어나면 재탐색이 안 되는 건 그대로다.**
Organic Maps·OSMAnd가 오프라인 라우팅을 갖는 건 라우팅 엔진을 통째로 온디바이스에
넣었기 때문이고, 그건 Valhalla 온디바이스 포팅이라는 **훨씬 큰 별도 과제**다.

완화책(오프라인 전환과 함께 하면 좋은 것):
- 출발 전 경로를 폰에 저장해 두면 **주행 자체는** 신호 없이도 끝까지 안내 가능
- S7(터널 추측항법)이 단기 GPS 상실을 덮는다
- 재탐색 실패 시 "경로 이탈 — 신호 없음" 명시 안내 (지금은 조용히 실패)

---

## 7. 제안 순서 (마스터 승인 대기)

**지금 당장 착수는 권하지 않는다.** S3(라이프사이클/PIP 오진입 → 안내 중단)이
아직 출시 차단급으로 남아 있다. 오프라인은 출시 차단이 아니라 큰 기능 개선이다.

| 단계 | 내용 | 규모 | 선행 |
|---|---|---|---|
| **O1** | **스타일 에셋 로컬화**(글리프·스프라이트 동봉) | 작음 | 없음 — 지금 해도 무방, 단독으로도 요청 수가 준다 |
| **O2** | **타일 오프라인** — mbtiles 사이드로드 + 도 단위 선택 UI + WiFi 백그라운드 다운로드 + `setOfflineTileCountLimit` | 중간 | O1 |
| **O3** | **POI 오프라인** — `poi.db` 배포 + Dart/`sqflite` 로컬 질의 전환 + 버전 매니페스트 | 중간 | 없음(O2와 병렬 가능) |
| **O4** | 측정 → Rust 이관 여부 판단 | 판단 | O3 |
| **O5** | (별도 트랙) 오프라인 라우팅 = Valhalla 온디바이스 | 큼 | — |

**착수 시점 권고: S3 완료 후.** 그때 P1(주행 품질 S4~S8)과 저울질하면 된다.

## 8. 마스터 결정이 필요한 것

1. **착수 시점** — S3 뒤가 맞나, 아니면 오프라인을 더 앞당기나?
2. **POI 다운로드 범위 기본값** — §5-2의 a/b/c/d 중 어느 것?
   (내 권고: 주유소+편의점 기본 포함, 식당·카페는 선택)
3. **분할 단위** — 도(道) 단위로 확정? 타일과 POI를 같은 단위로 묶나?
4. **전국 통짜(536MB) 옵션을 줄 것인가** — 장거리 투어러에겐 오히려 이게 편할 수 있다
5. **Rust 이관** — §5-3의 2단계안 동의하시는지, 아니면 처음부터 Rust로 갈지
