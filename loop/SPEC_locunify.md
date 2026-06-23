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
