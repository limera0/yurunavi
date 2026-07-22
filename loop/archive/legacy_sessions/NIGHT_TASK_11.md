# NIGHT_TASK — 11번째 세션 (OSM 스타일 적용 + 신규 ROADMAP 작성)

오케스트레이터: Claude Sonnet 4.6
실행 권장: `tmux new -s yurunavi` → `claude --permission-mode auto`
원칙: **이 파일에 적힌 2개 스테이지 외에는 아무것도 건드리지 말 것.**
완료 조건: STAGE 1 커밋 + STAGE 2 파일 생성 + MORNING_REPORT_night11.md 작성

---

## 사전 상태 확인 (작업 시작 전 반드시 실행)

```bash
cd /data/projects/yurunavi
git log --oneline -5          # Night 10 커밋 확인 (마지막: 8a58ff3)
flutter analyze               # 반드시 No issues
cargo test --manifest-path rust/Cargo.toml  # 33/33 PASS
```

위 세 가지 중 하나라도 실패하면 즉시 MORNING_REPORT에 [BLOCKED] 기록하고 중단.

---

## STAGE 1 — OSM Liberty 스타일 JSON 적용

### 목표

`assets/osm_liberty_yurunavi.json` 을 앱 지도에 실제로 적용하여
유루나비 전용 맵 스타일(고속도로 숨김 / 국도 강조 / 자전거길 제거)이 렌더링되도록 한다.

### 작업 범위 (이것만 할 것)

**Step 1 — pubspec.yaml assets 등록 확인**

```bash
grep -n "osm_liberty" pubspec.yaml
```

- 결과에 `assets/osm_liberty_yurunavi.json` 이 없으면 추가:

```yaml
flutter:
  assets:
    - assets/osm_liberty_yurunavi.json   # 이 줄 추가
```

**Step 2 — 현재 지도 타일/스타일 로딩 방식 파악**

```bash
grep -rn "styleString\|tileProvider\|urlTemplate\|MapLibre\|FlutterMap\|TileLayer" lib/ --include="*.dart" | head -30
```

결과를 보고 아래 둘 중 하나를 선택:

**케이스 A — MapLibre 기반 (`MapLibreMap` 또는 `maplibre_gl`)**

`main_map_screen.dart` (또는 지도 위젯이 있는 파일) 에서:

```dart
// 변경 전 (예시)
MapLibreMap(
  styleString: 'https://...',  // 기존 원격 스타일
)

// 변경 후
MapLibreMap(
  styleString: 'asset://assets/osm_liberty_yurunavi.json',
)
```

**케이스 B — flutter_map + TileLayer 기반**

`flutter_map`은 Mapbox GL Style JSON을 직접 지원하지 않음.
이 경우 스타일 JSON 적용 불가 — 아래 fallback 처리:

1. `pubspec.yaml`에 asset은 등록해두되 (미래 마이그레이션 대비)
2. 기존 TileLayer urlTemplate은 그대로 유지
3. MORNING_REPORT에 "flutter_map 구조라 스타일 JSON 직접 적용 불가,
   MapLibre 마이그레이션 필요" 명시하고 STAGE 1 커밋 없이 STAGE 2로 이동

**Step 3 — 적용 후 검증**

```bash
flutter analyze
flutter build apk --debug 2>&1 | tail -20
```

- `flutter analyze`: No issues
- 빌드 성공 시 커밋:

```bash
git add pubspec.yaml lib/ assets/
git commit -m "feat: apply osm_liberty_yurunavi map style [ROADMAP-OSM]"
```

### 절대 건드리지 말 것

- `routing_service.dart` (3경로 distinct 유지)
- `native_engine.dart`
- `rust/` 디렉토리
- 기존 경로 탐색 로직 일체

---

## STAGE 2 — 신규 ROADMAP.md 작성

### 목표

Night 10까지 완료된 항목(1~27)을 반영하고,
아직 미구현된 핵심 기능을 20개 이내 항목으로 정리한 새 ROADMAP.md를 작성한다.

