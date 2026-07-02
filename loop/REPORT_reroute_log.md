# REPORT — reroute offset 로그 채널 통일 + heading 가시화

커밋: 3da0323  
브랜치: feat/ic-early-guidance  
날짜: 2026-06-30

## 변경 파일:line

`lib/features/navigation/presentation/nav_screen.dart`

| 위치 | 변경 |
|------|------|
| L3 (삭제) | `import 'dart:developer' as developer;` 제거 |
| L292 (추가) | `debugPrint('YNAV_REROUTE hdg_src spd=${navState?.speedKmh} rawHdg=${navState?.headingDeg} used=$heading');` |
| L295 | `developer.log(…, name: 'NavScreen')` → `debugPrint('YNAV_REROUTE off origin hdg=$heading d=40')` |

## 다음 라이딩 관측 포인트

`adb logcat | grep YNAV_REROUTE` 로 필터 시 두 줄이 연달아 출력됨:

```
YNAV_REROUTE hdg_src spd=<속도> rawHdg=<원시heading> used=<실제사용값>
YNAV_REROUTE off origin hdg=<used값> d=40
```

### 판별 기준

| `spd` | `rawHdg` | `used` | 판정 |
|-------|----------|--------|------|
| ≤2 | (아무 값) | null | 저속→폴백. offset 없이 현위치로 재탐색 |
| >2 | null | null | GPS heading 미수신 → 폴백 U턴 가능성 |
| >2 | 숫자 | 숫자 | heading 정상 → U턴이면 offset 방향 버그 |

## 빌드 결과

- `flutter analyze`: 신규 에러 0 (기존 warning 2, info 2 는 다른 파일)
- `flutter build apk --debug`: ✓ Built app-debug.apk
