# 지도가 "초기화 중..."에서 멈추는 문제 — 디버깅 회고 (Post-mortem)

- **날짜:** 2026-06-10
- **대상:** `tools/tuning_dashboard` (Yurunavi 라우팅 파인튜닝 대시보드, Streamlit + MapLibre GL JS)
- **증상:** 대시보드 왼쪽 "지도 (모바일 비율)" 영역이 항상 빈 회색이며 상태 표시가 `초기화 중...`에서 멈춤. 에러 박스는 안 뜸.
- **결론(한 줄):** 스타일/타일/스프라이트는 전부 정상. 진범은 **Streamlit `components.html()`이 지도를 `srcdoc` iframe(=opaque "null" origin)으로 주입**해서, **MapLibre의 벡터타일 Web Worker가 네트워크 요청을 만들지 못한** 것.

---

## 1. 최초 코드 (Before)

### app.py — 지도 렌더
```python
def _load_style_obj() -> dict:
    with open(_STYLE_FILE, encoding="utf-8") as f:
        s = json.load(f)
    # 벡터 소스 url → 로컬 타일서버 tiles 배열로 인라인
    for src in s.get("sources", {}).values():
        if src.get("type") == "vector" and "url" in src and "v3" in src["url"]:
            src.pop("url", None)
            src["tiles"] = [f"{TILESERVER_BASE}/data/v3/{{z}}/{{x}}/{{y}}.pbf"]
            src["minzoom"] = 0
            src["maxzoom"] = 14
    if "glyphs" in s:
        s["glyphs"] = f"{TILESERVER_BASE}/fonts/{{fontstack}}/{{range}}.pbf"
    s.pop("sprite", None)          # ← sprite는 HTML에서 동적 주입
    return s

# ...
map_html = _build_map_html(geojson)
st.components.v1.html(map_html, height=780)   # ← 문제의 핵심: srcdoc 주입
```

### components/maplibre_map.html — sprite 주입
```html
<script>
const STYLE_OBJ  = {{STYLE_OBJ}};
// ...
var _origin;
try { _origin = parent.location.origin; } catch(e) { _origin = window.location.origin; }
STYLE_OBJ.sprite = _origin + "/app/static/sprites/osm-liberty";

let map = new maplibregl.Map({ container: "map", style: STYLE_OBJ, /* ... */ });
map.on("load",  () => statusEl.textContent = "지도 로드 완료");
map.on("error", (e) => showErr(e.error && e.error.message));
</script>
```

`st.components.v1.html(html_string)`은 내부적으로 `<iframe srcdoc="...">`로 렌더된다. 이 한 줄이 모든 문제의 원인이었다.

---

## 2. 증상 정밀 관찰

- 상태 표시는 `초기화 중...` 고정. `map.on("error")`도 `window.onerror`도 발화 안 함 → **조용히 멈춤(silent hang)**.
- 캔버스(`<canvas>`)는 생성됨. 즉 MapLibre 객체는 만들어졌지만 `load` 이벤트가 영영 안 옴.
- 헤드리스/실제 브라우저(앞으로 띄움) 모두 동일하게 멈춤 → 단순 환경 문제가 아닌 **재현 가능한 진짜 버그**.

---

## 3. 진단 과정 + 헛다리 (정직한 타임라인)

### 헛다리 ① — "외부 타일(klokantech)이 안 열리는 것 아닐까?"
스타일에 `natural_earth_shaded_relief` 래스터 소스가 외부(`klokantech.github.io`)를 가리키고 있어 이걸 의심.
→ **검증:** 브라우저에서 직접 `Image()` 로드 + `fetch()` 테스트. 결과 **512×512 정상 로드, fetch 200, CORS OK**.
→ **기각.** 외부 타일은 멀쩡했다.

### 헛다리 ② — "숨은 탭이라 멈춘 것 아닐까?" (= 진짜 헛다리, 동시에 진짜 함정)
디버깅용으로 띄운 Chrome 탭에서 테스트했는데, **최소 스타일(배경색만)조차 로드가 안 됨**.
→ `document.visibilityState`를 찍어보니 **`"hidden"`**. 창이 다른 창에 완전히 가려져 Chrome의 occlusion 감지가 탭을 hidden 처리.
→ **MapLibre의 렌더 루프는 `requestAnimationFrame` 기반인데, hidden 탭에서는 rAF가 멈춘다.** 게다가 MapLibre v4는 스타일 `_load`조차 rAF 안에서 돌기 때문에, hidden 탭에서는 `styledata`/`load`가 영영 안 뜬다.
→ **교훈:** 이 시점까지의 브라우저 테스트 결과는 전부 **오염된 데이터**였다. "최소 스타일도 안 뜬다"는 건 스타일 문제가 아니라 단지 rAF가 멈춘 신호였다.
- ⚠️ 단, 이건 별개의 진짜 함정이기도 하다: **가려진(occluded) 탭에서는 MapLibre 지도가 안 그려진다.** 사용자 탭이 다른 창에 완전히 가려져 있으면 같은 증상이 날 수 있다.

