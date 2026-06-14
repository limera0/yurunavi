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
