GOAL: layout_fixes 배치2(라운드4→5→6, 지도 코스 흐름) 순서대로 구현

이 파일을 읽는 Claude는: (1) 아래 요약이 여전히 유효한지 `git log`/실제 코드로
재검증할 것, (2) 라운드4→5→6을 **반드시 이 순서로, 한 세션 안에서** 진행할 것 —
서로 강한 의존관계가 있어 순서를 어기면 재작업이 생긴다(아래 "의존관계" 참고),
(3) `loop/layout_fixes/PROGRESS.md`의 각 라운드 섹션을 직접 읽고 "확정된 수정
계획"을 그대로 구현할 것 — 이미 마스터 승인이 끝난 계획이라 재질문 불필요.

---

## 이전 세션(2026-07-31) 요약 — 배치1 완료

전체 17개 라운드에 대한 구현 순서를 정리해 6개 배치로 나눴고(우선순위/의존관계
분석은 이 대화 이력 참고, 요약만 남김), 배치1(전역 인프라)을 완료했다:

- 커밋 `644a757` — 라운드8(라이더모드/야간모드 전체 삭제) + 라운드3(홈 레이아웃
  재구성: 헤더 검색창+설정버튼 68px, 기록·즐겨찾기 상단 고정그룹, 현위치·줌인·
  줌아웃 하단 고정그룹) **동일 세션 통합 구현**.
- 커밋 `21f6440` — 라운드2(전 화면 상태바/내비바 `#F5F1EC` 통일, `pastSplashProvider`
  도입, nav_screen dispose 버그 수정).
- 커밋 `6a9ce00` — 라운드10(AppBar 전역 배경 모스그린 `#8CA283`, `AppColors.brandMoss`
  신규 상수). **삭제 확인 다이얼로그 브랜드화(문서 2번 항목)는 의도적으로 미구현
  — 나중에 14/15번 등과 묶어서 처리 예정.**

전부 flutter-coder 구현 → code-auditor PASS(각 1회) → 체크포인트 커밋 순서로
진행, `flutter analyze`/`flutter build apk --debug` 매번 통과 확인. 상세 근거·
변경 파일 목록은 각 라운드 문서(`loop/layout_fixes/PROGRESS.md` 라운드2/3/8/10
섹션)의 "### 상태" 줄에 구현 완료 표시로 갱신해뒀다 — 새로 안 읽어도 됨.

**주의 하나**: 배치1 중 code-auditor가 라운드10 감사에서 존재하지 않는 코드
("야간/라이더 테마의 AppBar")를 언급한 적이 있다 — 실제로는 그냥 다른 버튼
위젯의 배경색이었다(라운드8이 그 테마들을 이미 삭제했으므로 애초에 없는 코드).
최종 PASS 판정 자체는 직접 재검증해서 맞았지만, **감사 보고서의 근거가 항상
정확하다고 맹신하지 말고 의심스러우면 직접 grep으로 재확인할 것**.

## 자산 준비 현황 (병렬로 이미 만들어둠)

- `assets/images/slide_to_ride_label.png` — **이번 배치(라운드5)에서 바로 씀**.
  "Slide to Ride" 텍스트 라벨, 투명 배경, Roboto Light, 따뜻한 회색톤. 아이폰
  slide-to-unlock 스타일 참고해서 제작 완료. `lib/core/widgets/slider_start_button.dart`의
  `_StartLabel`(현재 `Text('Start your Engine', ...)`)을 `Image.asset`으로 교체할 때
  이 파일을 쓰면 된다.
- `assets/images/yuru_circle_v2.png`(라운드1용), `assets/images/pointer_start.png`
  (라운드11용), `assets/icon/insta.svg`(라운드15용, 원래 있던 파일) — 이번 배치와
  무관, 이후 배치에서 사용.

## 이번 세션 작업 — 배치2 (라운드4→5→6)

`loop/layout_fixes/PROGRESS.md`에서 직접 읽을 것:
- 라운드4(POI 선택 카드): 365~473줄
- 라운드5(코스 선택 카드): 473~662줄
- 라운드6(경유지 관리 카드): 662~825줄

**주의**: 위 줄번호는 배치1 구현 후 문서에 상태 갱신 메모를 추가하면서 살짝
밀린 최신 값이다(원래 문서 초안보다 +9줄 정도). 코드 쪽 실제 줄번호는 배치1의
라운드3 구현(헤더/버튼그룹 재배치)으로 `main_map_screen.dart`가 상당히 바뀌어서
문서에 적힌 줄번호와 다를 수 있다 — 구현 전 grep으로 반드시 재확인할 것.

### 의존관계 (반드시 이 순서로)

1. **라운드4 → 라운드5**: 라운드5는 `_onMapTap`(지도 빈 곳 탭)을 라운드4의
   `_AddToRouteSheet`(4번 카드)로 합류시키는 배관 작업을 포함한다. 라운드4가
   먼저 끝나 있어야 라운드5의 그 부분이 의미가 있다.
2. **라운드5 → 라운드6**: 라운드6(경유지 관리 카드의 지도 기반 `+` 버튼)은
   "라운드5가 만든 지도탭→4번카드 배관"을 그대로 재사용한다는 전제로 계획돼
   있다. 라운드5 없이 라운드6만 하면 그 기능이 안 붙는다.
3. **`_MapCtrlBtn` 공용 위젯 추출**: 라운드6 계획은 원형 `+`/`-` 버튼 스타일을
   위해 `_MapCtrlBtn`(현재 `main_map_screen.dart`의 private 클래스, 배치1에서
   `size` 파라미터만 추가됨)을 `lib/core/widgets/`로 추출하는 작업을 포함한다.
   **이 추출은 아직 안 됐다** — 배치1(라운드3)에서는 안 했다. 라운드6 구현 시
   이 추출을 직접 하거나, 안 하기로 결정하면 그 이유를 기록해둘 것.
