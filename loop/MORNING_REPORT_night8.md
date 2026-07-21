# MORNING_REPORT — Night 8 (2026-06-02)

## 한 일 (모듈 3개 전부 PASS+커밋)

### Module 1 — Android 위치 권한 (PASS)
파일: `android/app/src/main/AndroidManifest.xml`

**발견**: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`은 이미 있었음. Flutter 런타임 권한 요청 흐름도 `main_map_screen.dart`, `nav_screen.dart`, `driving_screen.dart` 3곳에 이미 구현됨.

**추가**: Android 14(API 34+) 내비게이션 foreground 서비스용 2개 권한
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
```
flutter analyze: No issues. 순수 가산적 변경.

---

### Module 2 — Rust 1.3배 동적 배합 fallback (PASS)
파일: `native/Cargo.toml`, `native/src/main.rs`, `native/src/api.rs`

**변경 내용**:
- `reqwest 0.12` (rustls-tls, OpenSSL 헤더 불필요) 추가
- `VALHALLA_URL = "http://localhost:8002/route"` 상수 + 정적 HTTP 클라이언트
- `decode_polyline6` + `extract_trip_points` 헬퍼 추가
- `handle_calc_route` 교체: 모의 사인파 → Valhalla 실제 호출

**fallback 로직** (route_type == 0 시골길):
1. `tokio::try_join!` 으로 rural + provincial Valhalla 동시 요청
2. `t_rural / t_prov >= 1.3` 이면 balanced payload 재요청
   - balanced: FC2=4.0, FC3=1.2, FC4=0.8, FC5=0.5 (rural 제약 완화)
3. 미만이면 rural 그대로 반환

route_type 1/2는 Valhalla 직접 호출(provincial/national profile).

**검증**:
- cargo build: 0 errors (기존 flutter_rust_bridge 경고 17개, 신규 없음)
- cargo test: 17/17 PASS (신규 ratio 경계 테스트 2개 포함)
- live curl: route_type=0 → fallback 실제 트리거됨 (dist=15928m, winding=48.9, road_type=provincial)
- route_type=2 → 15412m, 두 경로 distinct 확인

---

### Module 3 — 곡률(τ=L/C) fun-road 스코어링 골격 (PASS)
파일: `native/src/api.rs` (순수 가산)

**추가된 공개 API**:
| 함수/구조체 | 설명 |
|---|---|
| `RouteRank { original_index, fun_score, curvature_tau }` | 후보 순위 결과 |
| `calc_tortuosity(route) -> f64` | τ = 궤적길이 L / 직선거리 C |
| `fun_score_v1(route) -> f64` | τ 기반 0~100점 (τ=1→0, τ=2→50, τ≥3→100) |
| `rank_candidates(routes) -> Vec<RouteRank>` | fun_score 내림차순 정렬 |

**다음 모듈에서 추가 예정**: 숲 근접도(`landuse=forest`), 교통량 대리지표(lanes/maxspeed), 도로등급 가중치.

- cargo test: 21/21 PASS (신규 4개 포함)
- 직선도로 τ≈1.0 ✓, 굽이길 τ>1.05 ✓, 순위 정렬 ✓

---

## git log

```
bf67dea feat(rust): tortuosity τ=L/C fun-road scoring skeleton (night8 module3)
13569b8 feat(rust): 1.3x dynamic fallback in /calc_route handler (night8 module2)
7864740 feat(android): add FOREGROUND_SERVICE_LOCATION permissions (night8 module1)
ea30571 checkpoint: before night8 — module1(android-perms) + module2(rust-fallback) + module3(curvature)
1d228bc docs: MORNING_REPORT night7 — class_factors+urban_penalty PASS
10eab85 feat(routing): add class_factors + urban_penalty per OSM spec (night7)
```

---

## PASS / FAIL

**전 모듈 PASS**

| 모듈 | 결과 | 검증 |
|---|---|---|
| Module1 (Android 권한) | ✅ PASS | flutter analyze 무이슈 |
| Module2 (Rust fallback) | ✅ PASS | cargo test 17/17, live curl distinct routes |
| Module3 (곡률 골격) | ✅ PASS | cargo test 21/21 |

---

## 막힌 점 / 주의 사항

1. **APK 화면 확인 미완**: urban_penalty + class_factors가 실제로 동탄 10차선 대로를 우회하는지는 APK로 눈으로 봐야 함.

2. **Rust 서버 재시작 필요**: Module 2에서 바이너리가 업데이트됐음. 현재 port 8003에 새 바이너리가 임시로 떠 있지만, 서버 재부팅 시 systemd 서비스가 구 바이너리를 가리킬 수 있음.
   ```bash
   # 확인/반영 필요
   sudo systemctl status yurunavi_server 2>/dev/null || echo "서비스 미등록"
   # 실행 중이면: sudo systemctl restart yurunavi_server
   ```

3. **ETA Valhalla 전환 보류 유지**: Dart 후처리 상수(`_speedCountrysideKmh` 등)와 이중보정 위험. 사람이 직접 검증 후 전환.

4. **Module 2 fallback은 route_type==0에만 작동**: route_type 1, 2는 Valhalla 직접 호출. Dart `routing_service.dart`는 건드리지 않았으므로 기존 3경로 distinct 동작 유지됨.

---

## 다음 세션 추천 1개

**APK 빌드 → 동탄 우회 화면 확인 → Rust 서버 systemd 반영**

```bash
# APK 빌드 (사람이 실행)
cd /data/projects/yurunavi
nohup flutter build apk --release > build_$(date +%H%M).log 2>&1 &

# Rust 서버 systemd 반영 여부 확인
sudo systemctl status yurunavi_server 2>/dev/null
```

화면 확인 결과에 따라:
- 동탄 우회 성공 → fun_score에 도로등급(class_factors) 항 추가(Module 3 확장)
- 동탄 여전히 직진 → `urban_penalty`를 100.0으로 상향
