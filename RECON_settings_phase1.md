# RECON: 설정 페이지 Phase 1
작성일: 2026-06-14 | 상태: 읽기 전용 정찰 완료

---

## A. 톱니(⚙️) 버튼

### A-1. onSettings 핸들러 현황
`main_map_screen.dart:896`:
```dart
onSettings: () {},   // ← 완전한 빈 핸들러. 아무 동작 없음.
```

`_MapHeader` 위젯에 콜백으로 전달:
- `main_map_screen.dart:1040` `final VoidCallback onSettings;`
- `main_map_screen.dart:1081` `_HeaderIcon(icon: Icons.settings_outlined, onTap: onSettings)`

### A-2. 옆 버튼 화면 전환 패턴 예시 (동일 패턴으로 연결)

**onSavedCourses** → `_showPlacesSheet` (바텀시트):
```dart
// main_map_screen.dart:895
onSavedCourses: _showPlacesSheet,
```

**NavScreen 전환** (full-screen push) — `main_map_screen.dart:677`:
```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => NavScreen(...),
  ),
).then((_) { if (mounted) _clearDestination(); });
```

→ **결론**: `onSettings: () {}` 자리에 `Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen()))` 를 넣으면 됨. 패턴이 확정돼 있음.

---

## B. profile_screen.dart 현황

### B-1. 파일 경로 · 위젯 타입
- 경로: `lib/screens/profile_screen.dart`
- 타입: `ConsumerStatefulWidget` (Riverpod ref 사용)

### B-2. 현재 섹션 목록 (profile_screen.dart:78~184)
| 섹션 | 위젯/구성 | 라인 |
|---|---|---|
| 아바타 (편집 아이콘 포함) | `CircleAvatar` + `Stack` | 98 |
| 기본 정보 | `닉네임` TextField, `인스타그램` TextField | 122 |
| 내 바이크 | `_BikeCard` 리스트 + 추가/삭제/선택 | 141 |

AppBar에 `저장` TextButton 포함. 저장 시 `userProfileProvider`에 반영.

### B-3. profile_screen으로의 진입 경로
`lib/` 전체 grep 결과: **`ProfileScreen`을 push/참조하는 코드 없음.**
`profile_screen.dart` 자체 내부의 `Navigator.pop(context)` 만 존재 (다이얼로그용).
→ **profile_screen은 현재 앱 어디에서도 연결되지 않은 미아 화면.**

### B-4. 판단 근거 (결정은 마스터)
- 현재 profile_screen에는 바이크/닉네임만 있음. 지도 언어·라이더모드·알림 등 앱 설정과 성격이 다름.
- profile_screen을 `settings_screen` 안의 한 섹션("프로필") 으로 흡수하면 톱니 하나로 모두 접근 가능.
- 반대로, 설정 화면을 신설하고 "프로필 편집" 링크로 profile_screen을 별도 push하면 분리도 명확.

**1줄 권고**: 신설 `SettingsScreen`을 만들고, profile_screen은 내부 링크로 push (설정 ≠ 프로필 편집, 분리가 명확). ★마스터 결정 필요.

---

## C. 라우팅 / 화면 전환 패턴

### C-1. 라우팅 방식
`main.dart:41~57`:
```dart
return MaterialApp(
  ...
  home: const SplashScreen(),
  // routes: 없음
);
```
**named routes 미사용.** `MaterialPageRoute` 직접 push 방식.

### C-2. 새 화면 추가 표준 패턴
```dart
// 어느 위젯에서든 동일
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const SettingsScreen()),
);
```
파일 위치 관례: `lib/screens/` (profile_screen.dart 등) 또는 `lib/features/settings/presentation/`.
현재 `lib/screens/`에 5개 파일, `lib/features/` 하위 map/navigation만 존재.
→ Phase 1 스파이크라면 `lib/screens/settings_screen.dart` 가 가장 단순.

---

## D. 지도 언어 코드 현재 상태 (feat/map-language 브랜치)

### D-1. MapLanguage enum
- 파일: `lib/models/map_language.dart`
- 정의: `enum MapLanguage { korean, english }`

### D-2. applyMapLanguageToStyle 함수
- 파일: `lib/features/map/style_language_transform.dart`
- 시그니처: `String applyMapLanguageToStyle(String styleJson, MapLanguage lang)`
- 동작: 23개 라벨 레이어의 `layout.text-field`만 교체. 나머지 속성 불변.

### D-3. main_map_screen.dart 언어 관련 코드 전체 위치
| 항목 | 위치 | 비고 |
|---|---|---|
| import `style_language_transform` | `main_map_screen.dart:24` | |
| `_debugLang` 상태 변수 | `:121` | **제거 대상** (provider로 이관) |
| `_rawStyle` / `_styleJson` 상태 변수 | `:122-123` | **유지** (로컬 캐시는 화면 레벨에 둬도 됨) |
| `_loadRawStyle()` 호출 | `:146` (initState 내) | |
| `_loadRawStyle()` 본문 | `:149-156` | rootBundle 로드 → setState |
| `_applyMapLanguage(l)` 메서드 | `:258-264` | **제거 대상** (provider 구독으로 교체) |
| `styleString: _styleJson!` 주입 | `:796` | **유지** |
| `_styleJson == null` 로딩 가드 | `:792-794` | **유지** |
| 임시 디버그 버튼 Positioned | `:989-1013` | **제거 대상** |
| 디버그 버튼 내 언어 토글 | `:991-994` | **제거 대상** |

