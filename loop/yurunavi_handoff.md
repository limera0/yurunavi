# 유루나비(ゆるナビ) 진행 현황 — 새 채팅 인수인계용

_최종 업데이트: 2026-06-02 새벽_

이 문서 하나로 새 채팅에서 맥락을 이어받을 수 있도록 정리함. 위에서부터 "프로젝트가 뭔지 → 인프라 현재 상태 → 최근 작업 → 지금 막힌 곳 → 다음 할 일 → 원칙" 순.

---

## 1. 프로젝트 개요

- **유루나비**: 오토바이 투어링 내비 앱. 핵심 차별점 = 고속도로 대신 **굽이굽이 한적한 시골길/풍경 좋은 길**로 안내.
- **타깃**: 한국 먼저 → 일본. **Android 우선.**
- **아키텍처**: Flutter(UI) + Rust(fun-road 스코어링) 하이브리드. 라우팅 그래프 계산은 **Valhalla(Docker)**, Rust가 이를 보강(대체 아님). 지도/도로 데이터는 **OpenStreetMap**.
- **세 가지 코스 타입**: `시골길로 느긋하게` / `지방도로 여유롭게` / `국도로 빠르게`.

---

## 2. 인프라 현재 상태 (확정·동작 중)

### 서버 (Ubuntu, westinx)
- 프로젝트 경로: `/data/projects/yurunavi`
- Valhalla: Docker 컨테이너 `yurunavi-valhalla`, 호스트 `0.0.0.0:8002` 노출. **한국 타일 빌드 완료**(tileset ~2026-06-01).
- Rust 서버: `yurunavi_server`, 호스트 `0.0.0.0:8003` 직접 리스닝. 엔드포인트 `/calc_route`.

### 외부 노출 = Cloudflare Tunnel (cloudflared)
- 터널 이름 **`navigation`** (Tunnel ID `77748b13-...`), systemd로 구동. n8n 스택과 같은 서버.
- **Published application routes (= public hostname):**
  | Hostname | Path | Service |
  |----------|------|---------|
  | `navi.westinx.com` | `*` | `http://localhost:8003` (Rust) |
  | `valhalla.westinx.com` | `*` | `http://localhost:8002` (Valhalla) |
- 검증 완료: `curl https://valhalla.westinx.com/status` → Valhalla JSON 정상 응답.
- ⚠️ cloudflared는 **경로 prefix를 안 떼어냄.** 그래서 Valhalla는 path 방식(`/valhalla/route`) 대신 **전용 서브도메인** 방식으로 분리함. 새 서비스 추가 시 같은 원칙 적용.

### 앱 코드 (확정값)
- `lib/services/routing_service.dart`: `_valhallaBase = 'https://valhalla.westinx.com'` (→ `$_valhallaBase/route` 호출).
- `lib/services/native_engine.dart`: `_rustBase = 'https://navi.westinx.com'` (→ `/calc_route`).
- 옛 Tailscale 주소(`westinx.tail2172f6.ts.net`) 잔재는 `lib/` 내 제거됨. **단 `native_engine.dart.bak`에는 아직 남아있음(컴파일 제외라 무해, 정리 예정).**

---

## 3. 최근 완료 작업

### Night5 — DNS/라우팅 인프라 (완료)
- 증상: 앱이 DNS `NODATA`로 경로 검색 실패. 원인: 코드에 죽은 Tailscale 주소(`*.ts.net`, MagicDNS 중단).
- 해결: Cloudflare 터널에 `valhalla.westinx.com → localhost:8002` 라우트 추가 + `_valhallaBase` 수정. → **경로가 실제로 뜨기 시작함.**

### Night6b — ETA 현실화 + 3경로 distinct (완료, PASS)
- 커밋: STAGE1 `48f320f`, STAGE2 `480ff27`. flutter analyze: No issues. APK 빌드 미수행.
- **STAGE 1 (ETA):** Valhalla가 차량 기준 낙관 속도(57~88km/h)를 줘서 ETA가 ~2배 빨랐음. 코스별 실효속도 상수로 보정:
  - `_speedCountrysideKmh=30` / `_speedLocalKmh=36` / `_speedNationalKmh=45`
  - 결과: 71km 지방도 = 118분 → 네이버 실측과 일치. ✓
- **STAGE 2 (distinct):** `alternates:2` 1회 호출 폐기 → 코스별 Valhalla 3회 병렬 호출, costing_options 차등:
  - 시골길: `use_living_streets:1.0, use_tracks:0.8, top_speed:40`
  - 지방도: `use_living_streets:0.5, use_tracks:0.2`
  - 국도: `shortest:true`, living_streets/tracks 0
  - 공통: `use_highways:0.0` (고속도로 전면 배제 = 정상 동작, 유지)
  - 결과: 거리·geometry 모두 상이, 국도가 지방도 대비 31% 빠름(요구 20~30% 충족). ✓

