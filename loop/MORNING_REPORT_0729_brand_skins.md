# MORNING_REPORT — 브랜드 방향 확정 + 스킨 3종 구현 (2026-07-29)

**목표 달성 판정:** 원래 목표: 로드맵 8번(브랜드 방향성 확정) — Claude가 방향 2~3개 제안,
사용자 결정, 필요 시 구현까지 / 달성: 예 — 방향 3안 제안 → 사용자가 3안 전부 채택(A 기본
+ B/C 선택형) → 무료 스킨 3종으로 구현 완료, flutter analyze/test PASS, code-auditor PASS.
단, 앱 전역 리스킨(ThemeData)까지는 의도적으로 범위 밖(아래 특이사항 참고).

---

## 오늘 한 일 요약

1. 사용자가 채팅에 재입력한 브랜드 아이덴티티 질문지 답변을 바탕으로 방향 3안을 제안
   (아티팩트: 색상 팔레트 + 홈 화면 목업 비교).
2. 사용자 결정: **A(유루캠 무드)를 기본, B(레트로 모터링)·C(동네 라이딩 메이트)도
   폐기하지 않고 설정 화면 선택형 무료 스킨**으로 채택. 향후 개성 강화 스킨은 유료
   예정("한국적 감성"은 한국 전통 모티프가 아니라 한/일 vs 서양 디자인 감각 구도로
   확정).
3. `loop/HANDOFF_0729_brand_skins.md` 작성 → flutter-coder 위임 → code-auditor 검수(PASS).

## 커밋

```
4dacce4  docs(roadmap): 8번 브랜드 방향성 확정 — A/B/C 무료 스킨 3종 채택
df2ef1f  feat(skin): 브랜드 스킨 3종(A유루캠/B레트로/C커브) 구현, 설정 화면 선택 UI 추가
```

## 구현 상세

- `SkinColors`에 `courseLineColor`(3-way 경로색: 시골길/지방도/국도) 필드 신설.
- `lib/core/skin/skins/{yurucam,retro_motoring,cub_buddy}_skin.dart` 3종 신규,
  hex 값은 `HANDOFF_0729_brand_skins.md` 스펙과 code-auditor가 필드 단위로 대조 확인.
- 기본 스킨을 `YuruCamSkin`(A)으로 교체, `SharedPreferences`(`selected_skin_id_v1`)로
  선택 영속화.
- 레거시 전역 `courseLineColor` 상수를 직접 참조하던 4개 소비처
  (`main_map_screen.dart` ×2, `nav_screen.dart` ×2, `course_sheet.dart`,
  `tour_summary_detail_screen.dart`)를 활성 스킨 참조로 마이그레이션 — `course_sheet.dart`는
  `static final`(최초 빌드 시 색이 고정되던 버그)을 `build()`-로컬로 바꿔서 스킨 전환이
  실제로 반영되게 수정됨 (감사 중 발견된 부수적 정합성 개선).
- 설정 화면에 "스킨" 섹션 추가(브랜드색 스와치 + 이름 + 체크), 탭하면 즉시 적용.
- 실기기(`RZ8RC1N3V9W`)에서 스킨 전환 → 재시작 후에도 유지 확인.

## 검증 방법

```
git show 4dacce4  ← 로드맵 결정사항 + HANDOFF
git show df2ef1f  ← 스킨 구현
```

앱 빌드 후:
1. 최초 실행 시 설정 → 스킨에서 "유루캠 무드"가 체크된 상태인지
2. B/C로 전환 → 설정 화면 스와치 즉시 변경, 앱 재시작 후에도 유지되는지
3. 경로 있는 상태로 코스 선택 화면(시골길/지방도/국도)에서 스킨별 경로색이 다른지

## 특이사항 — 다음 세션 참고

- **범위 밖으로 남겨둔 것 (의도적, HANDOFF에 명시)**: `AppSkin.toThemeData()`가 아직
  정적 `AppTheme.light`를 반환 — Scaffold 배경/AppBar/버튼 등 앱 전역 Material 크롬은
  스킨과 무관하게 항상 기존 주황 `AppColors` 고정. **오늘 구현으로 실제로 바뀌는 건
  경로선 색(지도/내비/코스시트/투어요약) + 설정 화면 자체 스와치뿐**, 앱 전체가 확
  달라지는 "전면 리스킨"은 아님. 이건 로드맵 11번(하드코딩 스타일 → 토큰 기반 전면
  리팩터, 현재 PARTIAL) Phase 5 이후 몫으로 남아 있음 — 사용자가 "스킨 골랐는데 앱이
  안 바뀐다"고 느낄 수 있으니 다음에 이 격차를 메울지 결정 필요.
- 안전 경고색(`structureAlert`/`curveAlert`, 후면단속카메라·커브 경고)은 3개 스킨
  전부 고정값 — 의도적 결정(가독성/일관성 우선, `feedback_safety_priority` 원칙).
- 오늘 작업 범위 외 파일(`lib/core/theme/palette.dart`, `app_theme_selector.dart`)
  변경 없음 — 별도의 미사용 스켈레톤이라 혼동하지 않도록 HANDOFF에 명시해뒀음.
- 9번(앱 아이콘)은 8번 완료로 착수 가능 상태.
