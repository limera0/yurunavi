# MORNING_REPORT — 3번째 밤 (2026-06-01)

오케스트레이터: Claude Sonnet 4.6

---

## 1. 완료 모듈 + 커밋 해시

| 모듈 | 내용 | 커밋 |
|------|------|------|
| 0 | Tailscale MagicDNS 주소 교체 | `1af76f9` |
| 1 + 2 | Android cleartext 허용 + APK 빌드 성공 | `309c89e` |
| 3 | 내비 버그 조사 (코드 수정 없음) | — (조사 전용) |

---

## 2. 완료 기준 체크 (모듈별)

### 모듈 0 — 라우팅 주소 교체
- [x] `routing_service.dart` 에 `192.168.0.57` 없음 → `westinx.tail2172f6.ts.net:8002` 로 교체됨
- [x] `native_engine.dart` 에 `192.168.0.57` 없음 → `westinx.tail2172f6.ts.net:8003` 로 교체됨
- [x] `grep -rn "192.168.0.57\|localhost:800" lib/` 결과 없음 (잔여 없음)
- [x] `flutter analyze` → No issues found
- 참고: 호스트명이 코드에 하드코딩되어 있음. **추후 `.env` 파일로 빼는 것을 권장** (예: `VALHALLA_HOST`, `RUST_HOST` 환경변수로 분리).

### 모듈 1 — Android cleartext 허용
- [x] `android/app/src/main/res/xml/network_security_config.xml` 생성됨
- [x] `AndroidManifest.xml` → `<application>` 태그에 `android:networkSecurityConfig="@xml/network_security_config"` 속성 추가됨
- [x] 기존 속성(android:label, android:icon, android:name) 전혀 변경 없음
- [x] 매니페스트 XML 구조 이상 없음 (육안 확인 완료)

### 모듈 2 — 빌드 검증
- [x] `flutter clean` 완료
- [x] `flutter analyze` → No issues found (0 errors, 0 warnings)
- [x] `flutter build apk --debug` → **빌드 성공**
  - APK 경로: `build/app/outputs/flutter-apk/app-debug.apk`
  - 경고(warning) 2개 발생했으나 빌드 실패에는 영향 없음:
    > Kotlin Gradle Plugin(KGP) 관련 경고 — 현재 버전에서는 빌드 가능. 미래 Flutter 버전에서 문제될 수 있음.
    > 영향받는 플러그인: `device_info_plus`, `package_info_plus`, `shared_preferences_android`
    > 지금 당장 수정 불필요 — 다음 플러그인 업그레이드 때 자연히 해결됩니다.
- [x] 커밋 완료 (`309c89e`)

---

## 3. 막힌 것 / 건너뛴 것

없음. 모듈 0·1·2 모두 정상 완료.

모듈 3은 NIGHT_TASK 지시에 따라 코드 수정 없이 조사만 수행함.

---

## 4. 사용자가 아침에 직접 할 일 (순서대로)

### APK 설치
1. 폰과 컴퓨터를 USB로 연결하거나, ADB over Wi-Fi를 사용하세요.
2. 아래 명령어로 직접 설치할 수 있습니다:
   ```bash
   flutter run -d <기기ID>
   ```
   또는 빌드된 APK 파일을 폰에 복사 후 직접 설치:
   ```
   build/app/outputs/flutter-apk/app-debug.apk
   ```
   > "알 수 없는 출처에서 설치 허용" 설정이 필요합니다 (안드로이드 설정 → 보안).

3. **폰에 Tailscale이 켜져 있는지 반드시 확인하세요.**

### 폰에서 확인할 것
- **경로 선 3개 테스트:** 지도에서 목적지를 터치 → 하단에 시골길·지방도로·국도 카드 3개가 나와야 함 → 각 카드를 누르면 지도에 경로 선이 그려지는지 확인
- **거리 일치 확인:** 카드에 표시된 거리(km)와 지도에 그려진 경로 선 길이가 대략 맞는지 확인 (현재 두 숫자가 다른 건 알려진 버그 — 아래 버그 3 참조)
- **"Start your Engine" 슬라이더:** 슬라이더를 밀어 내비 화면으로 진입되는지 확인

---

## 5. 모듈 3 — 내비 버그 조사 결과

### 버그 1: 내비 화면이 목적지 중심으로 뜬다 (출발지/현위치가 아닌)

**의심 위치:**
- `lib/features/navigation/presentation/nav_screen.dart:146`
  ```dart
  initialCenter: widget.destination ?? _currentPos ?? _kInitialMapView,
  ```
- `lib/screens/driving_screen.dart:153`
  ```dart
  initialCenter: widget.destination ?? _currentPos ?? kInitialMapView,
  ```

**이유:** 내비 화면이 처음 열릴 때 GPS 위치(`_currentPos`)가 아직 `null`입니다. 그래서 목적지(`widget.destination`)가 첫 번째로 선택되어 지도 중심이 목적지로 고정됩니다. GPS 스트림은 비동기로 늦게 도착합니다.

