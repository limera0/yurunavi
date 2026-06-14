import os
import requests
from collections import Counter


def road_class_distribution(coords: list, base_url: str = None) -> dict:
    """coords: [[lat,lon], ...] → road_class % 분포 dict"""
    base_url = base_url or os.environ["VALHALLA_URL"]
    shape = [[c[1], c[0]] for c in coords]  # [lon,lat] → Valhalla shape format [lat,lon] OK actually
    # trace_attributes 는 shape 를 encoded polyline 또는 위도/경도 배열로 받음
    body = {
        "shape": [{"lat": c[0], "lon": c[1]} for c in coords[::max(1, len(coords)//200)]],
        "costing": "motorcycle",
        "shape_match": "map_snap",
        "filters": {"attributes": ["edge.road_class"], "action": "include"},
    }
    try:
        r = requests.post(f"{base_url}/trace_attributes", json=body, timeout=30)
        r.raise_for_status()
    except Exception as e:
        return {"error": str(e)}
    data = r.json()
    edges = data.get("edges", [])
    if not edges:
        return {}
    counts = Counter(e.get("road_class", "unknown") for e in edges)
    total = sum(counts.values())
    return {cls: round(cnt / total * 100, 1) for cls, cnt in counts.most_common()}
