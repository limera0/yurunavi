# REPORT: nav_screen 뒤로가기 인터셉트

커밋: bab037a  
날짜: 2026-06-09  
브랜치: feat/maplibre-migration

---

## 변경 요약

### 사전검증 결과
| 항목 | 결과 |
|------|------|
| 기존 PopScope/WillPopScope | 없음 (grep 확인) |
| 최상위 위젯 | `Scaffold` (line 486) |
| Flutter SDK | 3.44.0 → `PopScope` + `onPopInvokedWithResult` 사용 |
| 체크포인트 커밋 | nav_screen.dart 미수정 상태라 생략 |

### 구현 내용

**추가 메서드: `_confirmExit(BuildContext ctx)` (line 452)**
- `showDialog`로 AlertDialog 표시
- "취소" → 다이얼로그만 닫음, 내비 유지
- "종료" → 다이얼로그 닫기 + `Navigator.of(ctx).pop()`
  - `dispose()`가 자동으로 wakelock disable / GPS 스트림 cancel / TTS stop 처리
  - 중복 호출 없음 (모두 nullable cancel 패턴)

**`build()` 수정: Scaffold → PopScope 래핑 (line 510)**
```dart
return PopScope(
  canPop: false,
  onPopInvokedWithResult: (bool didPop, _) {
    if (!didPop) _confirmExit(context);
  },
  child: Scaffold(...),
);
```

### 검증 결과

```
flutter analyze lib/features/navigation/presentation/nav_screen.dart
→ No issues found!

flutter build apk --debug
→ ✓ Built build/app/outputs/flutter-apk/app-debug.apk  (23.3s)
```

빌드 경고(KGP): 기존부터 있던 Kotlin Gradle Plugin 관련 경고. 이번 변경과 무관.

---

## 폰 실측 가이드 (마스터 직접)

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

확인 항목:
1. 내비 화면에서 Android 뒤로가기 버튼(또는 제스처) 탭
2. "내비게이션을 종료할까요?" 다이얼로그 출현 확인
3. "취소" → 다이얼로그 닫히고 내비 계속
4. "종료" → 이전 화면으로 복귀 (wakelock 해제 확인은 선택)
