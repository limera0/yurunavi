# MORNING_REPORT — Night 10 (2026-06-03) — 갱신본

## 완료 항목 (기존 + 이번 세션)

### ROADMAP 9 — 에러 핸들링 + 재시도 | `472f158`
- RoutingError enum / RoutingException 클래스
- serverDown 1회 자동 재시도, noRoute/serverError 즉시 반환
- _showRoutingError: 유형별 한국어 메시지 + 재시도 SnackBarAction

### ROADMAP 10 — scripts/check_all.sh | `f5af23e`
- flutter analyze + cargo test(33/33) + validate_rural_route.py 통합 실행
- --skip-validate 플래그, validate exit 2 = 경고

---

## 이번 세션 (11~27)

### 11 속도계 0 버그 | `db433e4`
- distanceFilter 0, 데드존 2.5km/h + accuracy>20m, 3-샘플 이동평균
- 적응 갱신: ≤10km/h 2Hz, 나머지 1Hz

### 12 즉시 위치 | `16cbfeb`
- getLastKnownPosition() → 즉시 카메라 이동
- kInitialMapView → 한국 지리 중심(36.5,127.5)으로 변경

### 13 실제 턴바이턴 | `e80a65d`
- ManeuverStep 파싱, _fetchedRoutes로 카드 전환 시 maneuvers 동기화
- _TurnStep.fromManeuver: type→아이콘+한국어 레이블

### 14 도착 이벤트 | `3a3aff9`
- 30m 반경 도달 시 "도착했습니다!" 다이얼로그 → 홈 복귀

### 15 이탈 재탐색 | `c42f43a`
- 20m 이탈 + 3s 디바운스 → RoutingService.fetchRoutes 자동 재탐색
- 디바운스 발화 시점 _currentPos 사용(stale loc 방지), routes.isNotEmpty 가드

### 16 속도계 위치 | `e05e465`
- bottom:160 → top:MediaQuery.of(context).size.height * 0.30

### 17 속도 연동 줌 | `98ff99f`
- 0~20→줌18, 20~60→줌16, 60+→줌14 선형 보간
- GPS 이벤트당 최대 0.5레벨 수렴으로 부드럽게

### 18 BMNT/EENT API | `b977d9e`
- api.sunrise-sunset.org nautical_twilight; UTC+9 변환(toLocal 이중변환 버그 수정)
- 정적 캐시(lat_1dp,lng_1dp,date), 오프라인 fallback → sunrise_sunset_calc
- cycleState: 낮(BMNT→EENT)/밤(EENT→익일BMNT) 진행도 + DaylightBar isNightMode

### 19 야간 디밍 | `c685afb`
- IgnorePointer + Colors.black alpha 0.35 오버레이 (색 재지정 없음)
- main_map_screen + nav_screen 양쪽 적용

### 20 화면 항상 켜짐 | `56e55b3`
- wakelock_plus 추가; initState에서 enable, dispose에서 disable

### 21 내 장소 | `bad27d7`
- FavoritePlace + RecentRoute 모델; PlacesService(SharedPreferences)
- 즐겨찾기 저장/삭제/선택, 최근 경로 5개 자동 저장
- _showPlacesSheet: 북마크 버튼에서 진입, 탭 → _applyDestination

### 22 앱 생명주기 | `34a1d6f`
- PopScope(canPop:false) + 2초 내 연타 → SystemNavigator.pop()
- "뒤로 한 번 더 누르면 종료됩니다" 토스트

### 23 음성 안내 | `c5d2b07`
- flutter_tts 추가; ko-KR, speed 0.5
- _announceStep: "dist 앞 label" 발화, 중복 방지 _lastAnnouncedIdx

### 24 지도 자동 회전 | `5744b28`
- pos.heading ≥ 0 && speed > 2km/h → _mapCtrl.rotate(-pos.heading)

### 25 코스 색상 구분 | `bbe30dd`
- 선택 경로도 시골길(초록)/지방도로(보조)/국도(주색) 고유색 0.92 적용

### 26 권한 흐름 | `814a60b`
- 스플래시에서 위치 권한 요청; denied → 재요청 다이얼로그, deniedForever → 설정 열기

### 27 경로 요약 | `8a58ff3`
- _showRouteSummary: 코스 시트 "요약" 버튼 → 총거리/예상시간/재미점수/와인딩 구간 수

---

## 최종 상태
- ROADMAP 항목 1~27 전부 [x] 완료
- flutter analyze: No issues found
- cargo test: 33/33 PASS
- 차단 없음
