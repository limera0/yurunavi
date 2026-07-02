# RECON — 사유지(삼성전자 공장) 관통 경로 회피 조사

증상(p8): 경로가 삼성전자 공장 등 진입 불가 사유지 내부로 들어감. 원인 규명 (읽기전용, 이번 tick 코드/서버/타일 변경 없음).

## ⚠️ 선행 제약: 정확한 재현 좌표 미제공

tick.md는 "p8 스크린샷의 공장 관통 출발/도착 좌표를 마스터가 제공"한다고 전제했으나, 이번 tick 지시문에 실제 좌표가 포함되지 않았음. Hard rule("불확실하면 추측 대신 보고")에 따라 임의의 좌표를 p8의 정답인 것처럼 단정하지 않는다.

대신 웹 검색으로 확인한 삼성전자 공식 캠퍼스 GPS 좌표(화성 나노시티 37.2169N 127.0692E, 수원 디지털시티 인근 37.2515N 127.0369E — [wikimapia](http://wikimapia.org/15276699/Samsung-Electronics-Nano-City-Hwasung-Campus))로 대체 재현을 시도했다. **아래 1번 결과는 p8 원본 재현이 아니라 대체 검증**이며, 마스터의 실제 좌표 확인 시 재검증 필요.

## 1. 문제 경로 재현 시도 (curl, `/route`, 로컬 valhalla `http://localhost:8002`)

시도한 좌표 쌍 5개 (Suwon Digital City 대각선, Hwaseong Nano City 남북/동서, 캠퍼스 내부 근접점 등) — 전부 아래 파일에 저장 (`/tmp/test_*.json`, 세션 임시본, 커밋 대상 아님):

| 시도 | 기본 motorcycle costing | 시골길(rural) costing (routing_service.dart 동일 파라미터) |
|---|---|---|
| Suwon 대각선 (37.258,127.032→37.246,127.048) | 권선로→삼성로 (퍼블릭 도로만) | 동일 |
| Hwaseong 남북 (37.232,127.069→37.202,127.069) | 삼성1로→효행로→84→동탄원천로 우회 | 동일 우회 |
| Hwaseong 동서 (37.217,127.055→37.217,127.085) | 여울로→동탄지성로 우회 | 동일 우회 |
| Hwaseong 캠퍼스 근접 내부 2점 (37.2169,127.0692→37.2190,127.0700, 770m) | **캠퍼스 내부로 진입** — service_road/unclassified/residential 엣지 경유 (아래 2번 참조) | — |

**결론**: 대체 좌표로는 명백한 "공장 관통 경로"를 재현하지 못했다 — 대부분 케이스에서 Valhalla는 이름 있는 공용도로(효행로/동탄원천로 등)로 캠퍼스를 우회했다. 단, 캠퍼스 정문 근접 2점 테스트에서는 `service_road`/`unclassified`/이름없는 도로를 경유했다 (2번 항목의 trace_attributes 대상). p8의 정확한 관통 지점은 이 근접 캠퍼스 내부도로류일 가능성이 높으나 **확정할 수 없음** — 마스터의 실제 좌표 필요.

## 2. edge 속성 실측 (`/trace_attributes`, filters: edge.use/road_class/destination_only/access_restrictions/names/surface)

- Suwon 권선로/삼성로 구간(공용 간선도로, 30개 엣지): `use: road, road_class: tertiary, names: [권선로/삼성로]` — `destination_only`, `access_restrictions` 필드 **전혀 미출력**.
- Hwaseong 캠퍼스 근접 내부도로 구간(4개 엣지, 정문 부근): `use: service_road / road, road_class: service_other / unclassified / residential` — 여기서도 `destination_only`, `access_restrictions` 필드 **전혀 미출력**.

Valhalla trace_attributes는 boolean/optional 필드를 값이 false·비어있을 때 JSON에서 생략하는 것으로 알려져 있음(공식 소스 직접 대조는 이번 tick 범위 밖). 즉 이 결과는:
- **미출력 = false/empty로 해석하는 것이 합리적** (필드 자체가 요청 filter에는 포함되어 있었고 use/road_class/names는 정상 출력됐으므로 메커니즘 자체는 작동함).
- 캠퍼스 정문 부근 service_road조차 access 태그가 실려 있지 않음 → **이 도로들에는 OSM 상 access=private/no, destination_only 태그가 없는 것으로 보임**.

## 3. Valhalla costing 설정 확인 (`valhalla.json`, 컨테이너 `yurunavi-valhalla` `/custom_files/valhalla.json`, 변경 없음)

- `mjolnir.data_processing`에 access/private 관련 서버 오버라이드 **없음** (grep 무결과).
- `mjolnir.include_driveways: true` — OSM `service=driveway` 태그 도로도 라우팅 그래프에 **포함**시키는 설정. 캠퍼스 내부 service_road/driveway류가 그래프에 들어와 있는 이유가 이것.
- `ignore_access`는 valhalla.json에는 없고, Valhalla 표준 API 기준 **요청(costing_options) 레벨 파라미터**이며 기본값 false — 즉 서버는 기본적으로 access 태그를 "존중"하는 방향(태그가 있으면 회피)이다. 문제는 태그가 존재하지 않는 것.
- 소스 데이터: `/custom_files/south-korea-latest.osm.pbf` (Geofabrik 표준 추출본, 2026-06-01) — 태그 자체가 원본 OSM에 없으면 애초에 pbf에도 없다. 커스텀 필터링으로 access 태그를 누락시키는 구조는 아님(표준 추출).

## 4. 클라이언트 라우팅 호출부 (`lib/services/routing_service.dart`)

- `costing_options` 3종(시골길 L158-178, 지방도로 L180-199, 국도 L201-220) 전부 `use_highways`/`use_ferry`/`use_living_streets`/`use_tracks`/`class_factors`/`curvature_penalty`/`long_bridge_factor`/`long_tunnel_factor`/`span_min_length`/`top_speed`/`shortest`만 설정.
- **`ignore_access`, `private_access_penalty` 등 access 관련 파라미터는 세 프로필 어디에도 없음** — 클라이언트는 access 회피를 서버 기본값 + OSM 태그에 전적으로 위임하고 있음. `_ruralBalancedOpts`(L93-108, 시골길 과다우회 폴백)도 동일하게 access 파라미터 없음.
- `/route` POST body 구성: `_doFetch` L261-277, `locations`/`costing`/`costing_options`만 전송. `exclude_polygons`류 필드는 어디서도 전송하지 않음.

## avoid_polygons(현재 API명 `exclude_polygons`) 지원 여부

curl 실측(로컬 서버, 이번 tick 한정 테스트 — 서버/설정 변경 없음):
- 두 지점이 모두 폴리곤 내부일 때 `exclude_polygons` 전달 → HTTP 400 `"No path could be found for input"` — **폴리곤이 실제로 라우팅에 반영됨을 확인** (폴리곤 무시라면 정상 200이 나왔어야 함).
- **결론: 이 Valhalla 3.7.0 서버는 `exclude_polygons` 파라미터를 지원한다.** 알려진 구역(삼성 공장 등)을 다각형 좌표로 요청 바디에 수동 첨부하면 즉시 회피 가능 — 코드 변경 없이 클라이언트 `costing_options`와 별도로 `/route` 요청 바디 최상위에 `exclude_polygons` 필드만 추가하면 됨.

---

## 결론

**원인 단정 1줄**: **(B) 근접** — 캠퍼스 정문 부근 실측 도로(service_road/unclassified)에서 access/destination_only 태그가 확인되지 않음 → 데이터 부재 가능성이 높다. 단, p8 정확 좌표로 재검증 전까지는 **(A)/(B) 최종 확정 보류** — 이번 대체 좌표가 실제 p8 관통 지점과 다를 수 있음.

### 해법 분기

- **(B) 데이터 문제로 확인될 경우** (가능성 높음):
  1. **즉시 가능한 우회책 — `exclude_polygons`** (3번 항목에서 지원 확인됨): 알려진 사유지(삼성전자 각 캠퍼스 등)의 폴리곤 좌표를 `routing_service.dart` `_doFetch`의 `/route` 요청 바디에 하드코딩 리스트로 추가. 코드 변경만으로 가능, 타일/서버 불필요. 단점: 사유지 목록을 수동 유지보수해야 함(전국 스케일 안 됨, 알려진 몇 곳 한정 대응).
  2. **근본 해법 — OSM 기여**: 실제 access=private/no 태그를 OSM에 추가(직접 매핑 또는 기존 매퍼 커뮤니티 제보) → `south-korea-latest.osm.pbf` 다음 갱신 시 자동 반영. 비용: 즉시 반영 안 됨(OSM 갱신 주기 + 이 프로젝트의 pbf 재다운로드/`valhalla_build_tiles` 재실행 필요), 하지만 전국 범용 해결.
  3. **중간책 — 타일 재빌드 시 필터링**: `include_driveways: false`로 전환하면 driveway류 자체가 그래프에서 빠짐 — 그러나 정상적인 골목/사유 진입로까지 광범위하게 사라져 부작용 큼(비추천, 언급만).
- **(A) 태그가 실제로 존재하는 것으로 재확인될 경우** (재검증 시): `costing_options.motorcycle`에 `ignore_access:false`는 이미 기본값이라 변경 불필요 — 대신 access 태그가 있는데도 뚫린다면 이는 Valhalla 버그이거나 `use_tracks`/`use_living_streets` 같은 다른 파라미터가 access 로직을 오버라이드하는 것이므로 별도 재조사 필요.

### 마스터 확인 필요 사항
- p8 스크린샷의 실제 출발/도착 좌표 (또는 스크린샷 자체) — 위 재현이 대체 좌표 기반이라 최종 확정에 필수.
- (B)로 갈 경우 `exclude_polygons` 하드코딩 방식에 넣을 "알려진 사유지" 목록 범위 (삼성전자만? 다른 대기업 캠퍼스도?).
