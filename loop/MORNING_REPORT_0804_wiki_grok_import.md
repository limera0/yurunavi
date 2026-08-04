# 세션 보고 — LLM-Wiki 3단계 Grok 대화 가져오기 (2026-08-04)

핸드오프: `HANDOFF_0804_wiki_import_gemini_grok.md`. 코드는 이 저장소가 아니라 `/data/wiki`
(독립 git 저장소)에 있다.

## 0. 파일 확보 — 78MB 업로드 실패 문제

마스터가 Grok 데이터 내보내기(78MB zip)를 채팅 첨부로 넘기려다 실패. 실제 원인은
웹UI(`/api/import`)의 80MB 상한이 아니라 채팅 첨부 자체의 용량 한도였다. 이 서버(westinx)와
마스터 PC(Windows, Tailscale명 `galaxybookofdavidha`)가 이미 같은 tailnet에 있어서
**Tailscale Taildrop**(`tailscale file cp`/`file get`)로 설정 없이 바로 전송.
압축을 풀어 보니 필요한 건 `export_data/<user-id>/prod-grok-backend.json` 하나뿐이었고
(나머지는 첨부 이미지 302개 + 계정/결제 메타 json 2개, 전부 이번 스코프 밖) 이걸
`/data/wiki/web/importers/samples/`에 배치.

## 1. 실제 파일 구조 확인 (추측 금지 원칙 준수)

- 최상위: `{conversations: [...373건], projects: [1], tasks: [], media_posts: [21]}` —
  `conversations`만 취급.
- 각 항목: `{conversation: {id, title, create_time, modify_time, leaf_response_id, ...},
  responses: [{response: {_id, parent_response_id, sender, message, create_time: {"$date":
  {"$numberLong": "<epoch ms>"}}, children, ...}}]}`.
- **핵심 발견**: `leaf_response_id`가 373개 대화 중 370개에서 비어있고 `children` 필드도
  대부분 안 채워져 있다. 다만 표본 전체(5142개 메시지)를 검사한 결과 **분기(재생성/편집
  브랜치)가 단 한 건도 없었다** — 그래서 leaf 있으면 parent를 거슬러 올라가고, 없으면(대부분)
  생성시각 정렬로 폴백해도 안전하다고 판단(chatgpt.py의 "current_node 없는 옛 형식" 폴백과
  동일 전략).
- `sender` 값에 `human`/`assistant`/`ASSISTANT`(대소문자 혼재) 외에 모델명 문자열
  (`grok-4-1-thinking-1129` 등)이 낀 경우가 있었는데, 확인해보니 전부 message가 빈 문자열이라
  텍스트 필터링에서 자연히 걸러짐(실질 영향 없음).

## 2. 구현

- `/data/wiki/web/importers/grok.py` 신규 — `chatgpt.py`와 동일한
  `parse(data) -> list[dict]` 계약. root sentinel id는 by_id에 없어 자연히 체인에서
  빠지는 구조라 chatgpt.py 패턴을 그대로 재사용.
- `server.py`: `IMPORTERS`에 `grok` 등록, `IMPORT_MAX_BODY` 80MB → 200MB(실제 파일 137MB —
  Tailscale 내부 전용 단일 사용자 서버라 위험 낮다고 판단, code-auditor도 동의).
- `index.html`: `grok` 옵션 `disabled` 해제 + 사용법 힌트(어떤 파일만 올리면 되는지) 추가.
- `app.js`: `originLabel()`에 grok 추가. **겸사겸사 버그 수정**: 대화 상세 화면에서
  어시스턴트 메시지가 소스 무관하게 항상 "Claude"로 라벨링되던 기존 버그(ChatGPT 가져오기에도
  있었음)를 열람 검증 중 발견 → `{chatgpt: "ChatGPT", grok: "Grok"}[s.entrypoint]`로 수정.

## 3. 검증

- 파서 단독 실행: 373개 대화 · 5087개 메시지(원본 5142 노드 중 55개는 빈 텍스트라 정상 제외).
- 서비스 재시작: `systemctl restart`는 sudo 비밀번호가 필요해 비대화식 세션에서 불가 →
  서비스가 `User=limera`(내 계정) + `Restart=always`라 프로세스만 kill해서 systemd가
  자동 재기동하게 함(설정 변경 없이 반영).
- curl로 실제 137MB 파일 업로드: `imported:373, new_messages:5087, redactions:15`. **재업로드로
  멱등성 확인**: `imported:0, updated:373, new_messages:0` — 중복 없음.
- Playwright로 실제 클릭 기준 검증(핸드오프 3절 요구사항 — curl만 믿지 않기): 가져오기 패널
  열기 → Grok 옵션 선택(disabled 아님 확인) → 파일 선택 → 업로드 버튼 클릭 → 완료 문구 확인.
  이어서 검색창에 실제 대화 키워드 입력 → 결과 클릭 → 상세 화면에서 메시지 본문·
  "Grok" 라벨(수정 전엔 "Claude"였음) 렌더 확인.
- redact() 동작 확인: 3개 세션에서 총 15건 마스킹(계정/키 관련 대화 위주) — 보안 게이트
  정상 작동.
- **이번 데이터는 테스트용이 아니라 마스터의 실제 Grok 대화 이력**이라 (합성 샘플과 달리)
  검증 후 DB에서 삭제하지 않음 — 이게 바로 이 작업의 목표 결과물.

## 4. code-auditor

PASS(non-blocking 2건 + caution 1건) → 전부 반영:
- **(저)** `conv = wrap.get("conversation") or {}`, `rr = (r or {}).get("response") or {}`가
  isinstance 체크 없이 진행돼 truthy 비-dict 값에서 `AttributeError` 가능(서버가 500으로
  잡아주긴 하지만 배치 전체가 실패) → 상위 레벨과 동일하게 `isinstance(..., dict)` 가드 추가.
- **(저)** `_iso()`의 `int(d["$numberLong"])`가 비정상 값에 `ValueError` 가능 →
  `try/except (TypeError, ValueError): return None` 추가.
- **(caution)** `web/importers/samples/`(개인 대화 원본 137MB+82MB)가 `.gitignore`에 안 잡혀
  있었음 → 추가(향후 실수로 커밋되는 것 방지).

수정 후 파서 재실행으로 동일 결과(373/5087) 재확인, 서비스 재기동 후 Playwright 재검증 통과.

## 5. 커밋

- `/data/wiki` 저장소(별도) `84650b5` feat(web): 3단계 완료 — Grok 대화 가져오기
- 이 저장소(yurunavi)는 코드 변경 없음 — 보고 문서만.

## 남은 것 / 다음 세션

- **Gemini**: 아직 실제 샘플 파일 미확보 — 마스터가 Google Takeout 내보내기를 받으면 이어서
  진행(같은 방식으로 Taildrop 전송 가능).
- Grok 가져오기 자체는 완료 — 마스터가 웹UI에서 다른 Grok 계정/추가 export를 올릴 때도
  같은 경로로 동작함.

**목표 달성 판정:** 원래 목표: LLM-Wiki 3단계 — Grok 대화 export를 웹UI "가져오기"로 들여올 수
있게 한다 / 달성: **예** — 파서·배선·UI 전부 완료, 실제 137MB 파일로 curl+Playwright 실클릭
검증까지 마쳤고 마스터의 실제 Grok 대화 373건이 이미 위키에 들어와 있다. Gemini는 핸드오프
원래 범위대로 샘플 확보 후 별도 세션으로 넘김("한 세션에 한 서비스씩"도 무방하다고 핸드오프에
명시돼 있었음).
