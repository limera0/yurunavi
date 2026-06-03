#!/usr/bin/env python3
"""
YuruNavi 자전거전용/하천공원도로 하드배제 검증 하니스
======================================================
motorcycle costing이 자전거전용도로(cycleway, 하천공원 자전거도로)를
자동으로 배제하는지 Valhalla trace_attributes 로 검증합니다.

핵심가치: 네이버 자전거길에서 "차량진입금지" 구간을 오토바이 경로에서 제거.
Valhalla motorcycle costing 은 motor_vehicle:no, highway=cycleway 를 이미
하드배제합니다. 이 스크립트는 그것을 자동으로 증명합니다.

사용법:
    python3 scripts/validate_bicycle_exclusion.py

종료 코드:
    0 = PASS (모든 테스트 구간에서 cycleway 엣지 미사용)
    1 = FAIL (cycleway 엣지 발견 — 배제 로직 점검 필요)
    2 = 에러 (Valhalla 연결 실패 등)
"""

import sys
import json
import urllib.request
import urllib.error
from collections import Counter

VALHALLA_BASE = "http://localhost:8002"

# 테스트 구간: 한강 자전거도로 근처를 통과하는 경로들
TEST_ROUTES = [
    {
        "name": "성수 → 뚝섬 (한강 자전거길 근처)",
        "origin": {"lat": 37.5443, "lon": 127.0557},
        "dest":   {"lat": 37.5370, "lon": 127.0727},
    },
    {
        "name": "반포 → 동작 (반포한강공원 인근)",
        "origin": {"lat": 37.5049, "lon": 126.9978},
        "dest":   {"lat": 37.4994, "lon": 126.9761},
    },
    {
        "name": "양재천 인근 (탄천 자전거도로 근처)",
        "origin": {"lat": 37.4820, "lon": 127.0500},
        "dest":   {"lat": 37.5000, "lon": 127.0600},
    },
]

# 차량 진입 금지 판정 기준 (Valhalla trace_attributes `use` 값)
FORBIDDEN_USES = {"cycleway", "footway", "pedestrian", "steps"}


def valhalla_post(path: str, payload: dict) -> dict:
    url = f"{VALHALLA_BASE}{path}"
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"[ERROR] HTTP {e.code}: {e.read().decode()[:200]}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"[ERROR] Valhalla 연결 실패: {e}", file=sys.stderr)
        sys.exit(2)


def decode_polyline6(encoded: str) -> list[dict]:
    result = []
    i = 0
    lat = lng = 0
    b = encoded.encode()
    while i < len(b):
        for is_lng in (False, True):
            acc = shift = 0
            while True:
                if i >= len(b):
                    break
                ch = b[i] - 63
                i += 1
                acc |= (ch & 0x1F) << shift
                shift += 5
                if ch < 0x20:
                    break
            delta = ~(acc >> 1) if acc & 1 else acc >> 1
            if not is_lng:
                lat += delta
            else:
                lng += delta
        result.append({"lat": lat / 1e6, "lon": lng / 1e6})
    return result


def check_route(test: dict) -> tuple[bool, str]:
    """단일 구간 검증. (passed: bool, detail: str) 반환."""
    name = test["name"]

    # 1. 시골길 프로필로 경로 취득
    route_resp = valhalla_post("/route", {
        "locations": [test["origin"], test["dest"]],
        "costing": "motorcycle",
        "costing_options": {"motorcycle": {
            "use_highways": 0.0,
            "use_living_streets": 1.0,
            "use_tracks": 0.8,
            "use_ferry": 0.0,
            "class_factors": {"1": 100.0, "2": 5.0, "3": 2.5, "4": 1.0, "5": 0.2},
            "urban_penalty": 50.0,
        }},
    })

    legs = route_resp.get("trip", {}).get("legs", [])
    if not legs:
        return False, f"  경로를 찾지 못했습니다 — 에러로 처리"

    all_pts: list[dict] = []
    for leg in legs:
        pts = decode_polyline6(leg["shape"])
        all_pts.extend(pts[1:] if all_pts else pts)

    dist = route_resp["trip"]["summary"]["length"]

    # 2. trace_attributes 로 edge 속성 조회
    step = max(1, len(all_pts) // 80)
    shape_sub = all_pts[::step]

    ta_resp = valhalla_post("/trace_attributes", {
        "shape": shape_sub,
        "costing": "motorcycle",
        "shape_match": "map_snap",
        "filters": {
            "attributes": ["edge.use", "edge.road_class", "edge.bicycle_network"],
            "action": "include",
        },
    })

    edges = ta_resp.get("edges", [])
    use_counter = Counter(e.get("use", "unknown") for e in edges)
    bnet_counter = Counter(e.get("bicycle_network", 0) for e in edges)

    # 3. 금지 도로 검출
    forbidden_found = {u for u in FORBIDDEN_USES if use_counter.get(u, 0) > 0}
    bnet_exclusive = bnet_counter.get(1, 0)  # bicycle_network=1 엣지 수

    detail_lines = [
        f"  경로: {dist:.1f} km, {len(edges)} 엣지",
        f"  use 분포: {dict(use_counter)}",
        f"  bicycle_network=1 엣지 수: {bnet_exclusive}",
    ]

    if forbidden_found:
        detail_lines.append(f"  ⚠️  금지 도로 발견: {forbidden_found}")
        return False, "\n".join(detail_lines)

    detail_lines.append("  ✅ 자전거전용/하천공원 도로 미사용")
    return True, "\n".join(detail_lines)


def main() -> int:
    print("=" * 60)
    print("YuruNavi 자전거전용도로 하드배제 검증")
    print("  (motorcycle costing의 차량진입금지 도로 자동배제 확인)")
    print("=" * 60)
    print()

    all_passed = True
    for i, test in enumerate(TEST_ROUTES, 1):
        print(f"[{i}/{len(TEST_ROUTES)}] {test['name']}")
        passed, detail = check_route(test)
        print(detail)
        result = "PASS ✅" if passed else "FAIL ❌"
        print(f"  → {result}")
        print()
        if not passed:
            all_passed = False

    print("=" * 60)
    if all_passed:
        print("최종: PASS — 모든 구간에서 자전거전용도로 배제 확인됨")
        print("  Valhalla motorcycle costing이 motor_vehicle:no /")
        print("  highway=cycleway 를 올바르게 배제합니다.")
    else:
        print("최종: FAIL — 자전거전용도로 배제 로직 점검 필요")
        print("  routing_service.dart의 costing_options를 확인하세요.")
    print("=" * 60)

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