### 작업 방법

1. 현재 ROADMAP.md 내용 확인:
   
   ```bash
   cat ROADMAP.md
   ```

2. MORNING_REPORT_night10.md 확인 (완료 항목 파악):
   
   ```bash
   cat MORNING_REPORT_night10.md
   ```

3. 아래 기준으로 ROADMAP.md 를 **덮어쓰기**:

```
# 유루나비 ROADMAP v2 (Night 10 이후)
# 완료 기준: [AUTO] = Claude Code 자율 수행 가능 / [HUMAN] = 마스터 직접 확인 필요
# 작업 방향: 핵심 가치(재미있는 시골길 탐색) → 완성도 → 배포 준비 순

## 완료 ✅ (Night 1~10, 항목 1~27)
[생략 — git log 참조]

## 미완료 항목 (위에서부터 처리)

### 🔴 핵심 가치 (앱 존재 이유)
1. [x] [BLOCKED] fun-road costing 실제 구현: Rust /calc_route가 반환하는 fun_score를
   Valhalla custom_costing에 실제 반영 → 3경로가 진짜 다른 도로를 탐색하도록.
   현재: 경로 카드 fun_score 표시만 있고 라우팅 로직에 미반영.
   검증: 동일 출발/도착에 대해 3경로의 폴리라인이 서로 30% 이상 달라야 PASS.

2. [x] [AUTO] 고속도로·자동차전용도로 완전 배제 검증:
   Valhalla costing에서 motorway/motorway_link use=0 강제 적용 확인.
   현재: 설정 여부 불명확. cargo test에 검증 케이스 추가.

3. [x] [AUTO] fun_score 구성요소 확장 — 도로 등급 가중치:
   class(motorway→0, trunk→0.3, primary→0.6, secondary→0.85, unclassified→1.0) 반영.
   cargo test 33→36으로 확장.

4. [x] [AUTO] fun_score 구성요소 확장 — 커브 밀도:
   Valhalla 엣지의 begin_heading/end_heading 차이로 와인딩 지수 계산.
   cargo test 추가.

### 🟠 내비게이션 완성도
5. [x] [AUTO] 경로 카드 선택/미선택 색상 구분:
   선택 경로 = 코스 고유색(초록/파랑/주황), 미선택 = 회색 0.4 opacity.
   현재: 선택 경로도 진한 색으로만 표시. Night 10 ROADMAP-25 후속 개선.

6. [x] [AUTO] 음성 안내 거리 정확도:
   현재 _announceStep이 maneuver index 기반. GPS 실거리(남은 거리 m)로 전환.
   "300m 앞 우회전" 형식으로 발화. distanceRemaining 계산 로직 추가.

7. [x] [AUTO] 도착지 주변 POI 표시:
   도착 30m 이내 진입 시 기존 다이얼로그에 추가로
   반경 500m 내 주유소/편의점/식당 3개를 지도에 마커 표시.
   Valhalla /locate 또는 Overpass API 사용.

8. [x] [AUTO] 경유지 추가 버튼 상태 버그 수정:
   경유지 버튼이 첫 터치 후 사라지는 문제. (Night 이전 피드백에서 미처리)
   목적지 선택 화면(_waypoint 상태 관리) 점검.

### 🟡 지도 표시 완성도
9. [x] [BLOCKED] OSM 스타일 실제 적용 확인 (STAGE 1 결과에 따라):
   MapLibre 마이그레이션이 필요하다면 flutter_map → maplibre_gl 전환.
   ⚠️ 고위험: 기존 지도 렌더링 전체 교체. 반드시 별도 브랜치에서 작업.
   검증: 지도에서 고속도로 미표시 + 국도 강조 확인 ([HUMAN] 시각 확인 필요).

10. [x] [AUTO] 지도 초기 줌 레벨 z16 고정:
    앱 기본 줌을 PPT 슬라이드 14번 기준(z16)으로 설정.
    kInitialMapView zoom 값 수정.

11. [x] [AUTO] 내비 중 지도 줌 속도 연동 튜닝:
    Night 10 ROADMAP-17에서 구현됐으나 실 주행 시 0~20km/h 구간
    줌 전환이 너무 빠름 보고됨. 수렴 상수 0.3으로 낮춤.

### 🟢 인프라·안정성
12. [x] [BLOCKED] Rust 서버 systemd 자동 재시작 확인:
    서버 재부팅 후 :8003이 자동 올라오는지 검증.
    `systemctl status yurunavi-rust` 출력을 check_all.sh에 추가.

13. [x] [AUTO] scripts/check_all.sh 확장:
    현재: flutter analyze + cargo test + validate_rural_route.py.
    추가: `curl https://valhalla.westinx.com/status` + `curl http://localhost:8003/health`
    둘 다 200이어야 전체 PASS.

