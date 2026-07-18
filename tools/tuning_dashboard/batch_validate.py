"""
3코스(시골길/지방도/국도) 정체성 튜닝용 배치 검증 스크립트.

5개 실측 OD × 3코스를 대상 Valhalla 인스턴스에 돌려서:
  - 코스별 도로등급 구성비(거리 가중), 총 거리/시간
  - 코스별 span 임계치(시골길 300m/지방도 1000m) 이상 교량·터널 회피 여부
  - 코스 쌍별 겹침률(%, way_id 공유 구간 근사)
  - 판정: 국도 코스 길이 > 10km인 OD에서 세 코스 쌍 겹침률 모두 < 10%인가
를 표로 출력한다.

사용법:
  VALHALLA_URL=http://localhost:8002 python3 batch_validate.py
  VALHALLA_URL=http://localhost:8016 python3 batch_validate.py   # 임시 검증 포트 대상
"""
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

from core.config import load_config
from core.valhalla_client import route
from core.metrics import trace_edges, distribution_from_edges, long_structure_spans_from_edges
from core.overlap import route_overlap

TEST_ODS = [
    ("송탄→팔당", (37.07328, 127.04747), (37.55612, 127.23657)),
    ("행촌동→강릉안목", (37.57481, 126.96196), (37.77084, 128.94993)),
    ("판교→무릉", (37.40459, 127.12035), (37.25445, 128.77929)),
    ("일산화정→강화석모도", (37.63163, 126.82495), (37.70934, 126.27884)),
    ("청파동→춘천레고랜드", (37.55338, 126.96680), (37.88661, 127.71461)),
]

# 코스별 장대교량/터널 회피 검증 임계치(m). None이면 검사 안 함(국도는 회피 대상 아님).
SPAN_THRESHOLDS = {"rural": 300, "provincial": 1000, "national": None}

PROFILE_ORDER = ["rural", "provincial", "national"]
OVERLAP_PAIRS = [("rural", "provincial"), ("provincial", "national"), ("rural", "national")]
NATIONAL_LENGTH_GATE_KM = 10.0
OVERLAP_LIMIT_PCT = 10.0


def main():
    base_url = os.environ.get("VALHALLA_URL", "http://localhost:8002")
    print(f"대상 Valhalla: {base_url}\n")
    cfg = load_config()
    overall_pass = True

    for label, origin, dest in TEST_ODS:
        print(f"{'=' * 78}\n{label}  {origin} → {dest}\n{'=' * 78}")

        results = {}
        edges_cache = {}
        for pname in PROFILE_ORDER:
            try:
                res = route(origin, dest, cfg["profiles"][pname], base_url=base_url)
            except Exception as e:
                print(f"  [{pname:11s}] 라우팅 실패: {e}")
                overall_pass = False
                continue
            results[pname] = res
            try:
                edges = trace_edges(res["coords"], base_url=base_url,
                                     distance_km=res["distance_km"])
            except Exception as e:
                print(f"  [{pname:11s}] trace_attributes 실패: {e}")
                edges = []
            edges_cache[pname] = edges
            dist = distribution_from_edges(edges)
            print(
                f"  [{pname:11s}] {res['distance_km']:6.1f}km  "
                f"{res['time_s'] / 60:5.1f}min  구성비(%)={dist}"
            )
            span_m = SPAN_THRESHOLDS[pname]
            if span_m:
                spans = long_structure_spans_from_edges(edges, span_m)
                b, t = spans["bridge"], spans["tunnel"]
                if b["count"] or t["count"]:
                    print(
                        f"    ⚠ {span_m}m↑ 교량 {b['count']}건/{b['total_m']:.0f}m, "
                        f"터널 {t['count']}건/{t['total_m']:.0f}m"
                    )

        if len(results) < 3:
            print("  (일부 코스 실패 — 겹침률 판정 스킵)\n")
            continue

        national_km = results["national"]["distance_km"]
        gate_active = national_km > NATIONAL_LENGTH_GATE_KM
        print(f"  국도 {national_km:.1f}km "
              f"({'>' if gate_active else '<='} {NATIONAL_LENGTH_GATE_KM}km "
              f"→ 겹침률 게이트 {'적용' if gate_active else '미적용'})")
        for a, b in OVERLAP_PAIRS:
            ov = route_overlap(edges_cache[a], edges_cache[b])
            flag = ""
            if gate_active and ov["pct_max"] >= OVERLAP_LIMIT_PCT:
                flag = f"  ❌ FAIL (≥{OVERLAP_LIMIT_PCT}%)"
                overall_pass = False
            print(f"  겹침 {a}-{b}: a기준 {ov['pct_of_a']}% / b기준 {ov['pct_of_b']}%{flag}")
        print()

    print(f"{'=' * 78}\n전체 판정: {'PASS' if overall_pass else 'FAIL'}\n{'=' * 78}")
    return 0 if overall_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
