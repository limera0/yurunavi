# RECON — 사유지 회피 오버레이, pbf 갱신마다 재현 가능한 파이프라인 설계

목표: `RECON_gate_avoid_poc.md`에서 검증된 태그(`motor_vehicle=no`+`motorcycle=no`, 또는 `access=no`) + `osmium apply-changes` 방식을, pbf 갱신 때마다 안전하게 재적용할 수 있는 유지보수 구조로 설계. **이번 tick도 프로덕션 pbf/tile_dir/valhalla.json 무변경** — 아래 5번 재검증만 격리 컨테이너(`poc_recon_verify`, 포트 18010, 종료 후 `docker rm -f` 완료)로 수행.

---

## 1. 현행 재빌드 절차 확정

`/data/valhalla/tile_build.log` (읽기전용 열람, 2026-06-01 08:00:07 ~ 08:01:42, 총 94초):

- 실제 호출: `valhalla_build_tiles -c <config> /custom_files/south-korea-latest.osm.pbf` 형태로 추정(로그에 CLI 전체 라인은 없으나 `Parsing files for ways: /custom_files/south-korea-latest.osm.pbf` 한 줄만 등장 — **이 로그가 남긴 빌드는 한국 pbf 단독**).
- 268개 타일, `Node Count 2790106 / Directed Edge Count 7401366`. `admins.sqlite`/`timezones.sqlite` 없음(경고, PoC에서 이미 확인한 것과 동일 — 프로덕션도 이 두 보조 DB 없이 운영 중).
- `valhalla_build_tiles --help` (컨테이너 `yurunavi-valhalla` 내부, `valhalla-fork:patch2-signals`, v3.7.0): `Usage: valhalla_build_tiles [OPTION...] OSM PBF file(s)` — **positional 인자로 pbf 파일을 여러 개 받을 수 있음**(공식 멀티 익스트랙트 지원).

**한국+일본 둘 다 빌드하는지** — 로그만으론 불확실했으나 실측으로 확정:
- `/data/valhalla/custom_files/`에 `japan-latest.osm.pbf`(2026-06-04 00:01 도착, 2.4GB)와 `south-korea-latest.osm.pbf`(2026-06-01, 279MB) 둘 다 존재.
- `valhalla_tiles.tar`/`valhalla_tiles/` 디렉토리는 **2026-06-04 08:58~09:02**에 재생성됨(소유자 root, `tile_build.log`의 06-01 빌드보다 나중 — 이 재빌드는 로그가 안 남음, 유실 또는 로그 파일 미보존).
- 이 06-04 타일셋에 대해 실제 프로덕션 서버(`localhost:8002`)로 도쿄역 인근 `/locate` 호출 → `way_id 342271473` 정상 반환, `/route`(도쿄역↔신주쿠, motorcycle)도 정상 경로 산출. **→ 현재 프로덕션 그래프에 일본이 포함되어 있음을 확인.** 즉 06-04 재빌드는 `valhalla_build_tiles ... south-korea-latest.osm.pbf japan-latest.osm.pbf`처럼 두 pbf를 함께 넘겨 실행된 것으로 판단됨(공식 멀티 파일 지원과 부합).
- `valhalla.json`과 `valhalla.json.bak.20260604`는 **바이트 단위로 동일**(diff 없음) — 06-04 작업은 config 변경이 아니라 pbf 추가 + 재빌드였던 것으로 보임(config 자체는 그대로 재사용 가능).

**결론**: 재빌드는 `valhalla_build_tiles -c valhalla.json <pbf1> [pbf2 ...]` 한 번 호출로 여러 지역 pbf를 동시에 처리한다. 오버레이 파이프라인도 이 멀티파일 호출 방식을 그대로 유지하면 됨(한국 pbf만 오버레이 적용, 일본 pbf는 그대로 두고 같이 넘기기).

---

## 2. 오버레이 표현 방식 — osmChange(apply-changes) 채택, id 대신 폴리곤 기반 재탐색으로 리스크 제거

### (a) osmChange(.osc, apply-changes) vs (b) osmium 태그 기반(tags-filter 등)

PoC에서 이미 `.osc` + `osmium apply-changes`로 동작 검증됨(`way version+1`로 modify, 그래프 빌드에 정상 반영). tags-filter 계열(`osmium tags-filter`, `osmium getid` 등)은 **읽기/추출 전용**이라 "기존 way에 태그를 추가"하는 쓰기 작업 자체를 못 함 — apply-changes(또는 동급의 pyosmium 스크립트)가 사실상 유일한 표준 경로. **(a) 채택 확정.**

