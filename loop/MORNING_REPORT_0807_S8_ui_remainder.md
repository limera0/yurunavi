# MORNING REPORT — S8 UI 잔여

- 작성 2026-08-07 (저녁 대화형 세션) · 브랜치 `verify/ride-0711`
- 지시서: [HANDOFF_0807_S8_ui_remainder.md](HANDOFF_0807_S8_ui_remainder.md)
- 체크리스트: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S8

---

## 착수 전 확인 — 시스템바 항목 원문 정정

체크리스트 원문("홈: 상단/하단 모두 투명")은 오전사였다. 실제 지적은 정반대: 2026-07-30
라운드2에서 결정한 "홈·코스시트·경로옵션시트 전체를 불투명 `#F5F1EC`로 통일"이 반영 안
되고 투명하게 보인 것에 대한 항의였다. 착수 전 이 충돌을 마스터에게 확인받았다.

이 세션에서 근본원인을 특정했다: `app_theme.dart`의 `AppBarTheme`에
`systemOverlayStyle`이 설정돼 있지 않아, `AppBar`를 쓰는 5개 화면(히스토리·설정·
프로필·즐겨찾기카테고리·약관 — 라운드2가 애초에 커버한 적 없는 화면들)이 Flutter의
기본 동작으로 전역 색을 자체적으로 덮어쓰고 있었다. `main.dart`/`nav_screen.dart`
쪽은 원래부터 정확했다.

## 뭐가 됐나

커밋 `fc638f2`. 5건 전부 완료.

1. **시스템바 색상 통일** — `app_theme.dart`의 `AppBarTheme`에 `kSystemBarColor` 조합의
   `systemOverlayStyle` 추가. 화면별 패치 대신 테마 한 곳에서 처리해 향후 새 AppBar
   화면에도 자동 적용.
2. **주유소 경유지 마커 미표시** — `_initDestLayer()`가 `widget.waypoints` 대신
   `_liveWaypoints`를 순회하도록 수정 + `_addGasStationWaypoint()`에서 삽입 직후
   즉시 `addSymbol` 호출.
3. **하단 카드 남은 거리** — 고정값(`routeKm`, 내비 시작 시점 스냅샷)을 `progressSub`의
   `distToDestM` 실시간 값으로 교체.
4. **현위치/목적지 3초 교대** — `GeocodingService.reverseGeocodeCoarse` 신설(기기
   내장 geocoder, 시/군/구 수준만). 300m/60s 스로틀(S2의 `PoiFetchThrottle` 재사용).
5. **상단 카드 줄바꿈** — 마스터 1순위(flexible 확장)로 해결. 카드를 `nav_top_card.dart`로
   분리해 `ConstrainedBox(minWidth 62%) + IntrinsicWidth + Flexible` 구조로 교체
   (`IntrinsicWidth` 안에서 동작 안 하는 기존 `Expanded`를 `Flexible`로 전환).
   위젯 테스트로 5개 화면폭 × 8개 거리문자열 × 4개 도로명 길이 조합에서 overflow 0건
   확인.

## 감사에서 잡힌 결함 1건 → 즉시 수정

code-auditor **1차 FAIL**: `_initDestLayer()`가 `_liveWaypoints`를 직접 순회하며 매
반복 `await`하는 구조인데, 그 사이 `_addGasStationWaypoint()`가 같은 리스트를
변경하면(플로팅 오버레이에서 복귀해 `_onStyleLoaded()`가 재실행되는 동안 등, 실제
발생 가능한 경로) `ConcurrentModificationError`가 날 수 있다는 지적. 감사가 Dart
실제 동작으로 직접 재현까지 확인한 정밀한 지적이라 그대로 반영했다 —
`List<LatLng>.of(_liveWaypoints)` 스냅샷을 순회하도록 한 줄 수정, 정적 테스트의
문자열 매칭도 새 패턴에 맞게 동기화. 재감사 없이 `flutter analyze`/`flutter test`
재확인 후 커밋했다(변경이 감사 지적 그대로였고 범위가 명확해서).

## 검증

- `flutter analyze`: 이슈 0
- `flutter test`: **629건 전건 통과**
- code-auditor: 1차 FAIL(위 1건) → 수정 → 커밋. 나머지 4개 항목은 전부 1차에서
  깨끗하게 통과(원본 동작 보존 여부까지 라인 단위로 대조 확인됨).

## 잔여

- **검증(실기기)**: 5개 AppBar 화면 육안 확인 / 실제 남은거리 감소 확인 / 3초 교대
  표시 육안 확인 / 88.8km급 목적지 줄바꿈 없음 / 주유소 추가 시 마커 즉시 표시 —
  **마스터 실기기 수동 검증 대기**
- **감사 부수 발견(스코프 밖)**: `nav_screen.dart`의 화면 카드(`_maneuverText`)는
  여전히 신뢰 불가로 확정된 `roundaboutExitCount`를 화면에 표시한다(S6 리포트에서도
  동일 지적). S6·S8 어느 쪽 스코프도 아니었다 — 후속 검토 필요.

---

**목표 달성 판정:** 원래 목표: S8 UI 잔여 5건(시스템바 색상, 주유소 마커, 하단 카드
남은거리·현위치교대, 상단 카드 줄바꿈) 처리. / 달성: **코드 완료 — yes**(감사 지적 1건
반영 포함). 실기기 육안 검증은 **마스터 대기**.
