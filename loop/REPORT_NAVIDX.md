# REPORT_NAVIDX — nav_screen 선택코스 유지 버그 수정

## 0단계 판정

| 항목 | 확인 내용 | 판정 |
|------|-----------|------|
| (a) L311 실문자열 | `if (mounted && routes.isNotEmpty) setState(() => _routePoints = routes[0].points);` | ✓ 정찰 일치 |
| (b) map_providers import | `nav_screen.dart:20` import 존재, `ref.read` L174에서 사용 중 | ✓ |
| (c) selectedRouteIdx 필드 | `mapInteractionProvider` state 필드, `map_providers.dart:87` | ✓ |

→ 모든 게이트 통과. 진행.

---

## 변경 Diff

**파일**: `lib/features/navigation/presentation/nav_screen.dart`

```diff
-      if (mounted && routes.isNotEmpty) setState(() => _routePoints = routes[0].points);
+      if (mounted && routes.isNotEmpty) {
+        final selIdx = ref.read(mapInteractionProvider).selectedRouteIdx.clamp(0, routes.length - 1);
+        setState(() => _routePoints = routes[selIdx].points);
+      }
```

- 위치: `_reroute()` 메서드 내부 (L311→L311-314)
- 변경 라인 수: 1줄 삭제 → 4줄 (net +3)
- 파라미터 추가 없음 — `ConsumerState`의 `ref` 직접 활용
- `clamp(0, routes.length - 1)` 로 재탐색 시 routes 수가 3개 미만인 경우 방어

---

## analyze / build 결과

```
flutter analyze → No issues found! (ran in 2.2s)
flutter build apk --debug → ✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

경고: Kotlin Gradle Plugin 관련 deprecation 경고 2건 — 기존 경고, 이번 변경과 무관.

---

## 커밋

| # | 해시 | 메시지 |
|---|------|--------|
| checkpoint | aadcf1e | checkpoint: before nav reroute selectedIdx fix |
| fix | d0f16bb | fix(nav): 재탐색 시 선택한 코스 인덱스 유지(routes[0] 하드코딩 제거) |

---

## 폰 실측 체크리스트

- [ ] 국도(또는 지방도) 코스 선택 후 내비 시작
- [ ] GPS 경로 이탈 → 재탐색 발생 시, 선택했던 코스 유지 (시골길로 안 바뀜)
- [ ] 시골길(idx 0) 선택 시에도 정상 (회귀 없음)
- [ ] 재탐색 후 폴리라인 정상 렌더링

---

## 별도 이슈 (이번 범위 밖)

**재탐색 시 maneuvers(_steps) 미갱신**
- 현상: `_reroute()`는 `_routePoints`만 교체하고 `_steps`(안내 단계)는 갱신하지 않음
- 결과: 재탐색 후 안내 단계가 초기 코스 기준으로 유지됨
- 영향: 방향 안내 TTS가 재탐색된 코스와 불일치할 수 있음
- 조치: 별도 이슈로 등록, 다음 내비 개선 턴에서 처리
