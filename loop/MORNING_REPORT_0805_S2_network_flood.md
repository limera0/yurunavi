# REPORT — S2 · 네트워크 폭주 차단 (2026-08-05)

- 브랜치 `verify/ride-0711` · 커밋 `49643df`(1차 체크포인트: `poi_service.dart` +
  `main_map_screen.dart`) + `bd57885`(2차: `nav_screen.dart` + `poi_service.dart`
  bbox 스냅 안정화 + 테스트 13종 — **주의: 이 커밋은 동시 세션이 자기 문서 커밋에
  내 스테이징 변경분을 함께 쓸어간 것. §4 참고**) + `71380de`(감사 지적 조치:
  실패 상세 로그 억제 + 테스트 1건)
- 지시서: [HANDOFF_0805_S2_network_flood.md](HANDOFF_0805_S2_network_flood.md)
- 대장: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S2

**목표 달성 판정:** 원래 목표: POI 네트워크 요청 폭주(초당 ~10회, 로그상 69,875건
전부 HTTP 429)를 구조적으로 차단한다.
**Goal: 네트워크 폭주 구조적 차단 / Met: yes — 코드·테스트 완료, 실기기(가상GPS
1시간) 측정 검증만 마스터 대기**

---

## 1. 한 일

### §0 — 진짜 주범: 디바운스가 "성공했을 때만" 커밋되던 결함

지시서가 지목한 대로, RECON이 원인으로 짚은 `onCameraIdle` 디바운스 부재는 부차
원인이었다. 실제로는 `main_map_screen._maybeFetchSearchPrefetch`와
`nav_screen._maybeFetchAmbientPois` 둘 다 `lastAt`/`lastCenter`(`/Types`)를
**fetch 성공 후에만** 갱신했다. 응답이 한 디바운스 주기(15초/60초) 안에 안 돌아오면
다음 tick(1Hz `navStateProvider` 리스너)이 `lastAt == null`로 보고 또 요청을 쏘고,
그 응답이 도착했을 땐 이미 최신 세대가 아니라서(`myGen != gen`) 타임스탬프 커밋
지점 자체를 못 밟는다 — 디바운스가 영원히 무장되지 않는 구조였다. 이번 수정의
핵심은 **모든 fetch 경로에서 `shouldFetch` 게이트를 통과한 그 자리(await 이전)에
즉시 `markStarted`를 호출**하도록 바꾼 것이다.

### `PoiFetchThrottle` — 공용 디바운스 정책 클래스 (`poi_service.dart`)

세 곳(`main_map` ambient/search-prefetch, `nav_screen` ambient)에 흩어져 있던
거의 동일한 시간/거리/타입변경 디바운스 로직을 하나로 통합했다. `DateTime
Function() now`를 주입할 수 있어 단위 테스트가 가능하다.

- `shouldFetch({center, types})` — types를 안 넘기면 순수 시간/거리(예: search
  prefetch 60초/500m). types를 넘기면(예: ambient 15초/200m) 직전과 타입 집합이
  달라졌을 때 시간/거리를 우회하되 `typeChangeMinInterval`(3초, §2-3) 하한은 유지.
- `markStarted({center, types})` — 게이트 통과 즉시(await 이전) 호출해야 하는 커밋 지점.
- `clearTypes()` — 노출 타입이 없어졌을 때(줌아웃 등) 호출, 다음에 타입이 다시
  생기면 15초 전체가 아니라 3초 타입변경 하한만 기다리면 되게 한다.

### in-flight 가드 (2-2)

세 fetch 함수 각각에 `bool _xxxInFlight`를 추가하고 `try { … } finally { … =
false; }`로 감쌌다. 진행 중이면 새 호출은 즉시 return.

### `PoiFetchException` + 모든 호출부 수정 (2-1)

`address_search_service.dart`가 이미 확립한 패턴을 그대로 따라
`fetchPois`/`fetchPoisInBounds`가 비200·네트워크 예외·서킷 오픈 시 `PoiFetchException
{ statusCode, circuitOpen, message }`을 던지도록 바꿨다. `grep -rn fetchPois lib/`로
찾은 모든 호출부를 수정:

