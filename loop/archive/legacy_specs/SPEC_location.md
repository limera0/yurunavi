# SPEC_location — 위치 파이프라인 사양 (단일 출처)

확정일: 2026-06-17 | 충돌 시: 이 SPEC > RECON > 현 구현.

## 1. 확정 결정 (변경 시 마스터 승인)
- 위치/속도 정확도·즉응성이 데이터·배터리보다 우선. 절전 목적의 위치 스트림
  중단·주기 완화·정확도 하향 금지. (마스터 결정 2026-06-17)
- 앱 시작 시점부터 위치 스트림을 워밍업한다. 홈/지도 화면 조작 중에도 계속 수신,
  nav 진입 시 GPS 락·fix 버퍼가 이미 따뜻한 상태여야 한다.
- 위치 스트림은 keepAlive(autoDispose 아님). 앱 시작 시 SplashScreen에서 구독을 걸어
  권한 승인 즉시 GPS를 기동한다 — main_map 진입 전에 이미 따뜻해야 함.
  (자율계획 §A "autoDispose로 충분"은 기각: 구독자 의존 시작이라 워밍업이 main_map 진입까지 지연됨. 마스터 결정 2026-06-17)
- 위치 소스는 단일화한다. 화면별 개별 getPositionStream 금지 →
  앱 수명주기 동안 사는 단일 소스(Riverpod provider 등)를 nav·main_map·속도계가 구독.
  (현 분산: nav_screen:232 / main_map_screen:193 / driving_screen:97 — RECON_location §B)

## 2. 성공 기준
- nav 진입 즉시 실제 위치·속도 표시 (콜드 0km/h 10초 구간 소멸) — 라이딩 검증
- 주행 중 위치 마커가 실제 위치를 1~2초 내 추종 — 라이딩 검증
- 위치 스트림 인스턴스가 앱 전체에서 1개 (코드 검증: getPositionStream 호출처 1곳)

## 3. 확정 (2026-06-17 RECON_1hz 근거)
- 5초 간극 원인 확정: geolocator _positionStream 캐시 충돌. main_map(LocationSettings, 5초 기본)이
  먼저 스트림 생성 → nav의 AndroidSettings(1Hz)가 캐시 히트로 무시됨 (geolocator_android.dart:169-171).
- 단일 위치 소스의 설정값: AndroidSettings(accuracy: bestForNavigation,
  intervalDuration: 1000ms, distanceFilter: 0, foregroundNotificationConfig 유지).
- driving_screen.dart: 확정 Dead Code(RECON_manifest §D, 참조 0건) → 통합 시 신경 쓸 필요 없음. 정리는 별건.
- 옵션 A(임시 취소)는 채택 안 함 — 워밍업과 충돌(nav 진입 시 GPS 락 식음). LOC-UNIFY로 직행.
