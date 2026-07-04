# RECON — 회전교차로 CW 표시 (방향 왜곡) 원인 조사

RECON ONLY. 편집 없음.

## 대상 로터리

Nominatim 지오코딩(신장동/신장로 → 평택시 신장동, lat 37.079–37.090, lon 127.049–127.053) 후,
`start=(37.0750,127.0500)` (SW, 남쪽) → `dest=(37.0950,127.0520)` (N, 북쪽) 경로를 로컬 prod Valhalla
(`localhost:8002`, 컨테이너 `yurunavi-valhalla`)에 `/route`로 질의. 자연스럽게(좌표 검색 없이) 신장로 상의
로터리를 통과하는 경로가 나옴 — 스크린샷 지명과 일치할 개연성 높음.

```
curl -s http://localhost:8002/route -d '{
  "locations":[{"lat":37.0750,"lon":127.0500},{"lat":37.0950,"lon":127.0520}],
  "costing":"auto","units":"kilometers"}'
```

## 1. Valhalla maneuver 목록 (실측)

```
0 type=3  len=51m   Drive west on 송월로16번길
1 type=10 len=428m  Turn right onto 송월로
2 type=26 len=37m   Enter the roundabout and take the 2nd exit onto 신장로   roundabout_exit_count=2
3 type=27 len=114m  Exit the roundabout onto 신장로
```
type26 maneuver: `begin_shape_index=10, end_shape_index=21` — 로터리 원환 구간은 전역 shape 인덱스 10–21.

## 2. Shape polyline 디코드 → CW/CCW 판정 (결정적 테스트)

`leg.shape`를 Valhalla 표준 encoded-polyline(precision=6, lat 우선)으로 디코드해 인덱스 10–21 구간(로터리 원환) 12점 추출.
Local ENU 변환(lon→x=east, lat→y=north, centroid 기준) 후 shoelace 공식 + 각도(atan2) 추적:

```
idx  x(m)   y(m)   angle(deg)
10  -7.20 -11.41   -122.2
11  -3.92 -10.97   -109.6
12  -0.98  -9.76    -95.8
...
16   4.88   1.19     13.7
...
21  -6.31  12.35    117.1
```
각도가 -122°→117°까지 **단조 증가**(모든 delta 양수, 합계 +239.3°), shoelace signed-area(×2) = **+263.9 (양수)**.
x=east, y=north 평면에서 각도 증가 = **반시계(CCW)**.

**→ Valhalla가 반환하는 로터리 원환 geometry 자체는 CCW. 한국 교통 규칙(우측통행, 로터리 반시계 순환)과 일치, 기하학적으로 정상.**

## 3. 클라이언트 디코드 — `lib/services/routing_service.dart:461-490` (`_decodePolyline6`)

Valhalla와 동일한 precision-6 알고리즘, **lat 델타 먼저 → lng 델타**, `LatLng(lat/1e6, lng/1e6)`로 축 순서까지 정확히 일치(스왑 없음). Python 검증 재현 결과와 좌표 동일.

- `_extractPoints` (`routing_service.dart:443-455`): leg 순서대로 `decoded`를 그대로 `addAll` (2번째 leg부터는 `.skip(1)`로 중복 접합점만 제거). **reverse/sort 없음.**
- `_collectManeuvers` (`:421-441`)의 `beginShapeIdx`/`endShapeIdx`도 leg 오프셋만 누적, 원본 순서 보존.
- 저장: `RouteResult(points: pts, ...)` (`:341`, `:395`) — 가공 없이 그대로 저장.

## 4. 렌더링 경로 — 순서 보존 확인

