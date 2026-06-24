# SPEC_heading — 재탐색 heading 전달 (증상: 경로이탈 후 불법유턴)

근거: RECON_reroute.md §D. Valhalla fork는 heading/heading_tolerance 수용 확인(curl B, 에코됨).
문제: Flutter가 재탐색 요청에 진행방향 미전송 → Valhalla가 방향 모르고 유턴을 최단으로 반환.

## 구현 (3커밋, 각 단일파일)
- 커밋1 nav_screen.dart: double? _currentHeading 상태 추가.
  _onPosition에서 pos.heading >= 0 일 때 _currentHeading 갱신.
  (heading은 현재 카메라 회전에만 쓰임 — 그 소비 지점 유지하되 상태로도 보관)
- 커밋2 routing_service.dart: fetchRoutes()에 {double? heading} 파라미터 추가.
  heading != null이면 locations[0]에 'heading': heading.round(), 'heading_tolerance': 45 삽입.
  (다른 호출처 시그니처 깨지지 않게 optional)
- 커밋3 nav_screen.dart: _reroute()에서 _currentHeading을 fetchRoutes(heading:)로 전달.

## 검증
- 객관(analyze): 컴파일 통과, heading optional이라 기존 호출 안 깨짐.
- 라이딩(필수, main 머지 전): 경로이탈 유발 → 재탐색이 진행방향 유지하는 경로 반환(즉시 유턴 아님).
