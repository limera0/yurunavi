#!/usr/bin/env python3
"""
YuruNavi 시골길 경로 자동 검증 하니스
======================================
Valhalla trace_attributes 로 시골길 경로 엣지 도로등급을 분류하여
동탄 bbox 내 도심 그리드 주행 비율을 계산합니다.
사람 눈 확인(APK 화면)의 자동 대체 수단.

사용법:
    python3 scripts/validate_rural_route.py
    python3 scripts/validate_rural_route.py --urban-threshold 0.25

종료 코드:
    0 = PASS (도심 그리드 비율 < threshold)
    1 = FAIL (도심 그리드 비율 >= threshold)
    2 = 에러 (Valhalla 응답 없음 등)
"""

import sys
import json
import argparse
import urllib.request
import urllib.error
from collections import Counter

# ── 설정 ──────────────────────────────────────────────────────────────────────

VALHALLA_BASE = "http://localhost:8002"

# 수원 영통구 → 평택 (동탄신도시를 잠재적으로 통과하는 경로)
ORIGIN = {"lat": 37.2759, "lon": 127.0613, "label": "수원 영통구"}
DEST   = {"lat": 36.9917, "lon": 127.1127, "label": "평택"}

# 동탄신도시 bbox (Dongtan New Town, 화성시 동탄)
DONGTAN_BBOX = {
    "min_lat": 37.19, "max_lat": 37.25,
    "min_lon": 127.03, "max_lon": 127.10,
}

# 도심 그리드 도로 클래스 (Valhalla 기준)
# residential = 주거지 격자도로, service_other = 서비스도로(주차장 등 포함)
URBAN_ROAD_CLASSES = {"residential", "service_other"}

# 시골길 costing_options (routing_service.dart와 동일)
RURAL_COSTING = {
    "use_highways": 0.0,
    "use_living_streets": 1.0,
    "use_tracks": 0.8,
    "top_speed": 40,
    "class_factors": {"1": 100.0, "2": 5.0, "3": 2.5, "4": 1.0, "5": 0.2},
    "urban_penalty": 50.0,
}

# ── Valhalla 유틸 ──────────────────────────────────────────────────────────────

def valhalla_post(path: str, payload: dict) -> dict:
    url = f"{VALHALLA_BASE}{path}"
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"[ERROR] Valhalla HTTP {e.code}: {e.read().decode()[:200]}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"[ERROR] Valhalla 연결 실패: {e}", file=sys.stderr)
        sys.exit(2)


def decode_polyline6(encoded: str) -> list[dict]:
    """Valhalla precision-6 encoded polyline → [{lat, lon}, ...]"""
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


# ── 검증 핵심 로직 ─────────────────────────────────────────────────────────────

def in_dongtan(lat: float, lon: float) -> bool:
    bb = DONGTAN_BBOX
    return bb["min_lat"] <= lat <= bb["max_lat"] and \
           bb["min_lon"] <= lon <= bb["max_lon"]


