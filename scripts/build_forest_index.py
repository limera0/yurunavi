#!/usr/bin/env python3
"""
YuruNavi 숲 근접도 인덱스 빌드 스크립트
========================================
한국 OSM PBF 파일에서 landuse=forest / natural=wood 폴리곤을 추출하여
SQLite R-tree 공간 인덱스를 생성합니다.

생성된 인덱스는 Rust fun_score_v4()의 forest_proximity 파라미터를
계산하는데 사용됩니다. (도로 세그먼트에서 50m 이내 숲 폴리곤 존재 여부)

사전 요구사항:
    sudo apt install osmium-tool
    pip install osmium shapely

사용법:
    python3 scripts/build_forest_index.py
    python3 scripts/build_forest_index.py --pbf /path/to/custom.osm.pbf
    python3 scripts/build_forest_index.py --output /path/to/forest.db

출력:
    data/forest_index.db  — SQLite R-tree 인덱스
      테이블: forest_polygons(id, min_lat, max_lat, min_lon, max_lon, centroid_lat, centroid_lon)
"""

import sys
import os
import sqlite3
import argparse

DEFAULT_PBF = "/data/valhalla/custom_files/south-korea-latest.osm.pbf"
DEFAULT_DB  = "/data/projects/yurunavi/data/forest_index.db"

# ── osmium 가용성 확인 ──────────────────────────────────────────────────────

def check_dependencies() -> bool:
    """필수 도구 확인. 없으면 설치 안내 출력 후 False 반환."""
    missing = []
    try:
        import osmium  # noqa: F401
    except ImportError:
        missing.append("osmium (pip install osmium)")
    try:
        from shapely.geometry import shape  # noqa: F401
    except ImportError:
        missing.append("shapely (pip install shapely)")

    import shutil
    if not shutil.which("osmium"):
        missing.append("osmium-tool (sudo apt install osmium-tool)")

    if missing:
        print("[ERROR] 필수 패키지가 없습니다:")
        for m in missing:
            print(f"  - {m}")
        print()
        print("설치 후 다시 실행하세요:")
        print("  sudo apt install osmium-tool")
        print("  pip install osmium shapely")
        return False
    return True


# ── OSM 숲 폴리곤 추출 ─────────────────────────────────────────────────────

def extract_forest_polygons(pbf_path: str) -> list[dict]:
    """PBF에서 landuse=forest / natural=wood 폴리곤 bbox 추출."""
    import osmium
    from shapely.geometry import shape

    class ForestHandler(osmium.SimpleHandler):
        def __init__(self):
            super().__init__()
            self.polygons: list[dict] = []
            self._count = 0

        def area(self, a):
            tags = a.tags
            if tags.get("landuse") == "forest" or tags.get("natural") == "wood":
                try:
                    wkb = osmium.geom.WKBFactory()
                    geom = shape(wkb.create_multipolygon(a))
                    bounds = geom.bounds  # (min_lon, min_lat, max_lon, max_lat)
                    centroid = geom.centroid
                    self._count += 1
                    if self._count % 5000 == 0:
                        print(f"  ... {self._count} 숲 폴리곤 처리 중")
                    self.polygons.append({
                        "min_lat": bounds[1],
                        "max_lat": bounds[3],
                        "min_lon": bounds[0],
                        "max_lon": bounds[2],
                        "centroid_lat": centroid.y,
                        "centroid_lon": centroid.x,
                    })
                except Exception:
                    pass  # 잘못된 geometry 무시

    handler = ForestHandler()
    handler.apply_file(pbf_path, locations=True, idx="sparse_file_array")
    return handler.polygons


# ── SQLite R-tree 인덱스 생성 ──────────────────────────────────────────────

