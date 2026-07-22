# REPORT: feat/map-language → main 머지
작성일: 2026-06-14 | 머지 커밋: `082d6e5`

---

## 머지 정보

| 항목 | 내용 |
|---|---|
| 머지 커밋 해시 | `082d6e5` |
| 머지 전략 | `--no-ff` (명시적 머지 커밋 생성) |
| 충돌 | 없음 |
| 포함된 브랜치 커밋 수 | 15개 |

## 포함된 커밋 목록 (feat/map-language)

| 해시 | 메시지 |
|---|---|
| `7f95dac` | fix(map): re-add location/dest/waypoint markers after style re-injection |
| `d495f6f` | checkpoint: before location-dot regression fix |
| `70e29e1` | feat(nav): apply map language selection to nav_screen |
| `e3e43ec` | refactor(map): migrate main_map_screen to mapLanguageProvider, remove debug toggle |
| `cd549d5` | feat(settings): wire settings icon to SettingsScreen |
| `b3b95a8` | feat(settings): add map label language selector (KO/EN) |
| `3a4ff83` | feat(settings): add SettingsScreen shell with profile link |
| `c33cfd7` | feat(settings): add mapLanguageProvider with persistence |
| `aa7fd46` | feat(settings): add LanguageService for map language persistence |
| `e344169` | checkpoint: before settings phase1 |
| `50a619c` | refactor(map): switch language mechanism to style re-injection |
| `e4bfbba` | feat(map): add applyMapLanguageToStyle (single-language style transform) |
| `e005079` | checkpoint: before plan-B style re-injection |
| `f111064` | spike(map): runtime language toggle via setLayerProperties |
| `fcc4031` | feat(map): add MapLanguage enum |

## flutter analyze (머지 후 main)

```
error 0, warning 0
info 2개: settings_screen.dart:71,73 Radio.groupValue / Radio.onChanged deprecated
  (Flutter 3.44 도입 예정 RadioGroup API; 빌드·동작 무관)
```

## push 결과

```
To https://github.com/limera0/yurunavi.git
   6646866..082d6e5  main -> main
```

push 완료.

---

## 이번 할일 종료 범위 요약

| 기능 | 상태 |
|---|---|
| MapLanguage enum + style transform | ✅ main 반영 |
| LanguageService (SharedPreferences 영속화) | ✅ main 반영 |
| mapLanguageProvider (AsyncNotifierProvider) | ✅ main 반영 |
| SettingsScreen 셸 + 언어 라디오 + 프로필 링크 | ✅ main 반영 |
| main_map_screen 언어 프로바이더 연결 | ✅ main 반영 |
| nav_screen 언어 프로바이더 연결 | ✅ main 반영 |
| 현위치 초록점 스타일 재주입 회귀 수정 | ✅ main 반영 |
