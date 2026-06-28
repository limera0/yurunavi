# REPORT_perm_halt.md — 권한 halt 수정 완료

작성일: 2026-06-27 (금 야간 세션)
브랜치: `feat/layer0-navstate` (main 미머지 — first-run 폰 검증 전)

---

## 결과 요약

RECON_perm_halt.md §E·§F 전항목 구현 완료. 3커밋 각 flutter analyze 새 에러 0.

---

## 커밋 목록

| # | SHA | 메시지 |
|---|-----|--------|
| C1 | `16988f7` | fix(map): stop stream self-requesting location permission |
| C2 | `7a8dcc4` | fix(nav): nav_screen checks permission, does not request |
| C3 | `c919712` | fix(nav): guard _seed against pre-grant location access |

---

## 변경 상세

### C1 — `lib/features/map/providers/map_providers.dart`

- **제거**: `if (permission == LocationPermission.denied) { permission = await Geolocator.requestPermission(); }` (3줄)
- **변경**: `var permission` → `final permission`
- 결과: `locationStreamProvider`는 checkPermission만 수행. 권한 없으면 조용히 빈 스트림 반환.

### C2 — `lib/features/navigation/presentation/nav_screen.dart`

- **제거**: `if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();` (1줄)
- **변경**: `var perm` → `final perm`, 조건문 중괄호 추가 (linter `curly_braces_in_flow_control_structures`)
- 결과: `_startLocation()`은 check 후 denied/deniedForever이면 return. 자가 요청 없음.

### C3 — `lib/features/navigation/providers/nav_state_provider.dart`

- **추가**: `checkPermission` 게이팅 — whileInUse/always 아니면 즉시 return
- **추가**: 전체 `_seed()` body를 `try { } catch (_) { return; }`으로 감쌈
- 결과: `build()`에서 동기 호출되는 `_seed()`가 권한 부여 전 `getLastKnownPosition()`을 호출하지 않음. 예외 발생 시 무해하게 흡수.

---

## 정적 검증

```
flutter analyze (전체 프로젝트)
→ info × 2  (settings_screen.dart Radio deprecated — 기존, 무관)
→ 새 error/warning: 0
```

---

## 수정 후 권한 요청 주체 현황

| 파일 | 호출 | 상태 |
|------|------|------|
| splash | `Permission.location.request()` | **유지 (단일 주체)** |
| map_providers | `Geolocator.checkPermission()` | 유지 (request 제거됨) |
| nav_screen | `Geolocator.checkPermission()` | 유지 (request 제거됨) |
| nav_state_provider | `Geolocator.checkPermission()` + try/catch | 추가 게이팅 완료 |

OS 다이얼로그 발생 주체: **splash 단일**. 두 라이브러리 동시 요청 소멸.

---

## 미완 / 다음 단계

- **폰 first-run 검증 필요** (T3): uninstall → install → 실행 → 위치 "허용" → halt 없이 알림 권한으로 진행 확인
- **main 머지 금지**: 콜드스타트 first-run 검증 전까지 브랜치 유지
- §G 검증 항목 (1~4번)은 폰 검증 세션에서 수행

---

## 주의

- 이번 변경은 운동학 로직 무변경 — Layer 0 속도계/카메라 동작 회귀 없음
- `_seed()` 실패는 무해: 첫 GPS fix가 곧 state를 채움 (`_onFix` 정상 동작)
