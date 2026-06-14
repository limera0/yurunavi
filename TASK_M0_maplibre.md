# TASK M0 — maplibre_gl 설치 + 빌드 환경 정비

브랜치: `feat/maplibre-migration` (이미 체크아웃됨 — 확인할 것)
실행: tmux 안에서 `claude --permission-mode auto`
스코프: **패키지 추가 + Android abiFilters 설정만. Dart 코드는 한 줄도 수정 금지.**
목표: maplibre_gl 0.25.0 설치 후에도 기존 flutter_map 앱이 그대로 빌드되는지 확인.

---

## 사전 확인 (작업 시작 전)

```bash
cd /data/projects/yurunavi
git branch                    # * feat/maplibre-migration 이어야 함. main이면 중단.
git status                    # clean 이어야 함
```

브랜치가 main이면 즉시 중단하고 보고. (작업 브랜치 밖에서 작업 금지)

---

## 환경 (이미 검증됨 — 참고용)

- Kotlin 2.2.20 ✅ (maplibre_gl 요구 2.1.0+ 충족)
- Flutter 3.44.0 / Dart 3.12.0 ✅
- AGP 8.11.1 ✅
- minSdk = flutter.minSdkVersion (Flutter 기본값 추종)

→ settings.gradle / Kotlin 버전 수정 **불필요**. 건드리지 말 것.

---

## STEP 1 — maplibre_gl 패키지 추가

`flutter_map` 은 **아직 제거하지 않는다** (M1~M6 동안 화면별로 점진 교체, 마지막에 제거).
두 패키지가 잠시 공존한다. pubspec.yaml 의존성에 추가:

```bash
cd /data/projects/yurunavi
flutter pub add maplibre_gl
```

성공하면 pubspec.yaml 에 `maplibre_gl: ^0.25.0` (또는 그 시점 최신)이 추가된다.
실패(버전 충돌 등) 시 에러 전문을 보고하고 중단.

확인:
```bash
grep -nE "maplibre_gl|flutter_map" pubspec.yaml
flutter pub get
```

---

## STEP 2 — OSM 스타일 asset 등록 확인

`osm_liberty_yurunavi.json` 이 assets/images/ 에 있다. pubspec.yaml 의
flutter: assets: 섹션에 등록돼 있는지 확인하고, 없으면 추가:

```bash
grep -n "osm_liberty\|assets/images" pubspec.yaml
```

assets 블록에 해당 경로가 없으면 추가 (이미 다른 assets 항목이 있을 것):

```yaml
flutter:
  assets:
    - assets/images/osm_liberty_yurunavi.json
```

⚠️ 디렉토리 통째(`assets/images/`)로 이미 등록돼 있으면 개별 추가 불필요.
중복 등록하지 말 것.

---

## STEP 3 — Android abiFilters (UnsatisfiedLinkError 예방)

maplibre_gl 은 네이티브 .so 라이브러리를 쓴다. release 빌드에서 ABI 누락 시
일부 기기에서 `UnsatisfiedLinkError` 크래시가 난다. android/app/build.gradle.kts 의
`android { defaultConfig { ... } }` 안에 ndk abiFilters 추가.

먼저 현재 build.gradle.kts 의 defaultConfig 블록을 view 로 확인한 뒤,
defaultConfig 안에 아래를 삽입 (이미 ndk 블록이 있으면 abiFilters 만 추가):

```kotlin
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
```

⚠️ x86 은 실기기에 거의 없고 에뮬레이터용이라 제외(빌드 크기 절감).
arm64-v8a 가 요즘 안드로이드 폰 대부분. armeabi-v7a 는 구형 호환.

---

## STEP 4 — 검증 (가장 중요: 기존 앱이 여전히 빌드되는가)

maplibre_gl 을 추가했지만 **아직 코드에선 안 쓴다.** 따라서 기존 flutter_map 앱이
그대로 작동해야 정상. 이게 M0 의 합격 기준.

```bash
cd /data/projects/yurunavi

# 1) 분석 — 무이슈여야 함 (maplibre import 안 했으니 새 경고 없어야)
flutter analyze

# 2) 디버그 빌드 — 성공해야 함 (패키지 공존이 빌드를 깨지 않는지)
flutter build apk --debug 2>&1 | tail -15
```

**합격 기준:**
- `flutter analyze` → No issues
- `flutter build apk --debug` → `✓ Built ...app-debug.apk`

빌드가 깨지면 → maplibre_gl 과 기존 의존성(flutter_map 8.x 등) 충돌 가능성.
에러 전문을 MORNING_REPORT 에 기록하고 [BLOCKED] 표시 후 중단.
(이 경우 git checkout main 으로 복귀 가능하니 안전.)

---

## 절대 금지
- Dart 코드(.dart 파일) 수정 — M0 는 환경 작업만
- flutter_map 제거 — 아직 화면들이 쓰고 있음
- settings.gradle / Kotlin 버전 변경 — 이미 충족, 건드리면 회귀
- main 브랜치에서 작업

---

## 커밋 + 보고

```bash
git add pubspec.yaml pubspec.lock android/app/build.gradle.kts
git commit -m "build(M0): add maplibre_gl 0.25 + abiFilters, flutter_map kept [maplibre-M0]"
```

보고:
- maplibre_gl 설치 버전
- flutter analyze 결과
- flutter build apk --debug 결과 (성공/실패)
- 커밋 해시
- 다음: M1 (main_map_screen 에 빈 MapLibre 지도 + osm_liberty 스타일)

---

## 참고 — 다음 단계 미리보기 (M1~M6)

| 단계 | 작업 |
|------|------|
| **M0** | (이번) 패키지 + 환경 |
| M1 | main_map_screen 에 빈 MapLibre 지도 + 스타일 적용 (오버레이 전부 제거한 최소판) |
| M2 | 경로 폴리라인 이식 (addLine GL API) |
| M3 | 마커 이식 — 커스텀 위젯 → 심볼 이미지 등록 (최난관) |
| M4 | 카메라 — 줌 티어/자동회전/CameraFit/줌버튼 |
| M5 | nav_screen 재작성 |
| M6 | driving_screen 재작성 + flutter_map 제거 |