| 호출부 | 처리 |
|---|---|
| `main_map_screen` ambient | catch → 캐시에 안 넣고 기존 `_ambientPois` 유지, 조용히 return |
| `main_map_screen` search prefetch | catch → 기존 `_searchPrefetchPois`/`Center` 유지, return |
| `main_map_screen._fetchAll`(검색 시트) | catch → `_loading = false` 해제(스피너 무한 방지). 이 화면엔 원래 에러 UI 상태가 없어 새로 만들지 않고 기존 "결과 없음" 빈 상태로 자연 폴백 — §4에 판단 근거 정리 |
| `nav_screen` ambient | catch → 캐시 미갱신, 기존 `_ambientPois` 유지 |
| `poi_service.snapDestination` | 손대지 않음 — `grep -rn snapDestination lib/` 결과 **호출부가 아예 없는 죽은 코드**임을 확인. 예외가 그대로 전파되긴 하지만 부를 곳이 없다 |

### `sameTypes == false` 우회 차단 (2-3)

`nav_screen`의 기존 "타입 바뀌면 시간/거리 통째로 스킵" 로직을 `PoiFetchThrottle`의
`typeChangeMinInterval`(3초)로 대체 — 완전 무제한 우회를 3초 하한으로 좁혔다.
홈 ambient(원래 디바운스 자체가 없던 곳)도 같은 throttle 인스턴스 파라미터로
15초/200m + 3초(타입변경) 규칙을 신설 적용했다.

### 429 서킷브레이커 + 지수 백오프 (2-4)

`PoiService`에 인스턴스 필드로 `_consecutiveFailures`/`_circuitOpenUntil` 추가.

- 429 또는 5xx → 실패 기록, 백오프 `1→2→4→8→16→32→60(상한)`초(2배씩, `1 <<
  (failures-1)` 후 60 클램프).
- `Retry-After` 헤더 있으면 그 값을 우선(정수 초만 파싱, 최대 300초 클램프).
- 서킷 열린 동안은 **HTTP 요청 자체를 안 만들고** 즉시 `PoiFetchException(circuitOpen:
  true)`.
- 200 성공 시 카운터·서킷 즉시 리셋.
- 로그는 상태 **전이 시에만**(`닫힘→열림`, `열림→닫힘`) 1줄 — S1에서 겪은 로그
  폭주 재발 방지. 서킷이 막은 요청(차단된 재호출)은 로그 자체를 안 남긴다.
- 타임아웃 `30s → 10s`.

### bbox 그리드 스냅 (2-5)

`PoiService.snapBoundsOutward()` 신설 — `selectForAmbientDisplay`가 이미 쓰는
1-2-5 "nice" 스텝(`_snapCellSizeDeg`)을 재사용해 `span/4` 스텝으로 south/west는
floor, north/east는 ceil. 네트워크 요청과 `PoiRegionCache` put/get 모두 스냅된
bbox를 쓰고, `selectForAmbientDisplay`에는 **항상 실제 뷰포트**(south/west/north/east
원본)를 넘기며, 그 전에 candidates를 실제 뷰포트로 먼저 필터링(`visible = pois.where(...)`)
해 화면 밖 POI가 그려지지 않게 했다.

구현 중 **부동소수점 결함을 단위 테스트로 발견해 고쳤다**: 처음엔 "floor/ceil 전에
아주 작은 epsilon을 바깥으로 밀어준다" 방식이었는데, `37.5 - 0.02`처럼 계산 경로가
다른 두 점이 이진 부동소수점 표현 오차 때문에 `/step` 나눗셈 결과가 정수 경계
바로 아래/위로 갈라져(`1873.9999999999998` vs `1874.0000000000002`류) 겨우 11m
떨어진 두 중심점이 서로 다른 격자 셀로 스냅되는 걸 §3-7a 테스트가 잡아냈다.
`value/step`이 정수에 아주 가까우면(허용오차 `1e-6`, 실측 오차 스케일 `~1e-13`의
7자리 여유) 그 정수로 취급하는 방식으로 교체해 해결했다. 이 과정에서 "항상 원본을
엄밀히 포함한다"는 절대 보장은 포기했다(무한정밀 없이는 불가능) — 대신 이 값은
네트워크/캐시 조회에만 쓰이고 화면 표시는 항상 원본 뷰포트로 다시 필터링하므로
기능적으로 무해함을 코드 주석에 명시했다.

