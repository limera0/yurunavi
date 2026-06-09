import json
import os
from pathlib import Path

import streamlit as st
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

from core.config import load_config, save_config
from core.valhalla_client import route, build_costing_options
from core.metrics import road_class_distribution

st.set_page_config(page_title="Yurunavi Tuning Dashboard", layout="wide")
st.title("Yurunavi 라우팅 파인튜닝 대시보드")

STYLE_URL = os.environ.get(
    "TILESERVER_STYLE_URL",
    "https://tiles.westinx.com/styles/osm_liberty_yurunavi/style.json",
)

PROFILE_LABELS = {
    "rural":      "시골길 우선 (Rural)",
    "provincial": "지방도 우선 (Provincial)",
    "national":   "국도 우선 (National)",
}

ROAD_CLASS_LABELS = {
    "0": "고속도로 (Motorway)",
    "1": "고속화도로 (Trunk)",
    "2": "일반국도 (Primary)",
    "3": "지방도 (Secondary)",
    "4": "시군도/시골길 (Tertiary)",
    "5": "미분류도로 (Unclassified)",
    "6": "주거도로 (Residential)",
    "7": "서비스도로 (ServiceOther)",
}

# ── session_state 초기화 ──────────────────────────────────────────────────────
if "cfg" not in st.session_state:
    st.session_state.cfg = load_config()
if "result" not in st.session_state:
    st.session_state.result = None  # {profile_name: {coords, distance_km, time_s, ...}}
if "error_msg" not in st.session_state:
    st.session_state.error_msg = None


def _build_map_html(routes_geojson: dict, loading: bool = False) -> str:
    tpl = (Path(__file__).parent / "components" / "maplibre_map.html").read_text()
    tpl = tpl.replace("{{STYLE_URL}}", STYLE_URL)
    tpl = tpl.replace("{{ROUTES_JSON}}", json.dumps(routes_geojson or {"type": "FeatureCollection", "features": []}))
    tpl = tpl.replace("{{SHOW_LOADING}}", "true" if loading else "false")
    return tpl


def _routes_to_geojson(results: dict, cfg: dict) -> dict:
    features = []
    for pname, res in results.items():
        coords_lonlat = [[c[1], c[0]] for c in res["coords"]]  # [lat,lon]→[lon,lat]
        features.append({
            "type": "Feature",
            "properties": {
                "profile": pname,
                "color": cfg["profiles"][pname]["color"],
                "label": PROFILE_LABELS.get(pname, pname),
                "distance_km": res["distance_km"],
                "time_s": res["time_s"],
            },
            "geometry": {"type": "LineString", "coordinates": coords_lonlat},
        })
    return {"type": "FeatureCollection", "features": features}


# ── 레이아웃 ──────────────────────────────────────────────────────────────────
left, right = st.columns([5, 4], gap="medium")

