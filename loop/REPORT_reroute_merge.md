# REPORT: reroute maneuver/TTS rebuild 머지 (증상4)
날짜: 2026-06-14

---

## 게이트 결과 (0-1 ~ 0-6)

### 0-1 main 상태
```
082d6e5 merge: map label language (KO/EN) + settings shell + location-marker style-reinjection fix
```
origin/main과 동기 (`git pull --ff-only` 성공)

### 0-2 merge-base
```
59b0ab8 docs: speed polish report
```
feat 브랜치가 이 커밋에서 분기 → main에 이미 반영된 5개 커밋(언어·마커) 이후의 변경분.

### 0-3 feat 커밋 목록 (5개)
```
d6af1b2 docs: add PROGRESS_goal4.md
5269b01 fix(nav): rebuild maneuver/TTS state on reroute
ff1c474 refactor(nav): use _applyRouteGuidance on initial route
4108368 refactor(nav): extract _applyRouteGuidance helper
8ce980b refactor(nav): make _steps mutable for reroute rebuild
```

### 0-4 diff 범위 (nav_screen.dart)
| 구간 | 내용 |
|------|------|
| import line 1 | `dart:math`에서 `max` 제거 |
| line ~109 | `late final List<_TurnStep>` → `late List<_TurnStep>` |
| line ~141 | initState maneuver 블록 → `_applyRouteGuidance(widget.maneuvers)` 호출로 교체 |
| line ~357 | `_applyRouteGuidance()` 메서드 신규 추가 |
| line ~463 | `_reroute` 내 setState에 `_applyRouteGuidance(routes[selIdx].maneuvers)` + `_announceStep(0)` 추
가 |

### 0-5 겹침 판정: **독립 (충돌 없음)**
- feat 변경 구간: `initState` 하단부(maneuver 변환), `_reroute` 내부
- main 언어·마커 코드: `_rawStyle`/`_styleJson` 필드(line 56-57), 언어 로드 콜백(line ~179), `onStyleLoadedCall
back`/`styleString`(line ~802-818)
- 두 영역은 텍스트상 분리. `_steps` 선언 변경(`final` 제거)만 같은 파일 내 근접하나 내용 충돌 없음.

### 0-6 드라이런
```
Auto-merging lib/features/navigation/presentation/nav_screen.dart
Automatic merge went well; stopped before committing as requested
```
**충돌 없음 확인.**

---

## [1] 머지 결과

- 커밋 해시: `80dd854`
- 메시지: `merge: reroute maneuver/TTS rebuild (fix symptom4)`
- 변경 파일: `PROGRESS_goal4.md` (신규), `nav_screen.dart` (수정)

### flutter analyze
```
2 issues found (info 수준, settings_screen.dart deprecated Radio API)
```
에러 없음. 경고는 머지 이전부터 존재하는 기존 항목.

### flutter build apk --debug
```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
```
빌드 성공.

---

## [2] 폰 검증 절차

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### 검증 순서

**사전 조건**
- GPS 켜짐, 타일서버(192.168.0.57:8080) 접근 가능
- 목적지 설정 후 탐색 화면 진입

**증상4 핵심 검증 (재탐색 후 maneuver/TTS)**

1. 탐색 화면 진입 → 첫 번째 안내 TTS 발화 확인
2. 경로에서 20m 이상 이탈하여 재탐색 트리거
3. 재탐색 완료 후:
   - [ ] 상단 maneuver 아이콘·텍스트가 새 경로 기준으로 업데이트됨
   - [ ] TTS가 첫 step 안내를 발화함 ("경로 안내 시작" 또는 첫 교차점 안내)
   - [ ] 진행하면 step 자동 진행 정상 작동

**회귀 검증 (언어·마커 — 이전 머지 기능)**

4. [ ] 지도 한글/영문 라벨 표시 정상 (설정에 따라)
5. [ ] 현위치 마커(파란 점), 목적지 마커(핀) 정상 표시
6. [ ] 재탐색 후에도 마커 유지됨

**블로커**
- 재탐색 후 maneuver 텍스트가 여전히 이전 경로 step을 보이면 → `_applyRouteGuidance` 미호출 의심
- TTS 발화 없으면 → `_announceStep(0)` 타이밍 문제

---

## 변경 요약

`_applyRouteGuidance()` 헬퍼 추출로 초기 진입과 재탐색 시 maneuver 리스트·stepIdx·announcedIdx 상태를 동일하게
재설정. `_reroute()` 내 setState 후 `_announceStep(0)` 호출로 TTS 즉시 트리거.