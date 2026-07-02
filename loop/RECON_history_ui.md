# RECON_history_ui — 히스토리 표시 (읽기 전용)
규칙: 읽기전용, 코드변경 금지, 모호하면 중단+보고. 하단 append.
- [ ] RecentRoute 리스트 위젯 file:line
      rg -n "RecentRoute|recentRoutes|recent_routes" lib/ --type dart
- [ ] 현재 타이틀/서브타이틀에 무엇 표시? destLat/destLng 직접? file:line
      rg -n "destLat|destLng|toStringAsFixed|destName" lib/
- [ ] 좌표 포맷 헬퍼 있나(예: '37.15, 127.07')
출력: 리스트 위젯 file:line + 현재 표시 표현식 원문.