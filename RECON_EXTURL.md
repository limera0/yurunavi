# RECON_EXTURL — 외부 접속 전환 사전조사

날짜: 2026-06-05  
작성: Claude Sonnet 4.6 (읽기 전용, 코드 수정 없음)

---

## 결론 먼저

**야외 실측을 막는 진범은 타일서버 하나다.**

| 서비스 | 현황 | 야외 차단 여부 |
|--------|------|---------------|
| Valhalla (`valhalla.westinx.com`) | ✅ 이미 공개 도메인, curl 응답 확인 | ❌ 차단 아님 |
| Rust 서버 (`navi.westinx.com`) | ✅ 이미 공개 도메인, curl 응답 확인 | ❌ 차단 아님 |
| 타일서버 (`192.168.0.57:8080`) | ❌ LAN IP만 존재, 공개 도메인 없음 | **✅ 차단 원인** |

경로 탐색과 fun-score는 야외에서도 이미 동작한다.  
지도 타일만 집 LAN 범위를 못 벗어나 **지도가 아예 안 나온다**.

---

## 1. Flutter/Dart 하드코딩 주소

### 1-1. 서비스 URL 상수

| 파일 | 라인 | 값 | 상태 |
|------|------|----|------|
| `lib/services/routing_service.dart` | L67 | `'https://valhalla.westinx.com'` | ✅ 공개 도메인 |
| `lib/services/native_engine.dart` | L170 | `'https://navi.westinx.com'` | ✅ 공개 도메인 |

### 1-2. 외부 서비스 URL (변경 불필요)

| 파일 | 값 | 비고 |
|------|----|------|
| `lib/services/poi_service.dart:12` | `https://overpass-api.de/api/interpreter` | 공개 API |
| `lib/services/daylight_service.dart:55` | `https://api.sunrise-sunset.org/json?...` | 공개 API |
| `lib/features/navigation/presentation/nav_screen.dart:361` | `https://overpass-api.de/api/interpreter` | 공개 API |
| `lib/screens/driving_screen.dart:170` | `https://{s}.basemaps.cartocdn.com/...` | 미사용 레거시 화면 |
| `lib/features/navigation/presentation/nav_screen.dart:508` | `https://{s}.tile.openstreetmap.org/...` | 미사용 레거시 화면 |

> `driving_screen.dart`와 `nav_screen.dart`의 CartoCDN/OSM 타일 URL은 현재 MapLibre 마이그레이션 이후 사용되지 않는 레거시 경로. 무해.

### 1-3. URL 중앙집중화 현황

- `_valhallaBase`, `_rustBase` 각각 개별 서비스 파일 내 `static const` 로 분산 선언.
- 단일 `AppConfig` / `Endpoints` 클래스 없음.
- 타일서버 URL은 Dart 코드가 아닌 **JSON 에셋에 직접 하드코딩**됨 (`osm_liberty_yurunavi.json`).
- **실제적 영향**: 도메인 교체 시 최소 3개 파일(routing_service, native_engine, JSON) 수정 필요.

---

## 2. Rust 하드코딩 주소

| 파일 | 라인 | 값 | 평가 |
|------|------|----|------|
| `native/src/main.rs` | L8 | `const VALHALLA_URL: &str = "http://localhost:8002/route"` | ✅ 무해 (서버 내부 호출) |
| `native/src/main.rs` | L150 | `"http://localhost:8002/trace_attributes"` | ✅ 무해 (서버 내부 호출) |
| `native/src/main.rs` | L484 | `TcpListener::bind("0.0.0.0:8003")` | ✅ listen 주소, 변경 불필요 |

**판정**: Rust 서버는 westinx 서버에서 실행되고, 같은 서버의 Valhalla(localhost:8002)에 직접 접근한다. 앱 관점에서 이 URL은 노출되지 않으므로 야외 실측과 무관.  
HTTP 사용도 루프백이므로 보안 문제 없음.

---

## 3. 타일서버 (192.168.0.57:8080)

### 3-1. 하드코딩 위치

| 파일 | 라인 | 값 |
|------|------|----|
| `assets/images/osm_liberty_yurunavi.json` | L12 | `"url": "http://192.168.0.57:8080/data/v3.json"` |
| `assets/images/osm_liberty_yurunavi.json` | L24 | `"glyphs": "http://192.168.0.57:8080/fonts/{fontstack}/{range}.pbf"` |
| `android/.../network_security_config.xml` | L12 | `<domain>192.168.0.57</domain>` cleartext 예외 |

### 3-2. 공개 도메인 현황

```
$ curl -s --max-time 5 "https://tiles.westinx.com/data/v3.json"
(응답 없음 — 도메인 미생성)

$ curl -s --max-time 5 "http://192.168.0.57:8080/data/v3.json"
{"tiles":["http://192.168.0.57:8080/data/v3/{z}/{x}/{y}.pbf"],"name":"OpenMapTiles",...}
(LAN에서 정상 응답)
```

