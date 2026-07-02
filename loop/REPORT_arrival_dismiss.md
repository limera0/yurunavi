# REPORT — 도착 다이얼로그 재탐색 시 dismiss (#2)

브랜치: `feat/arrival-dialog-dismiss` (main 대비 3커밋, main 머지 안 함 — T3)

## 커밋

1. `c74ac30` feat(nav): track arrival dialog visibility
2. `0795298` fix(nav): dismiss arrival dialog on reroute (p7)
3. `34a9c1c` test(nav): arrived+offRoute concurrency on overshoot

## 변경 file:line

- `lib/features/navigation/presentation/nav_screen.dart:80` — `bool _arrivalDialogShown = false;` 필드 추가 (기존 `_arrived`(:79) 바로 아래).
- `lib/features/navigation/presentation/nav_screen.dart:390` — `_showArrivalDialog` 진입 시 `_arrivalDialogShown = true;`.
- `lib/features/navigation/presentation/nav_screen.dart:435` — `showDialog<void>(...)`에 `.whenComplete(() => _arrivalDialogShown = false);` 부착. 확인 버튼 콜백(:426-430, 기존 pop/pop 로직)은 수정하지 않음 — 어떤 경로로 닫히든 whenComplete가 플래그를 정리.
- `lib/features/navigation/presentation/nav_screen.dart:288` — `_reroute()` 진입부 early-return(:287) 직후 `if (_arrivalDialogShown && mounted) Navigator.of(context).pop();` 추가. pop 이후 플래그 정리는 whenComplete가 담당(중복 리셋 없음).
- `test/route_progress_arrival_test.dart` (신규, 76줄) — `route_progress_provider.dart`의 `_advance` 순수 로직만 검증. Riverpod `ProviderContainer` + `navStateProvider` 오버라이드(`_FakeNavStateNotifier`)로 플랫폼 채널(Geolocator/locationStream) 우회.

## 테스트 결과

`flutter test test/route_progress_arrival_test.dart` — **2/2 green**:
- `정상 도착: 목적지 도달 시 arrived=true, offRoute=false` — PASS (perp=0.0)
- `목적지 지나쳐 계속 주행: arrived=true 유지되며 offRoute=true 동반` — PASS (도착 후 60m 더 주행 시 perp=60.0 > `_kOffRouteM`(50.0), `distToDest`는 폴리라인 끝에서 0으로 클램프되어 `arrived` sticky 유지)

`flutter analyze` (전체 프로젝트) — 이번 변경 관련 신규 에러/경고 0. 잔여 4건은 모두 이번 브랜치 변경과 무관한 기존 이슈:
- `route_progress_provider.dart:34,48` — `_dest`/`_kBackToleranceM` unused (기존 코드, 이번 커밋에서 건드리지 않음)
- `settings_screen.dart:71,73` — Flutter SDK `groupValue`/`onChanged` deprecation info (기존 코드)

C1 단독 커밋 시점(`_arrivalDialogShown` 아직 미소비)에는 `unused_field` 경고가 일시적으로 있었으나 C2 커밋으로 필드를 읽으면서 해소됨 — 최종 상태에는 잔존하지 않음.

## 라이딩 체크 (실기기 검증 필요 — 미검증)

- [ ] 목적지 지나쳐 계속 주행 → offRoute 감지로 재탐색 진입 시 도착 다이얼로그가 자동으로 사라지는지
- [ ] 도착 다이얼로그 '확인' 버튼 클릭 시 기존처럼 내비 화면이 정상 종료되는지 (다이얼로그 pop + 내비 화면 pop, 회귀 없음)
- [ ] 정상 도착(지나치지 않고 목적지 반경 내 정지) 시 다이얼로그가 여전히 정상 표시되는지

## 비고

- `_reroute`/`_showArrivalDialog`는 `State`+`Navigator`/`showDialog` 의존이라 위젯 테스트 없이 순수 유닛 테스트 불가 — RECON_arrival_dialog.md #5 근거에 따라 dismiss 배선 자체(하나의 훅 지점)는 실기기 라이딩으로만 검증 가능한 영역으로 남김.
- main 머지 금지(T3). 다음 틱에서 라이딩 검증 후 병합 여부 결정.
