GOAL: 21번(운영 서버 보안 강화) 3순위(ufw)·5순위(fail2ban)를 마스터가 콘솔 앞에서
직접, 단계별로 안전하게 실행하기 위한 순서서

> Claude는 이 서버 Bash 세션에서 `sudo`를 비밀번호 없이 실행할 수 없다(`sudo -n`
> → "a password is required")고 2026-07-30 확인했다. 그래서 이 작업은 Claude가
> 대신 실행하는 게 아니라 **마스터가 이 문서를 보며 직접 터미널에서 실행**해야
> 한다. 각 단계 사이에 반드시 검증하고, 이상하면 그 단계에서 멈추고 롤백할 것.
>
> **절대 원격 세션(SSH) 하나로만 이어서 실행하지 말 것.** SSH 자체가 막힐 수
> 있는 작업이라, 클라우드 provider 콘솔(웹 콘솔/시리얼 콘솔 등 SSH가 아닌 별도
> 접속 경로)을 먼저 열어두고, 그 창을 통해 다음 단계로 넘어가도 괜찮은지
> 확인하면서 진행한다.

## 0. 왜 이게 위험한가 — 결론부터

이 서버(호스트)에는 이 리포(`yurunavi`) 서비스 말고도 `/data/n8n-stack/`의 완전히
다른 프로젝트가 같이 떠 있다. `ufw enable`은 **리포 단위가 아니라 호스트 전체**에
적용되는 방화벽이다 — 잘못 설정하면 SSH가 끊기거나(락아웃), n8n-stack 서비스가
같이 죽을 수 있다. CLAUDE.md 하드룰상 n8n-stack은 "이 리포에서 손대지 말 것"이라,
아래 순서는 n8n-stack 포트는 건드리지 않는 방향으로 짰다.

**추가로 발견한, 이전 감사(`HANDOFF_0729`)에 없던 중요한 사실**: 이 서버의
docker 게시 포트(valhalla 8002, tiles 8080, style-ai 8014 — `docker-compose.yml`의
`ports:` 항목으로 게시된 것들) 는 **`ufw enable`만으로는 보호되지 않는다.**
Docker는 자체적으로 `iptables`의 `DOCKER-USER`/`FORWARD` 체인에 규칙을 넣는데,
이 체인이 `ufw`의 `INPUT` 체인보다 먼저 패킷을 가로챈다 — 즉 `ufw deny 8002`를
걸어도 실제로는 아무 효과가 없고, 8002/8080/8014는 여전히 공인 IP로 그대로
뚫려 있는 상태가 유지된다(이건 ufw+Docker 조합에서 아주 흔히 알려진 함정이다).
반면 `navi`(8003)와 `tuning-dashboard`는 `docker-compose.yml`에 `network_mode:
host`로 떠 있어서 일반 프로세스처럼 동작 — 이 둘은 `ufw`의 `INPUT` 체인 규칙이
정상적으로 먹힌다.

| 서비스 | 포트 | 네트워크 방식 | ufw INPUT 규칙이 먹히나 | 비고 |
|---|---|---|---|---|
| navi | 8003 | `network_mode: host` | 먹힘 | X-Api-Key 인증 있음(2026-07-30 완료) |
| valhalla | 8002 | docker bridge(`docker_default`, 172.19.0.0/16) 게시 | **안 먹힘**(DOCKER-USER 별도 규칙 필요) | 무인증 |
| tiles | 8080 | docker bridge(`docker_default`) 게시 | **안 먹힘** | 무인증, 공개 타일이라 보호가치는 낮음 |
| style-ai | 8014 | docker bridge(`style-ai-proxy_default`, 별도 compose 네트워크) 게시 | **안 먹힘** | 무인증 |
| tuning-dashboard | 8501(Streamlit) | `network_mode: host` | 먹힘 | 인증 전혀 없음, Cloudflare 공개 도메인 없는 것으로 추정(내부용) |
| SSH | 22(추정 — 아래 1단계에서 확인) | 호스트 | 먹힘 | |