- **지도 화면** `lib/features/map/presentation/main_map_screen.dart`: `routes[selIdx].points` → `setRoutePolyline` → `mapInteractionProvider`(`map_providers.dart:102-197`, 단순 필드 복사) → `_buildRouteGeoJson`/`_buildBgGeoJson`(`:250-263`) → `pts.map((p) => [p.longitude, p.latitude])` — **GeoJSON 표준 [lon, lat] 순서 정확**, reorder 없음 → MapLibre `addLineLayer`.
- **내비 화면** `lib/features/navigation/presentation/nav_screen.dart:506-517` (`_buildRouteGeoJson`) — 동일 패턴 `points.map((p) => [p.longitude, p.latitude])`, `:527-531`에서 `addGeoJsonSource`+`addLineLayer`로 등록. 재탐색 시(`:307-320`) `newPoints = routes[selIdx].points`를 통째로 교체(병합/재정렬 아님).
- `.reversed`/`.reverse()`/`sort(` 전수 grep: 지도·내비 관련 파일 내 유일한 히트는 `main_map_screen.dart:747`의 `_sheetCtrl.reverse()`(바텀시트 애니메이션 컨트롤러) — 경로 포인트와 무관.

**→ 디코드부터 GeoJSON 좌표 배열, MapLibre LineLayer까지 point order·axis 모두 원본(Valhalla CCW) 그대로 보존됨. 코드 경로상 반전/왜곡 지점 없음.**

## 5. roundabout_exit_count 등 방향 관련 필드

`/route` JSON의 type26 maneuver에 `"roundabout_exit_count": 2` 존재 확인(§1 raw dump). `direction`/`turn_degree` 필드는 없음 — Valhalla는 방향 정보를 exit_count와 shape geometry로만 암묵 제공, 명시적 CW/CCW 필드는 없음. (기존 `loop/RECON_roundabout.md`에서도 동일 필드 확인된 바 있음 — 별개 위치.)

## 6. 부수 관찰 (앵커 밖, 미확정)

`nav_screen.dart:206` `_mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(next.headingDeg!))` — 주행 중(`speedKmh>2`) 카메라를 heading-up으로 회전시킴. `:625` 주석은 `rotateGesturesEnabled: false, // North-up 고정`이라 되어 있으나 실제로는 사용자 제스처 회전만 막을 뿐 프로그램적 heading-up 회전은 활성 — 주석이 오도적. 다만 카메라 **회전(rotation)은 도형의 카이랄성(CW/CCW)을 바꾸지 않음**(반전/미러링이 아니므로) — 따라서 이것만으로는 CCW→CW 반전을 설명할 수 없음. `headingDeg` 부호 규약이 잘못되면 화면이 엉뚱한 방향으로 돌아 사용자가 진행 방향을 혼동할 순 있으나, 로터리 라인 자체의 회전 방향 왜곡 원인은 아님. 확정하려면 실기기 캡처 필요.

## ROOT CAUSE 판정 (1줄, §1-6 한정 — §7에서 갱신됨)

**Valhalla 로터리 geometry는 CCW(정상)이고, 클라이언트 디코드→GeoJSON→LineLayer 파이프라인 전 구간에서 순서·축 반전 없이 그대로 보존됨 — 코드상 CW로 뒤집히는 지점을 찾지 못함; 스크린샷이 이 교차로와 정확히 동일한 지점/경로인지, 혹은 heading-up 카메라 회전(§6, 미확정) 중 촬영된 것인지 재확인 필요.**

---

## 7. 고덕좌교로 CW 재현

### 대상 교차로 & 좌표

고덕좌교로 회전교차로, 4방향 진출입점(각 연결부 좌표, 사용자 제공):
N(37.02852,127.02945) / W(37.02839,127.02929) / S(37.02824,127.02941) / E(37.02839,127.02965).

각 진입 방향을 강제하기 위해 각 exit 지점에서 나침반 방향으로 정확히 200m 떨어진 지점을 계산(위도 111,320m/deg, 경도 111,320×cos(37.028°)≈88,835m/deg 사용):

```
N_pt = (37.030317, 127.029450)   # N-exit 200m 북쪽
W_pt = (37.028390, 127.027040)   # W-exit 200m 서쪽
S_pt = (37.026443, 127.029410)   # S-exit 200m 남쪽
E_pt = (37.028390, 127.031900)   # E-exit 200m 동쪽
```

로컬 prod Valhalla(`localhost:8002`, 컨테이너 `yurunavi-valhalla`, up 4일)에 4개 조합으로 `/route` 질의 (모두 `costing=auto`):