**전환 메커니즘**: `setState(() => _styleJson = applyMapLanguageToStyle(_rawStyle!, l))`
→ provider 연동 후에는 `ref.watch(mapLanguageProvider)` 값 변경 시 `_loadRawStyle` 와 유사한 반응 필요.

### D-4. nav_screen.dart 스타일 주입 현황
`nav_screen.dart:782`:
```dart
styleString: 'assets/images/osm_liberty_yurunavi.json',   // asset 경로 직접 하드코딩
```
**미이관.** 언어 provider 연동 시 main_map_screen과 동일 방식으로 교체 필요.

---

## E. 상태관리 / 영속화 패턴

### E-1. NotifierProvider 패턴 (riderModeProvider)
`lib/features/map/providers/map_providers.dart:321-327`:
```dart
final riderModeProvider =
    NotifierProvider<_RiderModeNotifier, bool>(_RiderModeNotifier.new);

class _RiderModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;       // ← 초기값 하드코딩 (영속화 없음)
  void toggle() => state = !state;
  void set(bool v) => state = v;
}
```
언어 provider는 이 패턴에 **SharedPreferences 로드/저장 추가**가 필요 (`AsyncNotifier` 또는 `Notifier` + initState에서 load).

### E-2. SharedPreferences 서비스 패턴 (profile_service.dart)
`lib/services/profile_service.dart:5-22`:
```dart
class ProfileService {
  static const _key = 'user_profile_v1';

  Future<UserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    ...
  }

  Future<void> save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, profile.toJsonString());
  }
}
```
언어 서비스 키 예시: `'map_language_v1'`, 저장값: `'korean'` / `'english'`.

### E-3. provider에서 서비스 소비 패턴
`lib/features/map/providers/map_providers.dart:16-30`:
```dart
final profileServiceProvider = Provider((_) => ProfileService());
final userProfileProvider = AsyncNotifierProvider<UserProfileNotifier, UserProfile>(...);

class UserProfileNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() async =>
      ref.read(profileServiceProvider).load();     // ← build에서 load()
  Future<void> save(UserProfile p) async { ... }
}
```
→ 언어 provider도 `AsyncNotifierProvider<MapLanguageNotifier, MapLanguage>` 형태로,
`build()`에서 `service.load()` 호출, `setLanguage(l)` 에서 `save(l)` + `state = AsyncData(l)`.

---

## F. 종합

### F-1. Phase 1 작업 범위 · 커밋 분할 초안

| # | 커밋 | 내용 | 파일 |
|---|---|---|---|
| C1 | `feat(settings): add LanguageService` | SharedPreferences 저장/로드 | `lib/services/language_service.dart` |
| C2 | `feat(settings): add mapLanguageProvider` | AsyncNotifierProvider, build()=load() | `lib/features/map/providers/map_providers.dart` 또는 신설 |
| C3 | `feat(settings): add SettingsScreen shell` | Scaffold + 섹션 플레이스홀더 | `lib/screens/settings_screen.dart` |
| C4 | `feat(settings): add language selector UI` | SettingsScreen 내 라디오 3개(한/영, 일어는 마스터 결정) | `lib/screens/settings_screen.dart` |
| C5 | `feat(settings): wire settings icon` | `onSettings: () {}` → Navigator push | `main_map_screen.dart` |
| C6 | `refactor(map): migrate main_map_screen to mapLanguageProvider` | `_debugLang`/버튼 제거, `ref.watch(mapLanguageProvider)` 연동 | `main_map_screen.dart` |
| C7 | `refactor(nav): apply language to nav_screen` | asset 경로 → `_styleJson` 동일 방식 적용 | `nav_screen.dart` |

### F-2. B 결론 요약

**권고**: `SettingsScreen` 신설 (`lib/screens/settings_screen.dart`).
기존 `profile_screen`은 섹션이 아니라 독립 화면으로 유지하고 SettingsScreen → "프로필 편집" 항목에서 push.
**이유**: 지도 언어·라이더모드 등 앱 전반 설정과 바이크/닉네임 편집은 사용 맥락이 다름.
★ **마스터 결정 필요**: (가) 신설+링크 vs (나) profile_screen 확장.

### F-3. 미확인 · 마스터 결정 필요 사항

| # | 항목 |
|---|---|
| U1 | profile_screen 흡수 vs 설정 신설 후 링크 (B 결론 참조) |
| U2 | 日本語 선택지 포함 여부 (Korea 타일 6% 커버리지 — RECON_mbtiles_langfields.md U1) |
| U3 | `mapLanguageProvider`를 `map_providers.dart`에 추가할지 별도 `settings_providers.dart` 신설할지 |
| U4 | nav_screen이 main_map_screen과 **동일 `_rawStyle` 캐시**를 공유할지(provider 내 캐시) 아니면 각자 로드할지 |
