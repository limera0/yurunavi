# REPORT_ZOOM — 줌맞춤 하단 패딩 보정

## 시트 높이 파악 방식 + 패딩 전략

- **시트 높이 파악**: `_CourseSheet`는 `mainAxisSize: MainAxisSize.min`으로 고정 height 상수 없음.
  기존 코드에서 시트 관련 참고값으로 라인 801 `_showCourseSheet ? 270 : 140`(터치 레이블),
  라인 1089 `showCourseSheet ? 220.0 : 60.0`(RightPanel 패딩) 사용 중.
  런타임 GlobalKey 측정은 복잡도 대비 효과 낮으므로 채택하지 않음.
- **채택 전략**: `_showCourseSheet` 기반 동적 고정값.
  시트 실제 점유 ~270px + 여유 90px = **360px** (시트 표시 시),
  시트 미표시 시 **80px**.
- **최종 값**: `final bottomPadding = _showCourseSheet ? 360.0 : 80.0;`
  (`_updateRouteLayer` 내 `newLatLngBounds` bottom 인자로 전달)

## 검증

- **flutter analyze**: 0 issues
- **flutter build apk --debug**: ✓ Built (KGP 경고 무해)
- **커밋**: `115014d` — `fix(map): enlarge bottom padding so route clears course sheet (#5)`