### 헛다리 ③ — 잘못된 정규식으로 스타일을 잘라 읽어 "소스가 없다"는 가짜 에러
iframe `srcdoc`에서 `STYLE_OBJ`를 정규식으로 추출하다 비탐욕(non-greedy) 매칭이 너무 일찍 끊겨 `sources`가 빈 객체로 파싱됨 → `There is no source with ID 'openmaptiles'` 가짜 에러.
→ **기각.** 서버에서 파이썬으로 최종 스타일을 직접 계산해 확인: 소스 2개·레이어 105개 모두 정상.

### 전환점 — "추측 그만, 제대로 재현하자"
1. **서버 사이드 진실 확보:** 파이썬으로 최종 스타일을 직접 덤프 → 유효함 확인.
2. **모든 리소스 직접 검증:** 타일(`.pbf`)·글리프·스프라이트·외부 래스터 전부 `200 + Access-Control-Allow-Origin: *`.
3. **rAF 함정 제거:** 서버에 깔려 있던 **Playwright(headless Chromium)**로 전환. 헤드리스 Chromium은 렌더 루프가 정상 동작 → 깨끗한 재현 환경 확보.

### 결정적 실험들 (headless)
| 실험 | 환경 | 결과 |
|---|---|---|
| A | 일반 페이지 + 동일 스타일 | ✅ `load` 발생, 벡터/래스터 모두 로드 |
| B | `srcdoc` iframe + 유효 origin | ❌ `초기화 중...`, **`.pbf` 요청 0건** |
| C | `srcdoc` iframe, sandbox 없음 | ❌ 동일하게 멈춤 → **sandbox 문제 아님** |
| D | 실제 `src` URL iframe + sandbox | ✅ **`.pbf` 요청 발생, `지도 로드 완료`** |

내부 상태 인트로스펙션 결과가 스모킹건이었다:
```
imageManager.isLoaded = true                  # 스프라이트 OK
sourceCache["natural_earth..."].loaded = true # 래스터 OK (메인 스레드)
sourceCache["openmaptiles"].loaded   = false  # 벡터 NG  ← 여기!
→ 네트워크 캡처: .pbf 요청 0건
```

---

## 4. 근본 원인

**MapLibre는 벡터타일을 Web Worker에서 받아 파싱한다. 래스터타일/스프라이트/글리프는 메인 스레드에서 처리한다.**

`st.components.v1.html()`이 만든 `srcdoc` iframe은 문서의 **origin이 `"null"`(opaque)**이다. opaque origin 컨텍스트에서는 MapLibre가 (blob URL로) 생성하는 **Web Worker가 정상 동작/네트워크 요청을 하지 못한다.**

그 결과:
- 메인 스레드 리소스(래스터·스프라이트·글리프)는 **정상** → 그래서 **에러가 안 떴다.**
- 벡터타일은 Worker라서 `.pbf` 요청이 **0건** → `openmaptiles` 소스가 영영 `loaded=false` → `map`의 `load` 이벤트 미발화 → 상태 `초기화 중...` 고정.

> 핵심 구분: 문제는 `sandbox` 속성이 아니라 **`srcdoc`에서 비롯된 opaque origin**이었다(실험 C·D로 분리 확인).

---

## 5. 최종 해결 방안 (After)

**아이디어:** 지도를 `srcdoc`이 아니라 **실제 origin을 갖는 URL**로 서빙하고 `components.iframe(src=...)`로 임베드한다.
`docker-compose`가 `network_mode: host`라 컨테이너 안에서 포트만 열면 호스트에서 바로 접근 가능(포트 매핑 불필요).

