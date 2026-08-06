GOAL: 백화 원인 확정을 위한 네이티브 로그 계측을 먼저 넣고, 이어서 유루나비에 없는 메모리·GPU 압박 대응(레퍼런스 앱 대비 결손 4종)을 구현한다.

# HANDOFF — 메모리/GPU 압박 대응 구현 (S1b 후속, 구현 세션)

- 작성 2026-08-06 · 브랜치 `verify/ride-0711` · 기준 HEAD `d0cb5c2`
- **선행 조사: [RECON_0805_render_resource.md](RECON_0805_render_resource.md) **§12**를 먼저 읽어라.
  §12-3(3자 비교표)·§12-4(판정)·§12-5(권고)가 이 지시서의 근거 전부다. 여기서 반복하지 않는다.**
- 요약 리포트: [MORNING_REPORT_0806_S1b_memory_audit.md](MORNING_REPORT_0806_S1b_memory_audit.md)
- 마스터 승인: **§12-5의 A·B·C 전부 진행 승인됨** (2026-08-06 저녁 스티어링)

> **이번엔 조사가 아니라 구현이다.** 단, **M32 실기기 재현 실험은 여전히 전면 금지**다
> (마스터 지시 — 재탐색 폭주 → Valhalla rate limit → 컨텍스트 폭증으로 세션 2회 사망).
> 빌드 검증(`flutter build apk`)·단위 테스트까지만 하고, 실주행 검증은 마스터 몫이다.

---

## 0. 이번 세션이 반드시 지킬 것

1. **청크마다 체크포인트 커밋.** 청크 하나 끝날 때마다 `code-auditor` → PASS → 커밋.
2. **`git add -A` 절대 금지.** 같은 브랜치에 다른 세션 작업물이 스테이징된 채 남아 있다
   (`MORNING_REPORT_0806_S1b_continue.md`, `repro_s1b/mem_gpu_samples_0806.csv` 등).
   커밋 전 `git status --short`로 **내 파일만** 스테이징됐는지 확인하라.
3. **시간·컨텍스트가 부족하면 청크 단위로 끊고** 남은 청크를 이 파일에 갱신해 넘겨라.
   무리해서 다 하려다 세션이 죽으면 앞의 커밋까지 애매해진다.
4. **추측 금지.** 아래 "확인하고 시작하라"는 항목은 실제로 SDK 소스를 열어 확인하라.

---

## 1. 청크 순서와 그 이유

**청크1(계측)을 먼저 한다.** 청크2~3이 압박을 줄여버리면 증상이 드물어져
**원인을 확정할 기회를 잃는다.** 계측 → 완화 순서가 맞다.
다만 **전부 같은 릴리스에 실려야** 마스터의 다음 실주행 1회에서
"고쳐졌는가"와 "원인이 무엇이었는가"를 동시에 얻는다.

| 청크 | 내용 | 위험도 |
|---|---|---|
| **1** | B-1 네이티브 로그 캡처 | 중 (Kotlin+Dart 신규) |
| **2** | A-1 `ui.Picture.dispose()` · A-3 `imageCache` 상한 | 저 |
| **3** | A-2 `didHaveMemoryPressure()` · A-4 백그라운드 캐시 드롭 | 중 |
| **4** | A-5 `_locLayerReady`/`_destLayerReady` 리셋 | **중상 (내비 회귀 위험)** |
| **5** | A-6 `flutter_map` 제거 | 저 (단 pubspec 변경 → `flutter clean` 필요) |
| **6** | B-2 GPU 메모리 스냅샷 · C-1 Impeller off A/B 산출물 | 저 |

---

## 2. 청크1 — B-1 네이티브 로그 캡처 (**최우선**)

### 왜 최우선인가

실주행 진단로그 95k줄을 `impeller|atlas|vulkan|GL_OUT_OF_MEMORY|OutOfMemory`로 grep하면
**매치 0건**이다. `FileLogger`가 Dart `debugPrint`만 가로채기 때문에
**Impeller validation·Vulkan·OOM 네이티브 로그가 통째로 안 남는다**(§12-2).
`Could not create valid atlas` 한 줄이 잡히면 §12-4의 (b)가설이 **즉시 확정**된다.
재현 실험 100번보다 값싸고 결정적이다.

