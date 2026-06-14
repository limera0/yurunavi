# CLAUDE.md - YuruNavi Core Autonomous Protocol

## What we are building
Motorcycle-tourer OSM navigation app. Flutter (UI) + Rust (fun-road scoring) + Valhalla (routing).

## Module structure (keep independent)
lib/core, lib/modules/{map,route_planning,navigation,daylight_bar,settings,auth,tour_summary},
lib/services, rust/, docker/

## 🚨 SYSTEM CONSTRAINTS
- **Execution Mode:** Running via `--permission-mode auto`. Direct execution authorized.
- **Scope:** Strictly locked to this repository (`yurunavi`). No external system modifications.
- **Efficiency:** Maximize autonomy. Zero administrative or conversational overhead.

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

1. Orchestrator reads the night's task (from NIGHT_TASK.md).
2. Break into small steps. Checkpoint commit.
3. Delegate to flutter-coder or rust-coder.
4. Run code-auditor. If FAIL, fix and re-audit (max 3 loops, then stop & report).
5. On PASS, commit. Move to next step.
6. At end, write MORNING_REPORT.md: what was done, what passed, what's blocked, token usage note.


---

## CAUTION

1. JDK21 is required on build.

## 지도 타일 인프라 (M1.5, 2026-06-04)
- 타일서버: tileserver-gl v5.6.0 Docker (컨테이너 `yurunavi-tiles`, 포트 8080)
- config: /data/tiles/data/config.json (data ID=`v3`, serveAllFonts:true, fonts:/fonts)
- 데이터: /data/tiles/data/korea.mbtiles (planetiler, OpenMapTiles 3.16 스키마)
- 폰트: /data/tiles/fonts/ (Noto Sans Regular + Noto Sans CJK TC Regular, fontnik으로 .otf→.pbf 빌드)
- 스타일: assets/images/osm_liberty_yurunavi.json
  - source url → http://192.168.0.57:8080/data/v3.json
  - glyphs → http://192.168.0.57:8080/fonts/{fontstack}/{range}.pbf
  - text-font → ["Noto Sans Regular","Noto Sans CJK TC Regular"]
- ⚠️ 192.168.0.57은 검증용 LAN IP. 출시 전 Tailscale/공개호스팅으로 교체 필수
- ⚠️ Android cleartext: network_security_config.xml에 192.168.0.57 평문 허용 (임시)
- TODO: 일본 mbtiles 추가(config에 data 항목), CJK 번체→jp 폰트 교체
- 빌드: headless 서버라 flutter run 불가 → flutter build apk --debug → 노트북 adb install

## 지도 백로그 (M4 등에서)
- 정보 밀도 너무 낮음 → 스타일 레이어 minzoom/filter 조정 (서버 무관, 순수 스타일)
- 일출일몰 인디케이터 시간·위치 어긋남 → Flutter 위젯
- 현위치/줌 버튼 무동작 → M4 카메라 이관에서 해결 (옛 FlutterMap 컨트롤러 호출 추정)
