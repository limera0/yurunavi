# RECON 0814 — Flutter/Impeller GPU 렌더링 소실 버그: Organic Maps 레퍼런스 + Flutter/Impeller 엔진 조사

조사일: 2026-08-14. 대상: 8/1·8/14 실주행에서 관찰된 "예외 없이 조용히 사라지는 렌더링"(속도계 숫자·일출일몰바 내부·위치화살표 → 8/14는 전체 블랙스크린) 버그. 목적: 코드 작성 전 두 레퍼런스(Organic Maps 아키텍처, Flutter/Impeller 엔진 실제 API)를 1차 소스로 검증.

방법: `gh` CLI 미인증 상태라 GitHub REST API(`api.github.com`, 비인증 공개 엔드포인트)와 `raw.githubusercontent.com`을 `curl`로 직접 조회, WebFetch/WebSearch로 공식 문서·이슈 스레드 보강. 아래 인용은 전부 실제로 fetch한 내용이며, 파일 경로는 이 조사 시점 organicmaps `master` 커밋 `3655a7033e65c2460150ca9e3fbc07754fe2d10b` 기준.

---

## 1. Organic Maps 실측 아키텍처

기존 프로젝트 메모(코드 주석에도 인용됨, `lib/core/memory/memory_pressure_observer.dart` 상단)의 `Framework::MemoryWarning()` / `Framework::EnterBackground()` 주장은 **사실로 확인됨** — 단, 경로가 바뀌었다(예전 `map/framework.*` → 현재 `libs/map/framework.*`).

### 1.1 Framework 레벨 훅 (`libs/map/framework.hpp:669-671`, `libs/map/framework.cpp:1283-1312`)

```cpp
void Framework::MemoryWarning()
{
  LOG(LINFO, ("MemoryWarning"));
  ClearAllCaches();
  SharedBufferManager::Instance().ClearReserved();
}

void Framework::EnterBackground()
{
  m_usageStats.EnterBackground();
  if (m_drapeEngine) m_drapeEngine->OnEnterBackground();
  SaveViewport();
  m_trafficManager.OnEnterBackground();
  ClearAllCaches();
}

void Framework::EnterForeground()
{
  m_usageStats.EnterForeground();
  if (m_drapeEngine) m_drapeEngine->OnEnterForeground();
  m_trafficManager.OnEnterForeground();
}
```

- 안드로이드 JNI 트리거 확인: `android/sdk/src/main/cpp/app/organicmaps/sdk/Framework.cpp:1809` — `nativeMemoryWarning` → `frm()->MemoryWarning()`. `EnterForeground`도 동일 파일 246행에서 호출.
- **중요한 정정**: `ClearAllCaches()`(`libs/map/framework.cpp:1250-1255`)는 GPU/렌더러 캐시가 아니라 **데이터 레이어 캐시만** 비운다 — `m_featuresFetcher.ClearCaches()`, `m_infoGetter->ClearCaches()`, `GetSearchAPI().ClearCaches()`. 즉 "무조건 캐시를 비운다"는 맞지만, 그 대상은 지도 피처/지오코더/검색 캐시지 GPU 텍스처가 아니다. GPU 쪽 회수는 아래 1.2의 별도 메커니즘이 담당한다.
- `DrapeEngine::OnEnterBackground/OnEnterForeground`(`libs/drape_frontend/drape_engine.cpp:726-750`)는 렌더 스레드로 메시지를 포스트하는데, 실제 `FrontendRenderer::OnEnterBackground`(`libs/drape_frontend/frontend_renderer.cpp:2644-2646`)가 하는 일은 `m_myPositionController->OnEnterBackground()` 호출뿐 — 즉 위치마커 애니메이션을 멈추는 것이지, "GPU 컨텍스트를 명시적으로 버리고 재생성"하는 호출은 이 경로에 없다. Android의 Surface/GL 컨텍스트 생명주기(surfaceDestroyed/Created)는 이 C++ Framework API와는 별개 레이어(플랫폼 코드)에서 처리되는 것으로 보이며, 이번 조사에서 그 안드로이드 쪽 글루 코드까지는 추적하지 않았다(§5 open question).

