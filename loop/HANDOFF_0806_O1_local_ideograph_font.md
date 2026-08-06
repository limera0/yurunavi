GOAL: O1(스타일 에셋 로컬화)을 localIdeographFontFamily 방식으로 구현한다 — iOS는 Info.plist 설정 한 줄, Android는 maplibre_gl 플러그인을 포크해 옵션을 노출하고, 설정 화면에 기기 폰트 선택 UI를 추가한다.

# HANDOFF — O1 · 스타일 에셋 로컬화 (localIdeographFontFamily)

- 작성 2026-08-06 · 브랜치 `verify/ride-0711` · HEAD `8d99aa8`
- 선행: 없음(코드상 독립). O2(타일 오프라인)와 순서 의존은 사라졌다 — 이번 설계 전환으로
  O1이 폰트 다운로드에 의존하지 않게 됐기 때문(구 RECON_0805 §7 표의 "O1→O2" 순서는 폐기된
  다운로드 방식 기준이었음).
- 근거(필독): [RECON_0806_O1_asset_localization_design.md](RECON_0806_O1_asset_localization_design.md)
  — **§0 "최종 결정 방향"부터 읽을 것.** §부록은 폐기된 초안(다운로드 패키지 방식)이니
  참고만 하고 그 방향으로 구현하지 마라.
- 대장: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) O1(553행 근처)
- 마스터 결정 원문(2026-08-06):
  - iOS: `Info.plist` `MLNIdeographicFontFamilyName` = **`Apple SD Gothic Neo`**
  - Android: 특정 삼성 폰트명 하드코딩 금지, **시스템 기본 별칭**(`"sans-serif"`/`null`) 사용
  - 이탤릭이 로컬 렌더링에서 무시되는 것 — **승인, 조치 불필요**
  - **신규**: 설정 화면에 "기기에 설치된 폰트 중에서 선택" UI 추가
  - Android `maplibre_gl` 플러그인 포크 — 이번 세션이 그 "별도 세션"이다, 착수해도 됨

---

## 0. 착수 전 확정된 사실 (다시 조사하지 마라)

### 0-A. 기술 검증 완료 (RECON §1)

- MapLibre Native `localIdeographFontFamily`는 'CJK Unified Ideographs' + 'Hangul
  Syllables' 레인지를 서버 글리프 대신 로컬 폰트로 렌더링하는 정식 기능. 확인 완료.
- **iOS**: `platform/darwin/src/MLNRendererConfiguration.h`(maplibre-native 소스 직접
  확인)에 `MLNIdeographicFontFamilyName` Info.plist 키로 노출됨. **`ios/Runner/Info.plist`에
  문자열 값 추가만 하면 끝 — `maplibre_gl` 플러그인 코드 수정 불필요.**
- **Android**: `maplibre-native` 자체엔 `MapLibreMapOptions.localIdeographFontFamily(String)`가
  있지만, 이 프로젝트가 쓰는 `maplibre_gl 0.26.1`(pub.dev) 플러그인은 Dart API에도 내부
  Android 네이티브 코드(`MapLibreMapBuilder.java` 등)에도 **이 옵션을 노출 안 함** —
  pub-cache 소스 직접 grep으로 확인됨. **포크 패치가 필요하다.**
- Android에서 `localIdeographFontFamily`는 `MapLibreMapOptions` **생성 시점에만** 적용됨
  (`Style.Builder` 레벨 런타임 override 없음, 문서·API로 확인). 즉 설정에서 폰트를
  바꿔도 떠 있는 지도엔 즉시 반영 안 되고 **지도 화면을 다시 열어야 적용**된다.
  실시간 미리보기를 만들려 하지 마라 — 안 되는 게 정상이다.

### 0-B. Android 폰트 열거 제약 (다시 조사하지 마라 — 결론 났다)

- `Typeface.getSystemFontMap()` 같은 공식 열거 API는 **존재하지 않는다**(AOSP 소스 확인).
- 유일한 실무 경로: `/system/etc/fonts.xml` 파싱(**비공식** — AOSP 자체가 포맷이 바뀔
  수 있다고 경고하는 파일) + `Paint.hasGlyph("한")`(API 23+, **공식**)으로 한글 지원
  여부 필터링.
- 파싱 실패 시 **"시스템 기본"만 있는 목록으로 조용히 폴백** — 폰트 선택 기능 자체가
  죽으면 안 된다.
