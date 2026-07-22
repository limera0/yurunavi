# Claude Code 작업 지시: 유루나비 스타일 AI 프록시 구축

## 배경
노트북 브라우저에서 여는 "스타일 튜너"에 자연어 명령창이 있다.
사용자가 "버스정류장 빼줘" 같이 입력하면 → 이 프록시가 OpenRouter LLM에 보내
MapLibre 스타일 변경 연산(ops)을 받아 돌려준다 → 튜너가 그 ops를 지도에 적용한다.
**API 키는 이 서버의 .env에만 두고 브라우저로 절대 내보내지 않는다.**

## 환경
- 서버: westinx (Ubuntu, Docker 사용 가능)
- 작업 위치: `/data/projects/yurunavi/tools/style-ai-proxy`
- 포트: **8014** (기존 8002/8003/8012/8013 과 충돌하지 않게 선택됨)

## 사용자(마스터)가 미리 준비할 것 — Claude Code는 작업 중 이걸 물어볼 것
- **OpenRouter API 키** (https://openrouter.ai/keys 에서 발급)

---

## 작업 단계 (Claude Code 수행)

1. 폴더 생성: `/data/projects/yurunavi/tools/style-ai-proxy`
2. 아래 **6개 파일을 그 폴더에 그대로 생성**한다 (내용은 이 문서 하단 참고).
   - `app.py`, `requirements.txt`, `Dockerfile`, `docker-compose.yml`, `.env.example`, `.gitignore`
3. `.env` 생성: `.env.example`을 복사한 뒤 `OPENROUTER_API_KEY` 값을 **마스터에게 물어서** 채운다.
   - ⚠️ 키 값을 로그로 출력하거나 git에 커밋하지 말 것.
4. 기동:
   ```bash
   cd /data/projects/yurunavi/tools/style-ai-proxy
   docker compose up -d --build
   ```
5. 검증 (두 줄 다 통과해야 함):
   ```bash
   curl -s localhost:8014/health
   # 기대: {"ok":true,"model":"...","key_loaded":true}

   curl -s -X POST localhost:8014/style-edit \
     -H 'Content-Type: application/json' \
     -d '{"command":"버스정류장 빼줘","layers":[
       {"id":"poi_z14","type":"symbol","source-layer":"poi","filter":["all",["==","$type","Point"],[">=","rank",1],["<","rank",7]]},
       {"id":"poi_transit","type":"symbol","source-layer":"poi","filter":["all",["in","class","bus","rail","airport"]]}
     ]}'
   # 기대: ops 안에 두 레이어 모두 ["!in","class","bus"] 가 추가된 setFilter
   ```
6. 결과(헬스체크 + 샘플 ops 결과)를 마스터에게 **한국어로** 보고한다.

---

## 마스터가 직접 해야 하는 것 (Claude Code는 못 함)
프록시는 westinx 서버에 있고 튜너는 노트북 브라우저에 있으므로, 노트북이 서버를 부를 주소가 필요하다. 둘 중 하나:

- **(어디서나 접속) Cloudflare 대시보드**에서 라우트 추가:
  `styleai.westinx.com → http://localhost:8014`
  (token 기반 tunnel이라 대시보드에서만 가능. 추가 후 튜너 "프록시 주소" 칸에 `https://styleai.westinx.com` 입력)
- **(같은 와이파이일 때)** 튜너 "프록시 주소" 칸에 `http://<westinx LAN IP>:8014` 입력
  (이 경우 튜너 HTML을 노트북에서 더블클릭(file://)으로 열 것 — https 페이지에서는 http 호출이 차단됨)

---

## 주의
- `.env`와 키를 git에 올리지 말 것 (`.gitignore`에 `.env` 포함됨).
- CORS는 개발용으로 `*`. 운영 시 `.env`의 `ALLOW_ORIGINS`를 튜너 주소로 좁힐 것.
- 모델 ID(`OPENROUTER_MODEL`)는 OpenRouter에서 현재 유효한 ID여야 함. 404가 나면 대시보드에서 확인 후 교체.

---

# 파일 내용

## app.py
```python
"""
유루나비 스타일 AI 프록시
- 브라우저(튜너)에서 자연어 명령 + 현재 레이어 목록을 받아
- OpenRouter LLM에 보내 "변경 연산 목록(ops)"을 받아 그대로 돌려준다.
- API 키는 .env(OPENROUTER_API_KEY)에서만 읽는다. 절대 클라이언트로 내보내지 않는다.
"""
import os
import json
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.environ.get("OPENROUTER_MODEL", "anthropic/claude-3.5-sonnet")
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
ALLOW_ORIGINS = os.environ.get("ALLOW_ORIGINS", "*").split(",")

SYSTEM_PROMPT = """너는 MapLibre GL JS 스타일 편집 어시스턴트다.
사용자의 한국어 자연어 명령과 현재 스타일 레이어 목록(layers)을 받아,
적용할 변경을 "연산 목록(ops)"으로만 출력한다.

반드시 아래 형태의 JSON 객체만 출력한다. 마크다운 코드펜스나 설명 문장을 JSON 밖에 쓰지 마라:
{
  "ops": [ ... ],
  "explanation": "무엇을 왜 바꿨는지 한국어 1~2문장"
}

ops 항목 종류(이 4가지만 사용):
- {"action":"setFilter","layer":"<id>","filter":<배열 또는 null>}
- {"action":"setPaint","layer":"<id>","prop":"<paint 속성명>","value":<값>}
- {"action":"setLayout","layer":"<id>","prop":"<layout 속성명>","value":<값>}
- {"action":"setZoomRange","layer":"<id>","minzoom":<숫자>,"maxzoom":<숫자>}

규칙:
- layer 값은 입력 layers에 실제로 존재하는 id만 쓴다. 없는 id를 만들어내지 마라.
- POI(class) 제외/포함은 source-layer가 "poi"인 모든 레이어에 일괄 적용한다.
  poi 레이어들은 rank로 섞여 있어 한 곳만 고치면 다른 레이어에서 다시 나타난다.
  버스정류장의 class는 "bus"다. 제외는 filter의 ["all", ...] 안에 ["!in","class", ...]를 넣는 방식으로 한다.
- filter는 항상 ["all", ...] 형태를 유지한다. 기존 조건을 보존하고 필요한 항목만 추가/교체한다.
- 색 값은 hex("#rrggbb") 또는 "rgba(...)" 문자열로 준다.
- 줌에 따라 달라지는 값은 ["interpolate",["linear"],["zoom"], z0,v0, z1,v1] 형태를 쓴다.
- 명령이 모호해 안전하게 바꿀 수 없으면 ops를 빈 배열로 두고, explanation에 무엇이 필요한지 묻는다.
"""

app = FastAPI(title="Yurunavi Style AI Proxy")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOW_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)


class EditReq(BaseModel):
    command: str
    layers: list


@app.get("/health")
def health():
    return {"ok": True, "model": OPENROUTER_MODEL, "key_loaded": bool(OPENROUTER_API_KEY)}


@app.post("/style-edit")
async def style_edit(req: EditReq):
    if not OPENROUTER_API_KEY:
        raise HTTPException(500, "OPENROUTER_API_KEY가 설정되지 않았습니다 (.env 확인)")

    user_payload = json.dumps(
        {"command": req.command, "layers": req.layers}, ensure_ascii=False
    )
    body = {
        "model": OPENROUTER_MODEL,
        "temperature": 0,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_payload},
        ],
    }
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://navi.westinx.com",
        "X-Title": "Yurunavi Style Tuner",
    }

    try:
        async with httpx.AsyncClient(timeout=90) as client:
            r = await client.post(OPENROUTER_URL, headers=headers, json=body)
    except httpx.HTTPError as e:
        raise HTTPException(502, f"OpenRouter 연결 실패: {e}")

    if r.status_code != 200:
        raise HTTPException(502, f"OpenRouter {r.status_code}: {r.text[:400]}")

    data = r.json()
    try:
        content = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError):
        raise HTTPException(502, f"예상치 못한 응답 형식: {json.dumps(data)[:400]}")

    content = content.strip()
    if content.startswith("```"):
        content = content.split("```", 2)[1] if "```" in content[3:] else content[3:]
        content = content.lstrip("json").strip().rstrip("`").strip()

    try:
        parsed = json.loads(content)
    except json.JSONDecodeError as e:
        raise HTTPException(502, f"모델 응답 JSON 파싱 실패: {e}; raw={content[:400]}")

    if not isinstance(parsed, dict) or "ops" not in parsed:
        raise HTTPException(502, f"ops 필드 없음: {content[:400]}")

    if "usage" in data:
        parsed["_usage"] = data["usage"]
    parsed["_model"] = OPENROUTER_MODEL
    return parsed
```

## requirements.txt
```
fastapi==0.115.6
uvicorn[standard]==0.34.0
httpx==0.28.1
```

## Dockerfile
```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8014

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8014"]
```

## docker-compose.yml
```yaml
services:
  style-ai-proxy:
    build: .
    container_name: yurunavi-style-ai
    ports:
      - "8014:8014"
    env_file: .env
    restart: unless-stopped
```

## .env.example
```
OPENROUTER_API_KEY=sk-or-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
OPENROUTER_MODEL=anthropic/claude-3.5-sonnet
ALLOW_ORIGINS=*
```

## .gitignore
```
.env
__pycache__/
```
