GOAL: 유루나비의 "다른 앱 위에 표시" 플로팅 오버레이를 네이버지도 스타일 기준으로
재설계한다 — 더 크게, 현재+다음 안내 2줄 동시 표시, 드래그로 위치 이동 가능하게.

- 작성 2026-08-14 · 마스터 확인(대화, 2026-08-14 저녁)
- 근거: [RECON_0814_testride_issues.md](RECON_0814_testride_issues.md) §4,
  `loop/testride_result/Screenshot_20260814_182523_Yurunavi.jpg`(참고 기준 스크린샷 —
  **유루나비가 백그라운드 상태일 때 전경 네이버지도 위에 뜬 네이버지도 자신의 플로팅 위젯**.
  나머지 UI(속도계·컴퍼스 등)는 네이버지도 자체 화면이니 오인하지 말 것)
- ⚠️ **`FloatingOverlayService.kt`를 공유하는
  [HANDOFF_0814_S20_nav_end_blackscreen.md](HANDOFF_0814_S20_nav_end_blackscreen.md)(내비 종료 후
  블랙스크린)가 먼저 큐에 잡혀있다. 그 세션이 이 서비스의 show/hide 생명주기를 먼저 손볼 가능성이
  높으니, 이 작업은 S20 완료 후 최신 코드 기준으로 착수할 것** — 동시에 건드리면 두 변경이
  뒤섞여 회귀 원인 추적이 어려워진다.

## 참고 스크린샷 관찰 (네이버지도 플로팅 위젯 — 모범사례)

- 검은 반투명 라운드 박스, 화면 폭의 약 1/3~40% 차지 — 현재 유루나비 72dp보다 훨씬 큼
- **2줄 구성**: 위 = 현재 안내(우회전 아이콘 + "843m"), 아래 = 다음 안내(좌회전 아이콘 + "169m")
  — 둘 다 흰색 아이콘 + 굵은 흰색 숫자
- 위치가 화면 중앙 부근 — 코너 고정이 아니라 사용자가 드래그해서 옮겨놓은 위치로 추정(또는
  최소한 코너 고정보다 유연한 배치)

## 현재 코드 상태

- [FloatingOverlayService.kt](android/app/src/main/kotlin/com/westinx/yurunavi/FloatingOverlayService.kt) —
  72dp 정사각형, `gravity = BOTTOM|END` 고정(x=16dp y=80dp), `FLAG_NOT_FOCUSABLE`만 설정(드래그
  리스너 없음), `showOverlay()`/`updateOverlay()`가 아이콘 1개(`nav_icon`)+텍스트 1줄(`nav_dist`)만
  갱신.
- [floating_nav.xml](android/app/src/main/res/layout/floating_nav.xml) — `LinearLayout` 72×72dp,
  `ImageView`(38dp) + `TextView`(11sp) 세로 배치 1세트뿐.
- [nav_floating_overlay.dart](lib/services/nav_floating_overlay.dart) — `GuidanceInfo` typedef가
  `({iconType, distanceText})` 단일 세트만 담음. `show`/`update`가 MethodChannel로 이 한 세트만
  전달.
