# REPORT: guidance-fix (T1~T3)
브랜치: feat/guidance-fix | 베이스: guidance-baseline (80dd854)

---

## [0] 셋업 게이트

| 항목 | 결과 |
|------|------|
| main push | origin/main ← 80dd854 (6커밋 선행분 push) |
| 브랜치 | feat/guidance-fix 생성·push |
| 태그 | guidance-baseline |

### 편집 대상 실위치 (grep 재확인)

| 심볼 | file:line |
|------|-----------|
| `_iconForType` | nav_screen.dart:1222 |
| `_labelForType` | nav_screen.dart:1238 |
| `_TurnStep.fromManeuver` | nav_screen.dart:1213 |
| 카드 `step.icon/label` | nav_screen.dart:948, 967 |
| 카드 `step.dist` | nav_screen.dart:955-959 |
| `remaining` 계산 | nav_screen.dart:411 |
| 400m 예비발화 `_steps[_stepIdx+1]` | nav_screen.dart:414 |
| `_stepIdx++` (GPS) | nav_screen.dart:423 |
| `_stepIdx++` (수동탭) | nav_screen.dart:909 |
| `_updateStepByDistance` | nav_screen.dart:406 |

RECON_direction.md 위치와 일치. 구조 변경 없음.

---

## [T1] 방향 매핑 전면 교정

**커밋:** 65528b7 | **태그:** guidance-T1

**변경 파일:** `lib/features/navigation/presentation/nav_screen.dart`

### 교정 내용

**`_iconForType`:**

| 변경 | 이전 | 이후 | 이유 |
|------|------|------|------|
| type 17 (RampStraight) | `turn_slight_right` | `straight_rounded` | 직진 아이콘↔레이블 불일치 해소 |
| type 18 (RampRight) | `turn_slight_left` ❌ | `turn_slight_right` ✓ | 좌우 반전 버그 수정 |
| type 19 (RampLeft) | `straight` (default) | `turn_slight_left` | 신규 매핑 |
| type 20 (ExitRight) | `straight` (default) | `turn_right_rounded` | 신규 매핑 |
| type 21 (ExitLeft) | `straight` (default) | `turn_left_rounded` | 신규 매핑 |
| type 22 (StayStraight) | `straight` (default) | `straight_rounded` (명시) | 신규 매핑 |
| type 23 (StayRight) | `straight` (default) | `turn_slight_right` | 신규 매핑 |
| type 24 (StayLeft) | `straight` (default) | `turn_slight_left` | 신규 매핑 |
| type 25 (Merge) | `turn_right_rounded` ❌ | `straight_rounded` | 합류=직진 계열 |
| type 26 (RoundaboutEnter) | `turn_left_rounded` ❌ | `turn_right_rounded` | 한국 우측통행 회전교차로 |
| type 27 (RoundaboutExit) | `straight` (default) | `turn_right_rounded` | 신규 매핑 |

**`_labelForType`:**

| 변경 | 이전 | 이후 |
|------|------|------|
| type 17 | `'진출로 직진'` | `'램프 직진'` |
| type 18 | `'직진'` (default) ❌ | `'램프 우측'` |
| type 19 | `'직진'` (default) | `'램프 좌측'` |
| type 20 | `'직진'` (default) | `'우측 출구'` |
| type 21 | `'직진'` (default) | `'좌측 출구'` |
| type 22 | `'직진'` (default) | `'직진'` (case 8과 공유) |
| type 23 | `'직진'` (default) | `'우측 유지'` |
| type 24 | `'직진'` (default) | `'좌측 유지'` |
| type 25 | `'진출로 우측'` ❌ | `'합류'` |
| type 26 | `'진출로 좌측'` ❌ | `'회전교차로 진입'` |
| type 27 | `'우측 출구'` ❌ | `'회전교차로 진출'` |
| type 28 | `'좌측 출구'` ❌ | `'도선 탑승'` |
| type 29 | 없음 | `'도선 하차'` |

**flutter analyze:** No issues (error 0) ✓  
**flutter build apk --debug:** ✓ Built

---

## [T2] 카드 거리 실시간 remaining 바인딩

**커밋:** 0195e6d | **태그:** guidance-T2

**변경 파일:** `lib/features/navigation/presentation/nav_screen.dart`

### 변경 내용

1. **상태 변수 추가** (`:110` 부근):
   ```dart
   double _cardRemainingM = 0.0;
   ```

2. **`_applyRouteGuidance` 리셋** (라우트 로드/재탐색 시):
   ```dart
   _cardRemainingM = 0.0;
   ```