# ══════════════════════════ 왼쪽: 경로 입력 + 지도 ══════════════════════════
with left:
    st.subheader("출발/목적지")
    c1, c2 = st.columns(2)
    with c1:
        origin_lat = st.number_input("출발 위도", value=float(os.environ.get("DEFAULT_ORIGIN_LAT", 37.5547)),
                                     format="%.6f", step=0.001, key="origin_lat")
        origin_lon = st.number_input("출발 경도", value=float(os.environ.get("DEFAULT_ORIGIN_LON", 126.9706)),
                                     format="%.6f", step=0.001, key="origin_lon")
    with c2:
        dest_lat = st.number_input("도착 위도", value=float(os.environ.get("DEFAULT_DEST_LAT", 37.5306)),
                                   format="%.6f", step=0.001, key="dest_lat")
        dest_lon = st.number_input("도착 경도", value=float(os.environ.get("DEFAULT_DEST_LON", 127.3214)),
                                   format="%.6f", step=0.001, key="dest_lon")

    st.markdown("---")
    st.subheader("지도 (모바일 비율)")

    # 에러 표시
    if st.session_state.error_msg:
        st.error(st.session_state.error_msg)

    # 지도 렌더
    geojson = {}
    if st.session_state.result:
        geojson = _routes_to_geojson(st.session_state.result, st.session_state.cfg)
    map_html = _build_map_html(geojson)
    st.components.v1.html(map_html, height=780)

    # 경로 지표 (결과 있을 때)
    if st.session_state.result:
        st.subheader("경로 요약")
        cols = st.columns(len(st.session_state.result))
        for i, (pname, res) in enumerate(st.session_state.result.items()):
            color = st.session_state.cfg["profiles"][pname]["color"]
            with cols[i]:
                st.markdown(f"**:{color[1:]}[{PROFILE_LABELS.get(pname, pname)}]**")
                st.metric("거리", f"{res['distance_km']:.1f} km")
                mins = int(res["time_s"] // 60)
                st.metric("예상 시간", f"{mins}분")

        # 도로등급 분포 (선택)
        with st.expander("도로등급 분포 (trace_attributes)"):
            for pname, res in st.session_state.result.items():
                st.write(f"**{PROFILE_LABELS.get(pname, pname)}**")
                dist = road_class_distribution(res["coords"])
                if "error" in dist:
                    st.warning(f"trace_attributes 실패: {dist['error']}")
                else:
                    st.dataframe(
                        {"도로 종류": list(dist.keys()), "비율(%)": list(dist.values())},
                        use_container_width=True,
                    )


# ══════════════════════════ 오른쪽: 가중치 패널 ══════════════════════════════
with right:
    st.subheader("가중치 조절")

    tabs = st.tabs([PROFILE_LABELS[p] for p in ["rural", "provincial", "national"]])

    for tab, pname in zip(tabs, ["rural", "provincial", "national"]):
        with tab:
            profile = st.session_state.cfg["profiles"][pname]

            st.markdown("##### 도로 등급별 비용 배율 (낮을수록 선호)")
            new_cf = {}
            for k in [str(i) for i in range(8)]:
                label = ROAD_CLASS_LABELS.get(k, f"class_{k}")
                val = float(profile["class_factors"].get(k, 1.0))
                new_cf[k] = st.number_input(
                    label, min_value=0.1, max_value=20.0, value=val,
                    step=0.1, format="%.2f",
                    key=f"{pname}_cf_{k}",
                )
            profile["class_factors"] = new_cf

            st.markdown("##### 특성 파라미터")
            profile["curvature_penalty"] = st.number_input(
                "굽은길 선호도 (curvature_penalty, 높을수록 굽은길 선호)",
                min_value=0.0, max_value=10.0,
                value=float(profile.get("curvature_penalty", 0.0)),
                step=0.1, format="%.2f",
                key=f"{pname}_curv",
            )
            profile["long_bridge_factor"] = st.number_input(
                "긴 교량 회피 정도 (long_bridge_factor, 1.0=중립, >1=회피)",
                min_value=0.0, max_value=20.0,
                value=float(profile.get("long_bridge_factor", 1.0)),
                step=0.1, format="%.2f",
                key=f"{pname}_bridge",
            )
            profile["long_tunnel_factor"] = st.number_input(
                "긴 터널 회피 정도 (long_tunnel_factor, 1.0=중립, >1=회피)",
                min_value=0.0, max_value=20.0,
                value=float(profile.get("long_tunnel_factor", 1.0)),
                step=0.1, format="%.2f",
                key=f"{pname}_tunnel",
            )
            profile["span_min_length"] = int(st.number_input(
                "교량/터널 최소 적용 길이 (span_min_length, 미터)",
                min_value=0, max_value=5000,
                value=int(profile.get("span_min_length", 500)),
                step=50,
                key=f"{pname}_span",
            ))
            profile["use_highways"] = st.number_input(
                "고속도로 사용 선호도 (use_highways, 0=회피, 1=선호)",
                min_value=0.0, max_value=1.0,
                value=float(profile.get("use_highways", 0.0)),
                step=0.1, format="%.2f",
                key=f"{pname}_hw",
            )
            profile["use_tolls"] = st.number_input(
                "유료도로 사용 선호도 (use_tolls, 0=회피, 1=선호)",
                min_value=0.0, max_value=1.0,
                value=float(profile.get("use_tolls", 0.0)),
                step=0.1, format="%.2f",
                key=f"{pname}_tolls",
            )

    st.markdown("---")

    # 디버그: 현재 costing_options
    with st.expander("현재 costing_options (JSON)"):
        for pname in ["rural", "provincial", "national"]:
            st.write(f"**{pname}**")
            st.json(build_costing_options(st.session_state.cfg["profiles"][pname]))

    # ── 경로 테스트 버튼 ────────────────────────────────────────────────────
    if st.button("🗺️ 경로 테스트 (3 프로파일)", type="primary", use_container_width=True):
        save_config(st.session_state.cfg)
        results = {}
        errors = []
        origin = (origin_lat, origin_lon)
        dest   = (dest_lat,   dest_lon)

        progress = st.progress(0, text="라우팅 계산 중...")
        for i, pname in enumerate(["rural", "provincial", "national"]):
            progress.progress((i + 1) / 3, text=f"{PROFILE_LABELS[pname]} 계산 중...")
            try:
                res = route(origin, dest, st.session_state.cfg["profiles"][pname])
                results[pname] = res
            except Exception as e:
                errors.append(f"{pname}: {e}")
        progress.empty()

        if errors:
            st.session_state.error_msg = "라우팅 오류: " + " | ".join(errors)
        else:
            st.session_state.error_msg = None

        st.session_state.result = results if results else None
        st.rerun()
