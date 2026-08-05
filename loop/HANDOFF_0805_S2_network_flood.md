GOAL: POI 네트워크 요청 폭주(초당 ~10회, 69,875건 전부 429)를 구조적으로 차단한다 — 디바운스 실효화 + 429 서킷브레이커 + 실패 무캐싱 + bbox 그리드 스냅 + in-flight 취소.

# HANDOFF — S2 · 네트워크 폭주 차단

- 작성 2026-08-05 · 브랜치 `verify/ride-0711` · HEAD `0d8f45b`
- 대장: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S2
- 근거: [RECON_0805_testride0802_master_plan.md](RECON_0805_testride0802_master_plan.md) §3
- 선행 완료: S0(시작 위치), S1(백화·크래시 정지)

---

## 0. ⚠️ RECON에 없던 진짜 주범 — 디바운스가 "성공했을 때만" 커밋된다

RECON §3-1은 홈 화면 폭주를 `onCameraIdle`(디바운스 부재) 탓으로 봤다. **실측 결과 그건
주 원인이 아니다.** 홈 지도 카메라는 첫 fix에서만 움직이므로(`_moveCameraToFix`,
`isFirstFix`일 때만) 주행 중 `onCameraIdle`은 거의 발화하지 않는다.

**실제 메커니즘 — 두 화면에 동일한 패턴의 결함이 있다.**

`main_map_screen.dart:817` `_maybeFetchSearchPrefetch`:

```dart
if (!movedEnough && !staleEnough) return;      // ← 가드 판단
final myGen = ++_searchPrefetchGen;
final pois = await ...fetchPois(...);          // ← 여기서 수백 ms~30초
if (!mounted || myGen != _searchPrefetchGen) return;   // ← stale이면 여기서 탈출
_searchPrefetchPois = pois;
_searchPrefetchCenter = center;
_searchPrefetchAt = DateTime.now();            // ← 디바운스 상태가 여기서만 갱신
```

`navStateProvider` 리스너는 **1Hz**로 이 함수를 부른다(`:361`). 응답이 1초 안에 안
돌아오면:

| t | 동작 |
|---|---|
| 0s | `_searchPrefetchAt == null` → 통과, gen=1, 요청 발사 |
| 1s | `_searchPrefetchAt` **여전히 null** → 통과, gen=2, 요청 발사 |
| 1.x s | 1번 응답 도착 → `myGen(1) != gen(2)` → **early return, 타임스탬프 갱신 안 됨** |
| 2s | 또 통과 … (영구 반복) |

**→ 디바운스가 영원히 무장되지 않고 1Hz 요청이 무한히 나간다.** 429가 오면 응답이
더 빨라져 완화될 것 같지만, 새 세대가 계속 덮어써서 `_searchPrefetchAt` 갱신 조건
(`myGen == gen`)이 성립할 확률이 낮게 유지된다. 4시간 × 1Hz = 14,400건 — 로그의
`fetchPois 28,934`(전체 11세션)와 자릿수가 맞는다.

`nav_screen.dart:1384` `_maybeFetchAmbientPois`도 **완전히 같은 구조**다.
`_lastAmbientFetchAt`/`_lastAmbientFetchCenter`/`_lastAmbientFetchTypes`가 전부
`:1507-1509`, 즉 두 개의 `await`와 gen 체크(`:1483`) 뒤에서만 세팅된다. 이쪽도
`navStateProvider` 1Hz 리스너에서 호출된다(`:544`). → `fetchPoisInBounds 41,005`.

**따라서 S2의 1순위 수정은 "요청 시작 시점에 디바운스 상태를 커밋"이다.**
서킷브레이커·캐시 개선은 그 위에 얹는 2차 방어선이다.

> RECON §3-1이 인용한 `main_map_screen.dart:634`의 "onCameraIdle마다 무조건 재조회"
> 주석은 현재 `:742`에 있다. 이 경로도 디바운스가 없는 건 사실이니 같이 고치되,
> **폭주의 주범은 위 커밋 타이밍 결함이다.** 보고서에 이 정정을 반드시 남겨라.

---

## 1. 작업 범위 (파일별)

| 파일 | 작업 |
|---|---|
| `lib/services/poi_service.dart` | 예외 전달 · 429 서킷브레이커/백오프 · in-flight 취소 · bbox 그리드 스냅 헬퍼 · 타임아웃 30s→10s |
| `lib/features/map/presentation/main_map_screen.dart` | 디바운스 선커밋 + in-flight 가드(2곳) · 실패 무캐싱 · 스냅 bbox 적용 |
| `lib/features/navigation/presentation/nav_screen.dart` | 동일 + `sameTypes == false` 우회 차단 |
| `test/services/poi_service_test.dart` (기존) 또는 신규 | 서킷브레이커·스냅·예외 전달 단위 테스트 |

