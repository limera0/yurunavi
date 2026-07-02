# IC 조기안내 구현 리포트

브랜치: `feat/ic-early-guidance` (main 미머지, T3 라이딩 전 금지)

## 변경 파일

| 커밋 | 파일 | 내용 |
|------|------|------|
| C1 `cb5bf8f` | `assets/config/guidance_profile.json` | ramp·exit에 IC 전용 tiers 추가 (1000/400/120 분기점) |
| C2 `87d98d8` | `lib/features/navigation/guidance_profile.dart` | `eventTiers` 필드, `tiersForEvent()` 메서드, load() 파싱 |
| C3 `abff941` | `lib/features/navigation/voice_engine.dart` | `tierFor` → `tiersForEvent(event)` 1지점 치환 |
| C4 `3646e5e` | `test/guidance_profile_test.dart` | 4케이스 단위 테스트 (red→green) |

## 테스트 결과

```
flutter test test/guidance_profile_test.dart  →  4/4 passed
flutter test test/voice_engine_test.dart      →  9/9 passed (회귀 없음)
flutter analyze (voice_engine.dart)           →  No issues found
```

## 라이딩 검증 체크리스트

- [ ] IC 진입 1km 전 "1킬로미터 앞 IC" 발화 들리는지
- [ ] IC 진입 500m 전 approach 발화 확인
- [ ] IC 진입 150m 전 approach 발화 확인
- [ ] 400m 미만 진입 시 400m 발화 → 150m 발화(1000·500 스킵) 확인
- [ ] 일반 좌/우회전 발화 거동 불변인지 (500·300·50 패턴 유지)
- [ ] 머지(merge) 발화 전역 tiers 그대로인지

## 주의사항

- `main` 머지 금지 (T3, 라이딩 전)
- APK 빌드 후 실차 검증 필요: `flutter build apk --debug` → `adb install`
