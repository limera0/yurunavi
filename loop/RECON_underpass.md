# RECON_underpass — Valhalla fork(:8002) 기능 실측 보고서

작성: 2026-06-30  
엔드포인트: `localhost:8002` (Valhalla 3.7.0)  
조사 항목: (A) lanes / (B) ramp·exit·merge maneuver type / (C) edge use(tunnel/bridge)

---

## 0. 엔드포인트 규명

| 항목 | 결과 |
|------|------|
| `/status` 생존 | ✅ `{"version":"3.7.0","tileset_last_modified":1780563736}` |
| 404/error106 원인 | 이전 호출이 Body 없이 GET으로 전달됐거나 `Content-Type` 헤더 누락. `-H 'Content-Type: application/json' --data-binary @req.json` 형태로 **POST** 하면 정상 200 반환 |
| 동작하는 호출 형태 | `curl -X POST localhost:8002/route -H 'Content-Type: application/json' --data-binary @req.json` |

---

## A. lanes — `/route` maneuver 내 차선 안내

**결론: 없음**

```
grep '"lanes"' loop/recon_route.json → (결과 없음)
```

- Valhalla 3.7.0의 기본 `/route` 응답 maneuver 객체에는 `lanes` 필드가 존재하지 않음.
- Valhalla OSS에서 `turn_lanes`는 OSM `turn:lanes` 태그가 있고 해당 기능이 활성화된 빌드에서만 포함됨. 이 fork에서는 비활성 상태로 판단됨.

---

## B. ramp · exit · merge maneuver type — `/route`

**결론: 있음 (exit/ramp), merge 미관측**

### 관측된 type 목록 (두 경로 합산)

| type | Valhalla enum | 관측 |
|------|---------------|------|
| 19   | kRampLeft     | ✅ (서울→수원 probe) |
| 20   | kExitRight    | ✅ (강남→군자 probe, 2회) |
| 23   | kStayRight    | ✅ |
| 24   | kStayLeft     | ✅ |
| 25/37/38 | kMerge/kMergeRight/kMergeLeft | ❌ (테스트 경로에서 미출현 — 고속도로 본선 합류 경로 부재) |

### 발췌 (type 20 ExitRight 예시)

```json
{
  "type": 20,
  "instruction": "오른쪽 46 출구로 진출",
  "sign": {
    "exit_branch_elements": [{"text": "46"}]
  },
  "street_names": ["46","70","강변북로"]
}
```

```json
{
  "type": 20,
  "instruction": "오른쪽 23 출구로 진출",
  "sign": {
    "exit_number_elements": [{"text": "23"}],
    "exit_name_elements": [{"text": "천호대교 북단"}]
  }
}
```

- `sign.exit_number_elements`, `sign.exit_branch_elements`, `sign.exit_name_elements` 모두 실려 있어 출구번호·출구명 TTS 안내 즉시 활용 가능.

---

## C. edge use / bridge / tunnel — `/trace_attributes`

**결론: 있음 (use, bridge, tunnel 모두 동작)**

### 호출 파라미터

```json
{
  "encoded_polyline": "<route.legs[0].shape>",
  "shape_match": "edge_walk",
  "costing": "motorcycle",
  "filters": {
    "attributes": ["edge.use","edge.road_class","edge.bridge","edge.tunnel","edge.surface"],
    "action": "include"
  }
}
```

### 관측 결과

| 필드 | 타입 | 관측 값 | 비고 |
|------|------|---------|------|
| `use` | string | `road`, `ramp`, `service_road`, `turn_channel` | 주요 도로·램프·서비스도로 구분 가능 |
| `bridge` | bool | `true`(14 edges), `false` | 한강교량 포함 경로에서 확인 |
| `tunnel` | bool | `true`(1 edge), `false` | 남산터널 경유 경로에서 확인 |

### 발췌 (tunnel=true edge 예시)

```json
{"surface": "paved_smooth", "bridge": false, "tunnel": true, "use": "road", "road_class": "primary"}
```

### 발췌 (bridge=true edge 예시)

```json
{"surface": "paved_smooth", "bridge": true, "tunnel": false, "use": "road", "road_class": "trunk"}
```

---

## 권고 분기

### lanes 없음 → 차선 안내는 별도 처리 필요

- Valhalla `/route` 응답만으로는 `"1차선 유지"` 등 차선 단위 안내 불가.
- **대안 경로**: OSM `turn:lanes` 태그를 앱 레이어에서 직접 파싱하거나, Valhalla 빌드 시 `turn_lanes` 기능 플래그 활성화 여부를 서버 운영팀에 확인. 단기 구현은 차선 안내 제외.

### ramp(19)/exit(20) 있음 → 나들목 TTS 안내 즉시 구현 가능

- `maneuver.type == 20(ExitRight) | 21(ExitLeft)`를 감지해 `sign.exit_number_elements` + `sign.exit_name_elements`를 TTS로 읽으면 됨.
- `type == 17~19(Ramp*)` 는 진입로(IC 진입) 안내.
- **우선순위**: 이 항목이 lanes보다 구현 준비도 높음 → 나들목 안내 먼저, 차선 안내 후속.

### edge use / tunnel / bridge가 trace_attributes에 있음 → 터널·고가 안내는 별도 trace 호출 설계 필요

- `/route` 응답에는 edge use·tunnel·bridge가 포함되지 않음.
- **설계 방향**: 
  1. `/route`로 경로 수신 → `shape` 추출
  2. `/trace_attributes` 별도 호출 → `tunnel=true` / `bridge=true` edge 목록 수신
  3. edge의 `begin_shape_index` / `end_shape_index` 와 route maneuver의 shape index를 매핑 → 터널 진입·진출 거리 계산
  4. 현재 위치가 터널 구간 진입 X미터 전 → TTS "터널 진입합니다"
- **주의**: `/trace_attributes`는 기존 shape에 대한 사후 조회이므로 경로 계산 시 1회 추가 호출이 발생. 경로 캐시와 함께 관리 필요.

---

## 실측 환경

- Valhalla: 3.7.0 (`localhost:8002`)
- 테스트 경로 1: 강남(127.0276,37.4979) → 군자(127.1058,37.5665) — 강변북로 경유
- 테스트 경로 2: 서울(126.9780,37.5665) → 수원(127.0127,37.2636) — 경수대로 ramp 포함
- 테스트 경로 3: 이태원(126.9920,37.5345) → 명동(126.9855,37.5640) — 남산터널 경유
- 전체 응답: `loop/recon_route.json` (경로 1 기준)