### way_id는 안정적인가 — 핵심 리스크

**결론: 하드코딩된 way_id를 1차 키로 쓰면 안 됨.** OSM에서 way id는 "그 way 객체가 삭제되지 않는 한" 안정적이지만, 아래 상황에서 깨진다:
- 매퍼가 캠퍼스 내부 도로망을 항공사진 갱신 등으로 **다시 그리면**(재작도) 기존 way가 삭제되고 새 id로 재생성됨 — 흔한 편집 패턴.
- 기존 way가 **분할(split)**되면 분할된 조각 중 한쪽만 원래 id를 유지하고 나머지는 새 id를 받음.
- 평택 캠퍼스처럼 매퍼 손을 덜 탄 구역(이름 없는 `unclassified` 4개 way, PoC에서 확인)은 정확히 이런 "언젠가 통째로 다시 그려질" 후보군 — 리스크가 이론상이 아니라 현실적임.

**대안 — id 대신 폴리곤(지리 좌표) 기반 재탐색.** id는 pbf 갱신마다 깨질 수 있지만, 우리가 정의하는 "캠퍼스 경계 폴리곤"(또는 완충 bbox) 좌표 자체는 절대 변하지 않는다(우리 데이터). 매 pbf 갱신마다:

1. `osmium extract --polygon campus.geojson south-korea-latest.osm.pbf -o campus_slice.osm.pbf` 로 캠퍼스 영역만 추출(id 무관, 순수 지리 클립).
2. `campus_slice.osm.pbf`에서 `highway=*` 태그를 가진 모든 way를 순회(pyosmium `SimpleHandler`)하며, **그 시점에 실제로 존재하는 id**를 읽어 `motor_vehicle=no`+`motorcycle=no`(캠퍼스 내부 도로 전부이므로 `access=no`도 대안 가능, PoC E)를 추가하는 `.osc`를 **그 자리에서 생성**.
3. 생성된 `.osc`를 원본 `south-korea-latest.osm.pbf`에 `osmium apply-changes`로 적용.

이렇게 하면 way_id는 "이번 실행에서 캠퍼스 폴리곤과 겹치는 도로가 무엇인가"를 매번 새로 묻는 매개변수일 뿐, 관리 파일에 박아두는 영속 키가 아니게 된다 — **id 재발급/분할/재작도가 일어나도 다음 재빌드에서 자동으로 흡수됨.** 단, 부작용: 폴리곤이 너무 넓으면 캠퍼스 인접 공용도로까지 잘못 태깅될 위험 — 폴리곤은 "관통이 실제로 일어나는 내부 도로망"만 타이트하게 감싸야 하고(PoC 4개 way의 bbox 기준으로 산출 가능), 진입/출구 접점(공용도로와 만나는 그 지점)은 **폴리곤 경계 밖**에 두어 공용도로 자체는 절대 태깅되지 않게 한다.

### 이번 tick 관리 파일에서 way_id를 완전히 뺄지 여부

완전히 빼진 않는다 — **감사(audit)/회귀테스트용 참고값**으로만 남긴다(PoC 기록값 그대로). 파이프라인이 실제로 태깅에 사용하는 것은 폴리곤이고, way_id 필드는 "지난 빌드에서 이 id들이 태깅됐었다"는 로그 성격 — 다음 빌드에서 id가 달라져도 파이프라인은 안 깨지고, 관리자가 "어? id가 바뀌었네"를 알아챌 수 있는 diff 신호로만 활용.

---

## 3. 사유지 목록 데이터 구조 (YAML, `docker/private_land_overlays.yaml` 안)

