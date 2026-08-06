# RECON — O1 스타일 에셋 로컬화 설계 (코드 착수 없음, 설계 전용)

- 작성 2026-08-06 · 근거: [RECON_0805_offline_first_architecture.md](RECON_0805_offline_first_architecture.md) §4-2, §7, §8-1
- 대상: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) O1(553행)·O2(555행)
- **이 세션은 설계만 — 코드 착수 없음.** 실제 구현(특히 Android 플러그인 포크)은 별도 세션.

## 0. 최종 결정 방향 (2026-08-06, 마스터 확정)

**§1~§4(초안: 폰트 104.6MB를 다운로드 패키지로 배포)는 폐기.** 더 나은 방법을 찾았다 —
글리프를 서버·다운로드에서 받아오는 대신 **기기에 이미 내장된 시스템 폰트로 한글/한자를
그 자리에서 렌더링**하는 MapLibre 기능(`localIdeographFontFamily`, §5)을 쓴다.
이러면 한글·한자 글리프는 **번들도 다운로드도 필요 없다.**

| 항목 | 결정 |
|---|---|
| iOS | Info.plist `MLNIdeographicFontFamilyName` = **`Apple SD Gothic Neo`** (하드코딩, iOS는 버전 걸쳐 안정적) |
| Android | **시스템 기본 별칭**(`"sans-serif"` 또는 `null`→`DEFAULT_FONT`) 사용, 특정 삼성 폰트명 하드코딩 안 함 — One UI 버전마다 기본 폰트명이 바뀌어서(§5-2) 별칭이 더 안전 |
| 이탤릭 | `localIdeographFontFamily`는 굵기(light/regular/medium/bold)만 반영하고 이탤릭은 무시됨 — **승인, 조치 불필요** |
| 신규 기능 | **설정 화면에 폰트 선택 UI 추가** — 기기에 설치된 폰트 중에서 사용자가 고르게 함 (§6) |
| Android 플러그인 포크 | 이번 세션엔 설계만 반영(§5-3). **착수는 별도 세션** |

---

## 1. 기술 검증 — MapLibre가 실제로 지원하는가

`localIdeographFontFamily`: **'CJK Unified Ideographs'+ 'Hangul Syllables' 레인지를
서버 글리프 대신 로컬 폰트로 즉석 렌더링**하는 MapLibre Native 정식 기능. 우리 문제에
정확히 맞는다.

### 1-1. iOS — 설정 파일 한 줄, 플러그인 패치 불필요

`maplibre-native` iOS(darwin) 소스 실측(`platform/darwin/src/MLNRendererConfiguration.h`):

```
Set `MLNIdeographicFontFamilyName` in your containing application's Info.plist to
font family name(s)... e.g. "PingFang TC"
```

**`ios/Runner/Info.plist`에 키 하나 추가하면 끝.** 렌더링 설정을 앱 번들 레벨에서 읽으므로
Flutter 플러그인(`maplibre_gl`) 코드를 건드릴 필요가 없다 — "빌드할 때 바꾼다"는 요청과
정확히 맞아떨어지는 메커니즘.

### 1-2. Android — 플러그인이 이 옵션을 안 뚫어놨다

`maplibre-native` Android엔 있다(`MapLibreMapOptions.localIdeographFontFamily(String)`,
`android.graphics.Typeface.create()`로 전달). **그런데 우리가 쓰는 Flutter 플러그인
`maplibre_gl 0.26.1`은 이 옵션을 Dart API에도, 내부 Android 네이티브 코드에도 안 뚫어놨다**
(pub cache 소스 직접 확인 — `MapLibreMapBuilder.java`, `MapLibreMapOptionsSink.kt`,
`MapLibreMap` 위젯 생성자 어디에도 `ideograph` 관련 필드 없음).

→ **Android에서 쓰려면 `maplibre_gl` 플러그인을 포크해서 패치해야 한다** — 이미 하고
있는 Valhalla 포크(memory: `reference_valhalla_fork_backup`)와 같은 패턴. 설정 한 줄이
아니라 코드 작업.

### 1-3. 런타임 반영 시점 (Android)

`localIdeographFontFamily`는 `MapLibreMapOptions`에 **MapView 생성 시점에만** 적용되는
값이다(`Style.Builder`에 동등한 런타임 override 없음 — 문서·API 확인). 즉 설정 화면에서
폰트를 바꿔도 **떠 있는 지도에 즉시 반영되지 않고, 지도 화면을 다시 열어야 적용**된다.
실시간 스타일 리로드가 아니라 "다음 진입 시 적용"으로 UX 문구를 잡아야 한다.

## 2. Android 기본값 — 왜 삼성 폰트명을 하드코딩하지 않는가

| One UI 버전 | 기본 폰트 |
|---|---|
| ~5.1 | "Default"(사실상 SamsungOne 계열) |
| 6+ | "One UI Sans"(`OneUISansKR-VF.ttf`, 한글 PostScript명 `SamsungKorean_v2.0`) |