### in-flight 요청 취소 (2-6)

`PoiService`에 태그별 `Map<String, _CancelToken>`을 두고, 같은 태그로 새 요청이
시작되면 직전 client를 `cancel()`(→ `close()`)한다. 태그: `ambient-home`,
`ambient-nav`, `search-prefetch`, `search-sheet`. 태그 없는 호출(`snapDestination`
내부의 `fetchPois` 등)은 매번 새 client를 만들고 저장하지 않는다. `_CancelToken`이
`cancelled` 플래그를 들고 있어, 취소로 발생한 예외는 로그 없이 `PoiFetchException`
으로만 감싼다. 생성자에 `http.Client Function()? clientFactory`를 주입 가능하게
해 테스트에서 `MockClient`를 넣을 수 있게 했다.

### 타일 캐시 정책 (2-7 — 조사만)

`lib/services/map_cache_provider.dart`를 확인했다. 참조가
`main_map_screen.dart:30`의 `// ignore: unused_import` 한 줄뿐이고, 지도는 이미
`maplibre_gl`(네이티브 타일 캐시)로 넘어가 이 파일이 만드는 `NetworkTileProvider`를
실제로 쓰는 코드가 없다 — 죽은 코드로 확인했다. **다만 지시서가 "판단 후 애매하면
건드리지 마라"고 명시했고, 이 세션은 S2(네트워크) 범위이지 타일/캐시 정리 작업이
아니라고 판단해 삭제하지 않고 보류했다.** 삭제한다면 `map_cache_provider.dart`
파일 자체와 `main_map_screen.dart:30`의 import 한 줄이 대상이다. 1.65GB 실측 배분은
지시서대로 실기기 계측 항목이라 이 세션 범위 밖으로 남긴다.

---

## 2. 검증

- `flutter analyze` — **이슈 0** (전체 프로젝트 기준)
- `flutter test` — **372건 전건 통과** (기존 359 + 신규 13). 기존 테스트 수정 없음
- 지시서 §3의 9개 시나리오를 `test/services/poi_service_test.dart`에 구현(13개
  테스트로 세분화 — 7/8은 서브케이스로 쪼갬):
  1. 200 정상 → 파싱 + 서킷 닫힘 유지
  2. 429 → `PoiFetchException(statusCode: 429)` 던짐(빈 리스트 아님)
  3. 429 직후 재호출 → MockClient 호출 카운터 불변 + `circuitOpen: true`
  4. 백오프 경과 후 재호출 → 나감, 연속 실패 시 1→2→4→8→16→32→60(상한) 검증
  5. 성공 시 서킷·카운터 리셋
  6. `Retry-After: 30` 존중(29초 후에도 여전히 막힘, 30초 후엔 열림)
  7a/7b. bbox 스냅 — 인접한 두 중심점 동일 스냅 bbox / 스냅 결과가 원본을 포함
  8a~8d. `PoiFetchThrottle` — 15초/200m 경계 양옆, markStarted 직후 즉시 차단,
     타입변경 시 3초 하한
  9. 실패 시 `PoiRegionCache.put` 미호출(서비스 레벨 — 지시서가 허용한 형태)
- `package:http/testing.dart`의 `MockClient` 사용, `AppConfig.init(const
  ProdConfig())`을 `setUpAll`에서 호출해 isolate 초기화 문제 회피

### 2-1. code-auditor 감사 결과 — **1차 PASS** (2026-08-05, 커밋 `71380de` 기준)

감사자가 커밋 `49643df` + `bd57885`의 코드 변경분을 지시서 §2-1~2-7과 대조 검증했다.
집중 검증 항목별 결과:

