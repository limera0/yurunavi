# RECON_B3 — 내비 종료 후 깨진 경로탐색창 정찰 결과

## 1. main↔nav 전이 방식 + X·뒤로 동작

- **전이 방식**: **별도 라우트 push** — `_startNavigation()` (라인 558) 에서
  `Navigator.of(context).push(MaterialPageRoute(builder: (_) => NavScreen(...)))` 호출.
  NavScreen은 별도 페이지. main_map_screen은 스택 아래에 살아있음.
- **X(종료) 버튼**: `nav_screen.dart:766` — `Navigator.of(context).pop()` 단순 pop.
  상태 리셋 콜백 **없음**.
- **시스템 뒤로**: NavScreen에 PopScope/WillPopScope **없음** → 기본 pop 동작.
  역시 상태 리셋 **없음**.
- **도착 다이얼로그 '확인'**: `nav_screen.dart:439-440` — `Navigator.of(ctx).pop()` + `Navigator.of(context).pop()` 순차 호출. 역시 상태 리셋 없음.
- **`push` 뒤 `.then()` 콜백**: `main_map_screen.dart:558-567` — `.then()` **없음**.
  pop으로 돌아와도 main_map_screen에서 아무 콜백도 실행되지 않음.

---

## 2. 경로탐색 시트 표시 조건 + 애니메이션 컨트롤러

- **표시 조건**: `_showCourseSheet: bool` 로컬 상태 (라인 107).
  `build()`에서 `if (_showCourseSheet) SlideTransition(child: _CourseSheet(...))` (라인 849).
  `_applyDestination()` (라인 429) 에서 `setState(() => _showCourseSheet = true)` + `_sheetCtrl.forward()` 호출.
- **애니메이션 컨트롤러**: `_sheetCtrl` (`AnimationController`, 라인 116) + `_sheetSlide` (`Animation<Offset>`, 라인 117).
  `initState`(라인 122)에서 초기화, begin=`Offset(0,1)` → end=`Offset.zero`.
  `_clearDestination()`(라인 534)에서 `_sheetCtrl.reverse()`로 내림.
- **증상 원인**: NavScreen에서 pop으로 돌아오면 `_showCourseSheet`는 여전히 `true`, `_sheetCtrl.value`는 1.0 (fully shown) 상태 그대로. 시트가 다시 슬라이드 없이 즉시 렌더됨.
  "슬라이드 버튼이 빠진" 현상 → `_CourseSheet` 내부 `SliderStartButton`이 재초기화되지 않아 발생 가능성 있음. 혹은 `_sheetCtrl.forward()` 재호출 없이 시트가 value=1.0 상태에서 정적으로 렌더되어 SlideTransition 애니메이션이 완료 상태로 고정 표시.

---

## 3. 종료 시 상태 정리 로직 유무 + 후보 위치

- **현재**: `_startNavigation()`의 `Navigator.push(...)` 에 `.then()` 콜백이 **없음** (라인 558-568).
  NavScreen pop 후 main_map_screen 복귀 시 어떠한 상태 정리도 실행되지 않음.
- **`_clearDestination()`** (라인 531)은 이미 구현되어 있음:
  `ref.read(mapInteractionProvider.notifier).reset()` (routePolyline·allRoutes·destination 전부 클리어) +
  `setState(() { _showCourseSheet = false; _touchPoint = null; })` +
  `_sheetCtrl.reverse()` + `_recenterMap()`.
- **수정 후보 위치**: `main_map_screen.dart:558` `Navigator.push(...)` 호출에 `.then()`을 추가:
  ```dart
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => NavScreen(...)),
  ).then((_) {
    if (mounted) _clearDestination();
  });
  ```
  이것만으로 pop 복귀 시 시트·경로·목적지 상태가 모두 정리됨. 코드 변경 1줄.