### 1.2 VulkanMemoryManager — 타입별 예산, 하드캡 아님

`libs/drape/vulkan/vulkan_memory_manager.hpp/.cpp` 확인. 기존 메모의 "Geometry ~80MB, Image ~100MB" 주장은 **정확히 일치**하며, 전체 그림은 다음과 같다(`vulkan_memory_manager.cpp:16-30`):

```cpp
enum class ResourceType : uint8_t { Geometry = 0, Uniform, Storage, Staging, Image };

kMinBlockSizeInBytes = { 1MB(Geometry), 128KB(Uniform), 128KB(Storage), 0(Staging), 0(Image) };
kDesiredSizeInBytes  = { 80MB(Geometry), UINT32_MAX(Uniform, 무제한), UINT32_MAX(Storage, 무제한),
                          20MB(Staging), 100MB(Image) };
```

- 리소스 타입은 5종(Geometry/Uniform/Storage/Staging/Image)이지 2종이 아니다. 그중 실제로 상한이 걸린 건 Geometry(80MB)·Staging(20MB)·Image(100MB) 셋뿐이고, Uniform/Storage는 사실상 무제한이다.
- **동작 방식이 핵심**: 이건 상시 강제되는 하드캡이 아니라 *지연 회수(lazy high-watermark reclaim)*다. `vulkan_memory_manager.cpp:274`, `:316` — 어떤 블록의 할당 카운터가 0으로 돌아올 때(= 화면 밖으로 나간 지도 타일의 렌더 버킷이 정리되는 등 일반적 사용 중 자연 발생), 그 시점 해당 타입의 누적 크기가 `kDesiredSizeInBytes`를 넘으면 그 블록은 즉시 `vkFreeMemory`로 반환되고, 안 넘으면 재사용을 위해 free-list에 보관된다. 즉 예산 집행이 "할당 해제가 일어나는 시점에 얹혀서" 벌어지지, 별도 타이머로 주기적 스윕하는 게 아니다. 백그라운드 진입 시 화면 밖 데이터가 대량으로 풀리면서 이 회수가 몰아서 발생하는 구조로 보인다.
- **이 타입별 예산 시스템은 Vulkan 백엔드 전용**이다. 저장소 전체를 뒤졌지만 OpenGL ES 백엔드용 동급 메모리 매니저 클래스는 발견하지 못했다 — GL 경로는 드라이버 기본 동작과 GLSurfaceView 생명주기에 의존하는 것으로 보인다(App 레벨 타입 예산 없음).

### 1.3 "GPU 텍스처/아틀라스가 백그라운드 후 조용히 재할당 실패" 패턴을 어떻게 피하는가

Organic Maps는 **자체 커스텀 렌더러(Drape)와 자체 폰트/글리프 배칭 시스템**을 쓴다 — Impeller가 아니다. 따라서 "Impeller 아틀라스 실패"라는 정확한 실패 모드 자체가 이 아키텍처에는 존재하지 않는다(발생할 수 있는 표면이 다르다). 이식 가능한 건 코드가 아니라 **설계 태도**다: (a) OS 메모리 경고와 백그라운드 진입 각각에 명시적 훅이 있고 무조건 발동한다, (b) 렌더러가 자기 GPU 할당자를 완전히 소유하고 타입별로 계속 감시하며 회수한다(Flutter/Impeller는 이 두 조건 중 (b)를 앱에 전혀 열어주지 않는다 — §2 참조).

---

## 2. Flutter/Impeller 엔진 실측

### 2.1 flutter/flutter#159578 — 실제로는 이미 고쳐진, 다른 사건

이슈 원문·댓글 6개 전부 확인(`https://github.com/flutter/flutter/issues/159578`).