### 현재 구조 (확인 완료)

- `lib/core/logging/file_logger.dart:6-45` — `FileLogger.init()`이 `debugPrint`를 교체해
  `${dir}/ynav_$ts.log`에 `IOSink`(`_sink`)로 기록. `_rotate()`로 오래된 파일 정리.
- `lib/main.dart:26` — `await FileLogger.init()` (`runApp` 전).
- `android/app/src/main/kotlin/com/westinx/yurunavi/MainActivity.kt:29-70` —
  `configureFlutterEngine`에 이미 MethodChannel 3개 등록돼 있다(`e2e_harness`,
  `nav_service`, `nav_floating`). **같은 패턴으로 추가하면 된다.**

### 구현 방향

1. **Kotlin**: 자기 프로세스 로그를 읽는 스레드.
   `logcat -v threadtime --pid=<Process.myPid()>` — **자기 pid 로그는 READ_LOGS 권한 없이
   읽을 수 있다.** 키워드 allowlist로 걸러서(예: `Impeller`, `impeller`, `Vulkan`,
   `vulkan`, `glyph`, `atlas`, `GL_OUT_OF_MEMORY`, `OutOfMemory`, `onTrimMemory`,
   `lowmemorykiller`, `Surface`, `EGL`) EventChannel로 Dart에 흘린다.
2. **Dart**: `FileLogger`에 **`writeRaw(String)` 추가** — 받은 줄을
   `YNAV_NATIVE ` 접두어를 붙여 **`_sink`에 직접 쓴다.**

> ⚠️ **피드백 루프 주의.** 받은 줄을 `debugPrint`로 흘리면
> `debugPrint → stdout → logcat → 펌프가 다시 읽음 → debugPrint`로 **무한 증폭**된다.
> **반드시 `_sink`에 직접 쓸 것.** allowlist에 `flutter` 태그 전체를 넣지도 마라.

3. **볼륨 관리**: allowlist 필터로 이미 적지만, 기존 `_rotate()`가 계속 동작하는지 확인하라.
4. **검증**: 디버그 빌드로 앱 실행 → 로그 파일에 `YNAV_NATIVE`가 실제로 찍히는지 확인.
   Impeller validation 줄이 안 나와도 정상이다(정상 상태에선 안 나온다) —
   **아무 네이티브 줄이라도 캡처되면 성공**이다. 인위적으로 만들려 하지 마라.

---

## 3. 청크2 — A-1 `ui.Picture` 해제 + A-3 `imageCache` 상한

### A-1 (자명한 결함)

`ui.Image`는 `dispose()`하는데 **`ui.Picture`는 3곳 전부 미해제**다:

- `lib/services/poi_icon_renderer.dart:56` (`renderPoiIconPng`)
- `lib/services/poi_icon_renderer.dart:70` (`renderPlainDotPng`)
- `lib/features/tour_summary/tour_share_helper.dart:167` (`_compositeVertically`)

`picture.toImage()` 이후 `picture.dispose()`를 추가하라. `try/finally`로 감싸는 게 안전하다.
POI 아이콘 5종은 **스타일 재주입마다 재생성**된다(`nav_screen.dart:1565-1573`, 주석에 명시).

### A-3

`imageCache` 튜닝이 **0건**이라 기본값(1000장 / 100MB)이 그대로다.
RAM 3.7GB 기기엔 과하다. OsmAnd처럼 **기기 기준으로 역산**하라
(레퍼런스: `ResourceManager.java:185-187`이 화면 픽셀 수로 타일 캐시 상한을 정한다).

- 설정 위치: `lib/main.dart`의 `WidgetsFlutterBinding.ensureInitialized()` **직후**.
- `PaintingBinding.instance.imageCache.maximumSizeBytes` / `.maximumSize`.
- 유루나비는 `Image.asset`/`SvgPicture.asset` 사용이 **총 6곳뿐**이라 상한을 크게 낮춰도
  실사용 손해가 거의 없다. 근거를 커밋 메시지에 남겨라.

---

## 4. 청크3 — A-2 `didHaveMemoryPressure()` + A-4 백그라운드 캐시 드롭

### 확인하고 시작하라 (추측 금지)