버전마다 정확한 패밀리명이 바뀐다. `Typeface.create()`에 `"sans-serif"`(Android 표준
별칭) 또는 `null`을 넘기면, 삼성이 One UI에서 **이미 이 별칭을 자사 기본 폰트로
치환해둔 시스템 설정**(`/system/etc/fonts.xml` 오버레이)을 그대로 타서 어느 One UI
버전이든 자동으로 삼성 기본 폰트가 잡힌다. 갤럭시 아닌 안드로이드 기기에서도 그
제조사 기본 폰트로 자연 대체되어 하드코딩보다 안전하다.

## 3. 설정 화면 폰트 선택 UI — 실현 가능성 확인

**iOS는 쉽다.** `UIFont.familyNames` — 공식 공개 API로 시스템에 설치된 전체 폰트
패밀리 목록을 그대로 준다. 한글 미지원 폰트(예: Zapfino)를 걸러내려면 Core Text
글리프 커버리지 체크(한글 테스트 문자 하나를 넣어 글리프 존재 여부 확인)를 추가하면 된다.

**Android는 공식 API가 없다.** `Typeface.getSystemFontMap()` 같은 열거 API는 **존재하지
않는다**(AOSP 소스·NDK 문서로 확인 — 한때 `FontManager#getSystemFonts()`가 제안됐다가
공개 API에서 빠졌다). 실무에서 쓰는 유일한 우회로는:

- `/system/etc/fonts.xml` 파싱 — 비공식, AOSP 소스 자체가 "포맷이 곧 바뀔 수 있다"고
  경고하는 파일. OEM·Android 버전마다 형식이 다를 수 있어 파싱이 깨질 위험 있음
- `Paint.hasGlyph(String)`(API 23+) — 후보 폰트가 실제로 한글 글리프를 갖는지 검사하는
  공식 API. 열거는 못 해도 **필터링(안전망)**은 이걸로 확실히 가능

**권고**: Android는 `fonts.xml` 파싱으로 후보 목록을 뽑고, `Paint.hasGlyph("한")`으로
한글 렌더 가능한 것만 걸러 사용자에게 보여준다. 파싱 실패 시(포맷 변경 등) **"시스템
기본"만 있는 목록으로 조용히 폴백** — 폰트 선택 기능이 아예 죽지 않게. 진짜 "기기에
설치된 모든 폰트"가 아니라 "시스템이 등록해둔 폰트 중 한글 지원되는 것들"에 가깝다는
점은 감안해야 한다(서드파티 폰트 앱으로 깐 폰트까지 잡힌다는 보장은 없음).

> 이 Android 우회 경로 자체가 위 §1-2의 플러그인 포크와 맞물린다 — 사용자가 고른
> 폰트명을 실제로 지도에 반영하려면 결국 포크된 플러그인의 `localIdeographFontFamily`
> 경로로 흘려보내야 한다.

## 4. 남은 결정/확인 사항

- [ ] Android 폰트 목록 UI의 "설치된 폰트 전체"가 아니라 "한글 지원되는 시스템 등록
      폰트"로 범위가 좁혀진다는 점 — 사용자 기대와 다를 수 있어 UI 문구로 명시 필요
      (예: "한글을 지원하는 폰트만 표시됩니다")
- [ ] 폰트 변경이 "다음 지도 화면 진입 시 적용"이라는 제약을 설정 화면에 어떻게
      안내할지 (즉시 미리보기 없음)
- [ ] `maplibre_gl` 포크 착수 시점 — 별도 세션으로 확정, 이번엔 스킵
- [ ] (참고, 낮은 우선순위) `/data/tiles/fonts`의 서버측 `Noto Sans CJK TC Regular`(31MB,
      우리 스타일 미참조 확인됨 — §부록)와 기존 4개 폰트스택 자체는, 로컬 렌더링으로
      전환하면 **서버·앱 양쪽에서 다운로드/번들 경로 자체가 없어지므로** 자연히 무관해짐.
      서버 파일 정리 여부는 별도 확인(운영 중인 공개 서버라 이번 범위 밖)

---

## 부록 — 폐기된 초안 (다운로드 패키지 방식, 2026-08-06 오전)

로컬 렌더링(§0~§4)으로 대체되기 전 실측한 내용. 참고용으로만 남긴다.

### A-1. 서버 폰트 자산 실측

`/data/tiles/fonts`: `Noto Sans Regular` 34.6MB · `Bold` 35.4MB · `Italic` 34.6MB ·
`CJK TC Regular` 31.4MB(181/256 range만 채워짐, 스타일 미참조 확인 — 죽은 자원).
스프라이트 4파일 합계 ~116KB.

### A-2. APK 정적 동봉이 부적합했던 이유

release APK 실측 90MB. 폰트 3종(104.6MB)을 정적 asset으로 넣으면 195MB로 2배 이상 —
오프라인을 안 쓰는 사용자까지 전원 부담. 이 문제 자체가 로컬 렌더링 방식으로 완전히
사라졌다(번들도 다운로드도 필요 없음).