### app.py — 경량 사이드카 HTTP 서버 추가
```python
PUBLIC_HOST     = os.environ.get("DASHBOARD_PUBLIC_HOST", "192.168.0.57")
DASHBOARD_PORT  = int(os.environ.get("DASHBOARD_PORT", "8501"))
MAP_SERVER_PORT = int(os.environ.get("MAP_SERVER_PORT", "8502"))
SPRITE_BASE     = os.environ.get("SPRITE_BASE",     f"http://{PUBLIC_HOST}:{DASHBOARD_PORT}")
MAP_SERVER_BASE = os.environ.get("MAP_SERVER_BASE", f"http://{PUBLIC_HOST}:{MAP_SERVER_PORT}")

@st.cache_resource                      # 리런 간 공유 (싱글턴)
def _map_store() -> dict:
    return {"renders": {}, "order": []} # token -> html

@st.cache_resource                      # 서버는 프로세스당 1회만 기동
def _start_map_server():
    store = _map_store()
    class _Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            token = self.path.lstrip("/").split("?", 1)[0]
            html = store["renders"].get(token)
            if html is None:
                self.send_response(404); self.send_header("Access-Control-Allow-Origin","*"); self.end_headers(); return
            body = html.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")  # ← 진짜 text/html
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers(); self.wfile.write(body)
        def log_message(self, *a): pass
    httpd = socketserver.ThreadingTCPServer(("0.0.0.0", MAP_SERVER_PORT), _Handler)
    httpd.daemon_threads = True; httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd

def _publish_map(html: str) -> str:
    _start_map_server()
    store = _map_store()
    token = hashlib.sha1(html.encode("utf-8")).hexdigest()[:16] + ".html"
    if token not in store["renders"]:
        store["renders"][token] = html
        store["order"].append(token)
        while len(store["order"]) > _MAP_RENDERS_MAX:   # 최근 N개만 유지
            store["renders"].pop(store["order"].pop(0), None)
    return f"{MAP_SERVER_BASE}/{token}"
```

### app.py — 렌더 호출 교체
```python
map_html = _build_map_html(geojson)
map_src  = _publish_map(map_html)                 # 토큰 등록 → 실제 URL
st.components.v1.iframe(map_src, height=780)       # srcdoc 대신 src
```

### app.py — sprite를 절대 URL로
```python
# (변경 전) s.pop("sprite", None)
# (변경 후) 지도 iframe origin(8502)과 다른 8501에서 받지만 CORS(*) 허용됨
s["sprite"] = f"{SPRITE_BASE}/app/static/sprites/osm-liberty"
```

### components/maplibre_map.html — origin 기반 sprite 주입 제거
```html
<!-- 제거: parent.location.origin 으로 sprite 만들던 코드 -->
<!-- sprite 는 app.py 에서 STYLE_OBJ.sprite 절대 URL 로 이미 주입됨 -->
```
> 이유: `components.iframe(src=8502)`이면 지도 iframe은 8501과 **cross-origin**이라 `parent.location.origin` 접근이 SecurityError → 잘못된 sprite URL이 된다. 그래서 서버에서 절대 URL로 못박는다.

### 배포
`COPY . .` 방식이라 `app.py`/템플릿 변경은 이미지 재빌드 필요:
```bash
docker compose up -d --build
```

---

## 6. 검증 (headless, rAF 정상 동작 환경)

라이브 대시보드(`:8501`)를 Playwright로 띄워 확인:
```
FRAMES: ["http://192.168.0.57:8501/", "http://192.168.0.57:8502/<token>.html"]
MAP FRAME: {"status":"지도 로드 완료","err":"","canvas":true}
pbfRequests = 8   spriteRequests = 2
```
→ 지도 iframe이 **실제 origin(8502)**, 상태 **`지도 로드 완료`**, **벡터타일 정상 로드**, 도로망 렌더 확인.

---

## 7. 교훈 / 체크리스트

1. **Streamlit + 지도/WebWorker 라이브러리 = 함정.** `st.components.v1.html()`은 `srcdoc`(opaque origin)이라 Web Worker가 죽는다. MapLibre/Mapbox/deck.gl 등은 **실제 URL을 `components.iframe(src=...)`로 임베드**할 것.
2. **"에러가 없다"가 곧 "정상"은 아니다.** 메인 스레드 리소스만 성공하면 에러 없이 조용히 멈출 수 있다. 증상을 "벡터=Worker / 래스터=메인스레드"로 쪼개니 원인이 드러났다.
3. **추측 말고 재현.** 외부 타일·정규식·숨은 탭으로 세 번 헛다리. 깨끗한 재현 환경(headless Chromium)을 확보한 뒤에야 진실이 보였다.
4. **테스트 환경 자체가 변수다.** 가려진 탭은 rAF가 멈춰 MapLibre가 안 뜬다(`document.visibilityState` 확인). 디버깅 도구의 부작용을 의심하라.
5. **레이어별로 좁혀라.** `sourceCache[id].loaded()`, `imageManager.isLoaded()` 같은 내부 상태 인트로스펙션이 "어디서 멈췄나"를 정확히 짚어준다.

---

## 8. 운영 메모

- 새 포트 **8502**(`MAP_SERVER_PORT`로 변경 가능). 사이드카 서버는 **첫 페이지 로드 시 lazy-start**(그 전엔 LISTEN 안 함).
- sprite/타일/글리프는 `8501`/`8080`에서 받지만 모두 `Access-Control-Allow-Origin: *`라 cross-origin OK. ufw 비활성(LAN 도달 정상).
- 백업: `app.py.bak`, `components/maplibre_map.html.bak`.
- 사용자 조치: 브라우저에서 대시보드 탭 **새로고침**.