Flutter Android 임베딩이 `Activity.onTrimMemory(level)`을 Dart의
`WidgetsBindingObserver.didHaveMemoryPressure()`로 전달하는 **레벨 조건**을
설치된 SDK 소스에서 직접 확인하라 (`FlutterActivityAndFragmentDelegate` /
`FlutterEngine` / `packages/flutter/lib/src/widgets/binding.dart`).
**조건이 좁으면**(예: 특정 레벨 이상만) `MainActivity.kt`에서 `onTrimMemory`를 직접
오버라이드해 **레벨 값까지** MethodChannel로 넘기는 쪽이 낫다 —
Organic Maps도 레벨을 보고 판단한다(`MwmActivity.java`:
`level >= TRIM_MEMORY_RUNNING_LOW && level != TRIM_MEMORY_UI_HIDDEN`).

### 구현

- `lib/main.dart`에 **앱 레벨 `WidgetsBindingObserver`** 를 새로 만들어 등록하라.
  현재 앱 전체에 옵저버가 `nav_screen.dart:131` 하나뿐이고 그건 화면 로컬이다.
- `didHaveMemoryPressure()` → `imageCache.clear()` + `imageCache.clearLiveImages()`.
  (레퍼런스: Organic Maps `Framework::MemoryWarning()` → `ClearAllCaches()`)
- **A-4**: 라이프사이클 `paused`(백그라운드 진입) 시에도 같은 정리를 수행하라.
  레퍼런스: `Framework::EnterBackground()`가 **무조건** `ClearAllCaches()`를 부른다
  (`libs/map/framework.cpp:1264-1276`).
- ⚠️ **주행 중 백그라운드는 정상 시나리오다**(S3b 플로팅 오버레이). 캐시를 비우는 건
  괜찮지만 **안내 상태·경로·TTS를 건드리면 안 된다.** 이미지 캐시로만 한정하라.
- 무엇을 언제 비웠는지 `debugPrint('YNAV_MEMPRESSURE …')`로 남겨라 — 이건 커밋해도 된다.

---

## 5. 청크4 — A-5 레이어 재설치 가드 리셋 (**회귀 위험 최고, 신중히**)

§3에서 찾고 §10-1-C에서 "결함은 남아 있다"고 판정한 항목. 마스터 승인 났다.

- 위치: `nav_screen.dart:1234-1261`(`_initLocationLayer`), `:1525-1528`(`_initDestLayer` 부근),
  `:1931`(`onMapCreated: (c) => _mlCtrl = c` — **여기가 리셋 지점**).
- **레퍼런스 구현**: Organic Maps `FrontendRenderer::OnContextDestroy()`
  (`libs/drape_frontend/frontend_renderer.cpp:2394-2447`)가 컨텍스트 의존 자원을 해제하면서
  **상태 플래그까지 전부 리셋**한다(`m_needRestoreSize=true`, `m_firstTilesReady=false`,
  `m_finishTexturesInitialization=false`). 같은 계약을 지키면 된다.
- **`main_map_screen.dart`에도 같은 패턴의 가드가 있는지 반드시 확인하라** — 거기도
  `ml.MapLibreMap`(`:1836`)과 `_mlCtrl`(`:175`)이 있다. 이번 조사는 `nav_screen`만 봤다.
- **회귀 테스트 필수**: 이미 있는 라이프사이클 회귀 테스트(커밋 `77b2ce8`)를 돌리고,
  "플랫폼뷰 재생성 시 퍽·핀이 재설치된다"는 케이스를 추가하라.
- 부수 효과: 체크리스트 **S8(주유소 경유지 마커 미표시)의 두 번째 메커니즘**이기도 하다(§3).

---

## 6. 청크5 — A-6 `flutter_map` 제거

**죽은 의존성임을 확정했다**(§12-6). 제거 대상 (전부 확인 완료):

| 대상 | 조치 |
|---|---|
| `pubspec.yaml:16` `flutter_map: ^8.2.2` | 삭제 |
| `lib/services/map_cache_provider.dart` (전체) | **파일 삭제** — `buildCachedTileProvider()` 호출 0건 |
| `main_map_screen.dart:10` `import 'package:flutter_map/flutter_map.dart';` | 삭제 |
| `main_map_screen.dart:174` `final MapController _mapCtrl = MapController();` | **삭제** (생성·dispose 외 사용처 없음) |
| `main_map_screen.dart:334` `_mapCtrl.dispose();` | 삭제 |

