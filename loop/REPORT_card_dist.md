# REPORT: 안내카드 거리 숫자 확대

## 변경 파일
`lib/features/navigation/presentation/nav_screen.dart`

## 변경 위치 및 전후 비교

| 항목 | 전 | 후 |
|---|---|---|
| 위젯 | `Text` (단일) | `Builder` + `RichText` (두 TextSpan) |
| 거리 숫자 fontSize | 13 | **38** |
| 거리 숫자 fontWeight | w600 | **w800** |
| 단위(m/km) fontSize | (숫자와 합쳐짐) | **17** |
| 단위 fontWeight | - | w700 |
| 색상 | cs.tertiary | cs.tertiary (유지) |
| maneuver 텍스트 | fontSize 20, bold | 그대로 (미변경) |

## 추가 메서드
- `_TurnStep._splitDistStr(String s)` — line 1095–1099
  - "819m" → ("819", "m")
  - "1.2km" → ("1.2", "km")

## 빌드 결과
- `flutter build apk --debug` exit 0 (경고는 기존 Kotlin Gradle 노이즈)

## 커밋
`88c06c6` style(card): enlarge distance number (naver-style)