| Test | 강제 진입 | start | dest | 실제 관측된 경로 |
|---|---|---|---|---|
| A | N-entry | N_pt | E_pt | N→E 만 통과(로터리 1/4 아크) |
| B | W-entry | W_pt | S_pt | W→N→E 통과 후 **로터리 이탈, 고속도로로 크게 우회**해 S_pt 도달 (로터리로 직접 S 진출 안 됨) |
| C | S-entry(control) | S_pt | N_pt | S→W→N 통과(3/4 아크) |
| D | E-entry(control) | E_pt | W_pt | E→S→W 통과(3/4 아크) |

### 결정적 확인: type26/27 maneuver 자체가 없음

4개 테스트 전부 maneuver type이 1/10/15(직진/우회전/좌회전)뿐 — **로터리 전용 maneuver(type 26/27, roundabout_exit_count)가 단 한 건도 나오지 않음.** (신장동 케이스는 §1에서 type26/27 확인됨 — 대조.)

`/locate`로 원환 3개 지점(37.02839,127.029445 / 37.0285,127.029388 / 37.02842,127.0296)을 질의한 결과, 원환을 구성하는 모든 edge가 **동일 `way_id=1304219907`, `round_about: false`**. 즉 Valhalla 그래프상 이 원은 로터리(oneway 순환)로 태깅되어 있지 않고, **평범한 tertiary 양방향 도로 루프**로 취급됨.

### CW/CCW 판정 (§2와 동일한 shoelace + 각도누적 방법)

각 테스트의 shape에서 원환 구간만 추출(로컬 ENU, x=east/y=north, centroid 기준)해 판정:

| 진입방향 | 실제 경유 아크 | 아크점수 | signed-area(×2) | angle Δ합(°) | 판정 |
|---|---|---|---|---|---|
| **N** (Test A) | N→E | 6 | −94.39 | −206.0 | **CW** |
| **W** (Test B) | W→N→E | 10 | −431.35 | −235.1 | **CW** |
| **S** (Test C, control) | S→W→N | 9 | −325.50 | −227.5 | **CW** |
| **E** (Test D, control) | E→S→W | 11 | −551.38 | −243.8 | **CW** |

signed-area 전부 음수, 각도 델타 전부 음수 누적 → **4방향 전부 예외 없이 CW.**

### 마스터 가설 기각

"N/W 진입만 CW, S/E 진입(control)은 CCW"라는 가설은 **기각**. S-entry, E-entry control도 동일하게 CW로 나옴 — 진입 방위(entry bearing)는 CW/CCW와 상관관계 없음. 이 로터리는 **진입 방향에 무관하게 Valhalla 자체 geometry가 항상 CW**.

### ROOT CAUSE 판정 (§7, 고덕좌교로 한정)

**신장동(§1-6)과 근본적으로 다른 케이스.** 신장동은 Valhalla 그래프에 `junction=roundabout`(round_about 플래그·type26/27 maneuver)로 정상 태깅되어 있어 회전 방향이 강제되고, 그 결과 CCW(정상)로 나온다. 반면 고덕좌교로의 원환 way(`way_id=1304219907`)는 Valhalla 그래프상 **로터리로 태깅되어 있지 않음(`round_about: false`, maneuver type26/27 부재)** — 단순 양방향 tertiary 도로 루프로 취급되어, Valhalla가 출발/도착 쌍마다 **기하학적으로 더 짧은 회전 방향(이 원의 노드 배치상 우연히 항상 CW)** 을 자유롭게 선택한다. 한국 우측통행 로터리는 CCW가 정방향인데 이 원은 반대로 통행 가능한 상태.

**→ 클라이언트/렌더링 버그가 아니라 업스트림 라우팅 데이터 문제다.** Valhalla가 반환하는 route geometry 자체가 CW이므로 client 파이프라인(§3-4, "순서·축 보존"이라는 결론은 여전히 유효)은 정확히 받은 대로 그린 것뿐. 근본 수정은 OSM 원본에서 way 1304219907에 `junction=roundabout` 태그(+올바른 반시계 방향 노드 와인딩, 또는 oneway 방향) 부여 후 Valhalla 타일 재빌드가 필요 — 이 리포 코드로는 고칠 수 없는 데이터 이슈. (RECON ONLY이므로 수정하지 않음.)
