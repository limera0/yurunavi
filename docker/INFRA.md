# YuruNavi 백엔드 인프라 (2026-07-11 정리, 로드맵 12번)

이 문서의 목적: 서버(현재 westinx.com 호스트 1대)가 사라졌을 때 "무엇을 어디서 다시
가져와서 어떤 순서로 살려야 하는지"를 코드/설정만 봐서는 알 수 없는 부분까지 포함해
기록하는 것. 실서버 조사 기준일 2026-07-11.

## 1. 서비스 구성

| 서비스 | 컨테이너명 | 포트 | 정의 위치 | 데이터 |
|---|---|---|---|---|
| Valhalla 라우팅 (fun-road 커스텀 포크) | `yurunavi-valhalla` | 8002 | `docker/docker-compose.yml` | `/data/valhalla/custom_files` |
| tileserver-gl (지도 타일) | `yurunavi-tiles` | 8080 | `docker/docker-compose.yml` | `/data/tiles/data`, `/data/tiles/fonts` |
| navi 백엔드 (fun-road 스코어링 + POI API, Rust) | `yurunavi-navi` | 8003 (host network) | `docker/docker-compose.yml` + `native/Dockerfile` | `/data/poi/poi.db`(SQLite, 읽기전용 마운트, 2026-07-15부터) |

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
| POI 원본 CSV + SQLite DB | `/data/poi` (raw/ + poi.db) | `/data/backups/yurunavi/poi/` | ~1.6GB |

`/data` 디스크 여유 1.7TB(2026-07-11 기준) — 3세대 유지해도 여유 충분. 백업은 **같은
물리 서버 안의 다른 경로**일 뿐 오프사이트 백업이 아님 — 디스크 자체가 죽는
시나리오에는 방어 안 됨. 진짜 재해복구를 원하면 이 경로를 주기적으로 서버 밖(S3,
다른 머신 등)으로 옮기는 걸 추후 고려.

복구: `rsync -a /data/backups/yurunavi/<name>/latest/ <원래경로>/`

## 5. POI 데이터 파이프라인 (2026-07-15 구축)

**배경**: 이전엔 Flutter 클라이언트가 공공데이터포털 실시간 API(`apis.data.go.kr`)를
서비스키로 직접 호출했다 — 이 방식은 전 사용자가 개발계정 쿼터(10,000건/일) 하나를
공유하는 구조라 실사용자 몇 명만 늘어도 매일 막히는 근본적 스케일링 결함이었다
(`loop/HANDOFF_0715_poi_quota.md` 참조, 실제로 개발자 1인 테스트만으로 하루 쿼터 소진
확인됨). 같은 기관이 같은 데이터를 분기별 무료 CSV로도 배포한다는 걸 확인하고, 이걸
`navi` 백엔드에 SQLite로 적재해 서빙하는 방식으로 전환했다.

- **원본 데이터**: [소상공인시장진흥공단_상가(상권)정보](https://www.data.go.kr/data/15083033/fileData.do)
  (data.go.kr, 로그인/키 불필요, 분기 갱신, 이용허락범위 제한없음). 17개 시도별 CSV가
  담긴 zip, 2026-07-15 기준 약 2.73M행/341MB.
- **적재**: `native/src/bin/ingest_poi.rs` — CSV를 카테고리 매핑(cafe/convenience_store/
  gas_station/supermarket/restaurant) + 오분류 필터링(업소명 키워드 휴리스틱, 과거
  Dart `looksMisclassified`에서 이관) 거쳐 `/data/poi/poi.db`(SQLite + R-tree 공간 인덱스)로
  전체 재적재한다. 2026-07-15 최초 적재: 696,255행, 153.6MB, 약 12초 소요.
- **서빙**: `native/src/main.rs`의 `GET /poi/nearby?lat&lon&radius_m&types` — DB를
  읽기전용으로 서버 시작 시 한 번만 연다. **DB 파일이 없거나 손상돼도 서버 전체가
  죽지 않는다** — 그 라우트만 503을 반환하고 라우팅/스코어링 등 다른 엔드포인트는
  정상 동작(`poi_db()` 함수의 `OnceLock<Option<Mutex<Connection>>>` 패턴 참조).
- **⚠️ 중요 — 갱신 후 반드시 컨테이너 재시작 필요**: 위와 같이 DB를 시작 시 한 번만
  열기 때문에, `/data/poi/poi.db` 파일을 새로 갈아끼워도 `docker compose restart navi`를
  하지 않으면 새 데이터가 반영되지 않는다(구 데이터를 계속 서빙).

### 분기 재동기화

`docker/refresh_poi_data.sh` — data.go.kr에서 최신 CSV를 받아 검증 후 raw 디렉터리와
`poi.db`를 원자적으로 교체하고 `navi` 컨테이너를 재시작한다. 실패 시(다운로드 링크를
못 찾음, zip이 아님, 행수/DB크기가 예상 범위 밖) 항상 **기존 데이터를 그대로 두고
비정상 종료** — 부분 갱신으로 데이터가 손상되는 경우는 없다.

```
/data/projects/yurunavi/docker/refresh_poi_data.sh
```

**자동 cron 등록은 의도적으로 하지 않았다.** 이유: 다운로드 링크 추출이 data.go.kr
페이지의 JSON-LD(`contentUrl`) 파싱에 의존하는데, 그 사이트 구조가 바뀌면 새벽 cron에서
조용히 실패(또는 더 나쁘게는 검증을 다 통과하는 이상한 응답)할 수 있고, 이걸 아무도
안 보는 채로 다음 분기까지 방치할 위험이 있다고 판단했다. 다음 갱신 예정일은
**2026-08-01** — 그 무렵 사람이(또는 다음 Claude Code 세션이) 수동으로 스크립트를
한 번 돌려보고, 문제없이 몇 차례 안정적으로 동작하는 걸 확인한 뒤에 아래 줄을
`crontab -e`로 직접 추가하는 걸 권장한다(스크립트 자체 주석에도 동일 안내 있음):

```
0 4 1 8,11,2,5 * /data/projects/yurunavi/docker/refresh_poi_data.sh >> /data/poi/refresh.log 2>&1
```

## 6. 여기서 다루지 않은 것 (범위 밖, 확인만 함)

- `tools/style-ai-proxy`, `tools/tuning_dashboard` — 내부 개발 도구, 이미 자체
  Dockerfile/compose가 있고 git 추적 중. 프로덕션 서빙 경로가 아니라 12번 스코프 아님.
- 모니터링(Prometheus/Grafana 등 정식 스택)은 이번 세션에 새로 안 만듦 — compose
  healthcheck 수준(tiles는 이미지 자체 헬스체크, navi는 Dockerfile의 HEALTHCHECK)만
  적용됨. `docker ps`로 상태 확인 가능. 본격 모니터링은 필요해지면 별도 항목으로.
