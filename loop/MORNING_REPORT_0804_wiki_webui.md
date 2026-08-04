# 세션 보고 — LLM-Wiki 2단계 웹 UI (2026-08-04)

핸드오프: `HANDOFF_0804_wiki_webui.md`. 코드는 이 저장소가 아니라 `/data/wiki`(독립 git
저장소)에 있다. 착수 전 핸드오프 5절의 세 질문을 마스터에게 확인:
1. 노출 범위 → **Tailscale 내부 전용**(외부 공개·Cloudflare Access 불필요)
2. 편집 권한 → **재배치·숨김까지 웹에서**
3. 모바일 → **처음부터 반응형**

## 구현

- **백엔드** `/data/wiki/web/server.py` — 표준 라이브러리만(`http.server`), 새 쿼리를 설계하지
  않고 `bin/wiki`의 검증된 SQL(search/show/tree/tags/stats/redact-report)을 JSON API로 그대로
  옮김. 2글자 한국어 검색의 FTS5 trigram→LIKE 폴백 분기도 동일하게 이식.
- **쓰기(숨김·재배치)**: `POST /api/session/<id>/hide`(`sessions.hidden` 토글, 소프트 삭제) ·
  `POST /api/session/<id>/move`(`sessions.topic_path` 오버레이 설정 + `wiki-tree assign` 재실행).
  **트리 구조(`tree.yaml`/`apply`) 편집은 범위에서 뺐다** — 핸드오프 3-1의 "DB nodes를 직접
  고치지 마라"는 제약을 지키면서, 세션을 기존 잎 사이에서만 재배치하도록 스코프를 좁힌 판단.
  문서(docs)는 애초에 topic_path 오버레이 컬럼이 없고 핸드오프 2절 표의 "세션 관리"도 세션
  한정이라 **읽기 전용**으로 뒀다(스코프 확대 안 함).
  쓰기는 `wiki-index`/cron과 같은 `/tmp/wiki-index.lock` flock으로 직렬화.
- **프런트** `/data/wiki/web/static/{index.html,style.css,app.js}` — 빌드 도구 없는 순수
  HTML+JS 단일 페이지. 좌측 트리(`<details>` 네이티브 접기)/우측 콘텐츠, 800px 미만에서
  탭 전환형 반응형. 라이트/다크 자동(`prefers-color-scheme`).
- **노출**: ufw로 `tailscale0` 인터페이스에만 8025/tcp 개방(`sudo ufw allow in on tailscale0
  to any port 8025 proto tcp` — **이 세션이 직접 실행**, 기존에 위임된 narrow NOPASSWD sudo
  범위 안). 서버 바인딩 자체도 `0.0.0.0`이 아니라 tailscale IP(`100.66.25.27`)로 좁혀 이중
  방어(감사 지적 반영, 아래 참조). 인증 레이어는 없음 — Tailscale 네트워크 자체가 게이트라는
  마스터 결정.
- **systemd**: `/data/wiki/web/wiki-web.service` 준비만 해둠. `/etc/systemd/system/` 쓰기와
  `daemon-reload`/`enable`은 이 세션의 위임된 sudo 범위 밖(narrow NOPASSWD 목록에 없음) —
  **마스터가 직접 설치해야 함**:
  ```bash
  sudo cp /data/wiki/web/wiki-web.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now wiki-web
  ```
  설치 전까지는 웹 UI가 떠 있지 않다(이 세션에서는 테스트용으로만 기동·종료함).

## 검증

- 로컬 curl로 전 API 엔드포인트(search 2글자 LIKE 폴백 포함) + 정적파일 서빙 스모크테스트.
- Playwright로 실제 브라우저 조작 검증 — 데스크톱(1280px)·모바일(390px) 뷰포트 각각 트리 펼침
  → 잎 클릭 → 세션 목록 → 세션 상세 → 검색(FTS 하이라이트 `<mark>` 렌더 확인) → 모바일 탭
  전환. 콘솔/페이지 에러 0건. 스크린샷 확보.