```yaml
# 사유지 관통 회피 오버레이 목록. 매 pbf 갱신마다 이 파일을 순회해 오버레이 적용.
# polygon은 절대 좌표 기반 재탐색의 유일한 근거 — way_id는 감사용 참고값일 뿐 재적용에 사용하지 않음.
version: 1
overlays:
  - id: pyeongtaek_samsung_campus
    name: "평택 삼성전자 캠퍼스(고덕)"
    reason: "관통 시 사유지 진입 — RECON_private_avoid.md, RECON_gate_avoid_poc.md 참조"
    # 캠퍼스 내부 도로망만 감싸는 타이트한 폴리곤. 공용도로 접점(진입/출구)은 폴리곤 밖에 위치시켜
    # 삼성로/첨단대로 등 공용도로가 실수로 태깅되지 않도록 함.
    polygon:
      - [127.05275, 37.03505]
      - [127.05330, 37.03505]
      - [127.05330, 37.04080]
      - [127.05275, 37.04080]
      - [127.05275, 37.03505]
    tag_overrides:
      motor_vehicle: "no"
      motorcycle: "no"
    filter: "highway=*"   # 폴리곤 내부에서 이 태그를 가진 way만 대상
    last_known_way_ids: [1195222150, 1195222147, 1195222146, 773739945]  # 감사/회귀테스트 참고용, 재탐색에는 미사용
    verified_poc: "RECON_gate_avoid_poc.md 변형 D/E (2026-07-02)"
```

평택 1건만 채움(이번 tick 범위). 추가 캠퍼스는 `overlays` 리스트에 항목 추가만 하면 됨 — 스키마 자체는 이미 다건 확장 가능.

---

## 4. 재적용 파이프라인 골격 (설계만, 미실행)

```
[0] pbf 갱신 감지
    south-korea-latest.osm.pbf / japan-latest.osm.pbf mtime 또는 Geofabrik 체크섬 비교
    (cron/수동 트리거 — 이번 tick은 스크립트 실행 대상 아님, 골격만)

[1] 체크포인트: 갱신 전 pbf + 현재 valhalla_tiles.tar 백업
    cp south-korea-latest.osm.pbf south-korea-latest.osm.pbf.bak.$(date +%Y%m%d)
    cp valhalla_tiles.tar valhalla_tiles.tar.bak.$(date +%Y%m%d)
    실패 시: 중단(디스크 공간 등) — 롤백 지점 A

[2] 오버레이 적용 (private_land_overlays.yaml 순회, 격리 작업 디렉토리에서)
    for each overlay:
      osmium extract --polygon <overlay.polygon as geojson> new_south-korea.osm.pbf -o slice.osm.pbf
      pyosmium 스크립트: slice.osm.pbf에서 filter 매치 way 전부 → tag_overrides 추가한 .osc 생성
      osmium apply-changes new_south-korea.osm.pbf overlay.osc -o new_south-korea.osm.pbf.tmp && mv .tmp new_south-korea.osm.pbf
    실패 시(폴리곤 안에 대상 way 0개 등 이상 신호): 중단 + 알림, 원본 pbf 그대로 둠 — 롤백 지점 B
    (way 0개는 "캠퍼스가 재작도돼서 폴리곤이 더 이상 안 맞는다"는 신호일 수 있음 → 사람이 폴리곤 재조정)

[3] 격리 빌드 + 자동 검증
    별도 tile_dir(/data/valhalla/staging_tiles)에 valhalla_build_tiles 실행(오버레이 적용된 새 pbf + 일본 pbf 같이)
    임시 포트(예: 18020)에 valhalla_service 컨테이너 기동
    각 overlay마다 RECON_gate_avoid_poc.md와 동일한 curl 회귀 테스트:
      - 진입 좌표 → 출구 좌표, costing=motorcycle: 관통 경로(짧은 쪽)가 더 이상 최단경로가 아님을 확인
        (거리/시간이 PoC baseline "관통 시" 값과 달라야 함 — 같으면 오버레이 미반영, FAIL)
    실패 시: 컨테이너 폐기, staging_tiles 폐기, 원본 pbf/tile 무변경 유지 — 롤백 지점 C(프로덕션 영향 없음)

[4] 프로덕션 타일 스왑 (검증 PASS 시에만)
    valhalla_tiles.tar를 staging 빌드 결과로 교체 → docker restart yurunavi-valhalla
    스왑 직후 프로덕션 포트(8002)로 동일 회귀 테스트 1회 더(스왑 자체가 깨지지 않았는지)
    실패 시: [1]에서 백업한 .bak 타일로 즉시 복원 + 재기동 — 롤백 지점 D(최종 안전망)

[5] 정리
    staging_tiles, 임시 pbf, 회귀테스트 컨테이너 삭제
    .bak 백업은 N세대만 보관(예: 최근 2개) 후 정리
```

**주의**: 이 골격은 설계 문서일 뿐 — 이번 tick에서 스크립트 파일이나 cron을 실제로 만들지 않았음(tick 지시 "실행 금지" 준수). 실제 구현은 별도 tick으로 분리 권장(작업량이 이 tick 하나로는 과함 — 아래 리스크/공수 참조).