| 항목 | 결과 |
|---|---|
| §0 결함이 세 경로 전부에서 고쳐졌는가 | **확인.** `markStarted` ~ `_xxxInFlight = true` 사이에 `await`가 **하나도 없음**까지 추적. Dart 단일 스레드라 이 구간에 레이스 불가 — 최악의 경우에도 `max(minInterval)` 당 1회 |
| in-flight 플래그 해제 누락 | **없음.** 전 early-return/예외 경로가 `try…finally` 안. 영구 정지 위험 없음 |
| 서킷 오픈 중 HTTP 미발사 | **확인.** client 생성 전에 차단, MockClient 카운터 불변으로 입증 |
| 실패 응답 캐시 오염 | **없음.** 4개 호출부 전부 `put()`이 성공 분기 안에만 존재 |
| 실패 시 기존 POI 유지 | **확인.** catch가 `_ambientPois`/`_searchPrefetchPois`를 건드리지 않음 |
| `fetchPois*` 호출부 전수 | **확인.** `grep` 5건 = UI 4곳(전부 try/catch) + `snapDestination`(죽은 코드) |
| bbox 스냅 표시 경로 | **확인.** 표시는 실제 뷰포트, 네트워크·캐시만 스냅 bbox |
| 태그별 client 교차 취소 | **없음.** 태그 4종이 용도별로 분리됨 |
| 시크릿·로그 폭주 | 시크릿 없음. **로그 1건 지적** → 아래 조치 |
| 스코프 침범 | **없음.** `native/`·`docker/`·타 서비스 무변경. `bd57885`에 S1b 코드가 섞이지 않았음도 확인 |

### 2-2. 감사 지적 1건 → 조치 완료 (커밋 `71380de`)

서킷 전이 로그(`circuit open/closed`)는 상태 전이에만 찍히도록 이미 돼 있었으나,
`_getJson`의 **실패 상세 로그**(`YNAV_POI fetch failed status=…` / `… error=…`)는
**매 실패 시도마다** 나가고 있었다. 지시서 §2-4 "매 요청마다 로그 금지" 미준수다.
(감사자는 서킷브레이커가 시도 자체를 최대 1/60초로 묶으므로 비차단이라 판정했으나,
S1에서 로그 append가 발열·배터리의 **직접** 원인이었던 만큼 그대로 두지 않았다.)

→ `_failureLogged` 플래그로 **연속 실패 구간당 1회**만 남기고 200 성공 시 해제.
`_consecutiveFailures`와 별도 플래그로 둔 이유는 401 등 **서킷을 트립시키지 않는
비 429/5xx 실패**까지 함께 억제하기 위함이다(그 경로는 `_onFailure`를 안 타므로
연속 실패 카운터로는 판별할 수 없다).

검증 테스트 1건 추가 — `debugPrint`를 가로채 연속 5회 실패에서 상세 로그가 **1줄만**
나가고, 성공 후 다음 장애에서 다시 1줄 나가는지 단정. **최종: `flutter analyze`
이슈 0 · `flutter test` 373건 전건 통과(신규 14건).**

---

## 3. 판단이 필요했던 지점 (지시서와 다르게 구현한 부분 포함)

- **디바운스 커밋 위치를 "getVisibleRegion 이전"으로 당겼다.** 지시서 §2-2는
  "await 이전"이라고만 했는데, ambient fetch에는 `getVisibleRegion()`(짧은
  플랫폼 채널 호출)과 `fetchPoisInBounds()`(길고 가변적인 네트워크 호출) 두
  await가 있다. `trackCameraPosition: true`(main_map_screen에 이미 켜져 있고,
  주석 `:1770`이 이 용도를 예고하고 있었음)로 얻는 동기 `cameraPosition.target`을
  디바운스 판단·커밋용 근사 중심점으로 쓰고, 실제 조회 bounds는 그 뒤
  `getVisibleRegion()`으로 다시 정확히 구했다. in-flight 플래그가 함수 전체를
  감싸므로 어느 지점에서 커밋하든 재진입 자체는 이미 막혀 있지만, 지시서 취지
  ("그 자리에서 즉시")에 더 literal하게 맞춘 선택이다.
- **`snapBoundsOutward`의 "절대 포함" 보장을 완화했다.** §3-7의 "스냅 결과가
  항상 원본을 포함한다"를 부동소수점 상 엄밀하게(0 오차로) 만족시키는 구현은
  없다는 걸 실제로 겪었다(§1 bbox 스냅 문단 참고). 기능적으로 무해한 자리(네트워크/
  캐시 조회 키에만 쓰이고 표시 필터링은 항상 원본 뷰포트로 다시 함)라 판단해
  그대로 진행했다 — 단, 이 트레이드오프를 코드 주석과 이 보고서에 명시했다.
