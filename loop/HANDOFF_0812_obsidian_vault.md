GOAL: LLM-Wiki를 Obsidian 볼트로 펴서 폰에서 대화를 읽고 파일 이동만으로 재분류할 수 있게 한다.

작성 2026-08-12 · 코드: `/data/wiki`(독립 git 저장소, 커밋 `48f31a0`) · 이 저장소엔 문서만

---

## 1. 서버 쪽은 끝났다

주제 트리를 그대로 폴더로 편 볼트가 `/archive/wiki/vault`에 있다. 세션 734건 ·
735파일 · 17MB. cron이 15분마다 `wiki-vault sync`를 돈다.

```bash
/data/wiki/bin/wiki-vault status    # 차이만 보고 (아무것도 안 고친다)
/data/wiki/bin/wiki-vault sync      # ingest(볼트→DB) 다음 export(DB→볼트)
```

**파일을 다른 잎 폴더로 옮기면 그게 재분류다.** 웹UI의 "재배치"와 완전히 같은
의미로 들어간다(`topic_path` + `topic_manual=1` → `wiki-tree assign`). `_미분류`
폴더로 옮기면 분류가 해제된다.

검증한 것(실 DB 사본으로 왕복 시험):

| 케이스 | 결과 |
|---|---|
| 잎 → 다른 잎 이동 | `topic_path` 갱신 · `manual=1` · 배치 1건으로 수렴 |
| 잎 → `_미분류` | `topic_path=NULL` · `manual=1` · 배치 0건 |
| 잎 → 중간(비-잎) 폴더 | 반영 안 함 + 경고 출력, 다음 export가 제자리로 되돌림 |
| 볼트에 직접 쓴 노트 | 건드리지 않음(frontmatter에 `wiki_id`가 없으면 관리 대상 아님) |
| 이동 없이 sync 반복 | 신규 0 · 갱신 0 · 정리 0 (Syncthing churn 없음) |

---

## 2. 남은 일 — 폰 연결(마스터만 할 수 있다)

Syncthing 컨테이너는 이미 `/archive/wiki`를 "LLM-Wiki" 폴더로 동기화 중이고
볼트도 이미 잡혀 있다(927파일 · 15.5MB · idle). **폴더를 새로 만들 필요 없고,
폰을 기기로 추가하기만 하면 된다.**

1. 폰에 Syncthing 안드로이드 앱 설치. 공식 앱은 2024년 말 개발 중단됐으니
   **Syncthing-Fork(Catfriend1)** 를 F-Droid나 Play 스토어에서 받아라.
2. 서버 Syncthing GUI(`http://100.66.25.27:8384`, Tailscale 안에서만 열린다)
   → Add Remote Device → 폰 앱에 뜨는 device ID를 붙여넣고, 공유 폴더로
   **LLM-Wiki** 를 체크.
   - 서버 device ID(폰 쪽에서 추가할 때 쓸 것):
     `5AFT73Z-JEADFAF-E5IT7RI-YHR23LR-GPC52UR-ABCYB3R-STYJWCM-55UWAAA`
3. 폰에서 수락하고 저장 위치를 고른다. **앱 전용 영역이 아니라 공유 저장소**
   (`/storage/emulated/0/LLM-Wiki` 같은 곳)로 잡아라 — 안드로이드 scoped storage
   때문에 앱 전용 영역에 두면 Obsidian이 못 읽는다.
4. Obsidian 앱 → "Open folder as vault" → 3번에서 고른 폴더를 지정.
   `.obsidian` 설정은 노트북 볼트에서 이미 같이 넘어온다.
5. 권장: Syncthing 폴더 ignore 패턴에 `.obsidian/workspace*` 를 넣어라.
   기기마다 열어둔 탭 상태가 달라서 이것만 계속 충돌 파일을 만든다.

연결되면 폰에서 파일을 옮기고 → Syncthing이 서버로 밀고 → 15분 안에 cron이
DB에 반영한다.