- 증상: Android에서 화면 off/on(전원버튼)만으로 텍스트 전부 소실, `Break on 'ImpellerValidationBreak' ... Cannot render glyphs without prepared atlas`. 터치/스크롤 한 번이면 복구.
- **레이블: `r: fixed`, 2024-12-02 닫힘.** 리포터(`kthguru`)가 Flutter `3.27.0-1.0.pre.653`에서 문제가 시작됐다고 정확히 bisect했고(2024-11-28), Flutter 엔진팀 `jonahwilliams`가 원인을 엔진 PR `flutter/engine#56798`로 지목하고 **revert를 큐에 넣었다**(2024-11-29 댓글). 즉 이건 특정 시점에 들어왔다 되돌려진 **한정된 리그레션**이었다.
- **YuruNavi는 Flutter 3.44.0을 쓴다** — 이 수정 시점(2024-12)보다 훨씬 뒤 버전이므로, 이 정확한 리그레션이 지금 원인일 가능성은 낮다. 프로젝트 기존 조사가 "가능성 있는 후보"로 이 이슈를 지목한 건 합리적 출발점이었지만, 실제 스레드를 읽어보면 **이미 닫힌, 버전이 다른 사건**임이 확인된다 — 다만 "Could not create valid atlas" 에러 텍스트 자체는 아래처럼 훨씬 넓은 클래스의 실패에 재사용되는 범용 Impeller 검증 메시지다.

### 2.2 "atlas" 에러 텍스트로 검색한 다른 이슈들 — 여러 건이 아직 열려 있음

`flutter/flutter` 저장소에서 정확한 문구로 검색(9건 히트): 열린 것 — `#188904`(컬러 글리프 아틀라스 캡, open), `#183297`(Flame 게임에서 텍스트 반복 스케일 시 아틀라스 오버플로, **P1 open**), `#164605`(글리프 위치 못 찾음, closed as waiting-for-response — 미해결 상태로 방치). 즉 이 에러 문구 자체는 원인 하나를 가리키는 지문이 아니라, 아틀라스 할당이 실패하면 엔진이 찍는 범용 검증 메시지다.

### 2.3 실제 증상과 가장 가깝게 매칭되는, 아직 미해결인 이슈들

**`#178264`** — "Mitigate OOM Crashes by Exposing Impeller GPU Memory Stats and Add a Manual GPU 'Pressure' Hook" (2025-11-10 오픈, **아직 open**, P2, `c: proposal`).
- 리포터가 실측: Dart 쪽 `imageCache.clear()`/`clearLiveImages()`를 호출하고 `maximumSizeBytes`를 낮춰도, 네이티브 GPU 메모리(`adb shell dumpsys meminfo`의 `GL mtrack`)는 전혀 안 줄어든다. Dart 이미지캐시와 실제 GPU 텍스처/렌더타깃 풀은 **완전히 분리된 자원**이라는 걸 실측으로 확인.
- Impeller 팀 리드 `chinmaygarde`의 응답(2025-11-17): Vulkan 백엔드에서는 엔진이 "allocator에 대한 완전한 제어권"을 갖고 있어서 "pressure hook"이 "tractable"하고 "조사해보고 싶다"고 함 — **그러나 이건 아직 제안 단계일 뿐, 마지막 댓글(2026-06-12)까지 구현된 API가 없다.**
- 2026-06-12 댓글(`shreyanshp`)이 `#187905`를 언급하며 남긴 핵심 지적: *"the trigger must be app-callable / CMA-aware, not `onTrimMemory`-only. `onTrimMemory`/lmkd are driven by system-RAM pressure"* — 즉 안드로이드 `onTrimMemory`(YuruNavi의 `MemoryPressureObserver.didHaveMemoryPressure()`가 유일하게 반응하는 신호)는 시스템 전체 RAM 압박에 반응하는 것이지, GPU 드라이버 쪽 자원 고갈과는 다른 신호다 — 아래 참조.