**손대지 말 것**: `native/`(Rust 서버), `docker/`, 다른 서비스(`gas_station_service`,
`routing_service`, `address_search_service`). S3(라이프사이클)·S5(정차 모드) 범위도 건드리지 마라.

---

## 2. 상세 지시

### 2-1. `PoiService` — 실패를 호출부에 전달 (예외 방식)

**이 리포에 이미 확립된 패턴을 그대로 따른다.** `address_search_service.dart:15`의
주석이 바로 이 결함을 지목하며 `AddressSearchException`으로 해결해 놨다:

> `PoiService.fetchPois`는 네트워크 실패와 "결과 0건"을 구분하지 못해(둘 다 빈 리스트
> 반환) 실기기 디버깅이 어려웠던 기지 결함(2026-07-13 확인)이 있다.

→ `PoiFetchException`을 신설하고 `fetchPois` / `fetchPoisInBounds`가
**비200 응답·네트워크 예외·서킷 오픈 시 던지도록** 바꾼다. 빈 리스트 반환은 이제
"진짜로 결과 0건"만 의미한다.

```dart
class PoiFetchException implements Exception {
  final int? statusCode;   // HTTP 상태코드 (네트워크 예외면 null)
  final bool circuitOpen;  // 서킷 차단으로 요청 자체를 안 보낸 경우
  final String message;
}
```

**모든 호출부를 빠짐없이 고쳐라** (`grep -rn "fetchPois" lib/`):

| 호출부 | 실패 시 처리 |
|---|---|
| `main_map_screen.dart:780` (ambient) | catch → **캐시에 넣지 않음**, `_ambientPois` 기존 값 유지(화면에서 POI가 사라지지 않게), 조용히 return |
| `main_map_screen.dart:827` (search prefetch) | catch → 기존 `_searchPrefetchPois` 유지, return |
| `main_map_screen.dart:3199` `_fetchAll` (검색 시트) | catch → `_loading = false` **반드시 해제**(안 하면 스피너 무한) + 기존 오류 표기 경로가 있으면 재사용 |
| `nav_screen.dart:1476` (ambient) | ambient와 동일 — 캐시 금지, 기존 POI 유지 |
| `poi_service.dart:294` `snapDestination` 내부 | 예외를 그대로 전파하되, 호출부가 이미 try/catch 하는지 확인하고 없으면 목적지 스냅 실패 = 팝업 경로로 흐르게 처리 |

### 2-2. 디바운스 선커밋 + in-flight 가드 (**최우선**)

두 화면 세 곳(`main_map._maybeFetchAmbientPois`, `main_map._maybeFetchSearchPrefetch`,
`nav._maybeFetchAmbientPois`) 전부:

1. 가드를 통과해 **요청을 시작하기로 결정한 그 자리에서** `lastAt`/`lastCenter`/
   `lastTypes`를 **즉시** 갱신한다 (await 이전).
2. `bool _xxxInFlight` 플래그를 두고, 진행 중이면 **즉시 return**한다.
   `try { ... } finally { _xxxInFlight = false; }`로 반드시 해제.
3. 응답 성공 후에는 결과만 반영한다(타임스탬프 재갱신 불필요/무해).

**정책 통일** (checklist "nav_screen과 동일 정책으로 통일"):

| 용도 | 최소 간격 | 최소 이동 | 근거 |
|---|---|---|---|
| ambient POI (홈·내비 공통) | 15초 | 200m | 현 nav_screen 값 유지 |
| search prefetch (홈) | 60초 | 500m | 현 값 유지 (반경 1500m라 완화 정당) |

- 홈 ambient는 지금 시간/거리 디바운스가 **아예 없다** → 위 15초/200m를 신설한다.
  `onCameraIdle`은 계속 트리거로 쓰되 이 가드를 통과해야 나간다. **단, 사용자가 직접
  줌/팬 해서 타입 집합이 바뀌거나 뷰포트가 크게 달라진 경우까지 15초 막으면 UX가
  나빠진다** — 아래 2-3의 예외 규칙을 따른다.
