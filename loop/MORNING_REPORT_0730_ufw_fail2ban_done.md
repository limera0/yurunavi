# 세션 보고 — ufw/fail2ban 완료 (2026-07-30 밤, 이어서)

`MORNING_REPORT_0730_access_log_and_ufw_prep.md`에서 "sudo 권한이 없어 3(ufw)/
5(fail2ban)는 RUNBOOK만 작성, 마스터 직접 실행 대기"로 보고했었는데, 같은 세션
안에서 마스터와 다시 논의해 진행 방식을 바꿔 실제로 완료했다.

## 상황이 바뀐 이유

마스터가 RUNBOOK을 읽고 "SSH 말고 콘솔 접속 경로가 없고(키보드/마우스를 새로
사야 함), 터미널 명령을 직접 치는 것도 부담스럽다"고 확인. RUNBOOK을 마스터가
직접 실행하게 하는 원래 계획은 비현실적이라고 판단.

## 한 일

- 마스터에게 두 옵션 제시(AskUserQuestion): "지금은 보류" vs "명령어 하나 붙여넣고
  나머지는 Claude가 자동으로" — 후자 선택받음.
- narrow-scope `NOPASSWD` sudoers 항목을 마스터가 한 번 붙여넣도록 안내
  (`/etc/sudoers.d/claude-ufw-fail2ban` — `ufw`/`iptables-save`/`/etc/ufw/
  after.rules` 백업·추가/`apt-get install fail2ban`/`systemctl`·`fail2ban-client`
  등 딱 필요한 명령어 12줄, `visudo -c`로 문법 검증 후 저장하는 방식이라 sudoers
  자체가 깨질 위험 없음).
- 위임받은 뒤 Claude가 직접 실행:
  1. 백업(`iptables-save`, `ufw status`, `after.rules` 복사본).
  2. SSH(22/tcp) 허용 + `default deny incoming`/`allow outgoing`.
  3. **`ufw enable` 직전 데드맨 스위치**(`nohup bash -c 'sleep 480 && sudo -n ufw
     disable'` 백그라운드) 걸어둠 — 콘솔이 없어도 몇 분 안에 자동 원상복구되게.
  4. `ufw enable` → SSH 세션 생존 확인, 도메인 3개(navi/valhalla/tiles) curl 200
     확인 → 데드맨 스위치 취소.
  5. navi(8003, `network_mode: host`)에 `172.18.0.0/16`(cloudflared가 있는
     `n8n_network`)·`127.0.0.1`만 허용하는 ufw 규칙 추가.
  6. valhalla(8002)/tiles(8080)/style-ai(8014)는 docker bridge 게시 포트라
     **일반 ufw 규칙이 안 먹힌다는 걸 발견**(Docker가 `DOCKER-USER`/`FORWARD`
     체인을 ufw `INPUT`보다 먼저 가로챔) — `/etc/ufw/after.rules`에
     `DOCKER-USER` 체인 전용 규칙(172.18.0.0/16·127.0.0.0/8만 RETURN, 나머진
     DROP) 추가.
  7. 도메인 3개 다시 curl 200 확인.
  8. fail2ban 설치(`apt-get install -y fail2ban` — 정확히 sudoers에 등록한
     인자와 일치해야 통과한다는 걸 실전에서 확인, `-qq` 등 추가 플래그 붙이면
     실패함), `[sshd]` jail 설정(`maxretry=5, bantime=1h, findtime=10m`),
     `fail2ban-client status sshd`로 정상 확인.
- 부수 발견: 이 호스트에 **Tailscale**(`tailscaled`)이 이미 설정돼 있음
  (`iptables-save`에서 `ts-input`/`ts-forward` 체인 발견). 마스터 본인 디바이스가
  이 tailnet에 연결돼 있다면 SSH 말고도 이미 별도 접근 경로가 있었다는 뜻일 수
  있음 — 확인은 안 했음, 다음에 콘솔 접근이 또 필요한 상황이 오면 이것부터
  물어볼 것.
- 문서: `loop/RELEASE_ROADMAP.md` 21번 섹션을 최종 완료 상태로 갱신(적용된
  규칙 전문 기록), `loop/RUNBOOK_ufw_fail2ban.md` 상단에 "완료됨, 참고용" 안내
  추가(내용 자체는 유지 — 다음에 비슷한 작업할 때 재사용 가능).

## 판정

- ufw: `active`, 기존 n8n/Ollama/Samba 규칙 그대로 유지 + navi/DOCKER-USER 규칙
  정상 추가 확인.
- fail2ban: `sshd` jail `enabled`, 정상 기동 확인.
- 종단 검증: SSH 리스닝 정상, navi/valhalla/tiles 공개 도메인 curl 전부 200
  (규칙 변경 전후 여러 차례 반복 확인, 재작업 없음).
- **미검증 한계**: 이 서버 자신에서의 curl은 hairpin NAT 때문에 "진짜 공인
  인터넷에서 직접 IP:포트로 못 들어오는지"까지는 확증 못 한다(원 감사 때부터의
  동일한 제약). 마스터가 와이파이를 끄고 모바일 데이터로
  `curl --max-time 5 http://112.186.40.91:8002/status`가 타임아웃/연결거부로
  나오는지 직접 재확인하는 걸 권장 — 아직 안 함.
- 위임받은 sudoers 항목(`/etc/sudoers.d/claude-ufw-fail2ban`)은 그대로 남아있음.
  회수하려면 `sudo rm /etc/sudoers.d/claude-ufw-fail2ban` 한 줄이면 됨(마스터에게
  안내 완료).

**Goal: 21번(운영 서버 보안 강화) 3(ufw)/5(fail2ban)순위 진행 / Met: yes —
narrow sudo 위임 + 데드맨 스위치 방식으로 안전하게 완료, 21번 항목(1~5순위)
전부 DONE. 단, 마스터의 외부망(모바일 데이터) 직접 재검증은 아직 남아있음.**