4. 라운드3(홈 레이아웃)이 남겨둔 "좌측 일출/일몰 바 반응형 전환"은 라운드5가
   맡기로 계획돼 있다 — 라운드5 구현 시 함께 처리할 것(`_LeftDaylightBar`가
   `_showCourseSheet` 상태를 받아 위치를 조정하도록).

### 각 라운드 핵심 요약 (상세는 문서 원문 참고)

**라운드4 — POI 선택 카드** (`_AddToRouteSheet`, `main_map_screen.dart`)
- 안내 문구("어디로 추가할까요?") 삭제.
- POI 이름 폰트 확대(15→20~22sp) + 우측에 즐겨찾기 별 버튼(`_FavoriteStarButton`
  재사용) 추가.
- 출발/경유지/목적지 버튼 3개: "경유지" 줄바꿈 버그 수정(`softWrap:false`),
  색상을 3개 다 `AppColors.primary` 하나로 통일(경유지 비활성 상태는 회색 유지),
  탭 시 브랜드컬러 오버레이로 시각 피드백 추가(즉시-`Navigator.pop` 동작 자체는
  유지).
- 경유지 비활성화 로직(`hasDest`)은 그대로.

**라운드5 — 코스 선택 카드** (`CourseSheet`/`RouteCard`, `lib/core/widgets/course_sheet.dart`;
슬라이드 버튼 `lib/core/widgets/slider_start_button.dart`)
- 상단 요약 행: `destinationName` 버그 수정(`interaction.destinationName ??
  interaction.stops.last.name` — 현재 늘 "목적지"로 폴백되는 버그), 점 인디케이터
  제거, 구분자를 ">>"로, 경유지 0개면 회색 "경유지" 텍스트.
- 지도 탭(`_onMapTap`) → 코스 시트 열려있으면 항상 4번 카드(`_showAddToRouteSheet`)로
  통일, POI 없으면 좌표 문자열 표시. 이 분기로 죽는 `_showTapConfirmSheet`의
  `hasRoute` 경로/`_TapAction.waypoint` 케이스는 정리(삭제).
- 재미 점수(`windingScore`/`isBestFun` 배지) 카드에서 완전 제거(계산 로직 자체는
  유지, 표시만 뺌).
- 카드 표면 디자인 강화(미선택 상태도 옅은 카테고리색, 선택 시 tint/보더 더 진하게),
  거리/시간 폰트 확대.
- 슬라이드 버튼: 트랙을 완전 pill+흰 배경+플로팅 그림자로, 썸은 흰배경+쉐브론
  아이콘으로, 텍스트는 위 자산(`slide_to_ride_label.png`)으로 교체. **드래그
  로직 자체는 절대 건드리지 말 것**(마스터가 명시적으로 확인한 부분).
- 좌측 일출/일몰 바 반응형 전환(위 의존관계 4번 참고).

**라운드6 — 경유지 관리 카드** (`WaypointManagementSheet`,
`lib/features/map/presentation/waypoint_management_sheet.dart`)
- 하단 검색식 "+ 경유지 추가" 버튼 삭제(지도 기반 `+`로 완전 대체).
- 리스트 행: 색깔 점 제거, 출발지·도착지 행만 bold, 삭제 아이콘 원형 배지 스타일로.
- 출발지/도착지 행에 `+` 버튼 신규 추가 — 출발지 옆은 첫 경유지로 삽입, 도착지
  옆은 마지막 경유지로 삽입. `addWaypoint`에 삽입 위치 파라미터 추가 필요.
  `+` 탭 → 시트 닫힘 → 지도 탭 → (라운드5가 만든 배관으로) 4번 카드 → 완료 후
  경유지 관리 시트 자동 재오픈. 상태 전달은 provider 플래그 방식 제안(문서 참고,
  다른 방식도 가능 — flutter-coder 재량).
- 재정렬(`reorderStop`)·삭제(`removeWaypoint`) 로직은 이미 요구사항과 일치 —
  변경 불필요, 시각 스타일만 정리.

## 작업 순서 (CLAUDE.md 워크루프 그대로)

1. `loop/layout_fixes/PROGRESS.md`의 세 라운드 섹션을 직접 읽고 실제 코드 줄번호를
   grep으로 재확인.
2. 라운드4 구현 → flutter-coder → code-auditor → PASS → 체크포인트 커밋.
3. 라운드5 구현(좌측 일출/일몰 바 반응형 포함) → flutter-coder → code-auditor →
   PASS → 체크포인트 커밋.
4. 라운드6 구현(`_MapCtrlBtn` 공용 추출 여부 결정 포함) → flutter-coder →
   code-auditor → PASS → 체크포인트 커밋.
5. `PROGRESS.md`의 라운드4/5/6 "### 상태" 줄을 구현 완료로 갱신(배치1에서 한 것과
   동일한 방식 — 커밋 해시·핵심 변경 요약 남기기).
6. 필요하면 `loop/MORNING_REPORT_*.md` 작성(Goal/Met 판정 포함) — 단, 이번은
   인터랙티브 저녁 세션이 아니라 인수인계 기반 세션이라 마스터가 별도로 요청하면
   작성.

## 다음 배치 예고 (이번 세션 범위 아님)

배치3 = 라운드7(내비게이션 레이아웃, 마스터가 "가장 중요한 화면"으로 명시).
`nav_screen.dart` 단독 작업이라 이번 배치(4/5/6, `main_map_screen.dart`/
`course_sheet.dart`/`waypoint_management_sheet.dart` 중심)와 파일 겹침 없음 —
병렬 세션으로 진행해도 무방.
