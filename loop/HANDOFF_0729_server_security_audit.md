GOAL: 인수인계 기록 — 21번(운영 서버 보안 강화) 착수 시 이 문서부터 읽고 권장
우선순위 1번(Cloudflare 대시보드 설정)부터 마스터와 확인 후 진행. 즉시 착수 지시
아님 — 마스터가 "별도 세션에서 하나씩" 진행하겠다고 결정(2026-07-29).

이 파일을 읽는 Claude는: (1) 아래 감사 결과가 여전히 유효한지 `git log`/실제 설정
확인으로 재검증할 것(시간이 지났으면 상황이 바뀌었을 수 있음), (2) 권장 우선순위
중 마스터가 고른 항목부터 진행, (3) 방화벽(`ufw`) 관련 작업은 특히 신중히 —
잘못하면 SSH 락아웃 또는 사이트 전체 다운 위험이 있으므로 콘솔 접속을 별도로
확보한 상태에서만 진행할 것.

---

## 배경

2026-07-29, 개인정보처리방침/이용약관 외부 법률 검토를 반영하던 세션 중, 마스터가
"네이버·카카오·중국 해커 등의 역설계·서버침입·해킹을 완벽하게 막도록, 운영 서버의
보안을 강화하는 방법을 보안 전문가 수준에서 검토하고 보고하라"고 요청. 읽기 전용
조사만 수행했고, 리스크 있는 변경(방화벽 활성화 등)은 이번 세션에서 실행하지 않고
보고 + 로드맵/이 핸드오프 기록만 남김.

전제로 먼저 밝혀둔 것: **"완벽한 차단"은 인터넷에 연결된 어떤 시스템에도 현실적으로
불가능하다.** 실현 가능한 목표는 계층적 방어로 뚫릴 확률과 뚫렸을 때 피해를 실질적
수준까지 낮추는 것이다.

## 감사 방법

운영 서버(`westinx` 호스트, 이 세션이 실행되던 바로 그 머신)에서 읽기 전용 명령만
사용: `ufw status`/`ss -tlnp`/`docker ps`/`docker inspect`/`docker network inspect`,
`native/src/main.rs`·`Cargo.toml`·`lib/core/config/app_config.dart` grep, 파일 권한
확인(`stat`, `ls -la`), sshd 설정 파일 크기 정황 확인(root 소유라 직접 못 읽음),
`unattended-upgrades` 상태, `/etc/passwd` 계정 목록. 변경한 것은 `native/.env` 파일
권한 644→600 단 하나뿐(아래 참고, 무위험 로컬 조치라 즉시 처리함).

## 확인된 사실

### 1순위 — 네트워크 노출

- `ufw` 방화벽이 꺼져 있음(`ufw status` → `ENABLED=no`, `/etc/ufw/ufw.conf` 확인).
- `docker-compose.yml`에서 다음 서비스가 전부 `0.0.0.0`에 직접 포트를 바인딩:
  - `yurunavi-valhalla` — `0.0.0.0:8002->8002`
  - `yurunavi-tiles` — `0.0.0.0:8080->8080`
  - `yurunavi-navi` — `network_mode: host`이므로 `0.0.0.0:8003`으로 바인딩
    (`native/src/main.rs`의 `TcpListener::bind("0.0.0.0:8003")` 확인)
  - `yurunavi-style-ai`(개발 도구, `0.0.0.0:8014`)도 마찬가지
- `docker/INFRA.md`에 따르면 공개 도메인(`tiles.westinx.com`/`valhalla.westinx.com`/
  `navi.westinx.com`) 접속은 Cloudflare Tunnel(`n8n_cloudflared`, 이 리포 밖
  `/data/n8n-stack/` 소유)을 경유한다. 하지만 그건 **도메인 경유 접속**에 대한
  이야기고, 위 포트들이 서버의 **공인 IP에 직접 열려 있는 것과는 별개 경로**다.
  클라우드 공급자(호스팅사) 쪽에 별도 보안그룹/방화벽이 없다면, 공인 IP만 알면
  Cloudflare를 완전히 우회해서 이 포트들에 직접 접근 가능한 상태로 추정된다.
  - **검증 안 됨**: 서버 안에서 자기 자신의 공인 IP로 `curl` 테스트를 시도했으나
    hairpin NAT 문제로 연결 자체가 실패(HTTP 000)해 결론을 못 냈다. **외부망(와이파이
    끄고 휴대폰 데이터 등)에서 `http://<공인 IP>:8002/status`,
    `http://<공인 IP>:8080/`, `http://<공인 IP>:8003/health`를 직접 열어보면 실제
    노출 여부를 바로 확인할 수 있다** — 다음 세션에서 이것부터 먼저 재확인 권장.
  - 참고로 같은 서버의 다른 프로젝트(`n8n-stack`) 컨테이너들도 VNC(5900),
    Selenium(4444), Syncthing(8384/22000) 등을 `0.0.0.0`에 노출 중이었다 — 이
    리포 범위 밖이라 손대지 않았지만, 같은 물리 서버라 방화벽을 켤 때 참고할 것
    (다른 서비스를 막지 않도록 규칙을 정확히 설계해야 함).

### 2순위 — API 인증/속도 제한 부재

- `native/src/main.rs`의 navi API(`/poi/nearby`, `/gasstations/nearby`,
  `/routing-config` 등), valhalla(8002), tiles(8080) 어디에도 인증 헤더 검사나
  속도 제한(rate limiting) 코드가 없다(`Cargo.toml`에 governor 등 관련 크레이트
  없음, `main.rs`에 `Authorization`/`X-Api-Key` 검사 없음).
