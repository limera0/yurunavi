#!/usr/bin/env python3
"""
Convert the raw zone-centric rear-camera source data into a flat, per-unit
rear-camera dataset for YuruNavi's rear-camera warning feature (release item 18).

Output: assets/data/rear_cameras.json (already generated and committed —
the raw input has since been deleted, so this script can no longer be re-run).

Each input "zone" object may contain multiple camera "units" in its `a` array.
Each unit is expanded into its own output record, using the unit's own
lat/lng (not the zone's centroid), with the parent zone's `v` (speed limit,
km/h) and `d` (post-zone range, m) carried down.

Known data quirk: 3 of 1458 zones have `d == 0` at the zone level (raw data
artifact — the source app defaults to 90m when this happens, and 90m is
already the value for 94% of zones). This script falls back to 90m for
those zones so that no output record has a zero/null postZoneM. This
fallback is called out explicitly in this docstring and in the run log.
"""
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
RAW_PATH = REPO_ROOT / "assets" / "data" / "rear_camera_raw_source.json"
OUT_PATH = REPO_ROOT / "assets" / "data" / "rear_cameras.json"

DEFAULT_POST_ZONE_M = 90


def main() -> None:
    with RAW_PATH.open(encoding="utf-8") as f:
        zones = json.load(f)

    records = []
    zero_d_fallback_count = 0

    for zone in zones:
        speed_kmh = zone["v"]
        post_zone_m = zone["d"]
        if not post_zone_m:
            # Zone-level `d` missing/zero — fall back to the dataset's
            # dominant default (90m). See module docstring.
            post_zone_m = DEFAULT_POST_ZONE_M
            zero_d_fallback_count += 1

        for unit in zone["a"]:
            records.append(
                {
                    "lat": unit["lat"],
                    "lng": unit["lng"],
                    "speedKmh": speed_kmh,
                    "postZoneM": post_zone_m,
                }
            )

    OUT_PATH.write_text(
        json.dumps(records, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"zones read: {len(zones)}")
    print(f"unit records written: {len(records)}")
    print(f"zones with zero/missing 'd' -> fell back to {DEFAULT_POST_ZONE_M}m: {zero_d_fallback_count}")
    print(f"output: {OUT_PATH}")


if __name__ == "__main__":
    main()
