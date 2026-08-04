GOAL: LLM-Wiki 3단계 — Gemini·Grok 대화 export를 웹UI "가져오기"로 들여올 수 있게 한다.

작성 2026-08-04 · 대상: 새 세션(마스터가 샘플 파일을 넘겨준 뒤) · 선행: ChatGPT 가져오기 완료
코드: `/data/wiki`(독립 git 저장소) · 이 저장소(yurunavi)엔 코드 없음, 문서만.

---

## 0. 지금 상태 — 착수 게이트, 아직 안 열렸을 수 있다

**마스터가 ChatGPT·Gemini·Grok 세 서비스 모두에 데이터 내보내기를 요청해 둔 상태다
(2026-08-04). 이메일로 다운로드 링크가 오면 받아서 이 세션에 등록하겠다고 했다.**

이 파일을 읽는 시점에 실제 Gemini/Grok export 파일이 아직 없다면 — **작업을 시작하지
마라.** `bin/wiki search "가져오기"` 또는 `wiki search "export"`로 마스터가 파일을
어디 뒀는지부터 확인하고, 없으면 마스터에게 물어라. 실제 파일 없이 형식을 추측해서
파서를 만들지 않기로 이미 합의했다(아래 1절 참조) — 그 결정을 뒤집지 마라.

샘플 파일을 어디서 찾을지 힌트가 없으면 흔히 쓰는 위치부터 봐라:
`~/Downloads/`, `/data/wiki/web/importers/samples/`(이 세션 이전엔 없었다 — 마스터가
새로 만들었을 수 있음), 또는 마스터가 직접 채팅으로 경로를 알려줬을 것이다.

---

## 1. 왜 ChatGPT만 먼저 됐고 이게 남았는가

ChatGPT는 OpenAI 데이터 내보내기의 `conversations.json` 형식이 2023년 이후 안정적이라
확신을 갖고 바로 구현했다(`/data/wiki/web/importers/chatgpt.py`). Gemini(Google Takeout)와
Grok(x.com/grok.com)은 형식을 확신할 수 없었다 — 실제 샘플 파일 없이 만들면 추측성
파서가 될 위험이 크다고 마스터에게 설명했고, **"ChatGPT 먼저, 나머지는 샘플 받은 뒤"로
합의했다.** 이 판단 자체는 다시 검토할 필요 없다 — 이제 샘플이 왔다는 전제로 실제
형식을 확인하고 구현하면 된다.

---

## 2. 참고 구현 — ChatGPT 임포터를 그대로 본떠라

전체 파이프라인(업로드 → 파싱 → 마스킹 → 저장 → 트리 배치)은 이미 만들어져 있고
검증됐다. 이번에 할 일은 **파서 하나 추가 + 두 군데 배선**뿐이다.

| 파일 | 역할 |
|---|---|
| `/data/wiki/web/importers/chatgpt.py` | **참고 구현.** 인터페이스 계약이 여기 있다 |
| `/data/wiki/web/server.py:45` | `IMPORTERS = {"chatgpt": importer_chatgpt.parse}` — 여기에 `"gemini": ..., "grok": ...` 추가 |
| `/data/wiki/web/server.py:35` | import문 — `from importers import chatgpt as importer_chatgpt` 옆에 같은 식으로 추가 |
| `/data/wiki/web/static/index.html:26-27` | `<option value="gemini" disabled>` / `grok` — `disabled` 속성과 "샘플 파일 필요" 문구 제거 |
| `/data/wiki/web/server.py:42` (`ORIGIN` dict) | 안 써도 됨(죽은 코드, 손대지 마라) |
| `/data/wiki/web/static/app.js` `originLabel()` (30번째 줄 근처) | `chatgpt: "ChatGPT 가져오기"` 옆에 `gemini: "Gemini 가져오기"`, `grok: "Grok 가져오기"` 추가 |

### 파서 인터페이스 계약 (chatgpt.py의 `parse()`가 지키는 것 — 반드시 동일하게)

```python
def parse(data) -> list[dict]:
    """[{id, title, created, updated, messages:[{id, role, ts, text}]}] 를 돌려준다."""
```

- `data`: 업로드된 파일을 `json.loads()`한 결과(서버가 이미 파싱해서 넘겨준다 — 파서는
  JSON 파싱을 다시 할 필요 없다. **단, 실제 export가 JSON이 아니라면**(Gemini Takeout은
  형식이 다를 수 있다 — HTML일 가능성도 있다) `server.py`의 `api_import()`도 같이
  고쳐야 한다. 지금은 `raw_bytes.decode("utf-8")` 후 `json.loads()`를 무조건 가정하고
  있다 — 이 가정이 깨지면 소스별로 분기하도록 바꿔라).
- `id`: 대화의 고유 id. **이게 세션 id(`gemini:<id>`/`grok:<id>`)로 그대로 박힌다** —
  같은 파일을 재업로드해도 중복이 안 생기게 하는 멱등성의 핵심이다. export에 안정적인
  id가 없으면(예: Gemini 항목에 고유 id가 없고 timestamp만 있다면) timestamp+제목
  해시 등으로 최대한 안정적인 대체 키를 만들어라.
