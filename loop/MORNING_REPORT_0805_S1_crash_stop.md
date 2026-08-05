# REPORT — S1 · 백화·크래시 완전 정지 (2026-08-05)

- 브랜치 `verify/ride-0711` · 커밋 `87c232e`(구현) + `aeaf227`(지시서)
- 지시서: [HANDOFF_0805_S1_crash_stop.md](HANDOFF_0805_S1_crash_stop.md)
- 대장: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) S1
- 근거: [RECON_0805_testride0802_master_plan.md](RECON_0805_testride0802_master_plan.md) §2

**목표 달성 판정:** 원래 목표: 실주행 800km에서 56,789건 터진
`Invalid argument(s): 0.0` 예외와 그로 인한 화면 백화를 완전히 멎게 한다.
**Goal: 백화·크래시 완전 정지 / Met: yes — 코드·테스트 완료, 실기기 육안 검증만 마스터 대기**

---

## 1. 한 일

### 주범 수정 — `DaylightBar`

`num.clamp(lower, upper)`는 `upper < lower`면 `ArgumentError(lower)`를 던진다.
`lower`가 `0.0`이라 메시지가 정확히 `Invalid argument(s): 0.0` — 로그 문자열과 일치.
`daylight_bar.dart`의 `handleY.clamp(0.0, totalH - 24)`가 그 자리였다. 위젯 고정
크롬이 상하 94px를 먹으므로 코스시트가 열리거나 화면이 작으면 게이지에 24px가 안 남는다.
`build()` 안에서 던지니 Flutter가 서브트리를 `ErrorWidget`으로 갈아끼웠고,
릴리스 기본 빌더의 회색/흰 박스가 **마스터가 본 "백화"의 정체**다.

2중으로 막았다.

- **위젯 전체**: 가용높이 `<72` → 렌더 안 함 / `72~118` → 축약형(시간 라벨 생략) /
  `>=118` → 기존 전체 렌더
- **게이지 내부**: `totalH`가 비유한·`<=0`이면 차단, `<24`면 핸들 아이콘 생략(바만 렌더),
  `top`은 안 던지는 `clampSafe`

### `clamp` 전수 감사 — 목록의 절반은 이미 안전했다

체크리스트가 "위험"으로 적어둔 12곳을 **현재 HEAD 코드로 하나씩 다시 확인**했다.

| | 결과 |
|---|---|
| 실제 수정 | `daylight_bar`, `route_progress_provider:320`, `nav_screen:563`, `nav_screen:3031`, `main_map_screen` 2곳, `waypoint_management_sheet:49` |
| **이미 안전 — 안 건드림** | `routing_service:935/941`, `nav_screen:850/1700/1785/1800`, `main_map_screen:1649`, `user_profile:26`, `route_progress_provider:374/378` |

- **`route_progress_provider:374/378`은 지시서가 틀렸다.** 함수 최상단에 이미
  `if (_cumFromStartM.isEmpty || _zones.isEmpty) return null;`이 있다(2026-07-27부터).
  RECON이 그 함수의 최신 상태를 놓쳤고, 코더가 코드를 확인하고 수정을 거부한 게 옳다.
- 반대로 **체크리스트에 없던 `main_map_screen.dart:1623`이 실제로 위험**했다.
  바로 다음 줄이 `selIdx < _fetchedRoutes.length`를 검사하고 있었으니 작성자도 빈 경우를
  알았는데, 그 검사에 닿기 전에 clamp가 먼저 터지는 구조였다.
- **리스트 인덱싱이 뒤따르는 자리엔 `clampSafe`를 쓰지 않았다.** 안 던지는 대신
  `list[0]`이 `RangeError`로 터져 증상만 바뀐다. 그런 자리는 전부 빈 리스트 조기 반환.

### 배관 수정

- **릴리스 `ErrorWidget.builder`** → 투명 `SizedBox.shrink()`. `kReleaseMode`일 때만이고
  디버그는 기본 빨간 박스를 유지했다 — 개발 중 에러를 숨기면 안 된다.