**결론**: `tiles.westinx.com` 서브도메인이 Cloudflare Tunnel에 등록되어 있지 않다.  
타일서버는 LAN(192.168.0.57) 범위에서만 접근 가능 → **야외에서 지도 타일 전혀 안 나옴**.

### 3-3. 추가 문제: tileserver가 반환하는 타일 URL

`/data/v3.json` 메타데이터 내부에도 타일 URL이 박혀있다:
```json
"tiles": ["http://192.168.0.57:8080/data/v3/{z}/{x}/{y}.pbf"]
```
타일서버가 자신의 IP를 응답에 포함하므로, 단순히 JSON 에셋의 URL만 바꿔도 타일서버가 `192.168.0.57` 주소로 다시 안내할 수 있다.  
**tileserver-gl config.json의 `publicUrl` 또는 Docker 실행 시 `--public_url` 옵션으로 공개 도메인을 알려줘야 한다.**

---

## 4. Cloudflare Tunnel 현황

### 4-1. 검증된 공개 도메인

```
터널 이름: navigation (ID: 77748b13-...)
systemd: 구동 중

valhalla.westinx.com → localhost:8002  
  curl: {"version":"3.7.0-5ed7267b7","available_actions":["route","trace_attributes",...]}  ✅

navi.westinx.com → localhost:8003
  curl: {"status":"ok"}  ✅
```

### 4-2. 미등록 서비스

```
tiles.westinx.com → (없음)  ❌ 등록 필요
```

Cloudflare Tunnel에 `tiles.westinx.com → localhost:8080` 인그레스 규칙 1줄 추가 필요.

---

## 5. Android cleartext 예외 현황

`android/app/src/main/res/xml/network_security_config.xml`:

```xml
<base-config cleartextTrafficPermitted="false">   ← 기본값: HTTPS 강제
<domain-config cleartextTrafficPermitted="true">
  <domain includeSubdomains="true">ts.net</domain>   ← Tailscale 잔재 (아직 필요?)
</domain-config>
<domain-config cleartextTrafficPermitted="true">
  <domain includeSubdomains="false">192.168.0.57</domain>   ← 타일서버 LAN 임시 허용
</domain-config>
```

- `ts.net` 예외: Tailscale MagicDNS는 Night5에서 Cloudflare로 전환됨. 현재 앱이 `*.ts.net`을 호출하지 않는다면 제거 가능 (CLAUDE.md "Tailscale/공개호스팅으로 교체 필수" 참고).
- `192.168.0.57` 예외: 타일서버 HTTPS 전환 완료 후 제거 가능.

---

## 6. 전환 작업 범위 정리

### 필수 (야외 실측 차단 해제)

**작업 1 — Cloudflare Tunnel 인그레스 추가** (서버 작업, 코드 아님)
```yaml
# cloudflared config.yml ingress에 추가
- hostname: tiles.westinx.com
  service: http://localhost:8080
```
tileserver-gl 재시작 불필요. cloudflared 재시작 필요.

**작업 2 — tileserver publicUrl 설정** (서버 작업)  
`/data/tiles/data/config.json`에 옵션 또는 Docker 실행 시 `--public_url https://tiles.westinx.com` 추가.  
설정 안 하면 타일 메타데이터 내부 URL이 여전히 192.168.0.57 반환.

**작업 3 — 스타일 JSON 교체** (코드 1파일, 2줄)
```
변경 전: "http://192.168.0.57:8080/data/v3.json"
변경 후: "https://tiles.westinx.com/data/v3.json"

변경 전: "http://192.168.0.57:8080/fonts/{fontstack}/{range}.pbf"
변경 후: "https://tiles.westinx.com/fonts/{fontstack}/{range}.pbf"
```
파일: `assets/images/osm_liberty_yurunavi.json` L12, L24

**작업 4 — cleartext 예외 제거** (코드 1파일)  
`network_security_config.xml`에서 `192.168.0.57` 도메인 설정 블록 제거.

### 선택 (정리)

- `network_security_config.xml`의 `ts.net` cleartext 예외 — Tailscale 완전 제거 시 함께 삭제.
- URL 중앙집중화 — 현재 분산 선언이지만 당장 문제는 없음. 도메인 추가 시 부채.

---

## 7. 야외 실측 체크리스트 (수정 완료 가정)

```
[ ] tiles.westinx.com curl 응답 확인 → 타일 JSON 정상
[ ] tiles.westinx.com 반환 타일 URL이 tiles.westinx.com 도메인인지 확인
[ ] APK 빌드 후 실내 WiFi에서 지도 타일 로드 확인
[ ] WiFi 끊고 LTE로 지도 타일 로드 확인 (핵심)
[ ] 경로 탐색 확인 (valhalla.westinx.com → 이미 작동 확인됨)
[ ] fun-score 표시 확인 (navi.westinx.com → 이미 작동 확인됨)
```

---

*정찰 완료: 2026-06-05. 코드 수정 없음. curl 검증 포함.*
