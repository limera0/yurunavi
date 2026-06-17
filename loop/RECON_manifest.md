# RECON-manifest — Android 위치 전달 제약 진단

작성: 2026-06-17

---

## §A 권한 체크 (app 소스 매니페스트)

파일: `android/app/src/main/AndroidManifest.xml`

| 권한 | 줄 | 결과 |
|------|-----|------|
| `ACCESS_FINE_LOCATION` | 4 | ✅ 존재 |
| `FOREGROUND_SERVICE` | 6 | ✅ 존재 |
| `FOREGROUND_SERVICE_LOCATION` | 7 | ✅ 존재 |
| `ACCESS_COARSE_LOCATION` | 5 | ✅ 존재 (보조) |

---

## §B `foregroundServiceType="location"` 서비스 선언

### 앱 자체 매니페스트
`android/app/src/main/AndroidManifest.xml` 에는 **`<service>` 요소가 없다.**  
앱 소스에서 foregroundServiceType 선언을 직접 하지 않는다.

### geolocator 플러그인 매니페스트 (머지 후)
`build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml:94-98`
```xml
<service
    android:name="com.baseflow.geolocator.GeolocatorLocationService"
    android:enabled="true"
    android:exported="false"
    android:foregroundServiceType="location" />
```

geolocator 플러그인이 자체 매니페스트에 `foregroundServiceType="location"`을 포함하고,  
Gradle 빌드 시 앱 매니페스트와 자동 머지된다.  
**빌드 결과물(APK)의 최종 매니페스트는 compliant** — Android 14(API 34) 이상 요건 충족.

### 리스크
- 앱 소스 manifest에 직접 선언이 없으므로 **geolocator 플러그인 업데이트가 이 선언을 제거하면 무음으로 Android 14+ 위반**이 된다.
- 현재 geolocator `^14.0.2` 기준 안전. 단, 메이저 업그레이드 전 merged manifest 재확인 필요.

---

## §C targetSdk

`android/app/build.gradle.kts:28`
```kotlin
targetSdk = flutter.targetSdkVersion
```

`FlutterExtension.kt:34` (Flutter 3.12.0):
```kotlin
val targetSdkVersion: Int = 36
```

빌드 확인: `build/app/intermediates/merged_manifests/debug/.../AndroidManifest.xml:9`
```xml
<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />
```

**targetSdk = 36 (Android 16)** — API 34 초과이므로 foregroundServiceType 명시 의무 발생.  
geolocator 플러그인이 이를 충족 중 (§B 참조).

---

## §D driving_screen.dart 생존 여부 (RECON_location §B-3 미해결 항목)

파일 존재: `lib/screens/driving_screen.dart`  
클래스 정의: `lib/screens/driving_screen.dart:26` — `class DrivingScreen extends ConsumerStatefulWidget`

**외부 참조 결과**: `grep -rn "DrivingScreen\|driving_screen" lib/ --include="*.dart"` →
driving_screen.dart 자기 자신 외 **0건**.

**판정: DrivingScreen은 라우팅 진입점 없는 Dead Code.**

- 라우터, main.dart, 다른 어떤 화면에서도 import·navigate 하지 않음
- 내부 GPS 스트림(`distanceFilter:5m`, `intervalDuration` 미지정)은 실행되지 않음
- RECON_location §E 표 마지막 행 "비활성 추정" → **확정 비활성**

---

## §E 종합 판정

| 항목 | 현황 | 위험도 |
|------|------|--------|
| ACCESS_FINE_LOCATION 권한 | ✅ 존재 (manifest:4) | 없음 |
| FOREGROUND_SERVICE_LOCATION 권한 | ✅ 존재 (manifest:7) | 없음 |
| foregroundServiceType="location" 서비스 | ✅ 플러그인이 제공, APK 머지 확인 | 낮음 (플러그인 의존) |
| targetSdk | 36 (Android 16) — API 34+ 요건 적용됨 | 조건부 위험 (현재는 충족) |
| DrivingScreen 활성화 | ❌ Dead code, 라우팅 진입 없음 | 없음 (영향 없음) |

**결론**: 매니페스트 관점에서 Android 위치 서비스 요건은 현재 충족.  
1Hz GPS 미보장 원인은 OS 전력 관리(Doze/배터리 최적화)로 추정 → INSTR-fixrate로 실측 필요.

---

## §F INSTR-fixrate 선행조건 해소

BACKLOG의 INSTR-fixrate 선행조건: "RECON-manifest 결과 확인 후"  
→ **매니페스트 이상 없음. INSTR-fixrate 착수 가능.**