**`#187905`** — "Impeller-Vulkan exhausts kernel CMA pool on Samsung Xclipse (Exynos) → renderer freeze + glyph-atlas corruption" (2026-06-12 오픈, **아직 open**, P2, `c: crash`). **이 조사에서 찾은, YuruNavi 증상과 형태가 가장 가까운 문서화된 사례.**
- 메커니즘: Exynos `sgpu` Vulkan 드라이버가 커널 CMA(연속 메모리 할당자) 풀에서 텍스처/렌더타깃을 뜬다. 지속적 사용(이미지 피드 스크롤) 하에 CMA 풀이 고갈되면 Vulkan 할당이 실패 → **"the renderer freezes / loses its context / renders a corrupted glyph atlas (garbled text)"** — 이때 **시스템 RAM은 충분**(`MemAvailable ~2.6GB`)한데 `CmaFree`만 ~0으로 떨어진다. 리포터는 이걸 "일반 OOM과 구별되는 지문"이라고 명시.
- 실패 시 실제 로그: `E flutter : [ERROR:...impeller/renderer/backend/vulkan/command_buffer_vk.cc(114)] Impeller validation: Failed to end command buffer` 등 — **에러 라인 자체는 찍힌다.** (§3 갭 분석에서 이 점이 YuruNavi의 "로그 완전 무증상"과 어떻게 안 맞는지 짚는다.)
- 확인된 사실: `imageCache.maximumSizeBytes`를 48MB로 고정해도 CMA 고갈에는 아무 효과 없었다("verified") — YuruNavi의 imageCache 캡(40장/20MB)도 원리상 같은 이유로 이 실패 모드엔 무력할 가능성.
- 후속 댓글(`grantreid74`, 2026-07-23): 동일 기기(Galaxy S25 FE/Exynos 2400/Xclipse 940)에서 순정 카운터 앱(Flutter 3.41.9 stable)으로 idle 상태 baseline 측정 — Impeller 기본값 `Graphics 157-162MB` vs `EnableImpeller=false`(Skia)일 때 `Graphics 17.1MB` — **동일 앱, 렌더러만 바꿔서 idle 시점에 약 9배 차이.** Exynos usable CMA 풀(~138MB) 규모와 Impeller idle baseline(~111MB GL)이 이미 근접해 있다는 관찰.
- 관련 이슈 `#160941`(Adreno/Samsung S23, 유사 증상 — 스크롤 중 Vulkan OOM SIGSEGV)도 언급되나 이건 **closed as `r: invalid`/`needs repro info`**(확정 원인 규명 안 됨) — 같은 모양의 불만이 다른 GPU 벤더에서도 나온다는 정황일 뿐, 확증은 아니다.

**`#161861`** — "[Android][Impeller]: Graphics Memory Leak" — **closed, `r: fixed`**(2025-01-24 수정, Impeller Vulkan `BackgroundCommandPoolVK`의 미사용 커맨드버퍼 누수, jonahwilliams가 직접 패치). YuruNavi 3.44.0 시점엔 이미 반영돼 있을 것 — "엔진이 이 영역을 계속 점진적으로 고쳐나가고 있다"는 근거로만 인용.

**`#173937`**(open) — Impeller에서 백그라운드 진입 시 이미지캐시 메모리가 안 풀리다가 포그라운드 복귀 시점에야 한꺼번에 풀리는 "이상한"(리포터 표현) 동작. YuruNavi 증상과 방향은 다르지만("사라짐" vs "안 풀림"), Impeller의 pause/resume 생명주기 처리가 일관되지 않는다는 걸 재확인해주는 근거.

### 2.4 공식 문서·앱 코드에서 실제로 쓸 수 있는 레버