---

## 4. 지금 막힌 곳 / 미해결

### (A) 검증 안 된 핵심 — APK 화면 확인 필요
- curl은 "세 경로가 서로 다르다"만 증명함. **"시골길이 어젯밤처럼 동탄신도시 10차선 대로를 직선 관통하는지"는 아직 미확인.** 거리가 길다고 시골길다운 건 아니므로, **APK로 지도에 띄워 동탄 구간을 확대해 눈으로 봐야 함.**
- 빌드 명령(피곤하면 걸어두고 자기):
  ```bash
  cd /data/projects/yurunavi
  grep -rn "tail2172f6\|\.ts\.net" lib/ | grep -v "\.bak" || echo "✅ clean"
  nohup flutter build apk --release > build_$(date +%H%M).log 2>&1 &
  ```
- 폰 설치 시 **반드시 기존 앱 삭제 후 클린 설치** (서명 불일치로 인한 조용한 설치 실패 방지).

### (B) "국도 vs 지방도"의 의미 구분은 미완 (설계상 예정된 한계)
- 현재 distinct는 Valhalla 노브 차등일 뿐. PPT 정의("국도 위주+지방도 약간+직선 넓은 길" vs "지방도 위주+숲길+직선 적게")는 Valhalla 노브로 구현 불가. → **Rust fun-road 스코어링** 몫.

---

## 5. 다음 할 일 (우선순위)

1. **[즉시] APK 빌드 → 폰 클린설치 → 시골길이 동탄 대로 타는지 화면 확인.** 이 결과가 분기점.
   - 여전히 대로 직진이면 → 시골길 costing을 더 조이거나 Rust 스코어링 착수.
   - 괜찮으면 → Rust 스코어링으로 품질 향상.
2. **[중기] Rust fun-road 스코어링 MVP.** Valhalla 후보 3개를 재평가/재정렬.
   - 입력: `highway` tag(도로등급), `surface`, 숲 근접도(`landuse=forest`/`natural=wood`), 굽이지수(geometry 곡률), `lanes`/`maxspeed`(교통량 대리).
   - 공식 초안: `fun_score = curviness*w + forest_proximity*w + (1-road_grade)*w - traffic_penalty`
   - PPT 규칙 반영: **시골길 거리 > 국도 거리 ×1.3이면 지방도 혼합 fallback**, 국도 대비 시골길 ETA 20~30% 이내면 "실용적 fun" 범주.
   - MVP는 highway tag + curviness만으로 시작, 숲 근접도는 이후.
   - 데이터: geofabrik 한국 OSM(`south-korea.osm.pbf`) → libosmium/OSMnx 전처리 → SQLite/FlatGeobuf 인덱스.
3. **[정리] `native_engine.dart.bak` 등 잔재 정리.**

### PPT에 있던 차기 UX 기능 (라우팅 버그 아님, 잊지 말 것)
- 한 화면에서 여러 코스 비교 표시.
- 지도 지점 터치 → 출발/도착/경유지 설정 → 코스 재검색.
- 시골길의 이상향 = 네이버 자전거길 같은 경로. **단 자전거전용도로(하천공원도로 등 차량·오토바이 진입금지)는 배제** — 이 보완이 유루나비 핵심 가치.

---

## 6. 작업 원칙 (자율 세션 포함)

- **수리 > 재작성.** 코드베이스는 audit상 양호, 빈 곳을 메우는 방향.
- **넓은 변경 = 회귀 위험.** (전례: 지도 타일 수정이 경로 검색을 깨뜨림.) 한 세션 = 한 모듈, 스코프 엄격.
- **Git 체크포인트가 1차 안전장치.** 단계마다 커밋, STOP 조건이면 추측 말고 보고.
- **자율 실행**: `claude --permission-mode auto` 선호(`--dangerously-skip-permissions` 회피). `NIGHT_TASK.md`로 작업 정의, `MORNING_REPORT*.md`로 결과.
- **APK 빌드는 사람이 아침에** (세션 시간 낭비 방지).
- 정직한 일정·비용·실패가능성 우선. "이렇게 해보세요"가 아니라 운영 가능한 수준.

---

## 7. 새 채팅 시작 시 첫 마디 예시

> "유루나비 이어서. 인프라(Cloudflare 터널 valhalla.westinx.com, ETA·3경로 distinct)는 night6b까지 완료. 지금 [APK 화면 확인 결과 / 또는 Rust 스코어링 착수]부터 하려고 해."
