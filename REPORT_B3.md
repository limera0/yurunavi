# REPORT_B3 — 내비 종료 후 경로탐색 상태 정리

## 수정 내용

- **원래 형태**: `Navigator.of(context).push(MaterialPageRoute(...));` (세미콜론으로 단독 종료)
- **변경 방식**: `.then((_) { if (mounted) _clearDestination(); });` 직접 체이닝.
  `push()`가 `Future<T?>` 반환이므로 `.then` 체이닝 가능. `mounted` 가드로 위젯 해제 후 호출 방지.
- **효과**: NavScreen X 버튼 / 시스템 뒤로 / 도착 팝업 확인 모두 pop → `.then` 실행 → `_clearDestination()` 호출 → routePolyline·allRoutes·destination 리셋 + `_showCourseSheet = false` + `_sheetCtrl.reverse()` + `_recenterMap()`.

## 검증

- **flutter analyze**: 0 issues
- **flutter build apk --debug**: ✓ Built (KGP 경고 무해)
- **커밋**: `22e9f5b` — `fix(nav): reset route sheet & state on nav exit (B3)`