- Flutter 앱 쪽(`lib/core/config/app_config.dart`, `lib/services/*.dart`)도 이
  API들을 호출할 때 아무 인증 헤더를 붙이지 않는다(코드로 확인).
- **의미**: 경쟁사가 앱을 디컴파일할 필요조차 없이, 자기 폰에 mitmproxy 같은 걸
  깔고 트래픽만 관찰하면 fun-road 스코어링 로직의 입출력을 블랙박스로 그대로
  긁어갈 수 있다. 동시에 무차별 스크립트 요청(DoS, 자원 낭비)에도 그대로 노출된다.

### 3순위 — 파일 권한 (조치 완료)

- `native/.env`(VWorld API 키 포함, `docker-compose.yml`에서 `navi` 컨테이너가
  `env_file`로 읽음)가 `644`(다른 로컬 계정도 읽기 가능)로 방치돼 있었다.
- **2026-07-29 이 세션에서 `600`으로 즉시 수정 완료** — 무위험 순수 로컬 조치라
  보고만 하지 않고 바로 처리함. 다만 `/etc/passwd` 확인 결과 이 서버엔 실사용자
  계정이 `limera` 하나뿐이라, 실제 노출 위험 자체는 낮았음(그래도 원칙적으로 맞는
  조치 — 다른 UID로 도는 프로세스가 생기면 의미가 커짐).

### 4순위 — 로그/감사 추적 부재

- Rust 백엔드에 `tower_http::TraceLayer` 등 요청 로깅 미들웨어가 전혀 없다
  (`Cargo.toml`에 `tower-http`/`tracing` 의존성 자체가 없음). 침입이 실제로
  발생해도 언제·어디서·무엇이 뚫렸는지 추적할 로그가 없다는 뜻.
  - 로드맵 20번(위치정보 확인자료 로깅)과 근본 원인이 같다 — 요청 로깅을 한 번
    구현하면 두 문제를 같이 해결할 수 있으니 묶어서 처리 권장.

### 5순위 — 이미 양호한 부분 (건드리지 말고 유지)

- SSH: `~/.ssh/authorized_keys`가 존재해 키 기반 인증을 쓰는 것으로 보임.
  `/etc/ssh/sshd_config.d/50-cloud-init.conf`는 root 소유 600이라 직접 못 읽었지만,
  파일 크기가 정확히 27바이트로 `PasswordAuthentication no\n`(26자+개행)와 일치 —
  **정황상 유력하지만 100% 확정은 아님**. 다음 세션에서 `sudo cat`으로 확정 가능하면
  확정해둘 것.
- OS 보안 자동 업데이트(`unattended-upgrades`)가 이미 `enabled` 상태.
- SQL 인젝션 경로 없음 — `rusqlite`에서 전부 `?1`/`?2` 파라미터 바인딩 사용 확인.
- APK 쪽 ProGuard/R8은 이미 활성화됨(로드맵 4번, DONE) — 정적 디컴파일 방어는
  기본 수준 확보된 상태.

## 권장 우선순위 (실행은 전부 마스터 확인 후, 단계별로)

1. **Cloudflare 대시보드에서 WAF/Rate Limiting/Bot Fight Mode 켜기.** 서버 코드
   변경이 전혀 없고 리스크도 최소라 가장 먼저 할 만하다. 다만 이 Cloudflare
   계정이 `/data/n8n-stack/`(별개 프로젝트) 소유라 Claude가 이 리포에서 직접
   조작할 수 없다 — 마스터가 대시보드에서 직접 진행해야 함.
2. **API에 최소한의 공유 키(헤더) 인증 추가.** Flutter 앱과 Rust 서버를 함께
   배포해야 하는 코드 작업 — 별도 세션으로 진행 권장(rust-coder + flutter-coder
   위임 대상). 스크래핑/역설계 방어와 무단 남용 억제를 동시에 해결한다.
3. **`ufw` 활성화 + 인바운드 규칙 구성.** `docker_default` 브리지 서브넷은
   `172.19.0.0/16`으로 확인해뒀다. 하지만 Cloudflare Tunnel(`n8n_cloudflared`,
   `n8n_network` 브리지 소속)이 정확히 어느 경로로 yurunavi 컨테이너들에 도달하는지는
   이 리포 밖(Cloudflare Zero Trust 대시보드에 라우팅 규칙이 원격 저장됨, `docker/
   INFRA.md` §2 참고)이라 이 세션에서 완전히 확정하지 못했다. **이게 왜 위험한
   작업인지**: 잘못된 규칙으로 `ufw default deny incoming`을 걸면 SSH가 막히거나
   (락아웃) 공개 도메인 전체가 죽을 수 있다. 진행할 때는:
   - 반드시 별도 콘솔 접속(클라우드 공급자 웹 콘솔 등, SSH가 아닌 경로)을 먼저
     확보해둔 채로 시작할 것.
   - SSH 허용 규칙을 가장 먼저 추가하고 확인한 뒤에 `ufw enable`.
   - 각 규칙을 하나씩 추가하며 그때그때 `curl`로 공개 도메인이 여전히 살아있는지
     확인.
4. **요청 로깅 추가** (`tower_http::TraceLayer` 등) — 로드맵 20번과 함께 처리.
5. **fail2ban 설치** — SSH가 이미 키 인증만 쓰는 것으로 보여 우선순위는 낮음.

## 관련 항목

- 로드맵 20번(위치정보 확인자료 로깅) — 이 문서의 4순위 항목과 근본 원인 동일,
  함께 처리 권장.
- 로드맵 6번(위치기반서비스사업 신고) — 여전히 사용자 액션 대기 중.