- **크래시 로그 폭주 차단**(지시서에 넣은 추가 항목). 동일 시그니처는 최초 1회 +
  이후 60초 1회만 발행하고 억제분은 `suppressed=N`으로 병기. 맵 상한 50 LRU.
  RECON §2-3이 짚었듯 초당 2~3회의 스택트레이스 + **디스크 append** + **Crashlytics 업로드**가
  발열·배터리의 직접 원인이었다(4시간에 36,680회). `FileLogger`가 `debugPrint`를 후킹하는
  구조라 이 한 지점을 막으면 디스크·네트워크가 함께 멎는다.
- 참조 0건인 `lib/widgets/daylight_bar.dart` re-export shim 삭제.

---

## 2. 검증

- `flutter analyze` — **이슈 0**
- `flutter test` — **359건 전건 통과** (기존 314 + 신규 45). 기존 테스트 수정 없음
- `daylight_bar_test.dart` — 높이 `[0,10,24,60,71,72,90,117,118,120,285,300,800]` ×
  progress `[0.0,0.5,1.0]` 전 조합 `takeException()` isNull.
  **285px = 플립7 커버화면 논리높이 근사 → 확보 불가한 그 기기 없이 결정론적으로 커버**.
  71/72·117/118은 분기 임계값 바로 양옆이라 임계값을 옮기는 회귀가 나면 여기서 먼저 걸린다
- `route_progress_empty_route_test.dart` — 빈 `_pts` + 비어있지 않은 `maneuvers`
  (재탐색 중 경로 일시 소멸) 케이스. 감사자가 수정 전 코드에서 실제로 던졌음을 역추적 확인
- **code-auditor 1차 PASS.** 감사자가 `analyze`·`test`를 직접 재실행했고,
  축약형 임계값 72px 산수(10+18+8+8+18+10)를 손으로 검증했다

---

## 3. 판단이 필요했던 지점

**축약형 임계값 60 → 72.** 지시서는 60px를 제시했는데, 라벨 없는 축약형이라도 고정 크롬이
정확히 72px를 먹는다. 60으로 두면 `ArgumentError`는 안 나지만 `RenderFlex overflow`라는
**다른 예외**가 남아 "높이 60px에서 예외 없음"을 만족 못 한다. 코더가 실측으로 올렸고
감사에서 산수까지 확인됐다. 배치 자체는 안 건드린 순수 임계값 보정이다.

**감사자 지적 하나를 직접 보강했다.** 임계값 72가 정작 테스트 높이 목록에 없었다.
71/72·117/118을 추가해 경계값을 고정했다(테스트 9건 증가).

---

## 4. 남은 것 — 마스터 몫

**실기기 육안 검증 2건.** 코드로는 다 막았지만 실렌더는 못 봤다.

1. A34에서 `adb shell wm size 720x748` → 플립7 커버화면 치수 흉내 → 실렌더 확인.
   **끝나면 `adb shell wm size reset` 필수.**
2. 세로/가로 × 코스시트 열림·닫힘 × 일반/PIP/분할화면에서
   `YNAV_CRASH … Invalid argument(s): 0.0` **0건**

## 5. 기록만 남기는 것

- `tour_summary_detail_screen.dart:199` `.clamp(squareMapHeight, screenWidth * 3.0)` —
  `screenWidth < 33.3` 논리픽셀에서만 역전. 실기기 도달 불가로 보고 스코프 밖으로 뒀다.
- 크래시 억제 로직 자체엔 단위테스트가 없다(감사자 지적, 비차단). `crash_reporting.dart`가
  Firebase 초기화와 얽혀 하네스 비용이 크다. 억제 정책만 순수 클래스로 떼면 붙일 수 있다.

---

**다음:** S2(네트워크 폭주 차단) → S3(라이프사이클). S1이 크래시를 멎게 했으니
이제 S2·S3의 전력·데이터 측정이 의미를 갖는다.