`docs.flutter.dev/perf/impeller` 확인 결과:
- **유일하게 문서화된, 지금 당장 쓸 수 있는 앱 레벨 스위치**: `AndroidManifest.xml`의 `<application>` 태그 아래 `<meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />` (또는 디버그 시 `flutter run --no-enable-impeller`). 이건 튜닝 노브가 아니라 **완전 on/off 스위치**다 — 끄면 Vulkan 경로를 통째로 버리고 레거시 Skia+OpenGL로 폴백한다.
- 리소스 캐시 크기, 아틀라스 크기, 힙 파라미터 등에 대한 **공개 문서화된 튜닝 API는 존재하지 않는다.** (문서가 소스 내 `impeller/README.md`, `docs/engine/impeller/docs/faq.md`를 참조하나 그쪽에도 앱이 호출 가능한 튜닝 API는 없었다.)
- **앱 코드에서 "GPU 컨텍스트/리소스 캐시를 강제로 릴리스하고 지연 재생성"할 방법은 존재하지 않는다.** 이게 정확히 `#178264`가 신규 기능으로 요청 중인 것 자체가 "지금은 없다"는 증거다. YuruNavi 오너가 명시적으로 물은 질문("drop and rebuild the surface 같은 게 있냐")에 대한 답은 **없다** — 엔진이 알아서 self-heal하길 기다리는 수밖에 없고, 그 self-heal도 `#173937`/`#159578`/`#187905`에서 보듯 일관되지 않다(터치 이벤트가 있어야 복구되거나, 프로세스 재시작까지 필요하거나).
- Flutter 3.44보다 나은가: `#178264`, `#187905`, `#173937` 모두 이 조사 시점(2026-08-14) 기준 **여전히 open**이고, `#178264`의 최신 실측 댓글은 **Flutter 3.41.9 stable**로 재현됐다 — 3.44와 가까운 최신 stable에서도 근본 아키텍처(불투명한 GPU 풀, 앱에 노출 안 됨)는 그대로다. 개별 버그(`#161861` 같은 누수)는 시간이 지나며 하나씩 고쳐지지만, "앱이 Impeller GPU 메모리를 보거나 건드릴 수 없다"는 구조적 갭 자체는 아직 안 풀렸다.

---

## 3. 갭 분석 (우선순위순)

1. **[dart-level]** `MemoryPressureObserver`는 Flutter `imageCache`(CPU 비트맵 캐시)만 비운다. `#178264`가 실측으로 증명하듯 이건 실제로 문제되는 GPU 텍스처/렌더타깃 풀과 무관한 자원이다 — 지금 하는 대응이 애초에 원인 자원에 안 닿는다.
2. **[engine-level, 지금은 행동 불가]** Impeller Vulkan 리소스 풀의 크기 조회/상한 지정/강제 회수 API가 앱에 전혀 없다. Organic Maps의 타입별 `VulkanMemoryManager`에 대응하는 게 Flutter 쪽엔 없다 — 이건 YuruNavi 코드로 못 메꾼다, 정확히 `#178264`가 요청 중인 미구현 기능이다.
3. **[unfixable-from-app / 미해결 의문]** "무증상" 자체가 기존 조사와 안 맞는다 — `#187905`가 보여주는 실제 Impeller-Vulkan 아틀라스/컨텍스트 실패는 `E flutter: [ERROR:...Impeller validation...]` 로그 라인을 **찍는다**. YuruNavi의 로그펌프는 Impeller/Vulkan/atlas/glyph 키워드로 grep해도 아무것도 못 찾았다. 이건 (a) 진짜 다른, 아직 보고 안 된 실패 모드이거나 (b) 같은 계열 버그인데 이 기기/버전에서 로깅 경로가 다르거나 (c) 로그펌프 타이밍/버퍼 문제일 수 있다 — 이번 조사로는 못 좁혔다(§5).
4. **[engine-level / unfixable-from-app]** Organic Maps의 진짜 GPU 쪽 규율은 background/foreground 훅 그 자체가 아니라, 렌더러가 자기 GPU 할당자를 소유하고 계속 감시하는 VulkanMemoryManager다. YuruNavi는 렌더러(Impeller)를 소유하지 않으므로 이 설계를 흉내낼 표면 자체가 없다.
5. **[dart-level, 탐색적]** `EnableImpeller=false`(Skia+OpenGL 폴백)는 실제로 존재하고 쓸 수 있는 유일한 "레벨을 바꾸는" 레버다 — 한 실측 댓글에서 동일 idle 앱 기준 Graphics PSS 약 9배 차이(157MB→17MB)가 확인됐다.
6. **[dart-level]** 기존 `GpuMemSampler`(60초 주기, `Debug.MemoryInfo`의 `summary.graphics`/`total-pss`)가 `#187905`가 짚은 CMA(연속 메모리) 고갈을 실제로 감지할 수 있는 지표인지 불확실 — `/proc/meminfo`의 `CmaFree`/`CmaTotal`은 다른 필드다.

