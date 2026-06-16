# REPORT: 설정 페이지 Phase 1 구현
작성일: 2026-06-14 | 브랜치: feat/map-language

---

## [0] 게이트 결과 (라인 변동 여부)

### 0-1. main_map_screen 제거/유지 대상 실제 라인 (RECON 대비)
RECON 예측과 거의 일치. 실제 기준:
| 항목 | 실제 라인 | RECON 예측 |
|---|---|---|
| `_debugLang` | :121 | :121 ✅ |
| `_applyMapLanguage` 블록 | :257-267 | :258-264 ✅ |
| 디버그 버튼 | :985-1012 | :989-1013 ✅ |
| `_rawStyle`/`_styleJson` | :122-123 | :122-123 ✅ |
| `_loadRawStyle` | :149-156 | :149-156 ✅ |
| `styleString: _styleJson!` | :796 | :796 ✅ |
| 로딩가드 | :792-794 | :792-794 ✅ |

추가 발견: `:154` `applyMapLanguageToStyle(raw, _debugLang)` 에서 `_debugLang` 참조 → `ref.read(mapLanguageProvider).value ?? MapLanguage.korean` 으로 교체.

### 0-2. AsyncNotifierProvider 패턴
`map_providers.dart:16-30` — `AsyncNotifierProvider<UserProfileNotifier, UserProfile>` 확인. 동일 형태로 `MapLanguageNotifier` 작성 완료.

### 0-3. ProfileService 패턴
`profile_service.dart:5-22` — `static const _key / load() / save()` 확인. `LanguageService` 동일 형태로 작성 완료.

### 0-4. onSettings / NavScreen push 패턴
- `onSettings: () {}` → `:896` 확인
- NavScreen push → `:677-686` `Navigator.of(context).push(MaterialPageRoute(...))` 확인

---

## 커밋 해시 7개

| # | 해시 | 메시지 |
|---|---|---|
| 체크포인트 | `e344169` | checkpoint: before settings phase1 |
| C1 | `aa7fd46` | feat(settings): add LanguageService for map language persistence |
| C2 | `c33cfd7` | feat(settings): add mapLanguageProvider with persistence |
| C3 | `3a4ff83` | feat(settings): add SettingsScreen shell with profile link |
| C4 | `b3b95a8` | feat(settings): add map label language selector (KO/EN) |
| C5 | `cd549d5` | feat(settings): wire settings icon to SettingsScreen |
| C6 | `e3e43ec` | refactor(map): migrate main_map_screen to mapLanguageProvider, remove debug toggle |
| C7 | `70e29e1` | feat(nav): apply map language selection to nav_screen |

---

## analyze / 빌드 결과

```
flutter analyze (전체 프로젝트) → error/warning 0개.
  잔여 info 2개: settings_screen.dart Radio.groupValue / Radio.onChanged deprecated
  (Flutter 3.44 도입 예정 RadioGroup API; info 레벨, 빌드 무관)

flutter build apk --debug → ✓ Built build/app/outputs/flutter-apk/app-debug.apk (215M)
```

부수 수정: `nav_screen.dart:3` `import 'dart:math' show ... max` → `max` 미사용 warning 발견·제거 (pre-existing, C7에서 함께 정리).

---

## 신규 파일 목록

| 파일 | 역할 |
|---|---|
| `lib/services/language_service.dart` | SharedPreferences 저장/로드 (`map_language_v1` 키) |
| `lib/features/settings/providers/settings_providers.dart` | `mapLanguageProvider` (AsyncNotifierProvider) |
| `lib/screens/settings_screen.dart` | 설정 화면 셸 + 언어 라디오 + 프로필 링크 |

---

## 폰 검증 절차

```
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### ① 앱 첫 실행 (기본값 = 한국어)
- 지도 라벨이 **한글 단일 표기** (영/한 병기 없음)
- 색상·halo·도로정렬 정상 확인

### ② ⚙️ 탭 → SettingsScreen
- 상단 "설정" AppBar
- "프로필 편집" ListTile 탭 → ProfileScreen 열림 → 뒤로 → SettingsScreen 복귀

### ③ "지도 표기 언어" → English 선택 → 뒤로
- **main_map_screen 지도 라벨이 로마자 단일 표기**로 변경
- 색상·halo·크기 정상 유지 (플랜 B 스타일 재주입 방식)
- 짧은 재로딩 깜빡임은 정상

### ④ 앱 완전 종료 후 재실행 (영속화 검증)
- **English 표기 유지** (`SharedPreferences map_language_v1` 키 확인)

### ⑤ 내비 화면 진입 (⑥ 선택 후)
- **nav_screen도 동일 언어** 표기로 진입
- 내비 중 색상·도로선·HUD 정상

### ⑥ 설정에서 한국어 선택
- 양쪽(main + nav) 라벨 한국어로 복귀

### ⑦ logcat
```powershell
adb logcat -d | Select-String -Pattern "MapLibre|style|exception|language"
```
- exception 없어야 통과
- style load 성공 로그 확인
