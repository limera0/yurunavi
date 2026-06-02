# MORNING_REPORT — Valhalla Base URL 진단 (2026-06-02)

오케스트레이터: Claude Sonnet 4.6

---

## 오늘 밤 작업 요약

**목표:** routing_service.dart의 Tailscale 주소(`westinx.tail2172f6.ts.net:8002`)를
`navi.westinx.com` 기반 URL로 교체하여 DNS NODATA 라우팅 실패 해소.

**결과: STOP — 수정하지 않음.**

---

## STEP 1 진단 결과

### 1-a. routing_service.dart 호출 경로

```
lib/services/routing_service.dart:25:  static const _valhallaBase = 'http://westinx.tail2172f6.ts.net:8002';
lib/services/routing_service.dart:55:            Uri.parse('$_valhallaBase/route'),
```

- Valhalla 호출: `http://westinx.tail2172f6.ts.net:8002/route`
- 수정 대상 확인 완료.

### 1-b. 서버 프록시 설정 탐색 결과

```
# /etc/nginx/ → 존재하지 않음 (nginx 미설치)
# /etc/caddy/ → 존재하지 않음 (caddy 미설치)
# docker/docker-compose.yml 탐색 결과:
```

```yaml
services:
  valhalla:
    image: ghcr.io/valhalla/valhalla:latest
    container_name: yurunavi-valhalla
    ports:
      - "8002:8002"
    command: valhalla_service /custom_files/valhalla.json 1
```

- docker-compose에 Valhalla 단독 서비스만 존재.
- nginx, caddy, traefik 등 리버스 프록시 서비스 **전혀 없음**.
- `navi.westinx.com → 8002(Valhalla)` 라우팅 규칙 **미발견**.

---

## STEP 2 판단: **STOP**

**근거:**

1. `navi.westinx.com`이 Valhalla(8002)를 뒤로 노출하는 프록시 규칙이 서버 어디에도 없음.
2. native_engine.dart의 Rust 백엔드(`navi.westinx.com/calc_route`)는 어딘가에 프록시가
   존재한다는 뜻인데, 이는 이 서버가 아닌 외부(클라우드/서버) 프록시일 가능성이 높음.
3. `_valhallaBase`를 `https://navi.westinx.com`으로 바꾸면 해당 도메인에 `/route` 엔드포인트가
   없어 404/502 에러가 남. 오히려 기존 Tailscale 오류보다 디버그가 어려워질 수 있음.
4. 프록시 설정 추가는 인프라 변경이므로 사람 확인 필요.

---

## 수정 내용

**없음.** routing_service.dart를 포함해 어떤 파일도 수정하지 않음.

---

## 다음 단계 (사람이 해야 할 일)

### 옵션 A: 리버스 프록시 경유 (권장)

`navi.westinx.com` 앞단 프록시(Caddy/nginx/Cloudflare Worker 등)에
Valhalla 경로 규칙 추가 후 `_valhallaBase` 수정:

```
# Caddy 예시
navi.westinx.com {
    handle /valhalla/* {
        reverse_proxy localhost:8002
    }
    handle /calc_route* {
        reverse_proxy localhost:8001   # (Rust 백엔드 포트 확인 필요)
    }
}
```

추가 확인 필요: `calc_route`가 어느 프록시를 타고 `navi.westinx.com`에 연결되는지.

그 후 코드 변경:
```dart
// lib/services/routing_service.dart:25
static const _valhallaBase = 'https://navi.westinx.com/valhalla';  // prefix 확인 후
```

### 옵션 B: Tailscale 복원

Tailscale MagicDNS가 다시 동작하도록 `westinx.tail2172f6.ts.net` 주소를 살리는 것.
임시 해결책이지만 프록시 없이 즉시 동작.

### 빌드/설치 시 주의

수정 후 재빌드:
```bash
flutter build apk --release
```
폰 설치 시 **기존 앱 완전 삭제 후 재설치** (캐시된 URL 설정 초기화 목적).

---

## 블록커

- `calc_route`가 navi.westinx.com을 통해 어떻게 라우팅되는지 불명확.
  → 확인 방법: `navi.westinx.com`이 호스팅되는 서버의 프록시 설정 열람.
- Valhalla에 대한 외부 공개 경로가 전혀 없음.
  → 프록시 규칙 추가 또는 Tailscale 복원 중 하나를 사람이 선택해야 함.

---

_체크포인트 커밋: a62d54d — 파일 수정 없이 진단만 수행_