- `role`: `user`/`assistant`/`system`/`tool` 중 하나여야 한다(스키마 제약은 없지만
  프론트 렌더링이 이 넷을 기준으로 색을 입힌다 — `chatgpt.py`의 role 정규화 로직 참고).
- `ts`: ISO8601 문자열(`_iso()` 헬퍼 참고, `chatgpt.py` 상단).
- 숨김/시스템 메시지, 이미지 등 텍스트가 아닌 콘텐츠는 걸러내라(`chatgpt.py`의
  `is_visually_hidden_from_conversation` 처리, `_text_of()`의 문자열 파트만 취하는 로직
  참고). Gemini/Grok에도 비슷한 "안 보이는 메타 메시지"가 있을 가능성이 높다 — 실제
  샘플을 열어서 확인해라.

### 서버 쪽은 거의 안 건드려도 된다

`api_import()`(`server.py`)는 이미 source-agnostic이다 — `IMPORTERS` dict에서 파서만
찾아 호출한다. 세션 upsert, redact(), `wiki-tree assign` 재실행까지 전부 공용이라
Gemini/Grok을 위해 새로 안 짜도 된다. **단 하나 확인할 것**: `entrypoint` 컬럼에
현재 `source`(즉 `"chatgpt"`)를 그대로 넣고 있다(`server.py`의 `INSERT INTO sessions`
근처) — `"gemini"`/`"grok"`도 같은 패턴으로 자연히 들어간다, 손댈 필요 없음.

---

## 3. 반드시 지켜야 할 것 (어기면 조용히 새는 구멍이 생긴다)

- **redact() 필수** — 가져온 대화라고 보안 게이트를 건너뛰지 마라. `chatgpt.py`
  경로처럼 제목·본문 모두 `redact()`(`/data/wiki/bin/redact.py`)를 거친 뒤에만
  DB에 들어가야 한다. 이건 `api_import()`가 이미 공용으로 하고 있으니 파서만 잘
  넘기면 자동으로 지켜진다.
- **실제 파일 없이 형식 추측 금지** — 1절 참고. Google Takeout은 특히 함정이 많다
  (여러 제품 데이터가 한 zip에 섞여 있고, "Gemini Apps Activity"처럼 대화 스레드가
  아니라 개별 프롬프트 로그 형태일 수도 있다). 실제로 압축을 풀어서 눈으로 구조를
  확인한 뒤 파서를 써라.
- **UI 기능은 반드시 Playwright로 실제 버튼 클릭 기준 검증** — ChatGPT 라운드에서
  curl로 API만 찍어보고 "된다"고 결론냈다가 프론트에 클릭 핸들러가 아예 빠진 버그를
  뒤늦게 발견했다(문서 열람 기능). 파서가 맞아도 업로드 버튼→파일선택→결과 문구까지
  실제 클릭으로 확인해라.
- **테스트 데이터는 DB에서 지워라** — 합성/샘플 파일로 끝단 테스트하면 `gemini:*`/
  `grok:*` 세션이 실제 DB에 들어간다. 검증 끝나면
  `sessions`/`messages`/`fts_messages`/`items`에서 지워라(sqlite3 CLI는 이 DB의
  FTS5 확장을 못 읽으니 **`wiki_db.connect()`로 Python에서 지워라** — 안 그러면
  "no such module: fts5" 에러가 난다, 이번에 겪은 함정).
- **`git add -A` 금지** — `/data/wiki`도 동시 세션이 브랜치를 공유할 수 있다.
  파일명 지정해서 스테이징.

---

## 4. 완료 판정

- [ ] Gemini/Grok 실제 export 파일 확보 확인(마스터로부터)
- [ ] 실제 파일 구조를 직접 열어서 확인(추측 금지)
- [ ] `web/importers/gemini.py`, `web/importers/grok.py` 작성 — `chatgpt.py`와 동일한
      `parse(data) -> list[dict]` 계약
- [ ] `server.py`의 `IMPORTERS` dict + import문에 배선
- [ ] `index.html`의 `disabled` 옵션 해제, `app.js`의 `originLabel()`에 라벨 추가
- [ ] 합성/실제 샘플로 파싱 단위테스트 + curl 업로드(redact 확인) + 재업로드 멱등성 확인
- [ ] Playwright로 실제 클릭 기준 업로드 UI 검증
- [ ] 테스트 데이터 DB에서 정리
- [ ] `loop/MORNING_REPORT_*.md`에 `Goal: X / Met: yes·partial·no — 이유` 한 줄
- [ ] 메모리(`project_llm_wiki.md`) 갱신

두 서비스 중 하나만 샘플이 왔다면 그것부터 끝내고, 나머지는 다음 세션으로 넘겨도 된다
(한 세션에 한 서비스씩도 무방 — "한 모듈당 한 세션" 원칙에 맞다).