- [nav_screen.dart:521-532](lib/features/navigation/presentation/nav_screen.dart#L521-L532)
  `_currentGuidance()` — 오버레이용 페이로드를 만드는 지점. 현재는 `_steps[_stepIdx]`(현재 안내)만
  사용.
- **다음 안내 데이터는 이미 존재함** — [nav_screen.dart:2016](lib/features/navigation/presentation/nav_screen.dart#L2016)
  `final upcoming = _stepIdx + 1 < _steps.length ? _steps[_stepIdx + 1] : step;`가 메인 UI의
  "다음 [도로명]" 카드에 쓰는 값과 동일한 소스 — 새로 계산할 필요 없이 `_currentGuidance()`에
  같은 로직만 추가하면 됨.

## 청크별 구현 (제안)

### 청크 1 — 2줄 레이아웃 + 크기 확대

- `floating_nav.xml`: 현재 1세트(아이콘+텍스트) 구조를 세로로 2세트 반복하는 레이아웃으로 교체.
  전체 크기는 72dp 고정에서 `wrap_content` 기반(내용에 맞춰 커지도록)으로 전환하거나, 참고
  스크린샷 비율(폭 화면의 30~40%)에 맞는 고정폭으로 변경 — 마스터 확인 없이 정확한 px값을
  임의로 고정하지 말고, 합리적인 기본값(예: 폭 140dp)으로 먼저 구현 후 실기기 검증에서 조정.
- `FloatingOverlayService.kt`의 `showOverlay`/`updateOverlay`: `EXTRA_ICON`/`EXTRA_TEXT`를
  현재용/다음용 2세트로 확장(`EXTRA_ICON2`/`EXTRA_TEXT2` 등). 다음 안내가 없으면(마지막 스텝)
  2번째 줄 `View.GONE` 처리.
- `sizePx` 고정 계산(72dp 정사각형 전제)을 새 레이아웃 크기에 맞게 `wrap_content` 또는 새
  치수로 교체 — `WindowManager.LayoutParams` width/height 값도 함께 수정.

### 청크 2 — 드래그 이동 + 위치 기억

- `showOverlay()`의 `view.setOnClickListener`(탭=앱 복귀)와 별도로 `setOnTouchListener` 추가 —
  `ACTION_DOWN`에서 초기 좌표 기록, `ACTION_MOVE`에서 `params.x`/`params.y` 갱신 후
  `windowManager.updateViewLayout()`, `ACTION_UP`에서 이동량이 임계값(예: 10dp) 미만이면 탭으로
  간주해 기존 클릭 동작(앱 복귀) 유지 — 드래그와 탭 제스처가 서로 삼키지 않게 주의.
- 마지막 위치를 `SharedPreferences`(Kotlin `getSharedPreferences`)에 저장, `showOverlay()` 시작
  시 저장된 좌표가 있으면 기본 좌표 대신 사용 — 매번 첫 위치로 리셋되지 않게.

### 청크 3 — Dart 쪽 다음 안내 데이터 전달

- `GuidanceInfo` typedef를 `({iconType, distanceText, nextIconType, nextDistanceText})`로 확장
  (nullable 허용 — 다음 안내 없을 때).
- `nav_screen.dart`의 `_currentGuidance()`에 `upcoming` 기반 두 번째 세트 계산 추가(2016행 로직과
  동일 패턴 재사용).
- `NavFloatingOverlay.show`/`.update`의 MethodChannel 인자에 새 필드 추가.

## 코딩 지시사항

- flutter-coder(Dart)와 필요시 직접 Kotlin 수정 — 이 서비스는 순수 Android 네이티브라 별도
  rust-coder 불필요.
- **정확한 크기/색상/폰트 px 값은 참고 스크린샷에서 눈대중으로 뽑은 추정치다** — 구현 후 반드시
  실기기 스크린샷으로 마스터에게 비교 확인받을 것. 첫 시도에 완벽히 맞추려 하지 말고, 합리적
  기본값 → 실기기 확인 → 미세조정 순서로 진행.
- 드래그 구현 시 `FLAG_NOT_FOCUSABLE`는 유지(키보드 포커스 안 뺏어야 함) — 터치 이벤트 자체는
  이미 뷰 자체 클릭 리스너로 받고 있으므로 별도 플래그 변경 불필요.
- S20(블랙스크린) 수정이 먼저 들어갔다면 `showOverlay`/`hideOverlay`의 상태 추적 로직이 바뀌어
  있을 수 있음 — 최신 커밋 기준으로 작업 시작 전 `git log -- android/app/src/main/kotlin/com/westinx/yurunavi/FloatingOverlayService.kt`로 확인.

## 검증 체크리스트

- [ ] 오버레이가 2줄(현재+다음 안내)로 표시되는지, 다음 안내 없을 때(도착 직전) 1줄로 정상
      축소되는지
- [ ] 크기가 참고 스크린샷과 비슷한 비율인지(실기기 스크린샷으로 마스터 확인)
- [ ] 드래그로 화면 어디든 이동 가능한지, 화면 밖으로 나가지 않는지(경계 clamp)
- [ ] 드래그 후 앱을 다시 백그라운드로 보내면 마지막 위치에서 다시 뜨는지
- [ ] 짧은 탭(드래그 아님)은 여전히 앱 복귀로 동작하는지 — 드래그 제스처 추가로 이 기존 기능이
      깨지지 않았는지 최우선 확인
- [ ] `VERIFY_0806...md` §2(정상 백그라운드 전환) 기존 통과 시나리오 재확인 — 회귀 없음