---

## 5. 격리 회귀 재검증 (실행함, 프로덕션 무영향)

PoC가 만든 격리 타일(`/data/valhalla/poc_gate/tiles_mvno/`, `valhalla_mvno.json`)을 그대로 재사용해 임시 컨테이너로 재확인(같은 pbf/이미지, 재빌드는 하지 않음 — PoC 이후 아무것도 안 바뀌었으므로 순수 재검증):

```
docker run -d --name poc_recon_verify -p 18010:8002 \
  -v /data/valhalla/poc_gate:/work valhalla-fork:patch2-signals \
  valhalla_service /work/valhalla_mvno.json 1
curl .../route (평택 진입 37.03529,127.05320 → 출구 37.04051,127.05290, costing=motorcycle)
→ 0.879km, 69.121s  (PoC 변형 D와 완전 동일값 — 회귀 없음)
docker rm -f poc_recon_verify
```

**결과: 회귀 없음.** `motor_vehicle=no`+`motorcycle=no` 오버레이는 여전히 관통을 차단(우회 경로로 전환)한다. 컨테이너는 검증 직후 제거 완료(`docker rm -f`), `/data/valhalla/poc_gate/`도 이전과 동일하게 유지(수정 없음).

---

## 리스크/공수 평가 — 이 파이프라인 vs `exclude_polygons`

| 항목 | 오버레이 재빌드 파이프라인 (이 문서) | `exclude_polygons` (클라이언트 요청 바디) |
|---|---|---|
| 구현 위치 | 서버 인프라(pbf 전처리 + 재빌드 자동화 스크립트, cron) | `lib/services/routing_service.dart` 한 곳(이미 위치 특정됨, `RECON_private_avoid.md` 참조) |
| 반영 속도 | pbf 갱신 주기 + 재빌드(94초/한국 단독 기준, 일본 포함 시 더 김) + 스왑 | 즉시(앱 배포 시점) |
| 인프라 리스크 | 타일 스왑 실패 시 프로덕션 라우팅 전체 영향 가능(4번 롤백 지점으로 완화하지만 실패 지점이 여러 개) | 없음(서버 무변경) |
| id 안정성 리스크 | 폴리곤 기반 재탐색으로 완화(2번) — 하지만 폴리곤 자체 정확도 유지 책임은 여전히 사람 몫 | 해당 없음(way_id 자체를 안 씀) |
| 확장성 | 사유지 수십~수백 곳도 스크립트가 자동 처리(폴리곤만 추가) | 요청 바디에 폴리곤 좌표 배열 추가 — 수십 곳까진 무리 없으나 요청 페이로드/폴리곤 정밀도 관리 필요, "정확한 캠퍼스 경계 좌표" 유지 책임은 동일하게 있음 |
| 부가효과 | pbf 자체가 고쳐지므로 라우팅 API를 직접 두드리는 다른 클라이언트(디버그 스크립트 등)에도 자동 적용 | 이 앱의 `/route` 호출에만 적용, 다른 호출자는 여전히 관통 |
| 공수(이번 확인 기준) | 스크립트 개발 + cron/트리거 설계 + 자동 회귀테스트까지 필요(4번 골격 전체 구현이 남은 작업) — **최소 1개 tick 이상 추가 소요 예상** | 이미 최소 구현 위치까지 특정됨(`routing_service.dart` `_doFetch`) — **가장 빠르면 1 tick 내 완료 가능** |

**결론 제안(마스터 최종 판단 필요)**: 사유지 목록이 소수(현재 평택 1건)인 현재 시점에는 **`exclude_polygons` 클라이언트 방식이 공수 대비 압도적으로 저비용**이며 프로덕션 서버를 전혀 건드리지 않아 리스크도 낮다. 오버레이 재빌드 파이프라인은 "사유지 목록이 수십 건 이상으로 늘거나, 이 앱 외 다른 라우팅 클라이언트도 지원해야 하는" 시점에 재고할 가치가 있는 투자 — 지금 당장 4번 골격을 구현하는 것은 이번 tick 범위를 넘어서는 별도 결정이 필요.

## 격리 산출물
이번 tick은 신규 격리 산출물을 만들지 않음(기존 `poc_gate/tiles_mvno`를 임시 컨테이너로 재조회만, 컨테이너는 검증 직후 삭제). 프로덕션 pbf/tile_dir/valhalla.json 무변경.