또 하나: 이 서버의 Cloudflare Tunnel(`n8n_cloudflared` 컨테이너, `n8n-stack` 소유)은
`n8n_network`(172.18.0.0/16)라는, `yurunavi`의 `docker_default`(172.19.0.0/16)와
**다른** docker 네트워크에 붙어 있다. navi/valhalla/tiles/style-ai에 도달하려면
호스트의 브리지 게이트웨이를 경유해야 하는 구조로 보인다 — **이 부분은 Claude가
로컬 파일만으로 100% 확인하지 못했다.** cloudflared는 `TUNNEL_TOKEN` 방식(대시보드
관리형 tunnel)이라 ingress 규칙이 로컬 설정 파일이 아니라 Cloudflare Zero Trust
대시보드에만 있고, 그 계정은 `n8n-stack` 소유라 Claude가 못 본다.

**→ 아래 순서를 실행하기 전에, 마스터가 Cloudflare Zero Trust 대시보드
(Networks → Tunnels → 해당 tunnel → Public Hostname)에서 navi/valhalla/tiles/
style-ai 각 도메인의 origin(서비스) 주소가 실제로 무엇으로 설정돼 있는지 먼저
확인해라.** 아래 규칙은 "172.18.0.0/16(n8n_network)에서 오는 트래픽은 허용"을
전제로 짰는데, 만약 origin이 다른 방식(예: 호스트의 실제 사설 IP를 직접 지정)이면
그 IP/대역을 반영해서 규칙을 조정해야 한다.

## 1. 사전 준비 (실행 전 필수)

```bash
# 1) 콘솔(SSH 아닌 경로) 접속 창을 미리 하나 열어둔다 — 이후 모든 단계에서
#    "SSH가 막혀도 이 창으로 들어가 ufw disable 할 수 있다"는 게 확인돼야 진행.

# 2) 현재 상태 백업
sudo ufw status verbose > /tmp/ufw_status_before.txt
sudo iptables-save > /tmp/iptables_before.rules
sudo cp /etc/ufw/after.rules /etc/ufw/after.rules.bak-$(date +%Y%m%d)

# 3) SSH 포트 확인 (기본 22가 아닐 수 있음 — sshd_config에 Port 지시자 없으면 22)
sudo grep -Ei '^Port ' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
# 아무 것도 안 나오면 기본값 22.

# 4) 지금 각 공개 도메인이 정상 동작하는지 기준선 기록
curl -s -o /dev/null -w "navi: %{http_code}\n"     https://navi.westinx.com/health
curl -s -o /dev/null -w "valhalla: %{http_code}\n" https://valhalla.westinx.com/status
curl -s -o /dev/null -w "tiles: %{http_code}\n"    https://tiles.westinx.com/
```

## 2. SSH 허용 규칙 먼저 (ufw enable보다 반드시 먼저)

```bash
sudo ufw allow OpenSSH        # 또는 Port가 22가 아니면: sudo ufw allow <포트>/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

## 3. ufw enable — 여기서부터 한 단계씩

```bash
sudo ufw enable
```

**즉시**, 기존 세션은 그대로 둔 채 **콘솔 창**에서 새 SSH 접속을 시도해라.
안 되면 콘솔로 들어가 `sudo ufw disable`로 즉시 원복.

성공하면:
```bash
sudo ufw status verbose
curl -s -o /dev/null -w "navi: %{http_code}\n" https://navi.westinx.com/health
```
(이 시점엔 navi는 host 모드라 default-deny의 영향을 받는다 — 아래 4단계에서
필요한 소스만 허용해줘야 계속 동작한다. 순서상 여기서 잠깐 navi가 502/타임아웃이
나는 건 정상이니 당황하지 말고 바로 4단계로.)

## 4. navi(8003)·tuning-dashboard(8501) 허용 규칙 — host-mode 서비스

```bash
# navi: cloudflared(n8n_network, 172.18.0.0/16)에서만 허용.
# ⚠️ 위 0장에서 언급한 대로, 실제 origin 주소를 Cloudflare 대시보드에서 먼저
#   확인했는지 재확인 — 다른 대역이면 172.18.0.0/16을 그 값으로 바꿀 것.
sudo ufw allow from 172.18.0.0/16 to any port 8003 proto tcp
sudo ufw allow from 127.0.0.1 to any port 8003 proto tcp

# tuning-dashboard(8501): 공개 도메인 없는 내부 도구로 추정 — 기본적으로 막고,
# 마스터 본인만 SSH 터널(`ssh -L 8501:localhost:8501 ...`)로 접속하는 걸 권장.
# 정말 외부에서 직접 붙어야 하는 상황이면 본인 고정 IP만 allow.
# (아무 규칙도 추가하지 않으면 default deny로 자동 차단됨 — 별도 조치 불필요)

