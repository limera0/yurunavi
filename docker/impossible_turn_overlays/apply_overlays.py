#!/usr/bin/env python3
"""
불가능한 좌회전 지점(manifest.yaml) 로컬 그래프 오버레이 파이프라인.

절대 프로덕션 pbf/tile_dir/컨테이너를 직접 건드리지 않는다 — 전부 격리된
staging 디렉토리 + 임시 포트 컨테이너에서만 검증한다. PASS 후 실제 프로덕션
반영은 이 스크립트가 아니라 별도의 swap_production_tiles.sh(수동 실행,
--yes-i-am-sure 필요)가 담당한다.

절차: verify(id/좌표 검증) -> apply(osmium apply-changes+sort) ->
build(격리 tile_dir) -> test(임시 컨테이너, target/regression 회귀 검사).
어느 단계든 실패하면 그 자리에서 중단하고 staging 산출물만 남긴다.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
OVERLAY_DIR = Path(__file__).resolve().parent
COORD_TOLERANCE_M = 5.0


def log(msg: str) -> None:
    print(f"[overlays] {msg}", flush=True)


def fail(msg: str) -> None:
    print(f"[overlays] FAIL: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    log("$ " + " ".join(str(c) for c in cmd))
    return subprocess.run(cmd, check=True, **kw)


def haversine_m(lat1, lon1, lat2, lon2) -> float:
    import math
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def parse_opl_nodes(text: str) -> dict[str, tuple[float, float]]:
    """node id -> (lat, lon)"""
    out = {}
    for line in text.splitlines():
        if not line.startswith("n"):
            continue
        m = re.match(r"n(\d+)\s", line)
        if not m:
            continue
        xm = re.search(r"\sx([\-0-9.]+)", line)
        ym = re.search(r"\sy([\-0-9.]+)", line)
        if xm and ym:
            out[m.group(1)] = (float(ym.group(1)), float(xm.group(1)))
    return out


def parse_opl_way_ids(text: str) -> set[str]:
    out = set()
    for line in text.splitlines():
        m = re.match(r"w(\d+)\s", line)
        if m:
            out.add(m.group(1))
    return out


def verify_overlay(overlay: dict, source_pbf: Path, workdir: Path) -> None:
    """expected_nodes/expected_ways가 source_pbf에 여전히 존재하고,
    노드는 기록된 좌표와 COORD_TOLERANCE_M 이내인지 확인. 실패 시 fail()."""
    node_ids = [str(n["id"]) for n in overlay.get("expected_nodes", [])]
    way_ids = [str(w["id"]) for w in overlay.get("expected_ways", [])]
    ids = [f"n{i}" for i in node_ids] + [f"w{i}" for i in way_ids]
    if not ids:
        return

    out_opl = workdir / f"{overlay['id']}_verify.opl"
    proc = subprocess.run(
        ["osmium", "getid", str(source_pbf), *ids, "--verbose-ids",
         "-f", "opl", "-o", str(out_opl), "--overwrite"],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        fail(f"{overlay['id']}: osmium getid 실패 — {proc.stderr[-800:]}")

    combined_log = proc.stdout + proc.stderr
    if "Found all objects" not in combined_log:
        fail(
            f"{overlay['id']}: 기준 id가 pbf에서 사라짐 (매퍼 재작도 가능성) — "
            f".osc를 사람이 다시 만들어야 함. osmium 로그:\n{combined_log[-1200:]}"
        )

    text = out_opl.read_text()
    found_nodes = parse_opl_nodes(text)
    found_ways = parse_opl_way_ids(text)

    for n in overlay.get("expected_nodes", []):
        nid = str(n["id"])
        if nid not in found_nodes:
            fail(f"{overlay['id']}: node {nid} 을 찾지 못함")
        lat, lon = found_nodes[nid]
        dist = haversine_m(lat, lon, n["lat"], n["lon"])
        if dist > COORD_TOLERANCE_M:
            fail(
                f"{overlay['id']}: node {nid} 좌표가 {dist:.1f}m 이동함 "
                f"(기록값 {n['lat']},{n['lon']} vs 현재 {lat},{lon}, "
                f"허용오차 {COORD_TOLERANCE_M}m) — 매퍼가 재작도했을 수 있음, "
                ".osc 재검토 필요"
            )
        log(f"  OK node {nid} ({n.get('note', '')}) drift={dist:.1f}m")

    for w in overlay.get("expected_ways", []):
        wid = str(w["id"])
        if wid not in found_ways:
            fail(f"{overlay['id']}: way {wid} 을 찾지 못함")
        log(f"  OK way {wid} ({w.get('note', '')})")


def build_patched_pbf(overlays: list[dict], source_pbf: Path, workdir: Path) -> Path:
    osc_paths = [str(OVERLAY_DIR / o["osc"]) for o in overlays]
    patched = workdir / "korea_patched.osm.pbf"
    run(["osmium", "apply-changes", str(source_pbf), *osc_paths,
         "-o", str(patched), "--overwrite"])
    sorted_pbf = workdir / "korea_patched_sorted.osm.pbf"
    run(["osmium", "sort", str(patched), "-o", str(sorted_pbf), "--overwrite"])
    return sorted_pbf


def read_prod_image() -> str:
    compose = (REPO_ROOT / "docker" / "docker-compose.yml").read_text()
    # image: line precedes container_name in this file
    m = re.search(r"image:\s*(\S+)\s*\n\s*container_name:\s*yurunavi-valhalla", compose)
    if not m:
        fail("docker-compose.yml에서 yurunavi-valhalla 이미지 태그를 못 찾음")
    return m.group(1)


def build_tiles(image: str, staging_dir: Path, korea_pbf: Path, japan_pbf: Path | None,
                 base_config: Path) -> None:
    tile_dir = staging_dir / "tiles"
    if tile_dir.exists():
        shutil.rmtree(tile_dir, ignore_errors=True)
    tile_dir.mkdir(parents=True)

    cfg = json.loads(base_config.read_text())
    cfg["mjolnir"]["tile_dir"] = "/work/tiles"
    cfg["mjolnir"].pop("tile_extract", None)
    cfg_path = staging_dir / "valhalla_staging.json"
    cfg_path.write_text(json.dumps(cfg, indent=2))

    pbf_args = [f"/work/{korea_pbf.name}"]
    if japan_pbf is not None:
        japan_dst = staging_dir / japan_pbf.name
        if japan_pbf.resolve() != japan_dst.resolve():
            shutil.copy(japan_pbf, japan_dst)
        pbf_args.append(f"/work/{japan_pbf.name}")
    korea_dst = staging_dir / korea_pbf.name
    if korea_pbf.resolve() != korea_dst.resolve():
        shutil.copy(korea_pbf, korea_dst)

    run([
        "docker", "run", "--rm", "--user", f"{os.getuid()}:{os.getgid()}",
        "-v", f"{staging_dir}:/work", image,
        "valhalla_build_tiles", "-c", "/work/valhalla_staging.json", *pbf_args,
    ])


def run_route(port: int, frm: dict, to: dict) -> float:
    body = json.dumps({
        "locations": [{"lat": frm["lat"], "lon": frm["lon"]},
                       {"lat": to["lat"], "lon": to["lon"]}],
        "costing": "motorcycle",
    })
    proc = subprocess.run(
        ["curl", "-s", "-X", "POST", f"http://localhost:{port}/route",
         "-H", "Content-Type: application/json", "-d", body],
        capture_output=True, text=True, check=True,
    )
    data = json.loads(proc.stdout)
    if "trip" not in data:
        fail(f"라우팅 실패 (port {port}): {data}")
    return data["trip"]["summary"]["length"]


def test_overlay(overlay: dict, port: int) -> None:
    tt = overlay.get("target_test")
    if tt:
        km = run_route(port, tt["from"], tt["to"])
        if km < tt["min_length_km"]:
            fail(
                f"{overlay['id']}: target_test 실패 — {km:.3f}km "
                f"< 최소 {tt['min_length_km']}km (유령 경로가 그대로 남아있음)"
            )
        log(f"  target_test OK: {km:.3f}km >= {tt['min_length_km']}km ({tt['description']})")

    rt = overlay.get("regression_test")
    if rt:
        km = run_route(port, rt["from"], rt["to"])
        if km > rt["max_length_km"]:
            fail(
                f"{overlay['id']}: regression_test 실패 — {km:.3f}km "
                f"> 최대 {rt['max_length_km']}km (정상 경로가 우회당함)"
            )
        log(f"  regression_test OK: {km:.3f}km <= {rt['max_length_km']}km ({rt['description']})")


def find_free_port(start: int = 18060) -> int:
    import socket
    for p in range(start, start + 50):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1", p)) != 0:
                return p
    fail("사용 가능한 임시 포트를 못 찾음")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--custom-files", default="/data/valhalla/custom_files",
                     help="프로덕션 pbf/valhalla.json이 있는 디렉토리 (읽기 전용으로만 사용)")
    ap.add_argument("--staging-dir", default="/data/valhalla/staging_impossible_turns")
    ap.add_argument("--image", default=None, help="기본값: docker-compose.yml에서 읽음")
    ap.add_argument("--korea-only", action="store_true",
                     help="일본 pbf 없이 한국만 빌드 (빠른 검증용, 프로덕션 반영 전엔 끄고 재실행할 것)")
    args = ap.parse_args()

    custom_files = Path(args.custom_files)
    korea_pbf = custom_files / "south-korea-latest.osm.pbf"
    japan_pbf = None if args.korea_only else custom_files / "japan-latest.osm.pbf"
    base_config = custom_files / "valhalla.json"
    manifest_path = OVERLAY_DIR / "manifest.yaml"
    staging_dir = Path(args.staging_dir)

    for p in [korea_pbf, base_config, manifest_path] + ([japan_pbf] if japan_pbf else []):
        if not p.exists():
            fail(f"필수 파일 없음: {p}")

    manifest = yaml.safe_load(manifest_path.read_text())
    overlays = manifest["overlays"]
    image = args.image or read_prod_image()
    log(f"image={image} overlays={[o['id'] for o in overlays]} korea_only={args.korea_only}")

    staging_dir.mkdir(parents=True, exist_ok=True)

    log("=== 1. verify: 기준 node/way id가 여전히 유효한지 확인 ===")
    for o in overlays:
        log(f"- {o['id']}")
        verify_overlay(o, korea_pbf, staging_dir)

    log("=== 2. apply: osmium apply-changes + sort ===")
    patched_pbf = build_patched_pbf(overlays, korea_pbf, staging_dir)

    log("=== 3. build: 격리 tile_dir에 valhalla_build_tiles ===")
    build_tiles(image, staging_dir, patched_pbf, japan_pbf, base_config)

    log("=== 4. test: 임시 컨테이너로 target/regression 검사 ===")
    port = find_free_port()
    container = f"poc_overlay_test_{port}"
    subprocess.run(["docker", "rm", "-f", container], capture_output=True)
    run(["docker", "run", "-d", "--name", container, "-p", f"{port}:8002",
         "-v", f"{staging_dir}:/work", image,
         "valhalla_service", "/work/valhalla_staging.json", "1"])
    try:
        time.sleep(3)
        for o in overlays:
            log(f"- {o['id']}")
            test_overlay(o, port)
    finally:
        subprocess.run(["docker", "rm", "-f", container], capture_output=True)

    marker = staging_dir / "LAST_VERIFIED_PASS"
    marker.write_text(
        f"pbf={patched_pbf}\nimage={image}\nkorea_only={args.korea_only}\n"
        f"overlays={[o['id'] for o in overlays]}\ntimestamp={time.strftime('%Y-%m-%dT%H:%M:%S')}\n"
    )
    log(f"=== PASS === staged tiles: {staging_dir / 'tiles'}")
    log("프로덕션 반영은 이 스크립트가 하지 않음 — "
        "swap_production_tiles.sh를 사람이 직접 확인 후 실행할 것 "
        "(korea-only 모드였다면 --korea-only 없이 재실행부터).")


if __name__ == "__main__":
    main()
