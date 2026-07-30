GOAL: 세션 종료 인수인계 — 21번(운영 서버 보안 강화) 남은 1/3/4/5순위 중 마스터가
고른 것부터 다음 세션에서 진행

이 파일을 읽는 Claude는: (1) 아래 요약이 여전히 유효한지 `git log`/실제 설정으로
재검증할 것, (2) 남은 후보 중 마스터가 고른 항목부터, (3) ufw(3순위)는 특히
신중히 — 콘솔 접속 확보한 상태에서만 진행.

---

## 이번 세션(2026-07-30) 요약

`loop/HANDOFF_0729_server_security_audit.md`의 5개 권장 우선순위 중 마스터가
"2. API 공유키 인증"을 선택, 완료했다.

- navi(8003) API — `/health`·`/privacy` 제외 전 엔드포인트가 `X-Api-Key` 헤더
  (상수시간 비교, `NAVI_API_KEY` 환경변수, 없으면 서버 시작 시 panic)를 요구.
- rust-coder(백엔드) → code-auditor PASS → 커밋 `bc1fa0c`.
- flutter-coder(클라이언트, `--dart-define-from-file=env.json` 관례 최초 실사용)
  → code-auditor PASS → 커밋 `c72f873`.
- 운영 navi 컨테이너 재빌드·재기동, curl(로컬+공개도메인)과 실기기 앱 스크린샷으로
  종단 검증 완료. 앱이 아직 스토어 배포 전(디버그 단일기기 테스트 단계)이라 이
  breaking change를 즉시 프로덕션에 반영해도 안전했다 — **스토어 출시 이후에는
  이런 식으로 즉시 강제하면 안 되고 단계적 롤아웃 필요**, 다음에 유사 작업 시 참고.
- 문서화: `loop/RELEASE_ROADMAP.md` 21번 상태 갱신(108행 테이블, 841행 상세),
  `loop/HANDOFF_0730_navi_api_key_auth.md`(상세 인수인계),
  `loop/MORNING_REPORT_0730_navi_api_key_auth.md`(세션 보고, Goal/Met 판정).
- 커밋: `bc1fa0c` → `c72f873` → `17fa4a2`(문서) → `aa3594d`(STATUS.md 재생성).

**상세는 `loop/HANDOFF_0730_navi_api_key_auth.md` 참고 — 이 파일은 요약만.**

## 다음 세션 후보 (21번 잔여 우선순위)

`loop/HANDOFF_0729_server_security_audit.md`와
`loop/RELEASE_ROADMAP.md:841` 상세 섹션 참고.

1. ~~Cloudflare 대시보드 WAF/Rate Limiting/Bot Fight Mode~~ — **완료(2026-07-30
   저녁, 마스터가 대시보드에서 직접)**. 무료 플랜 제약으로 실제 구성은: Rate
   limiting(navi+valhalla, IP당 30요청/10초 Block, 무료 쿼터 1/1 사용) + Custom
   rule(navi/valhalla/tiles를 KR·JP 외 국가는 Block, 무료 쿼터 1/5 사용). WAF
   Managed Rules(OWASP)는 Pro($25/월) 전용이라 스킵, Bot Fight Mode는 API 전용
   도메인이라 의미 없어 안 켜기로 결정. 실기기 테스트 완료, 이상 없음. 상세는
   `loop/RELEASE_ROADMAP.md:841` 21번 섹션 참고. Custom rules 잔여 4개 남음.
2. ~~API 공유키 인증~~ — 완료.
3. **`ufw` 활성화 + 인바운드 규칙** — 가장 효과 크지만 SSH 락아웃/사이트 전체 다운
   위험 있음. 콘솔 접속(SSH 아닌 별도 경로) 확보 후, SSH 허용 규칙부터 추가·확인,
   그다음 `ufw enable`, 각 규칙마다 공개 도메인 curl로 생존 확인하며 단계적으로.
   `docker_default` 서브넷은 `172.19.0.0/16` 확인해둠. 같은 물리서버의
   `n8n-stack` 프로젝트 서비스(VNC/Selenium/Syncthing 등)도 막지 않게 주의.
4. **요청 로깅** (`tower_http::TraceLayer` 등) — 로드맵 20번(위치정보 확인자료
   로깅)과 근본 원인 같음, 묶어서 처리 권장.
5. **fail2ban 설치** — SSH 이미 키인증 추정이라 우선순위 낮음.

valhalla(8002)·tiles(8080)는 서드파티 이미지라 이번 방식(앱단 헤더)이 안 통한다 —
1번(Cloudflare) 또는 3번(ufw) 경로로만 다룰 수 있음, 여전히 무인증 상태로 남아있음.

## 이번 세션에서 발견했지만 처리 안 한 것 (별도 확인 필요)

code-auditor가 이번 감사 중 `scripts/scrape_rear_camera_notices.py`가 untracked
상태로 다시 존재하는 것을 지적했다. 메모리 기록(`feedback_no_dreamrider_api_access`)상
후면단속카메라 관련 원본/스크립트/백업은 2026-07-29에 전량 삭제했고 해당 서드파티
API 재접속은 마스터가 명시적으로 금지한 항목이다. 이번 작업 범위 밖이라 손대지
않았지만, 다음 세션 시작 시 마스터에게 이 파일의 출처를 먼저 확인할 것 — 임의로
삭제하지도, 실행하지도 말 것.