14. [x] [BLOCKED] APK 서명 키 설정:
    `android/key.properties` + `android/app/build.gradle` 서명 블록.
    key.jks는 마스터가 생성 ([HUMAN] 게이트), 이후 빌드 스크립트 자동화.

### 🔵 배포 준비
15. [x] [BLOCKED/HUMAN] 앱 아이콘 + 스플래시 이미지 교체:
    현재 Flutter 기본 아이콘. 유루나비 전용 아이콘 필요.
    마스터가 PNG 파일 제공 → flutter_launcher_icons 자동 적용.

16. [x] [AUTO] 앱 버전 관리 자동화:
    `pubspec.yaml` version: 0.x.0+N 체계 수립.
    ROADMAP 항목 완료 시 patch 버전 자동 bump 스크립트.

17. [x] [AUTO] 릴리즈 APK 빌드 + 파일명 자동화:
    `flutter build apk --release` 후
    `yurunavi_v0.x.0_$(date +%Y%m%d).apk` 로 rename + outputs/ 복사.

18. [x] [BLOCKED/HUMAN] Google Play 내부 테스트 트랙 첫 업로드:
    APK → AAB 전환, Play Console 앱 생성, 내부 테스트 등록.
    마스터가 Play Console 계정 필요.

### ⚪ 일본 시장 확장 (MVP 이후)
19. [x] [BLOCKED] 일본 OSM 타일 빌드:
    Geofabrik japan-latest.osm.pbf → Valhalla 타일 빌드.
    valhalla.westinx.com이 한국/일본 타일 모두 서비스하도록 config 분기.

20. [x] [AUTO] 언어 다국어 지원 기반:
    flutter_localizations 추가, ko/ja ARB 파일 구조 생성.
    현재 하드코딩된 한국어 문자열 추출 (l10n.dart 자동 생성).
```

4. ROADMAP.md 저장 후 커밋:

```bash
git add ROADMAP.md
git commit -m "docs: add ROADMAP v2 (post Night-10, 20 items)"
```

---

## 최종 보고

작업 완료 후 `MORNING_REPORT_night11.md` 작성:

```markdown
# MORNING_REPORT — Night 11 (날짜)

## STAGE 1 결과
- [x] MapLibre 기반 확인됨 → osm_liberty_yurunavi.json 적용 성공 [해당 없음 — flutter_map 기반]
- [x] flutter_map 기반 확인됨 → 직접 적용 불가, 마이그레이션 필요 (ROADMAP-9에 반영)
- flutter analyze: _____
- APK 빌드: _____
- 커밋 해시: _____

## STAGE 2 결과
- ROADMAP v2 작성 완료: 20개 항목
- 커밋 해시: _____

## 다음 추천 작업
- ROADMAP 1번 (fun-road costing) 또는 ROADMAP 5번 (경로 색상)
```

---

## 절대 금지 (어떤 이유로도 금지)

- `routing_service.dart` 3경로 로직 수정
- `rust/` 디렉토리 신규 로직 추가 (이번 세션 스코프 밖)
- `git push` 원격 업로드
- `rm -rf` 류 삭제
- MapLibre 마이그레이션 (ROADMAP에만 기록, 이번 세션엔 미수행)
