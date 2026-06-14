# REPORT — GPS+IMU 1D 칼만 속도융합

날짜: 2026-06-12 / 브랜치: feat/maplibre-migration
목적: GPS 5초 throttle 시 "멈춰도 11~13km/h 5초 고착"(slope 외삽 한계)을
IMU 가속도 융합으로 해소. `_speedKmh`를 **채우는 방식만** 교체, 의존부(bearing349/줌646/throttle289) 무수정.

## 0단계 검증 결과
RECON 라인 전부 일치(`_onPosition`:277, `_tickSpeed`:230, 필드 59/65-75, 도플러 d:304,
parked:320, `_moving`:324-328, `_distanceM`:544 존재, bearing 게이트:349). 드리프트 없음 → 진행.
※ `DESIGN_speed_kalman.md`는 리포에 부재(RECON과 동일 확인). 모델은 본 태스크 명세를 그대로 구현.

## 커밋별 변경

| 커밋 | 해시 | 내용 |
|---|---|---|
| checkpoint | 30a3064 | 작업 전 체크포인트 |
| c1 | 5a880ae | `sensors_plus: ^6.1.1`(해소 6.1.2) 추가, pub get |
| c2 | 2d3ff5b | `lib/features/navigation/domain/speed_kalman.dart` 신설 + 단위테스트 6건 |
| c3 | c589516 | `userAccelerometerEventStream`(gameInterval ~50Hz) → `_kf.predict`. setState 없음 |
| c4 | 052676c | GPS/ZUPT update, 200ms ticker를 칼만 표시로 교체, 외삽 필드 제거 |
| c5 | 4fc2175 | KF/KFT 진단 로그 |

## 신설 파일
- `lib/features/navigation/domain/speed_kalman.dart` — 순수 Dart 1D 칼만(센서·UI 의존 0).
  상태 X=[v,b], P 2×2. `predict(a,dt)` / `updateGps(z,r)` / `updateZupt()` / `speedKmh` getter.
- `test/speed_kalman_test.dart` — predict 적분, GPS 수렴, ZUPT→0, clamp, 1000스텝 공분산 유한성. **6/6 PASS**.

## nav_screen.dart 변경 요약
- **추가 필드:** `_kf`(SpeedKalman), `_accelSub`, `_lastAccelAt`, `_lastFixAt`, `_prevDoppler`,
  `_gpsDelta`, `_lastASigned`.
- **제거 필드(외삽 상태):** `_vPrev`/`_vCur`, `_vPrevAt`/`_vCurAt`, `_vPrevPos`/`_vCurPos` (6개).
- **`_onAccel`(신규, ~50Hz):** `aMag=√(x²+y²+z²)` → 부호는 `_gpsDelta`(직전 GPS 도플러 추세).
  `dt`는 수신시각 기반, `dt>0.5s`/첫샘플 스킵. `_kf.predict`만, setState 금지.
- **`_onPosition`:** parked/`_moving` 히스테리시스 **유지**(트리거로). 이동중 `_kf.updateGps(d, r)`,
  정차 `_kf.updateZupt()`. `R = speedAccuracy²`(신뢰 낮으면 4.0, 하한 1.0). `_speedKmh=_kf.speedKmh`.
- **`_tickSpeed`:** 슬로프 외삽식(구 271-272) **삭제** → `_speedKmh=_kf.speedKmh`. staleness `>8000ms`
  안전폴백 **유지**(`_kf.updateZupt()`+0 강제, IMU 표류 차단).
- **불변 확인(미수정):** bearing 게이트 349, `_Speedometer`(937/1110), `_firstFixReceived` blink,
  LocationSettings, 카메라/재탐색/TTS.

## Q/R 초기값 (튜닝 출발점)
- Q = diag(qV=0.1, qB=0.001) — 속도 프로세스노이즈 0.1, 바이어스 0.001(느린 변화).
- R 기본 = 4.0 (도플러 σ≈2 m/s 가정). 실측 `speedAccuracy²`가 있으면 그 값(하한 1.0).
- ZUPT r = 0.01 (정차 강제).
- P0 = diag(1,1), v0=0, b0=0. 표시 clamp 0~75 m/s.

## 빌드
- `flutter analyze`: **No issues found** (구 `show max` 경고는 `max(1.0,…)` 사용으로 해소).
- `flutter test`: **6/6 PASS**.
- `flutter build apk --debug`: ✓ 성공(45.9s). KGP deprecation 경고만(sensors_plus 포함, 빌드 비차단).
- APK: `build/app/outputs/flutter-apk/app-debug.apk` (215 MB)
- 설치: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`

## 튜닝 가이드 (로그 보는 법)
- 수집: `adb logcat -d | Select-String "KF" > kf_log.txt` (KF=GPS fix시, KFT=200ms 표시시)
- **KF gps=<도플러> v=<칼만속도> b=<바이어스> P00=<공분산> zupt=<주입z> parked mov => km/h**
- **KFT v=<칼만속도> a=<predict가속도(부호)> => km/h**
- 증상별 조정:
  - **정차 후 잔류(고착)** → ZUPT가 안 걸림. `mov`가 true로 남는지 확인. parkThresh/도플러 게이트 점검.
    필요시 staleness 8000ms 단축. (목표: slope 한계였던 11~13 고착 해소가 최우선 체크)
  - **출발 지연** → IMU predict 반영 부족. `a` 부호가 +로 뜨는지, qV↑(반응↑) 검토.
  - **드리프트(정지인데 속도 상승)** → `b`가 비정상. qB↓ 또는 ZUPT r↓, predict `dt>0.5` 가드 점검.
  - **떨림(노이즈)** → R↑(도플러 신뢰↓) 또는 qV↓.

## 사용자 1회 주행 체크리스트 (KF 로그 수집이 핵심)
- [ ] ★멈추면 11~13 고착 없이 부드럽게 0 (slope 한계 해소 — 최우선)
- [ ] ★재출발 0→속도 지연 단축 (IMU 즉시 반영)
- [ ] 1분 정지 0 유지(ZUPT) / 주행 중 속도 정상
- [ ] bearing/카메라/재탐색 회귀 없음
- [ ] 로그 수집: `adb logcat -d | Select-String "KF" > kf_log.txt` → KF/KFT 첨부

## 미해결/주의
- **IMU 부호 단순화:** 진행방향 투영 없이 합벡터 크기 + GPS추세 부호(명세 "정확도 무의미" 원칙).
  급가감속 연속 시 부호 지연 가능 → 로그 `a` 컬럼으로 검증 필요.
- **predict 주기:** gameInterval(~50Hz) 가정. 기기별 실제율은 KFT `a` 빈도로 확인.
- **튜닝 미실시:** Q/R은 명세 초기값 그대로. 실주행 로그 확보 후 위 가이드로 조정 예정.
