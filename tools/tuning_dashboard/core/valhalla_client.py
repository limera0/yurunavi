import os
import requests


def build_costing_options(profile: dict) -> dict:
    m = {
        "class_factors": {k: float(v) for k, v in profile["class_factors"].items()},
        "use_highways": profile.get("use_highways", 0.0),
        "use_tolls":    profile.get("use_tolls",    0.0),
    }
    for k in ("curvature_penalty", "long_bridge_factor", "long_tunnel_factor",
              "span_min_length", "use_tracks", "use_living_streets",
              "top_speed", "use_ferry", "uturn_penalty"):
        if k in profile:
            m[k] = profile[k]
    return {"motorcycle": m}


def route(origin: tuple, dest: tuple, profile: dict, base_url: str = None) -> dict:
    base_url = base_url or os.environ["VALHALLA_URL"]
    body = {
        "locations": [
            {"lat": origin[0], "lon": origin[1]},
            {"lat": dest[0],   "lon": dest[1]},
        ],
        "costing": "motorcycle",
        "costing_options": build_costing_options(profile),
    }
    try:
        r = requests.post(f"{base_url}/route", json=body, timeout=30)
        r.raise_for_status()
    except requests.HTTPError:
        print(f"[valhalla] HTTP {r.status_code}: {r.text[:500]}")
        raise
    data = r.json()
    leg = data["trip"]["legs"][0]
    coords = decode_polyline(leg["shape"], precision=6)
    summary = data["trip"]["summary"]
    return {
        "coords":       coords,
        "distance_km":  summary["length"],
        "time_s":       summary["time"],
        "costing_opts": build_costing_options(profile),
    }


def decode_polyline(encoded: str, precision: int = 6) -> list:
    inv = 10 ** precision
    decoded, prev = [], [0, 0]
    i = 0
    while i < len(encoded):
        for j in range(2):
            shift, result = 0, 0
            while True:
                b = ord(encoded[i]) - 63
                i += 1
                result |= (b & 0x1f) << shift
                shift += 5
                if b < 0x20:
                    break
            prev[j] += ~(result >> 1) if (result & 1) else (result >> 1)
        decoded.append([prev[0] / inv, prev[1] / inv])  # [lat, lon]
    return decoded
