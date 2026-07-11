# YuruNavi 백엔드 인프라 (2026-07-11 정리, 로드맵 12번)

이 문서의 목적: 서버(현재 westinx.com 호스트 1대)가 사라졌을 때 "무엇을 어디서 다시
가져와서 어떤 순서로 살려야 하는지"를 코드/설정만 봐서는 알 수 없는 부분까지 포함해
기록하는 것. 실서버 조사 기준일 2026-07-11.

## 1. 서비스 구성

| 서비스 | 컨테이너명 | 포트 | 정의 위치 | 데이터 |
|---|---|---|---|---|
| Valhalla 라우팅 (fun-road 커스텀 포크) | `yurunavi-valhalla` | 8002 | `docker/docker-compose.yml` | `/data/valhalla/custom_files` |
| tileserver-gl (지도 타일) | `yurunavi-tiles` | 8080 | `docker/docker-compose.yml` | `/data/tiles/data`, `/data/tiles/fonts` |
| navi 백엔드 (fun-road 스코어링 API, Rust) | `yurunavi-navi` | 8003 (host network) | `docker/docker-compose.yml` + `native/Dockerfile` | 없음(stateless) |

세 서비스 모두 `docker compose up -d`로 기동 가능(2026-07-11 기준 compose 관리 편입 완료 —
`tiles`는 원래 `docker run`으로, `navi`는 원래 systemd로 떠 있던 걸 이 세션에서 전환함,
둘 다 데이터 손실 없음). `navi`는 소스에 하드코딩된 `http://localhost:8002`(valhalla 호출)를
그대로 쓰기 위해 `network_mode: host`로 붙어있음 — 다른 두 서비스와 달리 `docker_default`
브리지 네트워크에 없음.

**`navi` Docker 전환 완료(2026-07-11)**: `yurunavi-rust.service`(구 systemd 서비스, 유닛
파일은 `/etc/systemd/system/`에 여전히 존재 — 롤백용으로 남겨둠, `disabled`+`inactive`
상태)를 대체해 `yurunavi-navi` 컨테이너가 포트 8003을 서빙 중. `curl https://navi.westinx.com
/health` → `{"status":"ok"}`로 Cloudflare Tunnel 경로까지 실제 검증함.

문제가 생기면 롤백:
```
docker compose stop navi
sudo systemctl start yurunavi-rust.service
```

## 2. 공개 HTTPS는 이 리포 밖에 있다 — Cloudflare Tunnel 의존성

`tiles.westinx.com` / `valhalla.westinx.com` / `navi.westinx.com`은 로컬 nginx나 certbot이
아니라 **Cloudflare Tunnel**을 통해 나간다. 실제로 쓰는 컨테이너는 `n8n_cloudflared`이고,
이건 이 리포가 아니라 완전히 별개 프로젝트인 `/data/n8n-stack/`에 정의되어 있다
(compose 파일도 그쪽 소유). 즉:

- **유루나비의 공개 접속 가능 여부가 n8n 스택의 생존에 묶여있다.** `n8n_cloudflared`가
  내려가면 세 도메인 모두 같이 죽는다.
- 라우팅 규칙(어떤 hostname이 어떤 로컬 포트로 가는지)은 로컬 파일이 아니라
  **Cloudflare Zero Trust 대시보드에 원격으로 저장**되어 있다. 컨테이너는 `TUNNEL_TOKEN`
  환경변수 하나로 그 원격 설정에 연결될 뿐 — 로컬엔 라우팅 config 파일이 없다
  (`docker inspect n8n_cloudflared`로 확인, Mounts 비어있음).
- 서버를 새로 판다면: Cloudflare Zero Trust 대시보드에 로그인해 기존 터널의
  `TUNNEL_TOKEN`으로 새 `cloudflared` 컨테이너를 연결하면 기존 라우팅 규칙이 그대로
  살아난다(토큰 기반 터널은 라우팅이 클라우드 쪽에 저장됨). **이 토큰을 잃어버리면
  안 됨** — 지금은 `/data/n8n-stack/`의 docker-compose 환경변수로만 존재한다. 별도
  비밀번호 관리자에 백업해두길 권장(이 리포에서 직접 처리하지 않음 — 다른 프로젝트
  소유라 CLAUDE.md 범위 밖).