## 4. 권고 (구현 스케치 + 리스크/공수/신뢰도)

1. **진단 실험으로 `EnableImpeller=false` 빌드를 만들어 재현 시도.** 스케치: 별도 디버그/스테이징 APK 변형에 매니페스트 한 줄 추가 후 8/14와 비슷한 장시간+백그라운드 조건으로 실주행. 공수: 낮음(1줄+재빌드). 리스크: 실험 자체는 0(별도 빌드) — 그러나 만약 "성공"해서 실제 채택을 고려하게 되면, Impeller의 다른 렌더링 품질/성능 이점을 전부 포기하는 제품 결정이 된다. **이건 엔지니어링 판단이 아니라 오너 판단으로 넘겨야 한다** — 실험 결과만으로 조용히 전환하지 말 것. 재현 여부에 대한 신뢰도: 중간(이슈들이 "OpenGL/Skia 경로가 덜 영향받는다"는 정황은 있지만 면역이라는 증거는 없음).
2. **`#178264` 또는 `#187905`(기기 GPU 벤더 확인 후)에 YuruNavi 실측 데이터로 코멘트/신규 이슈 제출.** 다음 장거리 실주행 중 `adb shell cat /proc/meminfo`(CmaFree/CmaTotal)를 실시간 캡처. 공수: 낮음(데이터 수집 위주). 이건 버그 자체를 고치진 못하지만, 자체 로그가 전무한 상황에서 근본 원인 규명에 가장 신뢰할 수 있는 경로다. 리스크 0, 진단 가치 신뢰도 높음.
3. **`GpuMemSampler`에 `/proc/meminfo`의 `CmaFree`/`CmaTotal` 추가.** `GpuMemBridge.kt`에서 파일 읽어 MethodChannel 페이로드 확장. 공수: 낮음-중간. 리스크 낮음(순수 진단, 동작 변화 없음). 이게 §3-갭3(왜 로그가 무증상인지)에 직접 답할 수 있는 가장 저렴한 방법 — 실제 라이딩 중 CmaFree가 바닥을 친다면 `#187905` 계열 버그라는 강력한 정황증거가 된다(Impeller 검증 에러 라인이 없어도).
4. **"백그라운드→포그라운드 전이마다 무조건 화면/위젯트리 강제 리로드"는 하지 말 것을 권고.** 재현 시도(짧은 백그라운드 2회)가 실패했다는 사실 자체가, 흔한 정상 사용 패턴(전화 옴, 화면 잠금 등)에서 매번 화면을 갈아엎는 비용을 정당화하지 못한다는 신호다. 만약 뭔가 조건부 대응을 넣는다면 "장시간 가동 후 + GPU 텔레메트리 이상 신호가 있을 때만"처럼 좁혀야 한다 — 그런데 이것도 2·3번의 실측 데이터가 나오기 전엔 추측일 뿐이다. **정상 사용 UX vs 희귀 케이스 견고성의 트레이드오프는 오너 판단 영역**이라는 걸 명시적으로 플래그.
5. **Flutter 정식 릴리스 노트를 계속 추적**(가벼운 지속 작업) — Impeller 리드가 pressure hook을 "investigate"하겠다고 했으므로, 향후 릴리스가 이 갭 자체를 없앨 수 있다.

## 5. 미해결 질문

