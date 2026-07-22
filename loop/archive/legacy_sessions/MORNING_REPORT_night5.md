# MORNING_REPORT — 5번째 밤 (UI 빠른 정리 / A 묶음)

날짜: 2026-06-01  
모델: Claude Sonnet 4.6

---

## 결과 요약

| 모듈 | 상태 | 커밋 |
|------|------|------|
| 모듈 1 — 광고 영역 전체 제거 | ✅ PASS | `854dd5e` |
| 모듈 2 — 야간모드 폐지, 주간 단일 사양 고정 | ✅ PASS | `8e37a93` |
| 모듈 3 — 첫 화면 버튼 간격·safe-area 정리 | ✅ PASS | `d98e82d` |
| 최종 빌드 | ✅ PASS | — |

---

## 모듈 1 — 광고 영역 전체 제거

**변경 파일:** `lib/features/map/presentation/main_map_screen.dart`

- `_AdBanner` 위젯 호출 1줄 제거 (구 line 763-764)
- `_AdBanner` 클래스 전체 삭제 (구 lines 1344–1368, 약 25줄)
- LAYER 7 주석 "course sheet + ad banner" → "course sheet" 로 정리
- `pubspec.yaml` 에 AdMob/광고 패키지 없음 — 의존성 변경 불필요
- `flutter analyze` → No issues

---

## 모듈 2 — 야간모드 폐지, 주간 단일 사양 고정

**야간모드 분기 구조 (다음 밤 판단 자료):**

| 파일 | 역할 |
|------|------|
| `lib/features/map/providers/map_providers.dart:227` | `isNightProvider` — EENT~BMNT 사이면 `true` 반환 |
| `lib/main.dart:27-37` | `isNightProvider` watch → `AppTheme.night` vs `AppTheme.light` 분기 + 상태바 아이콘 밝기 전환 |
| `lib/core/theme/app_theme.dart:341` | `AppTheme.night` (다크 테마 정의) — 건드리지 않음 |
| `lib/core/widgets/daylight_bar.dart:37` | `cs.brightness == Brightness.dark` 로 야간 여부 감지, 색상 전환 — 건드리지 않음 |

**변경 내용:** `isNightProvider`를 `Provider<bool>((ref) => false)` 로 하드와이어.  
결과: `main.dart`의 분기와 `daylight_bar.dart`의 색상 분기가 모두 자동으로 주간(라이트)으로 고정됨. 야간 로직은 삭제하지 않아 rollback 가능.

지도 타일 URL: OSM 단일 URL 사용, 주/야간 전환 없음.

---

## 모듈 3 — 첫 화면 버튼 간격·safe-area 정리

**변경 파일:** `lib/features/map/presentation/main_map_screen.dart`  
대상 위젯: `_RightPanel` (우측 패널, LAYER 4)

- **현위치 버튼 ↔ 줌 그룹 간격**: `SizedBox(height: 8)` → `SizedBox(height: 20)` (+12px)
- **줌+/− 버튼 양쪽 간격**: `SizedBox(height: 2)` × 2 → `SizedBox(height: 4)` × 2 (균일 처리)

**상태표시줄 침범:** 기존 코드에서 이미 올바르게 처리되어 있음.  
- LAYER 3 헤더: `Positioned(top:0)` + `SafeArea(bottom:false)` → 상태바 아래 정렬  
- LAYER 4 우측 패널: `Positioned(top:0)` + `SafeArea` + 내부 `top: 56` 패딩 → 헤더 아래 정렬  
추가 변경 불필요.

---

## 최종 빌드 결과

```
flutter analyze → No issues found
flutter build apk --debug → ✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

경고(Kotlin Gradle Plugin) 는 기존 빌드와 동일, 빌드 실패 아님.

---

## 멈추거나 건너뛴 것

없음. 3개 모듈 모두 완료.

---

## 폰에서 마스터가 확인할 체크리스트

- [ ] 광고(Ads) 영역이 메인 지도 화면 하단에서 사라졌는지
- [ ] 새벽/밤에 실행해도 지도·UI가 주간(라이트) 상태로 뜨는지
- [ ] 첫 화면 우측 패널에서 현위치 버튼과 줌+/− 버튼 사이 간격이 충분히 벌어졌는지
- [ ] 상단 컨트롤바(로고·아이콘)가 상태표시줄에 가리지 않는지
