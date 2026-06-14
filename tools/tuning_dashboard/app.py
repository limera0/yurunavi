import hashlib
import http.server
import json
import os
import socketserver
import threading
from pathlib import Path

import streamlit as st
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

from core.config import load_config, save_config
from core.valhalla_client import route, build_costing_options
from core.metrics import road_class_distribution

st.set_page_config(page_title="Yurunavi Tuning Dashboard", layout="wide")
st.title("Yurunavi 라우팅 파인튜닝 대시보드")

TILESERVER_BASE = os.environ.get("TILESERVER_BASE_URL", "http://192.168.0.57:8080")

# 로컬 스타일 JSON 로드 + 소스/글립 URL을 로컬 타일서버로 패치
# Docker: 볼륨 마운트 ../../assets → /app/assets
# Dev:    ../../assets = /data/projects/yurunavi/assets
_default_style = Path(__file__).parent / "assets" / "images" / "osm_liberty_yurunavi.json"
if not _default_style.exists():
    _default_style = Path(__file__).parent.parent.parent / "assets" / "images" / "osm_liberty_yurunavi.json"
_STYLE_FILE = Path(os.environ.get("STYLE_FILE_PATH", str(_default_style)))

# -- map render sidecar HTTP server --------------------------------------------
# components.html() injects map HTML as srcdoc; a srcdoc iframe has a "null"
# (opaque) origin, where MapLibre's vector-tile Web Worker cannot issue network
# requests, so the map stalls at "초기화 중..." (raster/sprite work since they
# run on the main thread). Fix: serve the map from a real-origin URL and embed
# via components.iframe(src=...).
PUBLIC_HOST = os.environ.get("DASHBOARD_PUBLIC_HOST", "192.168.0.57")
DASHBOARD_PORT = int(os.environ.get("DASHBOARD_PORT", "8501"))
MAP_SERVER_PORT = int(os.environ.get("MAP_SERVER_PORT", "8502"))
SPRITE_BASE = os.environ.get("SPRITE_BASE", f"http://{PUBLIC_HOST}:{DASHBOARD_PORT}")
MAP_SERVER_BASE = os.environ.get("MAP_SERVER_BASE", f"http://{PUBLIC_HOST}:{MAP_SERVER_PORT}")
_MAP_RENDERS_MAX = 8


@st.cache_resource
def _map_store() -> dict:
    return {"renders": {}, "order": []}


@st.cache_resource
def _start_map_server():
    store = _map_store()

    class _Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            token = self.path.lstrip("/").split("?", 1)[0]
            html = store["renders"].get(token)
            if html is None:
                self.send_response(404)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                return
            body = html.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    httpd = socketserver.ThreadingTCPServer(("0.0.0.0", MAP_SERVER_PORT), _Handler)
    httpd.daemon_threads = True
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def _publish_map(html: str) -> str:
    _start_map_server()
    store = _map_store()
    token = hashlib.sha1(html.encode("utf-8")).hexdigest()[:16] + ".html"
    if token not in store["renders"]:
        store["renders"][token] = html
        store["order"].append(token)
        while len(store["order"]) > _MAP_RENDERS_MAX:
            store["renders"].pop(store["order"].pop(0), None)
    return f"{MAP_SERVER_BASE}/{token}"

def _load_style_obj() -> dict:
    with open(_STYLE_FILE, encoding="utf-8") as f:
        s = json.load(f)
    # TileJSON URL 방식 대신 tiles 배열 직접 인라인 → cross-origin TileJSON fetch 제거
    for src in s.get("sources", {}).values():
        if src.get("type") == "vector" and "url" in src and "v3" in src["url"]:
            src.pop("url", None)
            src["tiles"] = [f"{TILESERVER_BASE}/data/v3/{{z}}/{{x}}/{{y}}.pbf"]
            src["minzoom"] = 0
            src["maxzoom"] = 14
    # 글립 → 로컬 tileserver
    if "glyphs" in s:
        s["glyphs"] = f"{TILESERVER_BASE}/fonts/{{fontstack}}/{{range}}.pbf"
    # sprite: served from the map sidecar (separate origin) -> use absolute URL.
    # Streamlit static (8501) sends CORS(*), so cross-origin load works.
    s["sprite"] = f"{SPRITE_BASE}/app/static/sprites/osm-liberty"
    return s

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
    style_obj = _load_style_obj()
    tpl = tpl.replace("{{STYLE_OBJ}}", json.dumps(style_obj))
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
    map_src = _publish_map(map_html)
    st.components.v1.iframe(map_src, height=780)

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