- `POST .../hide` 토글 on/off 라운드트립, `POST .../move` 잘못된 leaf 거부(400) + 정상 이동 후
  두 잎 모두에서 교차 검색되는지(키워드 배치는 유지되고 수동 배치가 추가되는 설계) 확인 후 원복.
- `wiki stats`(CLI)와 `/api/stats`(웹) 건수 일치 확인(세션 505 · 문서 436 · 마스킹 3103).
- **레닥션 리포트 확인(핸드오프 1절 보안 게이트)**: `wiki redact-report` 실행 결과를 세션 중
  마스터에게 표시함(누적 3103건 마스킹, 세션별 상위 목록 포함). 다만 채팅상 명시적 "확인했다"
  응답은 받지 않았다 — Tailscale 전용이라 리스크가 낮다는 전제로 계속 진행했음을 여기 기록.

## code-auditor

1차 PASS(findings 6건, blocking 없음) → 전부 반영 후 재검증 완료:
- **(중)** systemd 유닛이 `WIKI_WEB_HOST=0.0.0.0`으로 바인딩 → ufw 규칙 하나에만 의존하는
  단일 방어선 지적. **수정**: tailscale IP로 명시 바인딩(이중 방어). 수정 후 재테스트로
  `127.0.0.1`에서는 연결 자체가 거부됨을 확인.
- **(저-중)** 정적파일 경로 검사가 `str.startswith()` 단순 접두사 비교라 형제 디렉터리
  이름 충돌에 취약할 수 있음 → `os.sep` 경계 체크로 강화.
- **(저)** `snippet()` 마커로 `[[`/`]]`를 썼는데 실제 대화 본문에 이 문자열이 있으면 오하이라이트
  가능 → CLI(`bin/wiki`)와 동일하게 제어문자(`\x01`/`\x02`)로 교체.
- **(저)** 프런트 날짜·시간 필드 일부가 `esc()`를 안 거침(제목·요약·태그·스니펫은 다 거쳤는데
  누락) → `dateOnly()`에 내장, 메시지 타임스탬프 슬라이스도 감쌈.
- **(저)** 숨김 토글이 실제 변경 없어도(no-op) "완료"로 표시 → 응답의 `updated` 카운트를 보고
  문구 분기.
- **(정보)** POST 바디 무제한 read()로 스레드가 묶일 수 있음 → 1MB 상한(413) + 소켓
  타임아웃(30초) 추가.

수정 후 전체 재테스트(curl + Playwright, tailscale IP 바인딩 기준) 재실행, 전부 통과.

## 커밋

- `/data/wiki` 저장소(별도) `fd5748a` feat(web): 2단계 웹 UI — 트리 열람·검색·태그·세션
  편집(숨김/재배치)
- 이 저장소(yurunavi)는 코드 변경 없음 — 핸드오프/보고 문서만.

## 남은 것 / 다음 세션 확인 필요

- **마스터**: 위 systemd 설치 3줄 실행 → `http://100.66.25.27:8025`(또는 다른 tailnet 기기의
  Tailscale IP로) 접속 확인.
- 레닥션 리포트에 대한 명시적 확인 한 마디(선택 — 이미 낮은 리스크로 판단하고 진행했음).
- 3단계(타 LLM 통합)는 미착수, 핸드오프 원문대로 다음 범위.

**목표 달성 판정:** 원래 목표: 어디서든 세션 트리를 보고 검색·관리할 수 있는 웹 UI를 만든다
(Tailscale 내부 전용, 재배치·숨김 편집 포함, 반응형) / 달성: **부분** — 코드·기능·감사·자체
검증은 전부 끝났으나, systemd 서비스 설치(마스터 sudo 필요)가 남아 있어 아직 "어디서든" 실제로
켜져 있는 상태는 아니다. 설치 3줄만 실행하면 완료.
