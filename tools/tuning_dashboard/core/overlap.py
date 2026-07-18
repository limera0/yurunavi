from collections import defaultdict


def _way_lengths(edges: list) -> dict:
    d = defaultdict(float)
    for e in edges:
        wid = e.get("way_id")
        if wid is not None:
            d[wid] += float(e.get("length", 0.0))
    return d


def route_overlap(edges_a: list, edges_b: list) -> dict:
    """두 경로(trace_attributes edges 리스트)가 공유하는 way_id 구간의 거리(km) 비율.

    같은 way_id를 공유하는 구간의 길이 합을 "겹치는 구간"으로 근사한다(2026-07-18,
    실제 shape 좌표 단위 비교가 아니라 way_id 단위 근사 — 검증 목적에는 충분).
    pct_of_a/pct_of_b는 각 경로 총 거리 대비 비율이라 대칭이 아닐 수 있다(짧은 경로일수록
    같은 겹침 길이의 비중이 커짐) — 판정 시 둘 중 더 큰 쪽을 기준으로 삼는다.
    """
    la = _way_lengths(edges_a)
    lb = _way_lengths(edges_b)
    shared_ways = set(la) & set(lb)
    overlap_km = sum(min(la[w], lb[w]) for w in shared_ways)
    total_a = sum(la.values())
    total_b = sum(lb.values())
    pct_a = round(overlap_km / total_a * 100, 1) if total_a else 0.0
    pct_b = round(overlap_km / total_b * 100, 1) if total_b else 0.0
    return {
        "overlap_km": round(overlap_km, 2),
        "pct_of_a": pct_a,
        "pct_of_b": pct_b,
        "pct_max": max(pct_a, pct_b),
    }
