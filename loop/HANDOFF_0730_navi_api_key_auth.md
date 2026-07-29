GOAL: 21번(운영 서버 보안 강화) 2순위 완료 기록 — navi API에 X-Api-Key 공유키 인증 추가
완료. 다음 세션은 이 문서 확인 후 남은 1/3/4/5순위 중 마스터가 고른 항목부터 진행.

---

## 배경

`loop/HANDOFF_0729_server_security_audit.md`의 5개 권장 우선순위 중, 마스터가
2026-07-30 이 세션에서 "2. API에 최소한의 공유 키(헤더) 인증 추가"부터 진행하기로
선택. 감사 결과는 실행 직전에 재검증했고(ufw 여전히 비활성, 포트 바인딩 동일,
`main.rs`에 인증 코드 없음 확인) 변한 것이 없었다.

## 한 일

1. **`native/src/main.rs`** (커밋 `bc1fa0c`, rust-coder 위임 + code-auditor PASS):
   - `NAVI_API_KEY` 환경변수를 시작 시 1회 읽어 `OnceLock`에 캐싱. 비어있으면
     **시작 시 panic**(fail-closed) — `VWORLD_API_KEY`처럼 조용히 우회하지 않음.
   - `X-Api-Key` 헤더를 상수시간 비교(`constant_time_eq`, 수동 XOR-fold, 새 크레이트
     추가 없음)로 검사하는 axum 미들웨어(`require_api_key`) 추가.
   - 라우터를 `public_routes`(`/health`, `/privacy`, 레이어 없음)와
     `protected_routes`(나머지 11개 라우트, `.route_layer(from_fn(require_api_key))`)로
     분리 후 `.merge()`. `/health`는 Dockerfile `HEALTHCHECK`와 Cloudflare Tunnel
     연결확인(`docker/INFRA.md:24`)이 헤더 없이 호출하므로 반드시 열어둬야 함.
     `/privacy`는 법적으로 공개 필수인 개인정보처리방침 페이지.
   - `native/.env.example`에 `NAVI_API_KEY=your_shared_secret_here` 추가.
   - `cargo build`/`cargo test`(기존 77개) 전부 통과 확인.

2. **Flutter 클라이언트** (커밋 `c72f873`, flutter-coder 위임 + code-auditor PASS):
   - `lib/core/config/app_config.dart`에 `naviApiKey` getter 추가 —
     `const String.fromEnvironment('NAVI_API_KEY', defaultValue: '')`.
     `.gitignore`에 이미 문서화돼 있던(하지만 지금까지 실제로 쓰인 적 없던)
     `--dart-define-from-file=env.json` 관례를 처음으로 실사용함.
   - `naviBaseUrl`을 호출하는 5곳 전부에 `X-Api-Key` 헤더 부착: `poi_service.dart`,
     `gas_station_service.dart`, `address_search_service.dart`, `native_engine.dart`
     (`calc_route`/`score_route`), 그리고 **flutter-coder가 지시서에 없던 5번째
     호출부를 스스로 찾아낸** `routing_config.dart`(`/routing-config`, 안 붙였으면
     조용히 401 → 기본 코스팅으로 폴백해 기능 저하가 나던 곳). code-auditor가
     `naviBaseUrl` 전수 grep으로 재검증, 빠진 곳 없음 확인.
   - `scripts/build_release.sh`에 `--dart-define-from-file=env.json` 추가.
   - `env.json.example`(커밋 대상) 신설. 실제 `env.json`(2026-07-12부터 이미 존재,
     `SEMAS_SERVICE_KEY` 포함— 공공데이터포털 쿼터 토큰)은 건드리지 않고
     `NAVI_API_KEY` 키만 추가.
   - `flutter analyze` 클린, 기존 서비스 테스트(`address_search_service_test.dart`,
     `poi_service_test.dart`) 18개 전부 통과.

3. **배포 + 종단 검증** (이 세션에서 직접 수행, 위임 아님 — 운영 컨테이너 재기동은
   코더에게 맡기지 않고 내가 직접 확인하며 진행):
   - `openssl rand -hex 32`로 실제 키 값 생성, `native/.env`와 `env.json`
     양쪽에 반영(둘 다 gitignored, 커밋 안 됨).
   - `docker compose build navi && docker compose up -d navi` — 재빌드/재기동.
   - curl로 로컬(`localhost:8003`)과 공개 도메인(`https://navi.westinx.com`)
     양쪽에서 확인: `/health`·`/privacy`는 헤더 없이 200, 나머지는 헤더 없거나
     틀리면 401, 맞으면 200. Cloudflare Tunnel 경유 경로도 동일하게 동작.
   - `flutter build apk --debug --dart-define-from-file=env.json` 후
     `adb install -r`로 테스트 기기(`RZ8RC1N3V9W`)에 설치, 앱 실행, 스크린샷으로
     지도에 POI(편의점/마트 아이콘)가 정상 표시되는 것 확인 — `/poi/nearby`가
     새 헤더로 실제 인증에 성공하고 있다는 뜻.

## 왜 지금 안전했나 (breaking change인데도)

이 변경은 하위호환이 없다 — 헤더 없는 기존 앱은 전부 401을 받는다. 하지만
`loop/RELEASE_ROADMAP.md:605-606`에 명시된 대로 **앱이 아직 배포 전, 개발자 1인이
디버그 APK로 단일 기기 테스트 중**이라 실사용자 영향이 없다. 스토어 출시(로드맵
10번) 이후에는 이런 계약 변경을 이렇게 즉시 프로덕션에 반영하면 안 되고, 반드시
새 헤더를 보내는 앱 버전이 먼저 배포·보급된 뒤에 서버 쪽 강제를 켜는 단계적 롤아웃이
필요하다 — 다음에 이런 API 계약 변경을 할 때 반드시 참고할 것.

## 남은 것 (`HANDOFF_0729_server_security_audit.md`의 5개 우선순위 중)

1. **Cloudflare 대시보드 WAF/Rate Limiting/Bot Fight Mode** — 여전히 마스터가
   직접 대시보드에서 해야 함(계정이 `/data/n8n-stack/` 소유, 이 리포에서 조작 불가).
2. ~~API 공유키 인증~~ — **이번 세션에서 완료.**
3. **`ufw` 활성화** — 여전히 미착수, 가장 위험한 항목(SSH 락아웃/사이트 다운 가능).
   콘솔 접속 확보 후 단계적으로만 진행할 것.
4. **요청 로깅**(`tower_http::TraceLayer`) — 미착수. 로드맵 20번(위치정보 확인자료
   로깅)과 근본 원인 같으므로 묶어서 처리 권장.
5. **fail2ban** — 미착수, 우선순위 낮음(SSH 이미 키인증).

**scope 밖으로 남겨둔 것**: valhalla(8002)·tiles(8080)는 서드파티 이미지(Valhalla
공식 바이너리, tileserver-gl)라 이번처럼 앱단 헤더로 인증을 걸 수 없다. 이 두
서비스의 노출을 줄이려면 1순위(Cloudflare) 또는 3순위(ufw) 경로가 필요하다.

## 참고

- 감사 원본: `loop/HANDOFF_0729_server_security_audit.md`
- 로드맵 갱신: `loop/RELEASE_ROADMAP.md` 108행(테이블), 841행(상세 섹션)
- 로드맵 20번(위치정보 확인자료 로깅)과 이번 4순위 항목은 함께 처리 권장(동일 근본 원인).