def build_sqlite_index(polygons: list[dict], db_path: str) -> None:
    """R-tree 공간 인덱스 SQLite DB 생성."""
    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # R-tree 가상 테이블 (SQLite built-in rtree 모듈)
    cur.execute("DROP TABLE IF EXISTS forest_rtree")
    cur.execute("DROP TABLE IF EXISTS forest_meta")
    cur.execute("""
        CREATE VIRTUAL TABLE forest_rtree
        USING rtree(id, min_lat, max_lat, min_lon, max_lon)
    """)
    cur.execute("""
        CREATE TABLE forest_meta (
            id INTEGER PRIMARY KEY,
            centroid_lat REAL,
            centroid_lon REAL
        )
    """)

    print(f"  {len(polygons)}개 폴리곤을 R-tree에 삽입 중...")
    batch = []
    meta_batch = []
    for i, p in enumerate(polygons):
        batch.append((i, p["min_lat"], p["max_lat"], p["min_lon"], p["max_lon"]))
        meta_batch.append((i, p["centroid_lat"], p["centroid_lon"]))
        if len(batch) >= 10000:
            cur.executemany("INSERT INTO forest_rtree VALUES (?,?,?,?,?)", batch)
            cur.executemany("INSERT INTO forest_meta VALUES (?,?,?)", meta_batch)
            batch.clear()
            meta_batch.clear()
    if batch:
        cur.executemany("INSERT INTO forest_rtree VALUES (?,?,?,?,?)", batch)
        cur.executemany("INSERT INTO forest_meta VALUES (?,?,?)", meta_batch)

    conn.commit()
    conn.close()
    size_mb = os.path.getsize(db_path) / 1024 / 1024
    print(f"  DB 저장 완료: {db_path} ({size_mb:.1f} MB)")


# ── 근접도 쿼리 예시 함수 ──────────────────────────────────────────────────

def query_forest_proximity(db_path: str, lat: float, lon: float, radius_deg: float = 0.0005) -> float:
    """
    주어진 좌표 반경 내 숲 폴리곤 존재 여부 (0.0 or 1.0).
    radius_deg ≈ 0.0005° ≈ 50m (위도 기준)

    Rust에서 호출하려면 이 쿼리를 FFI로 래핑하거나 HTTP 엔드포인트로 제공.
    """
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("""
        SELECT COUNT(*) FROM forest_rtree
        WHERE min_lat <= ? AND max_lat >= ?
          AND min_lon <= ? AND max_lon >= ?
    """, (lat + radius_deg, lat - radius_deg,
          lon + radius_deg, lon - radius_deg))
    count = cur.fetchone()[0]
    conn.close()
    return 1.0 if count > 0 else 0.0


# ── CLI ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="YuruNavi 숲 근접도 SQLite R-tree 인덱스 빌드"
    )
    parser.add_argument("--pbf", default=DEFAULT_PBF,
                        help=f"OSM PBF 파일 경로 (기본: {DEFAULT_PBF})")
    parser.add_argument("--output", default=DEFAULT_DB,
                        help=f"출력 SQLite DB 경로 (기본: {DEFAULT_DB})")
    args = parser.parse_args()

    print("=" * 60)
    print("YuruNavi 숲 근접도 인덱스 빌드")
    print("=" * 60)

    if not check_dependencies():
        print()
        print("NOTE: Rust fun_score_v4()의 forest_score 함수는 이미 구현됨.")
        print("      이 스크립트 실행 후 Rust /score_route 에 forest_proximity 연동 필요.")
        sys.exit(2)

    if not os.path.exists(args.pbf):
        print(f"[ERROR] PBF 파일 없음: {args.pbf}")
        sys.exit(2)

    print(f"\n[1/3] PBF 파일에서 숲 폴리곤 추출 중...")
    print(f"  입력: {args.pbf}")
    polygons = extract_forest_polygons(args.pbf)
    print(f"  추출 완료: {len(polygons)}개 숲 폴리곤")

    print(f"\n[2/3] SQLite R-tree 인덱스 생성 중...")
    build_sqlite_index(polygons, args.output)

    print(f"\n[3/3] 인덱스 검증 중...")
    # 서울 북한산 근처 테스트
    test_lat, test_lon = 37.6583, 126.9760
    score = query_forest_proximity(args.output, test_lat, test_lon)
    status = "PASS (숲 감지됨)" if score > 0 else "WARN (숲 미감지 — 위치 확인 필요)"
    print(f"  북한산 근처 ({test_lat}, {test_lon}): forest_proximity={score} → {status}")

    print("\n" + "=" * 60)
    print("완료! 다음 단계:")
    print("  1. Rust /score_route 핸들러에서 DB 쿼리하여 forest_proximity 계산")
    print("  2. fun_score_v4() 호출로 ScoreRouteResp에 fun_score_v4 포함")
    print("=" * 60)


if __name__ == "__main__":
    main()