def run_validation(urban_threshold: float, valhalla_base: str = VALHALLA_BASE) -> int:
    print(f"[YuruNavi Harness] {ORIGIN['label']} → {DEST['label']}")
    print(f"  동탄 bbox: lat {DONGTAN_BBOX['min_lat']}~{DONGTAN_BBOX['max_lat']}, "
          f"lon {DONGTAN_BBOX['min_lon']}~{DONGTAN_BBOX['max_lon']}")
    print(f"  도심 기피 임계: {urban_threshold*100:.0f}%")
    print()

    # Step 1: 시골길 경로 취득
    print("[1/3] Valhalla /route (시골길 프로필) 호출 중...")
    global VALHALLA_BASE  # allow override from CLI
    VALHALLA_BASE = valhalla_base
    route_resp = valhalla_post("/route", {
        "locations": [
            {"lat": ORIGIN["lat"], "lon": ORIGIN["lon"]},
            {"lat": DEST["lat"],   "lon": DEST["lon"]},
        ],
        "costing": "motorcycle",
        "costing_options": {"motorcycle": RURAL_COSTING},
    })

    legs = route_resp.get("trip", {}).get("legs", [])
    if not legs:
        print("[ERROR] /route 응답에 legs 없음", file=sys.stderr)
        sys.exit(2)

    # 모든 legs의 points 합산
    all_pts: list[dict] = []
    for leg in legs:
        pts = decode_polyline6(leg["shape"])
        if all_pts:
            all_pts.extend(pts[1:])  # 중복 접점 제거
        else:
            all_pts.extend(pts)

    summary = route_resp["trip"]["summary"]
    print(f"  경로: {summary['length']:.1f} km, "
          f"{summary['time']/60:.0f}분, {len(all_pts)}pts")

    # Step 2: trace_attributes
    print("[2/3] Valhalla /trace_attributes 호출 중...")
    # 포인트가 너무 많으면 서브샘플 (trace_attributes 권장 ~100pts)
    step = max(1, len(all_pts) // 100)
    shape_sub = all_pts[::step]

    ta_resp = valhalla_post("/trace_attributes", {
        "shape": shape_sub,
        "costing": "motorcycle",
        "shape_match": "map_snap",
        "filters": {
            "attributes": [
                "edge.road_class",
                "edge.length",
                "matched.point",
                "matched.edge_index",
            ],
            "action": "include",
        },
    })

    edges = ta_resp.get("edges", [])
    matched_pts = ta_resp.get("matched_points", [])

    if not edges:
        print("[WARN] trace_attributes edges 없음 — 서브샘플 감소 후 재시도")
        # fallback: 더 촘촘한 샘플
        shape_sub = all_pts[::max(1, step//2)]
        ta_resp = valhalla_post("/trace_attributes", {
            "shape": shape_sub, "costing": "motorcycle",
            "shape_match": "map_snap",
            "filters": {"attributes": ["edge.road_class","edge.length",
                                       "matched.point","matched.edge_index"],
                        "action": "include"},
        })
        edges = ta_resp.get("edges", [])
        matched_pts = ta_resp.get("matched_points", [])

    print(f"  전체 엣지: {len(edges)}, matched_points: {len(matched_pts)}")

    # Step 3: 동탄 bbox 내 엣지 분석
    print("[3/3] 동탄 bbox 내 도심 그리드 비율 계산 중...")

    # 동탄 bbox에 걸리는 edge_index 추출
    dongtan_edge_idxs: set[int] = set()
    for mp in matched_pts:
        lat = mp.get("lat", 0.0)
        lon = mp.get("lon", 0.0)
        if in_dongtan(lat, lon):
            eidx = mp.get("edge_index", -1)
            if eidx >= 0:
                dongtan_edge_idxs.add(eidx)

    if not dongtan_edge_idxs:
        print("  [INFO] 동탄 bbox를 통과하는 엣지 없음 → 도심 우회 성공 (PASS)")
        print()
        print("=" * 60)
        print("PASS  — 시골길 경로가 동탄 bbox를 통과하지 않습니다.")
        print("=" * 60)
        return 0

    # 도로 등급별 길이(km) 집계
    rc_counter = Counter()
    total_km = 0.0
    urban_km = 0.0
    for idx in sorted(dongtan_edge_idxs):
        if idx >= len(edges):
            continue
        edge = edges[idx]
        rc = edge.get("road_class", "unknown")
        length = edge.get("length", 0.0)
        rc_counter[rc] += length
        total_km += length
        if rc in URBAN_ROAD_CLASSES:
            urban_km += length

    urban_ratio = urban_km / total_km if total_km > 0 else 0.0

    print(f"  동탄 bbox 통과 엣지: {len(dongtan_edge_idxs)}개, 총 {total_km:.2f} km")
    print("  도로등급 분포 (동탄 내):")
    for rc, km in sorted(rc_counter.items(), key=lambda x: -x[1]):
        tag = " ← URBAN" if rc in URBAN_ROAD_CLASSES else ""
        print(f"    {rc:20s}: {km:.3f} km{tag}")
    print(f"  도심 그리드 비율: {urban_ratio*100:.1f}%  (임계: {urban_threshold*100:.0f}%)")

    print()
    print("=" * 60)
    if urban_ratio < urban_threshold:
        print(f"PASS  — 도심 그리드 비율 {urban_ratio*100:.1f}% < {urban_threshold*100:.0f}%")
        print("       시골길 경로가 동탄 도심 격자도로를 피하고 있습니다.")
        return_code = 0
    else:
        print(f"FAIL  — 도심 그리드 비율 {urban_ratio*100:.1f}% >= {urban_threshold*100:.0f}%")
        print("       시골길 경로가 동탄 도심 격자도로를 과다 통과합니다.")
        print("       → urban_penalty 상향(100.0) 또는 class_factors.5 강화 권장")
        return_code = 1
    print("=" * 60)
    return return_code


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="YuruNavi 시골길 동탄 도심 우회 자동 검증"
    )
    parser.add_argument(
        "--urban-threshold", type=float, default=0.20,
        help="도심 그리드 비율 FAIL 임계값 (기본: 0.20 = 20%%)"
    )
    parser.add_argument(
        "--valhalla-base", default=VALHALLA_BASE,
        help=f"Valhalla 베이스 URL (기본: {VALHALLA_BASE})"
    )
    args = parser.parse_args()

    sys.exit(run_validation(args.urban_threshold, args.valhalla_base))


if __name__ == "__main__":
    main()