- `latlong2`는 **남겨라** — `LatLng`는 그쪽 것이고 실제로 쓰인다.
- ⚠️ **pubspec 변경 후 `flutter clean` + `flutter pub get` 먼저**(CLAUDE.md 주의사항).
  안 하면 네이티브 빌드가 "cannot find symbol"로 깨진다.
- 관련 테스트가 `flutter_map`을 참조하는지 `grep -rn flutter_map test/`로 확인하라.

---

## 7. 청크6 — B-2 GPU 스냅샷 + C-1 Impeller A/B

### B-2

`loop/repro_s1b/sample.sh`가 하는 일(`dumpsys meminfo`의 `Graphics`/`EGL mtrack`/`GL mtrack`)을
**앱 내부화**하라. 그러면 M32 없이도 **마스터 실사용 폰의 실주행에서** 시계열이 남는다 —
§11-6-1이 요구한 "표본 규모 확대"를 실기기 실험 없이 달성하는 유일한 길이다.

- Android `Debug.getMemoryInfo()` / `Debug.MemoryInfo.getMemoryStat(...)`으로 얻을 수 있는지
  먼저 확인하라. 안 되면 `dumpsys` 없이 얻을 수 있는 값만이라도 남겨라.
- 주기는 길게(예: 60초). 진단로그에 `YNAV_GPUMEM ` 접두어로.

### C-1 Impeller off A/B — **커밋하지 마라**

§12-2의 실패모드가 **전부 Impeller 계열**이다. 판별용 APK만 만든다.

1. `android/app/src/main/AndroidManifest.xml`에 임시로
   `<meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />`
   추가 (현재 이 meta-data는 **없다** = 기본값 Impeller 켜짐 — §6에서 확인).
2. release APK 빌드 → **`loop/repro_s1b/` 밖의 산출물 경로에 이름 구분해 보관**.
3. **`git checkout android/app/src/main/AndroidManifest.xml`으로 즉시 원복.**
4. 리포트에 "이 APK는 원인 판별용이며 Impeller off를 해결책으로 채택한 것이 아니다"라고 명시.

⚠️ **끄는 것 자체를 해결책으로 커밋하지 마라** — 마스터 판단 사항이다.

---

## 8. 하지 말 것

- **M32 가상GPS 실주행 재현 실험 전면 금지** (마스터 지시). `adb`로 앱을 띄워 스크린샷을
  반복 캡처·분석하는 루프도 금지 — 이게 세션을 두 번 죽였다.
- **Valhalla 재탐색/rate limit은 이번 세션 범위 밖.** 별도 세션 항목이다
  (§12-7 백로그 1·2번, memory `project-valhalla-rate-limit`).
- Impeller off를 해결책으로 커밋하지 말 것.
- 안내 로직·경로 계산·TTS에 손대지 말 것. 이번 세션은 **자원 관리 축만**이다.

## 9. 산출물

1. 청크별 커밋 (각각 `code-auditor` PASS 후).
2. `loop/MORNING_REPORT_0806_memory_hardening.md` —
   `Goal: X / Met: yes·partial·no — reason` 한 줄 포함. 어느 청크까지 끝냈고 무엇이 남았는지 명시.
3. 못 끝낸 청크는 **이 파일(§1 표)을 갱신**해 다음 세션에 넘길 것.
4. 마스터에게 넘길 것: 다음 실주행에서 확인해야 할 것 한 줄 요약
   (= 진단로그에 `YNAV_NATIVE`/`YNAV_MEMPRESSURE`/`YNAV_GPUMEM`이 남는지, 백화가 재발하는지).

## 10. 빌드 주의

- JDK21 필요. 헤드리스 서버라 `flutter run` 불가 → `flutter build apk --debug`로 컴파일 검증.
- pubspec 변경(청크5) 후에는 `flutter clean` + `flutter pub get` 먼저.
- 릴리스 키와 디버그 키가 달라 **debug APK를 M32에 설치하면 데이터가 지워진다.**
  이번 세션은 기기 설치 자체를 하지 않으므로 해당 없지만, 습관적으로 `adb install` 하지 마라.
