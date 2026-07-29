GOAL: 다음 세션 착수 후보 정리 — 9번(앱 아이콘) 또는 11번(하드코딩 스타일 전면
리팩터, Phase 5 잔여분) 중 하나를 골라 진행

이 파일을 읽는 Claude는 아래 두 후보 중 마스터가 고른 쪽부터 시작한다. 스코프가
둘 다로 넓어질 것 같으면(예: 아이콘 확정 후 곧바로 리팩터까지) 반드시 각각 별도
체크포인트/커밋으로 나눠서 진행할 것 — 한 세션에 두 모듈 동시 진행 금지
(CLAUDE.md 하드룰).

---

## 이번 세션(2026-07-29) 요약

로드맵 8번(브랜드 방향성 확정)을 마무리했다.

1. 사용자가 채팅에 재입력한 브랜드 아이덴티티 질문지 답변 → Claude가 방향 3안(A/B/C)
   제안(아티팩트로 색상+홈화면 목업 비교).
2. 마스터 결정: A(유루캠 무드)를 기본, B(레트로 모터링)·C(동네 라이딩 메이트)도
   폐기 없이 **3안 전부를 설정 화면 선택형 무료 스킨**으로. 향후 개성 강화 스킨은
   유료 예정. "한국적 감성" = 한국 전통 모티프가 아니라 **한/일 vs 서양(유럽·미국)
   디자인 감각** 구도로 확정.
3. `lib/core/skin/`에 스킨 3종 구현 완료(flutter-coder → code-auditor PASS).
   기본 스킨 교체, `SkinColors.courseLineColor` 신설, 레거시 경로색 4개 소비처
   마이그레이션, 설정 화면 "스킨" 섹션, SharedPreferences 영속화.

**커밋**: `4dacce4`(로드맵 결정) → `df2ef1f`(스킨 구현) → `ed78cc8`(완료 반영).
**상세**: `loop/HANDOFF_0729_brand_skins.md`(지시서) / `loop/MORNING_REPORT_0729_brand_skins.md`(결과).

### 다음 세션이 알아야 할 격차 (중요)

`AppSkin.toThemeData()`가 아직 정적 `AppTheme.light`를 반환한다. 즉 **스킨을 바꿔도
Scaffold 배경/AppBar/버튼 등 앱 전역 크롬은 안 바뀐다** — 오늘 실제로 스킨을 타는
건 경로선 색(지도/내비/코스시트/투어요약) + 설정 화면 자체 스와치뿐. 11번을 잡으면
이 격차를 메울지가 핵심 결정 포인트다.

또한 code-auditor는 코드 추적으로만 확인했고, **실제 경로 계산 중 스킨별 3색
(시골길/지방도/국도)이 지도에 실제로 다르게 그려지는지는 실기기에서 목적지까지
찍어보는 시각 검증이 아직 없다** — 9번/11번 어느 쪽을 잡든 시간 나면 한 번 확인
권장.

---

## 후보 A — 9번: 앱 아이콘 확정

`RELEASE_ROADMAP.md:245` 근방. 8번 완료로 착수 가능 상태.

- 기준 팔레트: A안(유루캠 무드) — 코랄 `#E2896F` + 모스그린 `#8CA283`
  (`lib/core/skin/skins/yurucam_skin.dart` 참고).
- "한국적 감성" = 한/일 vs 서양 감각 축을 아이콘 모티프 선정에도 적용할 것
  (예: 서양풍 엠블럼/문장(紋章) 스타일보다는 일본 서브컬처·MUJI 계열의 단순한
  선/도형 쪽이 방향에 맞음 — 확신 없으면 마스터에게 시안 2~3개 먼저 제안).
- B/C 스킨도 이미 존재하므로, 아이콘을 스킨별로 다르게 가져갈지(스킨 = 앱 전체
  룩 체인지, 아이콘도 스킨 따라 바뀌는 게 자연스러울 수 있음) 아니면 아이콘은
  하나로 고정할지 — 이건 마스터에게 먼저 확인 필요한 지점, 임의로 정하지 말 것.

## 후보 B — 11번: 하드코딩 스타일 → 토큰 기반 전면 리팩터 (Phase 5 잔여)

`RELEASE_ROADMAP.md:254` 근방. Phase 0~4 완료(2026-07-22), Phase 5(스킨 목록 UI)도
오늘 완료. **남은 것**:

1. `toThemeData()` 정적 반환 격차 메우기 — 스킨별 `SkinColors`를 실제
   `ThemeData`(ColorScheme, AppBarTheme 등)로 변환해서 앱 전역이 스킨을 타게 할지
   결정. (스코프가 커질 수 있음 — `lib/main.dart`가 `riderMode`/`isNight`으로만
   테마를 고르고 있어서, skin 축까지 더하면 3중 분기가 됨. 어떻게 합성할지 설계
   먼저 필요.)
2. 인라인 `TextStyle(...)` 116건(15개 파일) — 스킨 타이포그래피 토큰으로 정리.
3. 실제 수익화(구매/잠금) 로직은 **아직 만들지 말 것** — 프리미엄 스킨 자체가
   없어서 스코프 밖(`AppSkin.isPremium` 필드만 존재).

---

## 세션 시작 시 공통 확인사항

- `git status`로 미커밋 파일 확인 — 이번 세션 기준 `assets/data/Opinet_API_Free.pdf`,
  `assets/data/cctv.json`, `assets/images/speedcam*.webp`,
  `scripts/scrape_rear_camera_notices.py`,
  `loop/HANDOFF_0728_multi_stop_ux.md`, `loop/MORNING_REPORT_0728_multi_stop_ux.md`,
  `loop/Screenshot_20260726_124125.jpg` 등이 미커밋 상태로 남아 있음 — **이번
  세션(8번/스킨) 작업물이 아니므로 손대지 말 것**, 다른 작업 스트림 소유.
- `lib/core/theme/palette.dart`/`app_theme_selector.dart`는 이번 스킨 작업과
  무관한 별도의 미사용 스켈레톤 — 11번 진행 시 혼동 주의(자세한 건
  `loop/HANDOFF_0729_brand_skins.md`의 "아키텍처 주의" 절 참고).