- 중복 로직 3벌을 만들지 말고 **작은 공용 정책 클래스**를 만들어 재사용해라
  (memory `feedback_prefer_simple_reuse`). 예: `poi_service.dart` 또는
  `lib/core/utils/`에 `PoiFetchThrottle { bool shouldFetch({center, types, now}); void markStarted(...); }`.
  `DateTime Function() now`를 주입 가능하게 해 **단위 테스트가 되게** 만들어라.

### 2-3. `sameTypes == false` 우회 차단 (`nav_screen.dart:1414`)

현재는 타입 집합이 달라지면 시간·거리 조건을 **통째로 건너뛴다**. 대신:

- 타입 집합 변화 시에도 **최소 간격(예: 3초) 하한**을 적용한다. 완전 무제한 금지.
- `_stickyEligibleTypes` 히스테리시스(`_resolveEligibleTypes:1343`, ±0.3)가 이미 있으니
  경계 떨림은 상당 부분 걸러진다 — 그 위에 하한만 얹으면 된다.
- 홈 화면 ambient에도 같은 규칙을 적용한다(줌 변경 시 3초 하한).

### 2-4. 429 서킷브레이커 + 지수 백오프 (`poi_service.dart`)

현재 코드베이스에 429 처리가 **한 줄도 없다.**

- 429 또는 5xx 수신 시 서킷을 연다. 백오프: **1s → 2s → 4s → 8s → 16s → 32s → 60s(상한)**.
  연속 실패마다 2배, 상한 60초.
- 응답에 `Retry-After` 헤더가 있으면 **그 값을 우선**한다(초 단위 정수만 지원, 상한 5분).
- 서킷이 열린 동안 `fetchPois*`는 **HTTP 요청을 만들지 않고** 즉시
  `PoiFetchException(circuitOpen: true)`를 던진다. ← 이게 폭주를 물리적으로 막는 마지막 벽.
- 200 성공 시 실패 카운터·서킷을 **즉시 리셋**한다.
- 서킷 상태는 `PoiService` 인스턴스 필드로 둔다(provider가 싱글톤이라 앱 전역 1개로 동작 —
  `map_providers.dart:389` 확인).
- 상태 전이 시에만 로그 1줄: `YNAV_POI circuit open backoff=Ns` / `YNAV_POI circuit closed`.
  **매 요청마다 로그 금지** — S1에서 로그 폭주가 발열·배터리 주범이었다.
- 타임아웃 `30s → 10s`로 단축. 주행 중 10초 지난 POI 응답은 이미 무가치하고,
  라디오 점유 시간을 그만큼 줄인다.

### 2-5. bbox 그리드 스냅 (캐시 적중률)

`PoiRegionCache.tryGet`(`poi_service.dart:433`)은 **저장 영역 ⊇ 요청 영역**일 때만
적중한다. 내비 자동추종 모드는 bbox가 `gps ± 0.02°`라 **1m만 움직여도 미스**다.

- `PoiService`에 정적 헬퍼를 추가: 요청 bbox를 **바깥쪽으로 스냅**
  (`south/west`는 `floor`, `north/east`는 `ceil`).
- 스텝은 **기존 `_snapCellSizeDeg`(1-2-5 nice 스텝, `:205`)를 재사용**해
  `step = _snapCellSizeDeg(span / 4)`로 잡는다. 같은 줌 레벨에서는 항상 같은 스텝이 나와
  스냅 격자가 안정적이다 — 이 클래스가 이미 같은 이유로 쓰고 있는 기법이다.
- **네트워크 요청과 캐시 put/get 모두 스냅된 bbox를 쓴다.**
- ⚠️ **표시 경로는 실제 뷰포트를 유지해야 한다.** 스냅 bbox는 더 넓으므로,
  `selectForAmbientDisplay`에는 **실제 뷰포트 bounds**를 넘기고 후보도 실제 뷰포트로
  먼저 필터링해라. 안 그러면 화면 밖 POI가 그려진다.
- ⚠️ **서버 cap 주의**: bbox가 커지면 응답이 `_serverCapHeuristic`(500) 이상이 되어
  `put()`이 캐싱을 건너뛸 수 있다(`:461`). 스텝을 span/4 기준으로 잡는 이유가 이것 —
  span 대비 과도하게 키우지 마라.

### 2-6. in-flight 요청 취소

`_ambientFetchGen`은 **응답만 버리고 HTTP는 안 끊는다.** 겹친 요청이 전부 타임아웃까지
살아 대역폭·라디오를 잡는다.

- `PoiService`에 태그별 `http.Client`를 두고(`Map<String, http.Client>`), 새 요청 시작 전에
  같은 태그의 이전 client를 `close()`해 강제 중단한다.