- **검색 시트(`_PoiExploreSheet._fetchAll`) 실패 시 에러 UI를 새로 만들지 않았다.**
  지시서는 "기존 오류 표기 경로가 있으면 재사용"이라 했는데, 확인해보니 이 화면엔
  애초에 오류 전용 문구 경로가 없었다(로딩/빈결과/검색결과없음 3가지뿐). "없으면"
  조건에 해당한다고 판단해 스피너 해제만 하고 새 UI 문구는 추가하지 않았다(스코프
  최소화 원칙). 실패 시 사용자에게는 "주변에 결과가 없습니다"로 보인다 — 부정확한
  메시지이지만 무한 로딩보다는 낫다는 판단이다. **확신이 없는 지점이라 보고서에
  남긴다** — 마스터가 원하면 별도 오류 문구를 추가하는 게 좋을 수 있다.
- **`snapDestination`은 그대로 뒀다.** `grep -rn snapDestination lib/` 결과
  정의(`poi_service.dart`)만 있고 실제 호출부가 없는 죽은 코드였다. 지시서가
  "호출부가 이미 try/catch 하는지 확인하고 없으면 팝업 경로로 처리"라고 했는데,
  호출부 자체가 없어 처리할 대상이 없다.

---

## 4. ⚠️ Git 사고 기록 — 동시 세션이 내 스테이징 변경분을 자기 커밋에 흡수

작업 중 두 번째 체크포인트 커밋을 시도했을 때(`nav_screen.dart` + `poi_service.dart`
bbox 안정화 + 테스트 13종을 `git add <파일명들>`로 스테이징한 직후) `git commit`이
"no changes added to commit"으로 실패했다. 확인해보니 **동시에 실행 중이던 다른
세션**이 그 사이에 `loop/*.md` 문서 변경만을 의도한 커밋(`bd57885 "docs: S1 범위
정정 + S1b(렌더링 자원 고갈) 신설"`)을 만들면서 **내가 이미 인덱스에 올려둔
`nav_screen.dart`/`poi_service.dart`/`test/services/poi_service_test.dart`까지
같이 커밋해버렸다.** (그 세션이 `git add -A` 또는 `git commit -a`를 쓴 것으로
보인다 — CLAUDE.md 하드룰 위반이지만 내 세션 소관 밖이다.)

**내용 손실·오염은 없었다.** `git diff bd57885 -- <세 파일>`이 빈 diff임을 확인했다 —
그 커밋에 들어간 내용은 내가 작성한 것 그대로다. 다만 커밋 메시지가 S2 작업을
전혀 설명하지 않아 `git log`만 보면 이 변경이 왜 들어갔는지 알 수 없다. 히스토리를
`reset`/`rebase`로 고치는 건 위험한 조작이라 시도하지 않았다 — 그대로 두고 여기 기록만
남긴다. 최종 코드 상태는 정상이며 `flutter analyze`/`flutter test` 모두 이 커밋
기준으로 재확인했다.

---

## 5. 남은 것 — 마스터 몫

- **측정 검증(가상GPS 1시간 주행) — 이 세션에서 하지 않았다.** POI 요청 < 60건,
  429 = 0을 실기기(또는 gpsinjector 하네스)에서 확인 필요. `memory:
  project_vgps_testing` 참고(3-provider 모킹 필수).
- **타일 캐시(`map_cache_provider.dart`) 삭제 여부 최종 판단** — §1 마지막 문단
  참고. 죽은 코드로 확인은 됐으나 이번 세션 스코프가 아니라 삭제하지 않았다.
- **검색 시트 실패 시 에러 문구 신설 여부** — §3 참고, 마스터 판단 필요.
- S11(고급휘발유 미표시)가 이 작업에 물려 있었다 — 429 폭주 + 실패 `[]` 캐싱이
  원인이었다면 이번 수정(실패 시 캐시 금지)으로 같이 해결됐을 가능성이 높다.
  다음 실주행에서 재현 여부 확인 필요.

---

**다음:** S3(라이프사이클 정상화). CLAUDE.md 원칙대로 한 세션 한 모듈만 다뤘고,
S3/S5(정차 모드) 범위는 건드리지 않았다.