curl -s -o /dev/null -w "navi: %{http_code}\n" https://navi.westinx.com/health
# 200(또는 헬스체크가 기대하는 코드)이 나와야 함. 안 나오면 172.18.0.0/16 가정이
# 틀렸다는 뜻 — Cloudflare 대시보드에서 origin 주소 재확인.
```

## 5. valhalla(8002)·tiles(8080)·style-ai(8014) — DOCKER-USER 체인 규칙

**0장에서 설명한 이유로, 이 셋은 위 `ufw allow/deny`가 전혀 효과가 없다.**
`/etc/ufw/after.rules` 맨 끝(`# END UFW AND DOCKER` 표시가 있으면 그 앞, 없으면
파일 끝)에 아래를 추가한다 — `ufw-docker` 같은 서드파티 스크립트를 새로 받아
root로 돌리는 대신, 직접 규칙을 넣어 신뢰 경계를 최소화하는 방식이다.

```bash
sudo tee -a /etc/ufw/after.rules > /dev/null <<'EOF'

# --- yurunavi: docker-published 포트를 n8n_network(cloudflared)에서만 허용 ---
# (이 블록만 추가/삭제하면 되므로 롤백이 쉽다 — n8n-stack 자체 포트는 건드리지 않음)
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -s 172.18.0.0/16 -p tcp -m multiport --dports 8002,8080,8014 -j RETURN
-A DOCKER-USER -s 127.0.0.0/8 -p tcp -m multiport --dports 8002,8080,8014 -j RETURN
-A DOCKER-USER -p tcp -m multiport --dports 8002,8080,8014 -j DROP
COMMIT
# --- end yurunavi block ---
EOF

sudo ufw reload
```

검증(각 도메인, 순서대로 하나씩 — 한 번에 다 바꾸고 나중에 몰아서 확인하지 말 것):
```bash
curl -s -o /dev/null -w "valhalla: %{http_code}\n" https://valhalla.westinx.com/status
curl -s -o /dev/null -w "tiles: %{http_code}\n"    https://tiles.westinx.com/
curl -s -o /dev/null -w "style-ai: %{http_code}\n" https://<style-ai 도메인>/
```
전부 기존과 같은 코드가 나와야 한다. 하나라도 실패하면 `sudo cp
/etc/ufw/after.rules.bak-* /etc/ufw/after.rules && sudo ufw reload`로 그 블록만
롤백.

공인 IP로 직접 포트 접근이 실제로 막혔는지도 확인(휴대폰 데이터 등 이 서버와
무관한 외부망에서):
```bash
curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://<서버 공인 IP>:8002/status
# 타임아웃/연결거부가 나와야 정상(막힌 것). 200이 나오면 아직 뚫려있다는 뜻.
```

## 6. fail2ban (5순위)

SSH가 키 인증만 쓰는 것으로 추정되는 만큼 우선순위는 낮지만, 위 단계가 전부
안정된 뒤 마무리로 진행:

```bash
sudo apt update && sudo apt install -y fail2ban

sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[sshd]
enabled = true
port    = ssh
backend = systemd
maxretry = 5
bantime  = 1h
findtime = 10m
EOF

sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

## 7. 마무리 (전부 끝난 뒤)

```bash
sudo ufw status numbered   # 최종 규칙 스냅샷을 남겨두면 다음 세션이 참고하기 좋다
```

이 결과와 함께 다음 세션에서:
- `loop/RELEASE_ROADMAP.md` 21번 섹션에 3/5순위 완료 기록
- 실제로 적용한 규칙이 이 문서와 다르면(예: SSH 포트가 22가 아니었다거나,
  Cloudflare origin이 다른 대역이었다거나) 이 문서를 그 내용으로 갱신

## 롤백 요약 (문제 생기면 어느 단계든)

- 전체 원복: `sudo ufw disable`
- DOCKER-USER 블록만 원복: `sudo cp /etc/ufw/after.rules.bak-* /etc/ufw/after.rules && sudo ufw reload`
- fail2ban 때문에 본인이 밴 당함: `sudo fail2ban-client set sshd unbanip <내 IP>`
- 그래도 안 되면: 콘솔로 들어가 `sudo ufw disable && sudo systemctl stop fail2ban`