- 태그는 호출부가 넘긴다: `'ambient-home'`, `'ambient-nav'`, `'search-prefetch'`,
  `'search-sheet'`. **태그 없는 호출은 기존처럼 매번 새 client**(전역 취소 사고 방지).
- 취소로 인해 발생하는 예외는 `PoiFetchException`으로 감싸되, **로그를 남기지 마라**
  (정상 동작이다).
- 테스트를 위해 생성자에 `http.Client Function()? clientFactory`를 주입 가능하게 하고
  기본값은 `() => http.Client()`.

### 2-7. 타일 캐시 정책 — 조사만 (코드 변경 최소)

`lib/services/map_cache_provider.dart`는 `flutter_map`의 `NetworkTileProvider`를 만드는데,
**참조가 `main_map_screen.dart:30`의 `// ignore: unused_import` 하나뿐인 죽은 코드**다.
지도는 이미 `maplibre_gl`(자체 네이티브 타일 캐시)로 넘어갔다.

- **판단 후 보고**: 이 파일과 unused import를 삭제할지 여부. 삭제가 맞다고 판단되면
  삭제하고, 애매하면 **건드리지 말고 보고서에만 적어라.**
- 1.65GB 실측 배분은 실기기 계측 항목이라 이 세션 범위 밖 — 보고서에 그렇게 명시.

---

## 3. 검증 (이 세션에서 반드시 통과시킬 것)

`flutter analyze` 이슈 0 · `flutter test` 전건 통과(현재 359건 기준, 회귀 금지).

**신규 단위 테스트** (`package:http/testing.dart`의 `MockClient` 사용 — `http` 패키지에 동봉):

1. 200 정상 → POI 파싱, 서킷 닫힘 유지
2. 429 → `PoiFetchException(statusCode: 429)` **던짐** (빈 리스트 아님)
3. 429 직후 재호출 → **MockClient가 호출되지 않음**(요청 카운터 0 증가) +
   `circuitOpen: true`로 던짐
4. 백오프 경과 후 재호출 → 요청 나감. 실패 반복 시 대기시간 1→2→4…60 상한
5. 성공 시 서킷·카운터 리셋
6. `Retry-After: 30` 존중
7. bbox 스냅: 인접한 두 중심점이 **동일한 스냅 bbox**를 만든다 / 스냅 결과가 항상
   원본을 **포함**한다
8. `PoiFetchThrottle`: 주입된 `now`로 15초/200m 경계 양옆 검증, `markStarted` 이후
   즉시 재호출은 차단됨
9. 실패 시 `PoiRegionCache.put`이 호출되지 않음 (throttle/캐시 레벨에서 검증 가능한
   형태로 — 화면 위젯 테스트가 과하면 서비스 레벨로 낮춰도 됨)

**측정 검증(가상GPS 1시간, POI 요청 < 60건 · 429 = 0)은 마스터 실기기 몫**이다.
이 세션에서는 하지 말고 보고서에 "마스터 대기"로 남겨라.

---

## 4. 절차 (CLAUDE.md 워크루프 준수)

1. 작은 단계로 쪼개고 단계마다 체크포인트 커밋. `git add <파일명>` — **`git add -A` 절대 금지**
   (동시 세션이 같은 브랜치를 쓴다).
2. 구현은 flutter-coder에 위임 → 끝나면 code-auditor. FAIL이면 수정 후 재감사(최대 3회).
3. PASS 후 커밋. 커밋 메시지: `fix(network): S2 — POI 요청 폭주 차단`.
4. 완료 후 `loop/CHECKLIST_0805_testride0802.md` §S2 체크박스 갱신 +
   `loop/MORNING_REPORT_0805_S2_network_flood.md` 작성
   (마지막 줄에 `Goal: X / Met: yes·partial·no — 이유`).
5. 확신이 안 서면 **추측하지 말고 보고서에 적어라.**

## 5. 주의

- **S11(고급휘발유 미표시)이 이 작업에 물려 있다.** 429 폭주 + 실패 `[]` 캐싱이 원인이면
  S2로 이미 해결된다 — 2-1의 "실패는 캐시 금지"를 특히 정확히 구현해라.
- 실패 시 **화면의 기존 POI를 지우지 마라.** 지우면 마스터에게는 "POI가 깜빡이며 사라짐"
  이라는 새 증상으로 보인다.
- S3(PIP/라이프사이클), S5(정차 모드)와 범위가 겹쳐 보여도 **넘어가지 마라.** 한 세션 한 모듈.