- 왜 YuruNavi 로그는 Impeller/Vulkan/atlas/glyph 키워드에 완전 무반응인가 — 실제 Impeller 아틀라스/컨텍스트 실패(`#187905`)는 에러 라인을 찍는데. 온디바이스 조사 필요(로그펌프 타이밍/버퍼 크기 vs 실패 발생 시점 확인, 혹은 정말 미보고 실패 모드인지).
- 실주행 기기의 정확한 GPU 벤더/드라이버(`ro.product.model`, `ro.hardware.vulkan`, `ro.board.platform`)를 이번 조사에선 확인하지 못했다 — `#187905`는 Exynos/Xclipse 특유의 CMA 메커니즘, `#160941`은 Adreno에서 유사 증상이지만 미확증 상태로 닫힘. 필드기기에서 `adb getprop`으로 확인 필요.
- Organic Maps iOS(Metal 백엔드)의 메모리 관리는 이번 조사에서 다루지 않았다 — 필드 리포트가 전부 Android라 우선순위를 낮췄다. iOS가 문제되면 재조사 필요.
- YuruNavi 기존 `GpuMemSampler`가 읽는 `Debug.MemoryInfo`의 `summary.graphics` 필드가 `#187905`의 CMA 압박과 같은 신호를 반영하는지는 문서/소스로 확정 못 했다 — 실기기 실측 필요.
- Organic Maps 안드로이드 쪽 `MapFragment`/`GLSurfaceView`의 `onPause`/`onResume`이 C++ Framework 메서드 호출 외에 뭔가 더 하는지(YuruNavi의 `didChangeAppLifecycleState`에 대응하는 안드로이드 글루)는 끝까지 추적하지 않았다 — 이미 확보한 C++ 레벨 그림으로 아키텍처적 결론은 충분하다고 판단해 우선순위를 낮췄다.

---

## 인용 소스

- Organic Maps (커밋 `3655a7033e65c2460150ca9e3fbc07754fe2d10b`):
  - https://github.com/organicmaps/organicmaps/blob/3655a7033e65c2460150ca9e3fbc07754fe2d10b/libs/map/framework.hpp#L669-L671
  - https://github.com/organicmaps/organicmaps/blob/3655a7033e65c2460150ca9e3fbc07754fe2d10b/libs/map/framework.cpp#L1250-L1312
  - https://github.com/organicmaps/organicmaps/blob/3655a7033e65c2460150ca9e3fbc07754fe2d10b/libs/drape/vulkan/vulkan_memory_manager.hpp
  - https://github.com/organicmaps/organicmaps/blob/3655a7033e65c2460150ca9e3fbc07754fe2d10b/libs/drape/vulkan/vulkan_memory_manager.cpp#L16-L30
  - https://github.com/organicmaps/organicmaps/blob/3655a7033e65c2460150ca9e3fbc07754fe2d10b/libs/drape_frontend/drape_engine.cpp#L726-L750
  - https://github.com/organicmaps/organicmaps/blob/3655a7033e65c2460150ca9e3fbc07754fe2d10b/libs/drape_frontend/frontend_renderer.cpp#L2644-L2646
  - https://github.com/organicmaps/organicmaps/blob/3655a7033e65c2460150ca9e3fbc07754fe2d10b/android/sdk/src/main/cpp/app/organicmaps/sdk/Framework.cpp#L1809-L1812
- Flutter/Impeller 이슈·문서:
  - https://github.com/flutter/flutter/issues/159578 (closed, r: fixed — 화면 off/on 리그레션, jonahwilliams가 engine#56798 revert로 확정)
  - https://github.com/flutter/flutter/issues/178264 (open — GPU pressure hook 제안, imageCache와 네이티브 GPU 메모리 분리 실측)
  - https://github.com/flutter/flutter/issues/187905 (open — Exynos Xclipse CMA 고갈 → 글리프 아틀라스 손상, 가장 근접한 사례)
  - https://github.com/flutter/flutter/issues/160941 (closed, r: invalid — 유사 증상이나 미확증, Adreno)
  - https://github.com/flutter/flutter/issues/161861 (closed, r: fixed — Vulkan CommandPool 누수)
  - https://github.com/flutter/flutter/issues/173937 (open — 백그라운드 이미지캐시 미회수)
  - https://github.com/flutter/flutter/issues/188904, #183297, #164605 (아틀라스 관련 기타, 일부 open)
  - https://docs.flutter.dev/perf/impeller (공식 문서, EnableImpeller 매니페스트 플래그)

