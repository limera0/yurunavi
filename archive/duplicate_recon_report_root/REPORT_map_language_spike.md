# REPORT: 지도 언어 전환 스파이크 (setLayerProperties 검증)
작성일: 2026-06-13 | 브랜치: feat/map-language

---

## [0] 게이트 결과

### 0-1. maplibre_gl 버전
```
pubspec.yaml:  maplibre_gl: ^0.26.1
설치본:        ~/.pub-cache/hosted/pub.dev/maplibre_gl-0.26.1
```
가정(0.26.1) 일치 ✅

### 0-2. 실제 API 시그니처 (설치본 기준)

**컨트롤러 메서드** (`controller.dart:686`):
```dart
Future<void> setLayerProperties(String layerId, LayerProperties properties) async {
  await _maplibrePlatform.setLayerProperties(
    layerId,
    properties.toJson(skipNulls: false),  // ← null도 전송됨
  );
}
```

**SymbolLayerProperties** (`layer_properties.dart:10,497,819`):
```dart
class SymbolLayerProperties implements LayerProperties {
  final dynamic textField;  // 문자열 '{name:nonlatin}' 직접 전달 가능
  const SymbolLayerProperties({ ..., this.textField, ... });
}
```

**스케치와 차이점**:
- 스케치: `ml.SymbolLayerProperties(textField: expr)` → **일치**
- 주의: `toJson(skipNulls: false)` 동작으로 null 속성도 전부 전송됨.
  Java 측 `interpretSymbolLayerProperties`에서 null Expression을 받으면
  `PropertyFactory.textColor(null)` 등 호출 → 스타일 기본값으로 리셋 가능성.
  **시각 확인 항목: 탭 후 텍스트 색상/크기가 유지되는지**

**setLayoutProperty 단독 메서드**: 없음 (0.26.1 미지원). `setLayerProperties`만 존재.

### 0-3. style JSON layer id 확인 결과
전수 확인 23개 전부 `OK` (누락 없음):

| Pattern | IDs | 결과 |
|---|---|---|
| ② (16개) | waterway-name, water-name-lakeline, water-name-other, poi-level-3, poi-level-2, poi-level-1, poi-railway, highway-name-path, highway-name-minor, highway-name-major, airport-label-major, place-other, place-village, place-town, place-city, place-city-capital | 전부 OK |
| ③ (7개) | water-name-ocean, place-state, place-country-other, place-country-3, place-country-2, place-country-1, place-continent | 전부 OK |

---

## 실제 사용 API (스케치 대비 차이)

스케치와 동일:
```dart
await c.setLayerProperties(id, ml.SymbolLayerProperties(textField: expr));
```

스케치와 차이 없음. `setLayoutProperty` 미존재 확인으로 `setLayerProperties` 채택 확정.

---

## 커밋 해시

| 단계 | 해시 | 메시지 |
|---|---|---|
| 체크포인트 | `67e2bec` | checkpoint: before map-language spike |
| 커밋 1 | `fcc4031` | feat(map): add MapLanguage enum |
| 커밋 2 | `f111064` | spike(map): runtime language toggle via setLayerProperties |

---

## 빌드 결과

```
flutter analyze → No issues found! (ran in 1.6s)
flutter build apk --debug → ✓ Built build/app/outputs/flutter-apk/app-debug.apk (215M)
```

APK 경로: `build/app/outputs/flutter-apk/app-debug.apk`

---

## 마스터 폰 검증 절차

1. APK 설치:
   ```
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

2. 앱 실행 → 지도 화면 진입. 좌하단에 `라벨: 한국어` 버튼 확인.
   - 이 시점은 아직 언어 적용 전 — 기존 영/한 **병기** 상태여야 함.

3. 버튼 탭 → `라벨: English` 로 전환됨.
   - **기대**: 라벨이 로마자 단일 표기로 바뀜 (영/한 병기 → 로마자만)
   - **확인 포인트**: 텍스트 색상·크기·halo가 유지되는지 (null 리셋 위험 검증)

4. 다시 탭 → `라벨: 한국어` 로 전환.
   - **기대**: 라벨이 한글 단일 표기로 바뀜

5. logcat에서 apply fail 없는지 확인:
   ```powershell
   adb logcat -d | Select-String -Pattern "lang apply fail"
   ```
   → 출력 없으면 23개 레이어 전부 성공.
   → 출력 있으면 해당 레이어 id와 에러 메시지 기록 후 보고.

---

## 주의: null 리셋 가능성

`setLayerProperties`는 `SymbolLayerProperties`의 모든 null 필드를 포함해 전송함.
Java 측에서 null Expression을 받은 속성(text-color, text-size 등)이
**MapLibre 하드코딩 기본값**으로 리셋될 경우 스타일 색상이 사라짐.
폰 검증 시 반드시 색상/크기 변화 여부 확인. 문제 발생 시 대안:
- 스타일 JSON을 언어별로 사전 생성 후 `styleString` 재주입 (화면 깜빡임 있음)
- maplibre_gl 0.27+ 업그레이드 후 `setLayoutProperty` 지원 여부 재확인
