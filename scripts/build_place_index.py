#!/usr/bin/env python3
"""
YuruNavi 출구 랜드마크 지명 인덱스 빌드 스크립트
================================================
korea.mbtiles(OpenMapTiles `place` 레이어)에서 city/town/village 지점을 추출해
앱에 번들되는 오프라인 지명 목록을 생성한다.

용도: EXIT-LANDMARK — 출구 maneuver에 OSM `sign.exit_name_elements`가 없을 때
"{인근 3km 지명} 방면 {좌/우}측 출구입니다" 발화의 지명 소스.
(lib/services/exit_landmark_service.dart 참조)

추출 줌은 z10 고정. z8은 village 다수 누락, z12+는 hamlet까지 폭발적으로 늘어
"주요 지명" 취지에 안 맞음 — 지명 밀도/처리량 균형점으로 z10 채택(534타일 전수).

MVT point 좌표는 타일 경계 버퍼(중복 사본)를 제외해야 한다: 버퍼 좌표를 그대로
쓰면 같은 지명이 인접 타일에서 최대 0.5도(~55km) 어긋난 위치로 중복 추출된다
(0 <= px < extent && 0 <= py < extent 필터로 해결, 아래 참조).

사전 요구사항:
    pip install mapbox-vector-tile

사용법:
    python3 scripts/build_place_index.py
    python3 scripts/build_place_index.py --mbtiles /path/to/custom.mbtiles

출력:
    assets/data/kr_places.json — [{"name","class","rank","lat","lon"}, ...]
"""

import argparse
import gzip
import json
import math
import sqlite3
import sys

DEFAULT_MBTILES = "/data/tiles/data/korea.mbtiles"
DEFAULT_OUTPUT = "assets/data/kr_places.json"

ZOOM = 10
WANT_CLASSES = {"city", "town", "village"}


def check_dependencies() -> bool:
    try:
        import mapbox_vector_tile  # noqa: F401
    except ImportError:
        print("[ERROR] mapbox-vector-tile 패키지가 없습니다: pip install mapbox-vector-tile")
        return False
    return True


def tile_to_lonlat(xt: int, yt: int, z: int, px: float, py: float, extent: int) -> tuple[float, float]:
    """XYZ 타일 좌표계 기준 tile-local pixel → lon/lat. buffer로 확장된
    px/py(>=extent 또는 <0)도 그대로 넣으면 올바른 전역 좌표가 나온다."""
    n = 2 ** z
    gx = xt + px / extent
    gy = yt + py / extent
    lon = gx / n * 360.0 - 180.0
    lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * gy / n)))
    return lon, math.degrees(lat_rad)


def pick_name(props: dict) -> str | None:
    # PoiNameResolver와 동일 관례: 한국어는 name:nonlatin 우선, 없으면 name.
    for key in ("name:nonlatin", "name"):
        v = props.get(key)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None


def extract_places(mbtiles_path: str) -> list[dict]:
    import mapbox_vector_tile as mvt

    db = sqlite3.connect(mbtiles_path)
    cur = db.cursor()
    cur.execute(
        "SELECT value FROM metadata WHERE name='bounds'"
    )
    row = cur.fetchone()
    bounds = tuple(float(x) for x in row[0].split(",")) if row else (-180, -90, 180, 90)

    cur.execute(
        "SELECT tile_column, tile_row, tile_data FROM tiles WHERE zoom_level=?",
        (ZOOM,),
    )
    rows = cur.fetchall()
    print(f"tiles at z={ZOOM}: {len(rows)}")

    dedup: dict[tuple, dict] = {}
    for tile_col, tms_row, data in rows:
        xt = tile_col
        yt = (2 ** ZOOM - 1) - tms_row  # mbtiles는 TMS(y반전) → XYZ 변환
        try:
            raw = gzip.decompress(data)
        except OSError:
            raw = data
        try:
            tile = mvt.decode(raw)
        except Exception:
            continue
        place = tile.get("place")
        if not place:
            continue
        extent = place.get("extent", 4096)
        for f in place["features"]:
            props = f["properties"]
            cls = props.get("class")
            if cls not in WANT_CLASSES:
                continue
            geom = f["geometry"]
            if geom.get("type") != "Point":
                continue
            px, py = geom["coordinates"]
            if not (0 <= px < extent and 0 <= py < extent):
                continue  # 타일 경계 버퍼(중복 사본) 제외
            lon, lat = tile_to_lonlat(xt, yt, ZOOM, px, py, extent)
            name = pick_name(props)
            if not name:
                continue
            rank = props.get("rank")
            key = (name, round(lat, 3), round(lon, 3))
            prev = dedup.get(key)
            if prev is None or (rank is not None and (prev["rank"] is None or rank < prev["rank"])):
                dedup[key] = {
                    "name": name,
                    "class": cls,
                    "rank": rank,
                    "lat": round(lat, 5),
                    "lon": round(lon, 5),
                }

    result = [
        r for r in dedup.values()
        if bounds[0] <= r["lon"] <= bounds[2] and bounds[1] <= r["lat"] <= bounds[3]
    ]
    result.sort(key=lambda r: (r["class"], r["rank"] if r["rank"] is not None else 999, r["name"]))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mbtiles", default=DEFAULT_MBTILES)
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    if not check_dependencies():
        return 1

    places = extract_places(args.mbtiles)
    by_class: dict[str, int] = {}
    for r in places:
        by_class[r["class"]] = by_class.get(r["class"], 0) + 1
    print(f"extracted {len(places)} places: {by_class}")

    with open(args.output, "w", encoding="utf-8") as fh:
        json.dump(places, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