---

## 3. 알아둘 것

- **본문 수정은 DB로 안 간다.** 볼트는 읽기 전용으로 봐라. 고쳐도 다음 export가
  덮어쓴다. 폴더 위치만 되읽는다 — 본문까지 양방향으로 하면 Syncthing 충돌
  사본(`.sync-conflict-*`)이 DB로 새어들 길이 생긴다.
- **사람 대화는 원문, `claude-code`는 요약 스텁**(요약 + 첫 지시 + 마지막 응답).
  요약이 있는 claude-code 세션이 166/652건뿐이라 요약만 넣으면 나머지가 제목만
  남아 폰에서 분류 판단이 안 된다 — 그래서 첫 지시를 같이 넣었다. 최대 파일
  452KB라 폰에서 열린다.
- **서브에이전트 세션 419건은 볼트에 없다.** `wiki-tree assign`이 원래
  `parent_session IS NULL`만 다루므로 그 기준을 그대로 따랐다.
- **문서(docs) 487건은 아직 볼트에 없다.** `docs` 테이블에 `topic_path`가 없어서
  수동 재배치 자체가 현재 시스템에 없다(키워드 자동배치만 있다). 넣으려면 스키마
  2열 추가 + `wiki-tree assign` + 웹UI `api_move`까지 같이 손봐야 해서 별도 건으로
  남긴다. 넣지 않은 이유가 "잊어서"가 아니다.
- `/archive/wiki/vault`는 `wiki-index` 문서 색인에서 제외된다. 안 그러면 같은
  대화가 세션으로도 문서로도 잡히고 트리에 두 번 배치된다.
  (참고: `/archive/wiki/sessions/`의 `wiki-enrich notes` 요약 노트 168건은 지금도
  docs로 재색인되고 있다 — 기존부터 있던 중복이고 이번에 건드리지 않았다.)
- **보안**: 볼트 본문은 DB에서 그대로 뽑는다. DB 텍스트는 색인 시점에 이미
  `redact.py`를 통과한 것이라 새 유출 경로는 없다. 다만 이제 폰까지 나간다 —
  노트북보다 잃어버리기 쉽다는 점은 감안해라.

---

## 4. 이번에 밟은 함정 (다시 밟지 마라)

- **CRLF.** 대화 30건에 `\r\n`이 섞여 있는데, 파이썬은 리눅스에서 쓸 때는 개행을
  안 바꾸고 읽을 때는 universal newline으로 `\r\n`→`\n`으로 바꾼다. 그래서 쓴
  내용과 읽은 내용이 영원히 달라 보여 매 실행 30건이 "갱신"으로 잡혔고, Syncthing이
  같은 파일을 계속 폰으로 밀 뻔했다. 렌더링 마지막에 LF로 정규화하고 읽기·쓰기
  모두 `newline=""`로 열어서 막았다.
- **sync 순서.** 반드시 ingest가 먼저다. export를 먼저 돌리면 사람이 옮긴 파일을
  DB 기준 제자리로 되돌린 다음에 그 이동을 읽으므로 재분류가 통째로 사라진다.
  실제로 시험 중에 한 번 그렇게 날렸다.
- **`wiki-tree assign` 따라잡기.** items가 마지막 assign(8/6) 이후 늘어난 코퍼스
  대비 낡아 있어서, 재분류 2건에 파일 44개가 움직였다. 볼트를 만들기 전에 assign을
  한 번 돌려 따라잡기를 끝내뒀다(수동배치 119건은 그대로 보존됨). 이후로는 이동
  1건 → 파일 1건만 갱신된다.

---

**Goal: LLM-Wiki를 Obsidian으로 확장해 폰에서 읽기·재분류 / Met: partial — 서버
파이프라인은 구현·검증·커밋 완료, 폰 기기 등록만 마스터 몫으로 남음(§2).**