**다음 밤 수정 방향:** `widget.destination`을 초기 중심에서 제거하고 `_currentPos ?? _kInitialMapView`로 변경. 어차피 GPS 첫 신호가 오면 `_recenter(loc)`가 자동 호출되어 현위치로 이동합니다.

---

### 버그 2: 현위치 버튼을 눌러도 현위치로 안 돌아온다

**의심 위치 (핵심):**
- `lib/screens/driving_screen.dart:160-162`
  ```dart
  onMapEvent: (event) {
    if (event is MapEventMoveStart) {
      _onCameraMove(event.camera, true);  // ← 출처 구분 없음
    }
  },
  ```

**이유:** `_mapCtrl.move()` (= 현위치 복귀 버튼이 호출하는 함수)를 실행하면 Flutter Map이 `MapEventMoveStart` 이벤트를 발생시킵니다. 위 코드는 이 이벤트의 출처(손가락으로 움직인 것인지, 코드로 움직인 것인지)를 구분하지 않습니다. 복귀 버튼을 눌러 지도가 이동하는 순간 다시 `_isManualMode = true`로 되돌아가 버튼 효과가 즉시 취소됩니다.

**비교:** `nav_screen.dart:154`는 올바르게 처리합니다:
```dart
if (event is MapEventMoveStart && event.source != MapEventSource.mapController) {
  _onMapGesture();
}
```

**다음 밤 수정:** `driving_screen.dart:161`에 `&& event.source != MapEventSource.mapController` 조건 추가.

---

### 버그 3: 카드 거리(54~83km)와 내비 거리(23.4km)가 다르다

**의심 위치:**

**(A) 카드 거리** — `lib/features/map/presentation/main_map_screen.dart:1167-1172, 1222`
```dart
static const _routes = [
  _RouteInfo('시골길로\n느긋하게', 1.55, ...),  // 직선거리 × 1.55
  _RouteInfo('지방도로\n여유롭게', 1.22, ...),   // 직선거리 × 1.22
  _RouteInfo('국도로\n빠르게', 1.0, ...),        // 직선거리 × 1.0
];
// 카드 거리 = haversine(출발지→목적지) × 고정 배수
```
카드 거리는 **직선 거리 × 임의의 배수**로 계산됩니다. 실제 도로 거리가 아닙니다.

**(B) 내비 화면 거리** — `lib/features/navigation/presentation/nav_screen.dart:409`
```dart
Text('23.4km', ...)  // ← 하드코딩된 임시 값
```
- `NavScreen`은 `routePolyline`을 파라미터로 받습니다 (`_startNavigation()`에서 전달됨, `main_map_screen.dart:302-309`).
- 그러나 ETA 바에서 그 폴리라인의 실제 길이를 계산하지 않고 `23.4km`를 하드코딩했습니다.

**(C) `DrivingScreen`(구버전으로 보이는 내비 화면)** — `lib/screens/driving_screen.dart:469`
```dart
Text('23.4km', ...)  // ← 동일하게 하드코딩
```
- `DrivingScreen`은 `destination`만 파라미터로 받고 `routePolyline`을 받지 않습니다.
- 현재 `_startNavigation()`은 `DrivingScreen`이 아닌 `NavScreen`을 사용합니다. `DrivingScreen`은 별도 진입점이 있는 구버전 화면으로 보임 (추가 확인 필요).

**결론:** 카드는 "직선거리×배수"를, 내비는 "하드코딩 23.4km"를 보여줌 — 서로 다른 소스. 실제 Valhalla 도로 거리(RoutingService가 반환하는 polyline 길이)는 두 화면 모두 사용하지 않고 있음.

**다음 밤 수정 방향:**
1. `NavScreen`의 ETA 바: `widget.routePolyline`으로 Haversine 누적 거리를 계산하여 표시.
2. 카드 거리도 Valhalla 실제 거리(`allRoutes` 폴리라인 길이)로 교체하면 두 값이 일치하게 됩니다.

---

## 6. 토큰/한도 메모

모듈 0·1·2·3 모두 단일 세션에서 완료됨. 한도 초과 없음.

---

## 7. 용어 설명

- **Tailscale MagicDNS**: 인터넷을 통해 내 서버에 접속하기 위한 주소. `192.168.0.57`은 집 안 내부망에서만 쓰이는 주소라 밖에서 안 됩니다. `westinx.tail2172f6.ts.net`은 어디서든 접속 가능한 Tailscale 전용 주소입니다.
- **cleartext(평문 HTTP)**: 암호화 없이 데이터를 주고받는 방식. 안드로이드 9 이상은 보안상 이걸 기본으로 차단합니다. 내부 서버 연결이라 신뢰할 수 있으므로 `.ts.net` 도메인에만 예외로 허용했습니다.
- **APK**: 안드로이드 앱 설치 파일. 구글 플레이가 아닌 파일 직접 설치용입니다.
- **Haversine 직선 거리**: 지구 표면 위 두 점의 최단 거리를 구하는 공식. 실제 도로 거리보다 항상 짧습니다.
- **Valhalla**: 도로 지도 기반으로 실제 경로와 거리를 계산해주는 서버. 카드에 표시되는 거리는 아직 이것을 제대로 활용하지 않고 있습니다.
