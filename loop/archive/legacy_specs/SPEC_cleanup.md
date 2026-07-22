# SPEC_cleanup.md — 죽은 코드 제거 (기초 재설계 선행 Cleanup)

작성일: 2026-06-27
근거: loop/AUDIT_architecture.md §1.B + main.dart 라우팅 RECON.
대상: 죽은 파일 삭제만. 로직 변경 없음.
분류: **저위험** (라이딩 불필요). 검증 = analyze + 빌드 + 앱 실행 스모크.
브랜치: `chore/cleanup-dead-code` (main 기준 분기 — 죽은코드는 main에 존재).

---

## 1. 라우팅 확정 사실

- 앱 진입: `main.dart:56` `home: SplashScreen()` → features 트리.
- `lib/screens/` 외부 참조 grep: **settings_screen만** features에서 import
  (`features/map/presentation/main_map_screen.dart:27`). 나머지 5개 참조 0.
- `route_service.dart`(2KB)는 LIVE(map_providers:12 사용, 경로유사도 NativeEngine). **삭제 금지.**
- `routing_service.dart`(17KB) LIVE. **삭제 금지.**

## 2. 삭제 대상 (확정)

```
lib/screens/driving_screen.dart        # 자체 GPS 스트림 가진 구 nav (단일소스 위반원)
lib/screens/main_map_screen.dart       # 구 중복 (live: features/map/presentation/main_map_screen.dart)
lib/screens/route_options_screen.dart  # 랜덤좌표 가짜코스 생성 더미
lib/screens/profile_screen.dart        # 구
lib/screens/intro_screen.dart          # 구
lib/services/native_engine.dart.bak    # 백업파일 커밋
```

## 3. 보존 (삭제 금지)

```
lib/screens/settings_screen.dart   # LIVE (features main_map_screen:27 import)
lib/services/route_service.dart    # LIVE (별개 서비스, 중복 아님)
lib/services/routing_service.dart  # LIVE
```

- settings_screen은 구 트리에 있으나 live. **features/로 이전 + deprecation 경고(:71,:73)
  수정은 별도 후속 작업**(이번 Cleanup 범위 밖).

## 4. 삭제 전 가드 (실행자 필수)

삭제 전 `settings_screen.dart`가 죽은 5개를 import하지 않는지 확인:

```bash
grep -n "screens/driving_screen\|screens/main_map_screen\|screens/route_options_screen\|screens/profile_screen\|screens/intro_screen" lib/screens/settings_screen.dart
```

**출력이 있으면** 해당 파일은 삭제 목록에서 제외하고 보고 후 중단. (없어야 정상.)

## 5. 커밋 (2커밋)

- **C1** `chore(cleanup): remove dead legacy screen tree`
  — §2의 lib/screens 5개 삭제 (settings_screen 보존).
- **C2** `chore(cleanup): remove committed backup file`
  — native_engine.dart.bak 삭제.

각 커밋 후 `flutter analyze` — **에러 0**(기존 settings_screen 경고 2개는 잔존 가능, 그 외 새 에러 없어야).
auditor 7/7.

## 6. 검증 (라이딩 불필요)

1. `flutter analyze` No issues 또는 기존 경고 2개만 (새 에러 0).
2. `flutter build apk --debug` 성공.
3. 갤A34 설치 후 **스모크**: 앱 실행 → 스플래시 → 지도 표시 → 즐겨찾기/최근경로 진입 → 경로 1개
   탐색 시작까지 정상(크래시 없음). 라이딩은 불필요.

## 7. 미결

- settings_screen features/ 이전 + 경고수정: 후속 별도 SPEC.
- 매직넘버 중앙화(nav_config): Layer 0/1에서 해당 상수의 소속이 정해지므로 그때 처리. 지금 별도 파일
  선작성 금지(불필요 churn).
