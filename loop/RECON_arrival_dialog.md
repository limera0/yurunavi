# RECON — 도착 다이얼로그가 재탐색 진입 후에도 안 사라지는 문제

## 앵커

1. **다이얼로그 표시 지점** — `lib/features/navigation/presentation/nav_screen.dart:388-434` (`_showArrivalDialog`).
   트리거는 `nav_screen.dart:222-227`: `routeProgressProvider` 구독 콜백 안에서 `if (prog.arrived && !_arrived)` → `_arrived = true` 후 POI 조회 완료 시 `_showArrivalDialog(pois)` 호출. `prog.arrived`는 `route_progress_provider.dart:144` `distToDest <= _kArrivalM(25.0)`로 계산.

2. **'확인' 버튼 콜백** — `nav_screen.dart:424-430`. `Navigator.of(ctx).pop()`(다이얼로그 닫기) 후 `Navigator.of(context).pop()`(내비 화면 자체 종료) — 이게 "확인 누르면 내비 강제종료" 증상의 근원. showDialog가 Navigator 스택에 새 route를 push하는 구조이므로, 다이얼로그가 떠 있는 동안은 `Navigator.of(context).pop()` 한 번으로 다이얼로그만 닫을 수 있음(스택 최상단이 다이얼로그 route이므로).

3. **표시 상태 플래그** — 전용 "다이얼로그가 현재 떠 있다" bool은 없음. 있는 건 `_arrived`(`nav_screen.dart:79`) 뿐이며, 이는 "도착 이벤트를 이미 처리했다"는 1회성 래치(재-트리거 방지)일 뿐 다이얼로그 표시 여부와 결합되어 있지 않음(`showDialog` 자체가 dismiss돼도 `_arrived`는 리셋되지 않음). dismiss 배선을 걸려면 `_arrivalDialogShown`류의 새 플래그가 필요 — 후보: `_showArrivalDialog` 진입 시 true, 확인 콜백에서 false로 리셋.

4. **재탐색 진입 지점** — `nav_screen.dart:277-284` (`_triggerReroute`, offRoute 감지 시 디바운스 타이머로 `_reroute` 호출) → `nav_screen.dart:286-325` (`_reroute(origin)`, 실제 재탐색 수행: 새 경로 fetch, `_applyRouteGuidance`, `_vps?.speak('reroute')`). `_reroute` 시작부(287번 줄, `if (_isRerouting || !mounted) return;` 직후)가 다이얼로그 dismiss 훅을 걸 최적 지점 — 이미 "1개 진입점"으로 좁혀져 있고, 재탐색이 실제로 확정된 시점(early return 이후)이라 불필요한 dismiss를 피할 수 있음.

5. **목적지 지나침 vs 일반 이탈 재탐색 — 구분 없음.** `route_progress_provider.dart:104-163` (`_advance`)를 보면 `arrived`와 `offRoute`는 같은 프레임에서 동일한 스냅 계산(`bestSeg`/`perpM`/`distToDest`)으로부터 독립적으로 산출됨. 폴리라인은 마지막 세그먼트에서 단조 증가가 막혀 있어(127-131행), 목적지를 지나쳐 계속 주행하면 `distToDest`는 낮게 유지되어 `arrived=true`가 sticky한 채로 `perpM`이 커져 `offRoute=true`가 함께 뜨는 구조. 즉 "지나쳐서 재탐색"은 코드상 일반 offRoute 재탐색과 완전히 동일 경로(`prog.offRoute` → `_triggerReroute`)로 처리됨 — 별도 판정 로직 없음.

## 수정 슬라이스 제안

- **훅 위치**: `_reroute()` 진입부 1곳(`nav_screen.dart:287` 직후, `setState(() => _isRerouting = true)` 전후 어디든) — "재탐색이 실제로 시작되면 무조건 도착 다이얼로그 dismiss"라는 단일 규칙으로 충분(#5에서 확인했듯 지나침 재탐색을 구분할 필요가 없으므로 이 규칙이 안전함).
- **다이얼로그 핸들 확보**: `_showArrivalDialog` 호출 시 `_arrivalDialogShown = true` 플래그를 새로 두고, `_reroute()`에서 `if (_arrivalDialogShown) { Navigator.of(context).pop(); _arrivalDialogShown = false; }` 형태로 닫기. 확인 버튼 콜백(424-430)에서도 플래그를 false로 리셋해야 이중 pop 방지. `showDialog`가 리턴하는 Future를 활용해 `.then((_) => _arrivalDialogShown = false)`로 대체하는 방법도 가능(버튼 콜백 수정 불필요, 다이얼로그가 어떤 경로로 닫히든 플래그 정리됨) — 이 편이 더 안전한 배선.
- **순수 테스트 가능 경계**: `_reroute`/`_showArrivalDialog`는 `State` 내부 메서드 + `Navigator`/`showDialog` 의존이라 위젯 테스트(`WidgetTester`) 없이는 순수 유닛 테스트 불가. `RouteProgress.arrived`/`offRoute`가 동시에 true가 되는 케이스 자체는 `route_progress_provider.dart`의 `_advance` 로직만으로 순수 유닛 테스트 가능(#5 검증용).
- **별건(범위 밖)**: 다이얼로그 UI/디자인 개선(POI 목록 스타일 등)은 이번 범위 밖.
