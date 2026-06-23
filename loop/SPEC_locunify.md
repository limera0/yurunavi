# SPEC_locunify — LOC-UNIFY 실행 스펙 (tick이 추가지시 없이 읽고 진행)

확정 2026-06-23. 충돌 시 이 SPEC 우선. Riverpod 3 기준.

## 완료 (phase1/loc-unify 브랜치)
- 커밋1 locationStreamProvider + ref.keepAlive() (map_providers.dart) — done
- 커밋2 main_map_screen listenManual 전환 (dcf6019) — done
- 커밋3 nav_screen listenManual 전환 (7aae78a) — done

## 패턴 (커밋4 및 이후 위치구독 모두 이 패턴 강제)
- ref.listenManual(locationStreamProvider, ...) 사용. StreamProvider.stream getter 없음(R3).
- 구독 핸들 타입: ProviderSubscription<AsyncValue<Position>>?, dispose는 .close().
- AsyncValue에서 Position 꺼내 기존 콜백에 전달. 콜백 내부 로직 불변.
- ref.watch 금지(중복구독). geolocator import 삭제 금지(getLastKnownPosition/LocationPermission).

## 커밋4 — Splash 워밍업 (남음, 라이딩 검증 묶음)
- 목표: 앱 시작 SplashScreen에서 locationStreamProvider 구독 → 권한 승인 즉시 GPS 기동.
- SplashScreen을 ConsumerStatefulWidget으로 전환, initState에서 ref.listenManual로 구독만 걸어 워밍업.
  (위치 데이터 소비 불필요 — keepAlive라 구독만으로 스트림 가동 유지)
- 단일파일·1커밋. analyze 게이트.

## 검증 분류
- 커밋1~4: analyze 객관검증 (getPositionStream 활성코드 1곳 = provider 내부)
- 전체 LOC-UNIFY: T3 — 라이딩 필수, main 머지 전 확인:
  (1) 콜드 0km/h 구간 소멸 (2) 위치마커 1~2초 추종 (3) 속도계 즉시 정상
- 라이딩 통과 후에만 main 머지.

## 커밋5 — 워밍업 권한 타이밍 수정 (회귀 픽스, 2026-06-24)
증상: 앱이 GPS 못 잡음. logcat "Unhandled Exception: CanceledError".
원인 확정: Splash initState에서 ref.listenManual(locationStreamProvider)가 권한 승인 전 실행
  → 스트림이 권한 없이 시작하다 CanceledError로 죽음 → keepAlive라 죽은 스트림이 캐시에 박제
  → 이후 main_map/nav가 죽은 스트림 물려받아 영영 fix 없음.

수정 (둘 다 적용):
1. splash_screen.dart: initState의 ref.listenManual 제거 →
   권한 요청/승인이 끝나는 지점(_runSequence 내 권한 granted 분기 직후)에서 구독.
   미승인 시 구독하지 않음.
2. map_providers.dart locationStreamProvider: 스트림 권한 에러에 죽어 박제되지 않도록 방어.
   - 구독 전 LocationPermission 확인(whileInUse/always 아니면 스트림 생성 보류),
   - 또는 .handleError로 CanceledError 시 재구독 가능하게.
   keepAlive 유지하되 "죽은 스트림 박제" 불가하게.

검증: analyze 통과. 라이딩(필수): 앱 시작 시 GPS 정상 획득 + 콜드스타트 0km/h 소멸.
단일 변경 단위로 커밋 분리(splash / provider).

## 커밋6 — provider 권한 게이트 견고화 (2026-06-24)
문제: locationStreamProvider가 async*에서 권한 없으면 else 없이 종료 → 빈 스트림을
  keepAlive로 박제 → 권한 생겨도 죽은 빈 스트림 물려줌(커밋5 회귀 잔존).
수정 (map_providers.dart locationStreamProvider):
1. checkPermission()이 denied면 requestPermission()으로 요청.
2. 최종 권한이 whileInUse/always 아니면: ref.keepAlive() 호출 전에 return (빈 종료 박제 금지).
3. 권한 확보된 경우에만 ref.keepAlive() + getPositionStream yield*.
   → 권한 미승인 상태의 구독은 캐시에 박제되지 않아, 다음 구독에서 재시도 가능.
검증: analyze 통과. 라이딩: 앱 시작 GPS 정상 획득.