- TLS 인증서: 위 세 도메인은 Cloudflare 엣지에서 처리되므로 로컬 certbot 갱신 대상이
  아니다. 로컬 `/etc/letsencrypt`엔 `n8n.westinx.com`만 있음(확인됨) — 이것도 이 리포와
  무관.

## 3. ⚠️ 이번 조사 중 발견한 더 심각한 문제 — valhalla 포크 소스가 커밋 안 되어 있었음

`docker-compose.yml`의 `valhalla-fork:patch3-uturn` 이미지를 실제로 빌드하는 소스는
`/data/projects/valhalla-src`(공식 `valhalla/valhalla` git checkout, 현재 로컬 브랜치
`yurunavi-fork`)에 있다. 2026-07-11 조사 시점에 이 브랜치는 **detached HEAD 위에
uncommitted 상태로만** 존재했다 — `motorcyclecost.cc`(곡률/신호/U턴 커스텀 코스팅,
이 앱의 핵심 차별화 로직)와 `proto/descriptors/options.proto` 수정분, 그리고
`docker/Dockerfile.fork`(빌드 파일 자체)가 전부 git 이력이 전혀 없는 워킹트리 변경으로만
존재. 이 디렉토리가 사라지면 앱의 핵심 라우팅 로직이 영구 소실될 뻔한 상태였음.

**조치 완료(2026-07-11, 이번 세션)**: `yurunavi-fork` 로컬 브랜치를 만들어 세 파일 모두
커밋(`cbf9a425b`). **origin(공식 valhalla/valhalla.git)에는 push 안 함** — 이 브랜치는
로컬 전용. `docker/backup.sh`가 이 디렉토리 전체(`.git` 포함)를 매일 백업 대상에 포함하도록
추가함.

**남은 리스크**: 이 소스는 여전히 이 서버에만 존재하는 로컬 커밋이다. 진짜 원격
백업(예: private GitHub 리포로 push)은 하지 않았음 — 다른 GitHub 계정/조직 리소스를
새로 만드는 일이라 사용자 승인 없이 진행하지 않음. 원한다면 다음 세션에서
`git remote add backup <private-repo-url> && git push backup yurunavi-fork`로 처리 가능.

## 4. 백업

`docker/backup.sh` — 매일 03:00 cron(`crontab -l`로 확인 가능, hm-tracker의 기존
`0 0 * * *` 항목은 그대로 유지됨). rsync `--link-dest` 기반 하드링크 스냅샷으로 최근
3세대 보관(변경 없는 파일은 디스크를 다시 안 씀).

| 대상 | 원본 | 백업 위치 | 대략 크기 |
|---|---|---|---|
| 지도 타일 데이터 | `/data/tiles/data` | `/data/backups/yurunavi/tiles/` | ~3.4GB |
| Valhalla 그래프/원본 PBF | `/data/valhalla/custom_files` | `/data/backups/yurunavi/valhalla/` | ~11GB |
| Valhalla 포크 소스(git) | `/data/projects/valhalla-src` | `/data/backups/yurunavi/valhalla-src/` | ~423MB |

`/data` 디스크 여유 1.7TB(2026-07-11 기준) — 3세대 유지해도 여유 충분. 백업은 **같은
물리 서버 안의 다른 경로**일 뿐 오프사이트 백업이 아님 — 디스크 자체가 죽는
시나리오에는 방어 안 됨. 진짜 재해복구를 원하면 이 경로를 주기적으로 서버 밖(S3,
다른 머신 등)으로 옮기는 걸 추후 고려.

복구: `rsync -a /data/backups/yurunavi/<name>/latest/ <원래경로>/`

## 5. 여기서 다루지 않은 것 (범위 밖, 확인만 함)

- `tools/style-ai-proxy`, `tools/tuning_dashboard` — 내부 개발 도구, 이미 자체
  Dockerfile/compose가 있고 git 추적 중. 프로덕션 서빙 경로가 아니라 12번 스코프 아님.
- 모니터링(Prometheus/Grafana 등 정식 스택)은 이번 세션에 새로 안 만듦 — compose
  healthcheck 수준(tiles는 이미지 자체 헬스체크, navi는 Dockerfile의 HEALTHCHECK)만
  적용됨. `docker ps`로 상태 확인 가능. 본격 모니터링은 필요해지면 별도 항목으로.
