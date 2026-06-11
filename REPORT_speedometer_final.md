# REPORT — 속도계 종결 통합 (위치설정 복구 + 포그라운드 서비스 + OM 보간 엔진)

날짜: 2026-06-11
브랜치: feat/maplibre-migration
대상 파일: `lib/features/navigation/presentation/nav_screen.dart`, `android/app/src/main/AndroidManifest.xml`

## 0단계 확인 결과 (HALT 미발생)
- `ForegroundNotificationConfig` 시그니처(`geolocator_android-5.0.2`, geolocator 14.0.2가 re-export): `enableWakeLock` 필드 **실존**(기본 false). 필수: `notificationTitle`, `notificationText`. 추측 없음.
- Manifest 권한: `ACCESS_FINE/COARSE_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` 보유 / **`POST_NOTIFICATIONS` 누락** → 커밋2에서 추가.

## 불변 영역 (수정 안 함)
카메라/재중심(`_recenter`), `_reroute`, TTS, bearing 게이트(`pos.heading>=0 && _speedKmh>2.0`), 속도 히스테리시스 핵심 판정(parked / d>=2 / d<1.5) — 전부 그대로 유지.

## 커밋별 변경

| 커밋 | 변경 라인 | 내용 |
|---|---|---|
| `a4198c4` revert(nav): drop forceLocationManager, target fused 1Hz | AndroidSettings (구 191–196) | `forceLocationManager: true` 삭제, `intervalDuration` 333ms→**1000ms**, `distanceFilter: 0` 유지 |
| `a0950f8` feat(nav): foreground location service… | AndroidSettings + Manifest | `foregroundNotificationConfig`(title "유루나비 주행 중", text "경로 안내를 위해 위치를 수신하고 있습니다", `enableWakeLock: true`) 추가 / Manifest에 `POST_NOTIFICATIONS` 1줄 추가 |
| `793c73a` fix(nav): widen position window to 12s | _posBuffer 주석 + removeWhere | ZUPT 링버퍼 윈도우 `inSeconds > 4` → **> 12** (1Hz/5초 fix 양쪽 호환) |
| `7193e35` refactor(nav): remove 3s watchdog… | 필드/dispose/_onPosition | `_staleTimer` 필드·dispose cancel·3초 워치독 본체 제거 (ticker가 흡수) |
| `32b7b61` feat(nav): 200ms speed extrapolation ticker… | 필드 + _startLocation + dispose + _onPosition + 신규 `_tickSpeed` | 200ms 외삽 ticker 신설 |

**Manifest 변경 여부: YES** — `POST_NOTIFICATIONS` 1줄 추가 (커밋2).

## 200ms 보간 ticker 설계 (`_tickSpeed`)
- 보관: `_vPrev/_vCur`(도플러 m/s), `_vPrevAt/_vCurAt`(수신시각, pos.timestamp 불신 → `DateTime.now()` 기반), `_vPrevPos/_vCurPos`(위치). `_onPosition` 적응-throttle 통과 시점에 2칸 시프트 저장.
- `Timer.periodic(200ms)` → `_tickSpeed()`. `_startLocation`에서 가동, `dispose`에서 cancel.
- 판정 순서:
  1. `sinceFix > 8000ms` → **0** (staleness, `_moving=false`)
  2. `!_moving` → **0** (ZUPT 존중)
  3. 직전 fix 부재(첫 fix) → 마지막 실측 표시
  4. 가드 트립 시 보간 OFF·마지막 실측 표시: `dtFix<=0`(timestamp 역전) / `dtFix>6500ms` / `jumpM>150m` / `avgMs>75 m/s`
  5. 통과 시 외삽: `v = vCur + ((vCur−vPrev)/dtFix)*sinceFix`, `clamp(0,75) m/s × 3.6`
- 스냅-온-fix: `_onPosition`은 실측 도플러 속도를 그대로 setState(불변 유지) → fix마다 실측으로 스냅, 사이 200ms는 ticker가 외삽.

## 빌드
- `flutter analyze` (대상 파일): 0 error. 잔존 경고 1건은 import의 `show … max` unused — **기존 코드, 이번 변경과 무관**.
- `flutter build apk --debug`: ✓ 성공 (22.2s)
- APK: `/data/projects/yurunavi/build/app/outputs/flutter-apk/app-debug.apk` (≈214 MB)
- (KGP 경고는 플러그인 측 사항, 빌드 영향 없음)

## 시나리오표 (화면 거동 예측)

| 시나리오 | fix/도플러 입력 | 화면 거동 |
|---|---|---|
| 가속 | vCur>vPrev, _moving | ticker가 양(+) 기울기로 fix 사이 상승 외삽 → 부드러운 증가 |
| 정속 | vCur≈vPrev | 기울기≈0 → 평탄 유지 |
| 감속 | vCur<vPrev | 음(−) 기울기로 하강 외삽, 0~75 clamp |
| 정차 | bufRadius<parkThresh → _moving=false | ticker 2번 가드에서 즉시 0, 200ms 주기로 0 고정 |
| 출발 | d>=2 → _moving=true | 다음 fix부터 외삽 시작, 실측으로 스냅 상승 |
| fix 두절 | 마지막 fix 후 무수신 | 8초까지는 마지막 추세 외삽(가드 내), **8초 초과 시 0으로 강제** (고착 소멸) |
| GPS 점프 | jumpM>150m or avg>75m/s | 보간 OFF, 마지막 실측값 유지(튐 방지) |

## 사용자 1회 주행 체크리스트 (재확인용)
- [ ] ★SPD 로그 fix 간격: 1초 복구? 여전히 5초? (forceLocationManager 제거 효과 심판)
- [ ] ★정차 → 2~3초 내 0으로 연속 하강 (고착 소멸)
- [ ] 주행 중 0 깜빡임 없음 / 가감속 부드럽게 추종
- [ ] 1분 정지 0 유지 / bearing·카메라·재탐색·TTS 회귀 없음
- [ ] 알림바에 "유루나비 주행 중" 노티 표시 (포그라운드 서비스 가동 증거)

## 노트북 설치
헤드리스 서버라 `flutter run` 불가. 위 APK를 노트북으로 옮겨 `adb install -r app-debug.apk`.

## 토큰/리스크 노트
- 모든 변경은 `nav_screen.dart` + Manifest 1줄로 국한. 불변 영역 미접촉.
- 잠재 회귀 포인트: ticker와 `_onPosition`이 둘 다 `_speedKmh`를 setState → 충돌 아님(스냅-온-fix 의도). bearing 게이트는 `_onPosition` 실측 시점 값 사용으로 기존과 동일.
- 미검증: 실제 1Hz 복구 여부는 단말 주행 로그로만 확정 가능(헤드리스 한계).
