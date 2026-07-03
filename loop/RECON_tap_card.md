# RECON_tap_card — 탭 확인 카드 (읽기 전용)
규칙: 읽기전용, 코드변경 금지, 모호하면 중단+보고. 하단 append.
- [ ] 현재 탭 시 하단 시트/카드 위젯 있나? 없으면 화면 하단 오버레이 구조 확인
      rg -n "showModalBottomSheet|BottomSheet|Positioned.*bottom|_TapActionSheet" lib/ --type dart
- [ ] _showTapActionSheet(목적지/경유지 선택) 위젯 구조·표시 표현식 file:line
      rg -n "_showTapActionSheet|_TapAction" lib/
- [ ] _resolveTappedPoiName 결과를 카드가 쓰려면: 호출 시점·반환 타이밍(탭 즉시 vs 목적지확정 후) file:line
- [ ] best PickFeature의 분류(class/subclass) props 키 — 카드에 "레스토랑" 류 표시용
      (props 예시: name:nonlatin, class, subclass — RECON_query 반환 properties 재확인)
- [ ] 좌표→주소 없음 확인(역지오코딩 부재) → 카드 부제목은 분류+좌표 폴백
출력: 하단 카드/시트 위젯 file:line + 탭 데이터 흐름 + props 분류 키.