3. **`_updateStepByDistance` 갱신** (GPS 틱마다):
   ```dart
   setState(() => _cardRemainingM = remaining);
   ```

4. **카드 렌더 교체** (`:955` 부근):
   - 이전: `step.dist` (정적 Valhalla 문자열)
   - 이후: `_cardRemainingM > 0 ? _TurnStep._formatDist(_cardRemainingM / 1000.0) : step.dist`
   - 폴백: GPS fix 이전에는 `step.dist` (Valhalla 정적 거리) 표시

**flutter analyze:** No issues ✓  
**flutter build apk --debug:** ✓ Built

---

## [T3] 카드 타깃 off-by-one 교정

**커밋:** 2048379 | **태그:** guidance-T3

**변경 파일:** `lib/features/navigation/presentation/nav_screen.dart`

### 충돌 사전 점검 결과

| 점검 항목 | 판정 | 근거 |
|-----------|------|------|
| `_announceStep(_stepIdx)` TTS | 충돌 없음 | TTS = 현재 행동 발화, 카드 = 다음 행동 표시 → 자연 분리 |
| 400m 예비발화 `_steps[_stepIdx+1]` (:414) | 충돌 없음 | 이미 upcoming 기반 → T3 카드와 일관 |
| `_stepIdx++` 50m 진행 | 충돌 없음 | remaining은 현재 세그먼트 기준 → 카운트다운 후 step 전환 = 정상 |
| 수동탭 가드 `_stepIdx < _steps.length - 1` (:908) | 충돌 없음 | 마지막 step에서 탭 불가 → upcoming 경계 안전 |
| 진행바 `(_stepIdx + 1) / _steps.length` (:932) | 충돌 없음 | `_stepIdx` 직접 참조, 영향 없음 |

### 변경 내용

`build()` 내에 `upcoming` 로컬 변수 추가:
```dart
final upcoming = _stepIdx + 1 < _steps.length ? _steps[_stepIdx + 1] : step;
```

- 카드 아이콘: `step.icon` → `upcoming.icon`
- 카드 레이블: `step.label` → `upcoming.label`
- 거리 폴백: `step.dist` 유지 (현재 세그먼트 총 거리 = 다음 회전까지 거리 추정)

**flutter analyze:** No issues ✓  
**flutter build apk --debug:** ✓ Built

---

## HALT 발생 태스크

없음. T1~T3 전부 PASS.

---

## 커밋 요약

```
2048379  fix(nav): card shows upcoming maneuver (off-by-one)     ← guidance-T3
0195e6d  fix(nav): bind maneuver card distance to live remaining  ← guidance-T2
65528b7  fix(nav): correct maneuver type icon/label mapping       ← guidance-T1
80dd854  (guidance-baseline)
```

---

## ★ 복귀 후 폰 검증 체크리스트 (주행)

adb install build/app/outputs/flutter-apk/app-debug.apk 후 실제 주행 테스트.

```
[ ] ① 회전 방향 일치
      - 좌회전(type15), 우회전(type10) 화살표·레이블이 실제 교차로 방향과 일치
      - 램프 우측(type18) 화살표가 우측(←수정 핵심)
      - 합류(type25) 화살표가 직진 계열
      - 회전교차로(type26/27) 레이블이 '회전교차로 진입/진출'

[ ] ② 거리 카운트다운
      - 주행 중 카드 상단 거리가 줄어드는가 (100m 단위)
      - 재탐색 후에도 갱신되는가

[ ] ③ 카드 = "다음 회전" 표시
      - 직진 구간 주행 중: 카드가 "우회전 Xm" (다가오는 회전)을 표시
      - TTS와 카드 텍스트가 다른 step을 가리켜도 논리 맞는지 확인
        (TTS: 지금 실행할 행동 / 카드: 다음에 올 행동)

[ ] ④ 마지막 step 표시
      - 목적지 30m 이내 접근 시 카드가 '목적지 도착' 레이블·flag 아이콘으로 유지
      - 인덱스 초과 크래시 없음

[ ] ⑤ 재탐색 후 정상
      - 이탈 → 재탐색 후 카드 거리·방향 모두 새 경로 기준으로 갱신

[ ] ⑥ logcat 무결성
      adb logcat | grep -iE "reroute|maneuver|TTS|exception|error"
      - 새 exception 없음
      - _updateStepByDistance 관련 로그 정상
```

> **검증 통과(①~⑥ 전부 체크)한 후에만 feat/guidance-fix → main 머지할 것.**
> 머지 방법: `git checkout main && git merge --no-ff feat/guidance-fix -m "merge: guidance fix (T1-T3)"`
