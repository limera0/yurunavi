import os
import requests
from collections import defaultdict


_TRACE_ATTRIBUTES_MAX_KM = 200  # Valhalla trace_attributes 기본 service_limits(200000m)
_TRACE_CHUNK_TARGET_KM = 150    # 안전 마진을 두고 청크당 목표 거리


def _trace_edges_chunk(coords: list, base_url: str) -> list:
    body = {
        "shape": [{"lat": c[0], "lon": c[1]} for c in coords[::max(1, len(coords) // 200)]],
        "costing": "motorcycle",
        # edge_walk가 긴/복잡한 경로에서 정확히 매칭 못하면 400을 내므로(routing_service.dart의
        # fetchStructureZones와 동일 이유) walk_or_snap으로 자동 map-matching 폴백을 쓴다.
        "shape_match": "walk_or_snap",
        "filters": {
            "attributes": ["edge.road_class", "edge.length", "edge.way_id",
                           "edge.bridge", "edge.tunnel"],
            "action": "include",
        },
    }
    r = requests.post(f"{base_url}/trace_attributes", json=body, timeout=30)
    r.raise_for_status()
    return r.json().get("edges", [])


def trace_edges(coords: list, base_url: str = None, distance_km: float = None) -> list:
    """coords: [[lat,lon], ...] → Valhalla trace_attributes edges 리스트
    (road_class/length/way_id/bridge/tunnel 포함). 실패 시 예외 발생.

    trace_attributes는 200km(200000m) 거리 상한이 있어(/route 자체의 상한보다 훨씬 낮음)
    시골길처럼 실제 이동거리가 긴 경로는 그대로 넘기면 400을 낸다. distance_km가 상한을
    넘으면 좌표를 구간별로 나눠 여러 번 호출해 이어붙인다(청크 경계의 edge 하나가 양쪽에
    중복 집계될 수 있으나 구성비/겹침률 통계용 근사이므로 무시할 수준)."""
    base_url = base_url or os.environ["VALHALLA_URL"]
    if not distance_km or distance_km <= _TRACE_ATTRIBUTES_MAX_KM:
        return _trace_edges_chunk(coords, base_url)

    n_chunks = -(-int(distance_km) // _TRACE_CHUNK_TARGET_KM)  # ceil
    chunk_size = -(-len(coords) // n_chunks)
    edges = []
    for i in range(0, len(coords), chunk_size):
        chunk = coords[i:i + chunk_size + 1]  # 다음 청크와 한 점 겹치게 이어서 연속성 유지
        if len(chunk) < 2:
            continue
        edges.extend(_trace_edges_chunk(chunk, base_url))
    return edges


def distribution_from_edges(edges: list) -> dict:
    """edges 리스트 → road_class별 거리(km) 가중 비율(%) 분포."""
    if not edges:
        return {}
    totals = defaultdict(float)
    for e in edges:
        totals[e.get("road_class", "unknown")] += float(e.get("length", 0.0))
    grand_total = sum(totals.values())
    if grand_total <= 0:
        return {}
    return {
        cls: round(length / grand_total * 100, 1)
        for cls, length in sorted(totals.items(), key=lambda kv: -kv[1])
    }


def road_class_distribution(coords: list, base_url: str = None, distance_km: float = None) -> dict:
    """coords: [[lat,lon], ...] → road_class별 거리 가중 비율(%) 분포.
    (대시보드 UI에서 쓰는 편의 래퍼 — 내부적으로 trace_edges + distribution_from_edges)"""
    try:
        edges = trace_edges(coords, base_url, distance_km)
    except Exception as e:
        return {"error": str(e)}
    return distribution_from_edges(edges)


def long_structure_spans_from_edges(edges: list, min_length_m: float) -> dict:
    """edges 리스트 중 길이가 min_length_m 이상인 개별 bridge/tunnel edge의 개수/총길이(m).
    연속 edge 병합은 하지 않는다 — Valhalla 코스팅(span_min_length)이 개별 edge 길이만
    보고 판정하는 것과 동일한 근사(2026-07-18 사용자 확인, 정확한 mjolnir 레벨 병합은
    이번 범위 밖)."""
    result = {
        "bridge": {"count": 0, "total_m": 0.0},
        "tunnel": {"count": 0, "total_m": 0.0},
    }
    for e in edges:
        length_m = float(e.get("length", 0.0)) * 1000
        if length_m < min_length_m:
            continue
        if e.get("bridge"):
            result["bridge"]["count"] += 1
            result["bridge"]["total_m"] += length_m
        if e.get("tunnel"):
            result["tunnel"]["count"] += 1
            result["tunnel"]["total_m"] += length_m
    return result


def long_structure_spans(coords: list, min_length_m: float, base_url: str = None,
                          distance_km: float = None) -> dict:
    """coords 기준 편의 래퍼 (trace_edges + long_structure_spans_from_edges)."""
    try:
        edges = trace_edges(coords, base_url, distance_km)
    except Exception as e:
        return {"error": str(e)}
    return long_structure_spans_from_edges(edges, min_length_m)