- 이 경로로는 "기기에 설치된 모든 폰트"가 아니라 "시스템에 등록된 폰트 중 한글 지원되는
  것들"만 잡힌다(서드파티 폰트 앱으로 깐 것까지 잡힌다는 보장 없음). **설정 화면 UI
  문구에 이 한계를 명시할 것** — 예: "한글을 지원하는 폰트만 표시됩니다".

### 0-C. iOS 폰트 열거는 쉽다

`UIFont.familyNames`(공식 API)로 전체 패밀리 열거. 한글 미지원 폰트(Zapfino 등) 제외는
Core Text 글리프 커버리지 체크(한글 테스트 문자 하나 넣어 글리프 존재 확인)로 필터링.

---

## 1. 작업 범위

### 청크1 · iOS Info.plist 설정 (리스크 최소, 먼저 착수 권장)

- [ ] `ios/Runner/Info.plist`에 `MLNIdeographicFontFamilyName` = `Apple SD Gothic Neo` 추가
- [ ] 실기기 또는 시뮬레이터에서 지도 화면 한글 지명 라벨이 정상 렌더되는지 확인

### 청크2 · Android `maplibre_gl` 플러그인 포크 + 옵션 노출

- [ ] GitHub에 포크 생성 — Valhalla 포크와 동일 패턴(memory: `reference_valhalla_fork_backup`,
      오프사이트 백업 위치 관례 재사용)
- [ ] `android/src/main/java/org/maplibre/maplibregl/MapLibreMapBuilder.java`(또는 실제
      맵뷰 생성 경로)에서 `MapLibreMapOptions.Builder`에 `.localIdeographFontFamily(값)`
      호출 추가
- [ ] Dart `MapLibreMap` 위젯에 옵션 파라미터 추가(예: `localIdeographFontFamily: String?`)
      → 플랫폼 채널로 전달 → 위 네이티브 코드가 수신
- [ ] 기본값 `"sans-serif"`(또는 `null`) — **삼성 폰트명 하드코딩 금지**(RECON §2 근거:
      One UI 버전마다 정확한 패밀리명이 바뀜)
- [ ] `pubspec.yaml`을 이 포크의 git 의존성으로 전환

### 청크3 · 설정 화면 폰트 선택 UI

- [ ] 설정 화면(`lib/features/settings/presentation/`, `providers/`)에 항목 추가
- [ ] iOS: `UIFont.familyNames` → Core Text 글리프 체크로 한글 지원 폰트만 필터링 → 목록
- [ ] Android: `fonts.xml` 파싱 → `Paint.hasGlyph` 필터링 → 목록(실패 시 "시스템 기본"만)
- [ ] 선택값 저장 — `shared_prefs`(memory: `feedback_prefer_simple_reuse` — 새 의존성
      추가하지 말고 기존 패턴 재사용)
- [ ] 선택값을 청크2에서 추가한 `localIdeographFontFamily` 파라미터로 지도 화면에 전달
- [ ] UI 문구 2개 필수: "한글을 지원하는 폰트만 표시됩니다" / "변경 사항은 지도 화면을
      다시 열 때 적용됩니다"(즉시 미리보기 없음, 0-A 참고)

## 2. 검증

- [ ] iOS 실기기: 한글 지명 라벨 정상 렌더, `Apple SD Gothic Neo`로 보이는지 육안 확인
- [ ] Android 실기기(갤럭시 우선): `sans-serif` 별칭 사용 시 One UI 기본 폰트로 한글
      렌더되는지 확인
- [ ] 설정에서 폰트 변경 → 지도 화면 재진입 → 변경 반영 확인
- [ ] `flutter analyze` 이슈 0 · `flutter test` 전건 통과
- [ ] code-auditor PASS

## 3. 미결정/유의 사항

- Android 폰트 목록이 "설치된 폰트 전체"가 아니라는 한계는 §0-B에 이미 결론 났다 —
  다시 "진짜 전체 목록 가능한지" 조사하지 말 것.
- 서버 `/data/tiles/fonts`의 `Noto Sans CJK TC Regular`(31MB, 우리 스타일 미참조 죽은
  자원) 정리 여부는 **이번 스코프 밖**(운영 중인 공개 서버 파일이라 별도 확인 필요).
- 청크1~3은 서로 연결된 하나의 기능이라 억지로 쪼개면 어중간해질 수 있다(CLAUDE.md
  "세션당 1모듈" 원칙과 다소 긴장 관계). 스코프가 크다고 판단되면 **청크1(iOS)만 먼저
  끝내고 체크포인트 커밋 후 청크2·3으로 이어가는 것**을 권장 — 오케스트레이터 판단.
