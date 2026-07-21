# CLAUDE.md - YuruNavi Core Autonomous Protocol

## What we are building
Motorcycle-tourer OSM navigation app. Flutter (UI) + Rust (fun-road scoring) + Valhalla (routing).

## Module structure (keep independent)
lib/core, lib/modules/{map,route_planning,navigation,daylight_bar,settings,auth,tour_summary},
lib/services, rust/, docker/

## 🚨 SYSTEM CONSTRAINTS
- **Execution Mode:** Running via `--permission-mode bypassPermissions`. Direct execution authorized.
- **Scope:** Strictly locked to this repository (`yurunavi`). No external system modifications.
- **Efficiency:** Maximize autonomy. Zero administrative or conversational overhead.

## 🔗 무인 야간 실행 = tick 체인 (2026-07~)
하룻밤 실행은 하나의 긴 세션이 아니라, `loop/run_night_auto.sh`가 순서대로
실행하는 여러 개의 짧고 독립된 `claude -p` 세션("틱")의 연쇄다. 이유: 큰
트랜스크립트 + 긴 단일 스트리밍 응답 조합이 서버쪽 mid-stream 실패를 유발하는
알려진 문제 회피(anthropics/claude-code#51164).
- 지금 이 세션은 직전 틱의 대화 기록을 전혀 갖고 있지 않다. 필요한 상태는 전부
  파일에서 읽어라: 오늘 밤 작업 지시서 + `loop/.auto/handoff.md`.
- "이전에 이미 했음" 같은 서술을 그대로 믿지 마라 — `git log`/`git show`로 직접 검증.
- 이번 틱에서는 오늘 밤 작업 전체가 아니라 체크포인트 단위 하나만 진행해라.

## Hard rules (never violate)
- NEVER commit secrets. All keys go in .env (which is gitignored).
- NEVER run destructive commands: rm -rf, git push --force, dropping data, mass file deletion.
- NEVER push to a remote unless explicitly told in the night's task.
- Make a git commit BEFORE starting each subtask (checkpoint), and after each PASS.
- One module per night. Do not expand scope beyond the night's assigned task.
- If unsure, STOP and write it in the morning report instead of guessing.

---

## 🔄 AUTONOMOUS TDD & GIT WORKFLOW
You MUST follow this atomic iteration loop for every feature or fix. Do not bundle tasks.

1. Orchestrator reads the night's task file passed in the prompt (dated `loop/HANDOFF_MMDD_*.md`-style task files; the stale root `NIGHT_TASK.md` is not the current convention).
2. Break into small steps. Checkpoint commit.
3. Delegate to flutter-coder or rust-coder.
4. Run code-auditor. If FAIL, fix and re-audit (max 3 loops, then stop & report).
5. On PASS, commit. Move to next step.
6. At end, write MORNING_REPORT.md: what was done, what passed, what's blocked, token usage note.


---

## CAUTION

1. JDK21 is required on build.

## 지도 타일 인프라 (M1.5, 2026-06-04 구축 → 2026-06-05 공개호스팅 전환, 2026-07-06 문서 갱신)
- 타일서버: tileserver-gl v5.6.0 Docker (컨테이너 `yurunavi-tiles`, 포트 8080, 내부망만)
- config: /data/tiles/data/config.json (data ID=`v3`, serveAllFonts:true, fonts:/fonts)
- 데이터: /data/tiles/data/korea.mbtiles (planetiler, OpenMapTiles 3.16 스키마)
- 폰트: /data/tiles/fonts/ (Noto Sans Regular + Noto Sans CJK TC Regular, fontnik으로 .otf→.pbf 빌드)
- 스타일: assets/images/osm_liberty_yurunavi.json — **HTTPS 공개 호스트로 전환 완료**(커밋 `9b31cf8`)
  - source url → https://tiles.westinx.com/data/v3.json
  - sprite → https://tiles.westinx.com/styles/osm-bright/sprite
  - glyphs → https://tiles.westinx.com/fonts/{fontstack}/{range}.pbf
  - text-font → ["Noto Sans Regular","Noto Sans CJK TC Regular"]
- 같은 방식으로 `lib/services/routing_service.dart`(`https://valhalla.westinx.com`), `lib/services/native_engine.dart`(`https://navi.westinx.com`)도 공개 호스트 사용 (로컬 개발/curl 계측 시엔 `localhost:8002` 등으로 직접 호출).
- 192.168.0.57 LAN IP·cleartext 예외는 제거됨 — `network_security_config.xml`엔 현재 `ts.net`(Tailscale) 예외만 남아있음(다른 용도, 지도 타일과 무관).
- TODO: 일본 mbtiles 추가(config에 data 항목), CJK 번체→jp 폰트 교체
- 빌드: headless 서버라 flutter run 불가 → flutter build apk --debug → 노트북 adb install

## 지도 백로그 (M4 등에서)
- 정보 밀도 너무 낮음 → 스타일 레이어 minzoom/filter 조정 (서버 무관, 순수 스타일)
- 일출일몰 인디케이터 시간·위치 어긋남 → Flutter 위젯
- 현위치/줌 버튼 무동작 → M4 카메라 이관에서 해결 (옛 FlutterMap 컨트롤러 호출 추정)
