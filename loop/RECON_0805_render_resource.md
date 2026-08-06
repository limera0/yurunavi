# RECON — S1b · 렌더링 자원 고갈 / 백화 (조사 중간 기록)

- 작성 2026-08-05 · 브랜치 `verify/ride-0711` · 조사 시점 HEAD `71380de`→`bb7c4df`(동시 세션 진행 중)
- 지시서: [HANDOFF_0805_S1b_render_resource.md](HANDOFF_0805_S1b_render_resource.md)
- 대장: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) S1b
- 증거물: `loop/testride_result/Screenshot_20260801_062518_Yurunavi.jpg`
- 산출 도구: `loop/repro_s1b/detect_whiteout.py` (자동 판정기)

> **표기 규칙.** 이 문서는 **[관측]** 과 **[추론]** 을 분리한다.
> 지시서 §5-4 요구사항이며, 이 건은 이미 한 번 "확정"이 뒤집힌 이력이 있다.

---

## 0. 세션 시작 시점 상태 확인 (지시서 요구)

`git log` 확인 결과 **S2는 이미 완료 커밋됨** — `0269487`(지시서) → `49643df`(구현)
→ `72187ef`(체크리스트) → `71380de`(감사 반영) → `bb7c4df`(감사 PASS 기록).
지시서에 적힌 "다음은 S1b → S2" 순서는 실제와 어긋났고, S2가 먼저 나갔다.

따라서 지시서 **§2-3의 "S2가 아직 안 됐으면 타일 캐시를 여기서 같이 재라"는 해당 없음.**
단, S2 보고서는 "1.65GB 실측 배분은 실기기 계측 항목이라 범위 밖"으로 남겼으므로
**타일 캐시 실측은 여전히 미측정 상태**다(§6 다음 할 일에 넣었다).

---

## 1. [관측] 증거 스크린샷 정밀 실측 — 마스터 판정 재확인 + 자동화

`detect_whiteout.py`를 증거물에 돌린 결과:

```
속도계 껍데기(주황 링)  : 있음   (max_chroma=118)
속도계 내용물(숫자)     : 없음   (ink=0.0000, min_lum=254.3)
일출일몰 내용물         : 없음   (ink=0.0044, max_chroma=61)
내 위치 화살표          : 없음   (arrow_puck 파랑 27px < 임계 300)
=> 백화 판정: YES
```

일출일몰 바 내부를 40px 간격 행 주사한 결과 **전 구간 (253,253,251) ± 최대 chroma 5**.
게이지 막대(`0xFFFFF59D`, chroma 98)가 있었다면 절대 안 나오는 값이다 —
**게이지 막대까지 진짜로 없다**는 지시서 §1-B의 관측을 독립 확인했다.

알약 배경도 계산과 일치한다: `Colors.white.withValues(alpha:0.95)`를 지도 배경
(241,237,233) 위에 합성하면 254.3 — 실측 253~254. **알약 자체는 정상 렌더 중이다.**

### 1-A. [관측·신규] 레이아웃은 100% 정상이었다 → **페인트 단계 손실이다**

속도계 주황 링의 실측 기하와 `nav_screen.dart` 레이아웃 상수를 대조했다.

| 항목 | 실측(px) | 코드 계산값(density 450 기준) |
|---|---|---|
| 링 중심 x | 157 | `(12+44)×2.8125` = **157.5** |
| 링 중심 y | 825 | `(2340/2.8125×0.30+44)×2.8125` = **825.8** |
| 링 반지름 | 130.5 | `44×2.8125` = 123.75 → `×1.06`(펄스 상한) = **131.2** |
| 알약 좌/우 x | 34 / 139 | `12×2.8125`=33.8 / `50×2.8125`=**140.6** |

**전 항목 오차 1px 이내로 일치한다.** 즉 캡처 시점에 위젯들은
**정상 전체 크기로, 정확한 위치에 레이아웃되어 있었다.**

이것이 이번 세션의 가장 중요한 신규 사실이다. 다음이 **전부 배제된다**:

- PIP 축소 지오메트리에서 찍힌 화면이 아니다 (그랬으면 `H*0.30`이 작아진다)
- `RenderFlex` overflow / 제약 붕괴가 아니다 (알약 높이 286논리px, 임계 118의 2.4배)
- `SizedBox.shrink()` 경로가 아니다 (껍데기가 풀사이즈로 그려져 있다)
- ErrorWidget이 아니다 (마스터 실측대로 순백 vs 회색 196)

→ **레이아웃은 성공했고 페인트만 유실됐다.**

### 1-B. [관측·정정] "파란 원만 남고 화살표 소실"은 사실이 아니다

좌측 가장자리 파란 원의 실측색은 **(1,68,217)**.
`arrow_puck.png`의 단색 파랑은 **(45,125,246)** — 전혀 다르다.
그 원은 `poi_icon_renderer.dart` `_drawDotBase`의 시그니처(단색 채움 + 2px 안쪽
흰 링)를 그대로 갖고 있어 **POI/미리보기 마커 계열**이다.

→ 지시서 §1-B의 *"파란 원만 남고 방향 화살표 스프라이트 소실"* 이라는 서술은
**픽셀 증거로 지지되지 않는다. 위치 퍽은 통째로 없다.**
(스프라이트 부분 손실이 아니라 **레이어 자체의 부재**로 봐야 한다 — §3 참조.)

### 1-C. [관측·신규] 캡처 순간 앱은 `resumed`가 아니었다

우측 버튼 컬럼을 `loop/layout_fixes/7_navigation_layout.png`(확정 레이아웃:
주유소→나침반→현위치→줌인→줌아웃)와 대조하면, 스크린샷의 반투명 회색 세로 패널
(상단 `•••` + 하단 블루투스 토글)은 **앱 UI가 아니다.** 화면 오른쪽 가장자리에
붙어 주유소·나침반 버튼을 덮고 있는 **시스템 오버레이(엣지 패널류)** 다.

→ **백화가 찍힌 그 순간, 앱 위에 시스템 패널이 열려 있었다.**
마스터의 "알림바를 잠깐 스와이프한 것만으로도 화살표가 없어졌다"는 증언과 같은 계열이다.

---

## 2. [관측] 프로덕션 로그 — 백화는 라이프사이클 이벤트에 붙어 있다

`loop/testride_result/log/ynav_2026-08-02T08-05-18.log` (95,459줄, 3시간 51분 주행).
`MissingPluginException` **567건**이 정확히 **두 구간에만** 몰려 있다.

```
09:21:52.971  YNAV_LIFECYCLE state=inactive
09:21:53.019  YNAV_PIP enter ok
09:21:55.197  MissingPluginException(source#setGeoJson … maplibre_gl_2)   ← 이후 초당 4건
09:21:56.859  YNAV_LIFECYCLE state=resumed

10:12:43.428  YNAV_LIFECYCLE state=inactive
10:12:43.465  YNAV_PIP enter ok
10:12:45.640  MissingPluginException(… maplibre_gl_4)  ← 2분16초간 초당 4건 = 559건
10:14:59.529  YNAV_LIFECYCLE state=resumed
```

- 메서드 내역: `source#setGeoJson` 431건 + `camera#move` 136건
- **채널 ID가 `maplibre_gl_2` → `maplibre_gl_4`로 바뀌었다.**
  이 접미사는 플랫폼뷰 인스턴스 ID다. **[관측]** 지도 플랫폼뷰가 파괴되고
  **다른 ID로 재생성되고 있다.**
- 로그 전체에서 `inactive` 4건 / `PIP enter ok` 2건 / `resumed` 2건 — 전부 이 두 구간.

### 2-A. [관측] `camera#move` 실패 = 카메라 추종 정지

증거 스크린샷에서 위치 마커가 **화면 왼쪽 가장자리에 반쯤 걸려 있는데**
(§1-B의 파란 원이 아니라 지도 자체가 사용자 위치를 벗어난 상태),
`camera#move`가 죽어 있었다면 정확히 그렇게 된다. 정합적이다.

---

## 3. [추론·강함] 코드 결함 — 일회성 가드가 플랫폼뷰 재생성을 영구화한다

`nav_screen.dart` `_onStyleLoaded()`는 스타일이 로드될 때마다 호출된다.
그 안에서 재설치되는 것과 안 되는 것이 갈린다:

| 대상 | 가드 | 재생성 시 |
|---|---|---|
| `_initRouteLayer()` | **없음** | 다시 추가됨 ✅ |
| `addImage` 4종 + POI 아이콘 5종 | 없음 | 다시 등록됨 ✅ |
| `_initPoiLayer()` | **없음** | 다시 추가됨 ✅ |
| `_initDestLayer()` | `_destLayerReady` (한 번 true → **리셋 없음**) | **영영 안 돌아옴** ❌ |
| `_initLocationLayer()` | `_locLayerReady` (한 번 true → **리셋 없음**) | **영영 안 돌아옴** ❌ |

```dart
// nav_screen.dart:1258  (_initLocationLayer)
if (ctrl == null || _locLayerReady) return;   // ← 새 맵에서도 즉시 return
```

`onMapCreated: (c) => _mlCtrl = c` — 컨트롤러만 갈아끼우고 **플래그는 그대로다.**

**이 표가 증거 스크린샷의 지도 상태와 정확히 일치한다:**
경로선 ✅ · POI 마커 ✅ · 도로 라벨 ✅ · **위치 퍽 ❌ · 목적지/경유지 핀 ❌**

→ **[추론]** 위치 화살표 소실의 직접 원인은 "스프라이트 텍스처 유실"이 아니라
**플랫폼뷰/스타일 재생성 후 일회성 가드 때문에 심볼 레이어가 재설치되지 않는 것**이다.
(아직 실기기에서 이 경로를 직접 계측해 확정하지는 못했다 — §5 참조.)

> 부수 소득: 이 결함은 체크리스트 **S8의 "주유소 경유지 마커 미표시"** 에 대한
> **두 번째 독립 메커니즘**이다. S8은 `_liveWaypoints`만 원인으로 적고 있다.

---

## 4. [관측] 실기기 재현 성공 — 알림창 한 번으로 동일 시그니처

### 4-A. 환경

- 기기: **SM-M325F(갤럭시 M32) · Android 13 · RAM 3.7GB · 1080×2400 · density 450**
  ⚠️ **A34가 아니다.** 이 서버에 물려 있는 건 M32(vGPS 상용 검증기)다.
  다만 증거 스크린샷의 A34도 **density 450**으로 확인돼(§1-A 기하 일치)
  레이아웃 계산은 두 기기가 동일하다. 저사양 조건은 오히려 M32가 목표에 가깝다.
- 빌드: **현 HEAD 릴리스 빌드(S1+S2 적용)** 를 기존 1.0.1 위에 `adb install -r`
  (릴리스 키 동일, **앱 데이터 보존**). 권한은 `pm grant`로 부여.
- GPS: `gpsinjector` 3-provider 모킹 + `bgnav_route.csv`(365pt/약 6분)
- 내비 시작: adb 탭/스와이프로 UI 조작 (릴리스라 E2E 인텐트 하네스는 `kDebugMode` 게이트로 비활성)

### 4-B. 결과

**베이스라인(내비 정상 주행 중)**
```
속도계 내용물 있음(ink 0.145) · 일출일몰 있음(ink 0.296) · 화살표 있음(파랑 2426px)
=> 백화 판정: no
```
화살표 2426px는 `arrow_puck.png`의 불투명 파랑 픽셀수 2494와 거의 일치 — **판정기 교차검증 완료.**

**T1 · `adb shell cmd statusbar expand-notifications` (알림창 내리기) 만 실행**
```
05:10:35.359  YNAV_LIFECYCLE state=inactive
05:10:35.541  YNAV_PIP enter ok
05:10:40.239  MissingPluginException(source#setGeoJson … maplibre_gl_1)
05:10:40.254  MissingPluginException(camera#move … maplibre_gl_1)
05:11:43.009  … suppressed=39   (S1의 크래시 억제 정상 동작 확인)
```

→ **[관측] 알림창을 내린 것만으로 프로덕션 로그와 완전히 동일한 시그니처가 재현됐다.**
마스터 증언("알림바 스와이프만으로도")이 **결정론적·스크립트 가능한 재현**이 됐다.

**T2 · PIP에서 복귀 후 재측정**
```
속도계 내용물 있음 · 일출일몰 있음 · 화살표 있음(파랑 9230px)
=> 백화 판정: no
```

→ **[관측] PIP 1회 왕복만으로는 영구 백화가 남지 않았다.**
이 1회 시행에서는 복귀 시 전부 되돌아왔다. **§3의 추론이 이 경로에서
곧바로 관측되지는 않았다** — 반복/장시간/메모리압박 축이 더 필요하다.
(화살표 픽셀이 2426→9230으로 늘어난 것은 미해명 — 퍽이 중복 설치됐거나
줌·마커 구성이 달라졌을 수 있다. **다음 세션에서 확인할 것.**)

---

## 5. 현재 판정

| 증상 | 상태 |
|---|---|
| 지도 위치 퍽/핀 소실 | **원인 후보 확정적 수준(§3) — 실기 계측으로 최종 확인 남음** |
| 라이프사이클 트리거 | **확정 — 알림창/엣지패널 → `inactive` → PIP → 플랫폼뷰 파괴** |
| 속도계 숫자·일출일몰 내용물 소실 | **미확정.** 페인트 단계 손실이라는 것까지만 확정(§1-A) |

**속도계·일출일몰 쪽이 왜 안 그려지는지는 아직 모른다.** 다음이 배제됐다:
레이아웃/제약 실패, ErrorWidget, 색상 문제, PIP 지오메트리.
단순 "글꼴 아틀라스 고갈" 가설도 잘 안 맞는다 — 같은 프레임에서 우측 버튼의
`Icons.add`/`Icons.remove`(같은 MaterialIcons 폰트)와 상·하단 카드 텍스트는
**정상 렌더**됐다. 게이지 막대는 글리프도 아니다.

**추측하지 않고 여기서 멈춘다** (CLAUDE.md: *If unsure, STOP and write it in the report*).

---

## 6. 지시서 §2-2 사실 확인 (추측 금지 항목)

- `io.flutter.embedding.android.EnableImpeller`는 **Flutter 3.44에서도 여전히 읽힌다**
  — `packages/flutter_tools/lib/src/project.dart:1038-1044`, 기본값 `true`.
  → **Impeller on/off A/B는 지금도 가능하다.**
- `AndroidManifest.xml`에 Impeller 관련 meta-data **없음** → 기본값(Impeller 켜짐).
- `configChanges`에 `screenSize|smallestScreenSize|screenLayout|orientation|density|uiMode`가
  들어 있어 **PIP 전환으로 Activity가 재생성되지는 않는다.**
  로그에서 Dart 상태(`_locLayerReady` 등)와 로깅이 연속인 것과 정합.
  → **즉 플랫폼뷰만 따로 파괴·재생성되고 있다.**

---

## 7. 산출물

- `loop/repro_s1b/detect_whiteout.py` — 스크린샷 1장 → 3요소 자동 판정.
  ROI를 `nav_screen.dart` 레이아웃 상수에서 역산하므로 **기기 독립**.
  ```
  python3 loop/repro_s1b/detect_whiteout.py shot.png --screen 1080x2400 --density 450
  ```
  증거 스크린샷(A34)·실기기 베이스라인(M32) 양쪽에서 교차검증 완료.

---

## 8. 다음 세션이 할 일 (우선순위 순)

1. **PIP 왕복 반복 N회**(5/10/20) + 매회 자동 판정 — 몇 회째에 영구화되는가
2. **PIP 체류 시간 연장**(프로덕션 실측 2분16초 이상)
3. **메모리 압박 축 추가** — `am send-trim-memory`, 백그라운드 앱 다수
4. **§3 직접 계측** — `onMapCreated`/`_onStyleLoaded`에 임시 `debugPrint`로
   컨트롤러 교체 시점과 `_locLayerReady` 값을 찍어 가드 가설을 확정/반증
   (조사용 임시 로깅. **수정 커밋 금지**)
5. **속도계·일출일몰 축** — PIP 전/중/후 1초 간격 연속 캡처 + `dumpsys gfxinfo`·`meminfo`
6. **Impeller A/B** — 재현이 안정된 뒤에
7. **타일 캐시 1.65GB 실측** — S2가 범위 밖으로 남긴 항목, 실기기가 붙은 김에

---

## 9. 미확정으로 남긴 것 (지시서 §4)

**"재탐색하며 코스가 마구 엉킴"은 여전히 어느 쪽인지 모른다.**
이번 세션에서 이 축은 관측하지 못했다. 단정하지 말 것.

---

## 10. (2026-08-06 이어받기 세션) 전제 붕괴 — S3b가 트리거 메커니즘 자체를 폐기했다

지시서: [HANDOFF_0806_S1b_continue.md](HANDOFF_0806_S1b_continue.md)

### 10-0. [관측] 세션 시작 시 기기에 설치된 빌드가 S3b 이전이었다

기기(`lastUpdateTime=2026-08-05 20:40:23`)는 §1~9의 조사 대상이던 **구 PIP 경로 빌드**였다.
그런데 `git log`상 오늘(2026-08-06) `2ffd233`/`7e68a72` 커밋으로 **시스템 PIP를 완전히
폐기하고 `SYSTEM_ALERT_WINDOW` 플로팅 오버레이로 교체**하는 S3b가 이미 병합돼 있었다.
**[정정, 마스터 확인]** 이건 이 조사와 "동시 진행"이 아니었다 — 이전 세션이 ECONNRESET로
끊긴 사이 **별도 세션이 진행한 작업**이다([MORNING_REPORT_0806_S3b_floating_and_notif.md](MORNING_REPORT_0806_S3b_floating_and_notif.md)).
§1~9의 관측·추론은 **여전히 유효한 역사적 기록**이지만, **현재 HEAD의 실제 동작을
더 이상 대표하지 않는다.**

결정적으로 `nav_screen.dart:449-467`의 `didChangeAppLifecycleState`에 이런 주석이 있다:

```dart
/// ⚠️ inactive에는 절대 반응하지 않는다 — S3 청크1에서 근원 차단한
/// "알림창 내림·스크린샷으로 오검출" 문제가 여기서 재도입되면 안 됨.
```

§4의 재현 절차(`cmd statusbar expand-notifications`)가 정확히 이 "오검출"이다.
**이 세션이 지금까지 반복 재현해 온 트리거 자체가 이미 알려진 버그로 취급되어
S3에서 고쳐진 것**이다. → 현 HEAD로 재빌드해 재검증이 필요하다고 판단, 진행했다.

### 10-1. [관측] 현 HEAD 재빌드 + 재검증 (JDK21, 데이터 보존 설치)

`onMapCreated`/`_onStyleLoaded`/`_initLocationLayer`에 임시 `debugPrint`(`YNAV_MAPDBG`)를
추가해 release 재빌드 → `adb install -r`(데이터 보존 확인: `firstInstallTime` 불변) →
검증 후 **원상복구하고 로깅 없는 클린 release로 재빌드·재설치**까지 완료했다
(기기가 마스터 실사용 폰이므로 조사 흔적을 남기지 않았다).

**10-1-A. 노티피케이션 트리거(구 버그) — 현재 완전 무반응**

`expand-notifications`+`collapse` 실행 후 `YNAV_MAPDBG` 로그 **0건**. S3의
"라이프사이클 오검출 근원 제거"가 실기기에서 확인됐다.

**10-1-B. 실제 트리거(HOME 키 → paused/hidden → 오버레이 표시 → 아이콘 1탭 복귀) — 16회 전부 무결함**

- 단발 검증 1회 + `loop/repro_s1b/real_trigger_repeat.sh`로 15회 반복(dwell 3초) +
  별도로 2분 20초 장기 체류 1회 = **총 17회 왕복, 전부 백화 없음.**
- `onMapCreated`는 **최초 진입 시 1회만 호출되고 이후 단 한 번도 재호출되지 않았다**
  (17회 왕복 전체에서 로그 1건). `MissingPluginException` **0건.**
- 위치 퍽 픽셀수는 라운드마다 2452~2494px로 안정적 유지(§4-B에서 봤던 2426→9230
  같은 튀는 현상도 없었음 — 그 현상 자체가 플랫폼뷰 재생성의 부산물이었다는 정황).
- 오버레이 반환 탭 좌표는 최초 계산(그래비티 기준 역산)이 실제 프레임과 21px 정도
  달라 실패했다 — `dumpsys window windows`로 실측한 `frame=[833,1838][1035,2040]`
  (중심 934,1939)을 써야 한다. 이 기기엔 SYSTEM_ALERT_WINDOW를 쓰는 다른 앱
  (immich, 최적화 위젯)이 같은 우측 하단 구역에 떠 있어 겹침에 주의.

**10-1-C. [추론] §3의 코드 결함은 여전히 존재하지만 트리거가 사라졌다**

`_locLayerReady`/`_destLayerReady` 미리셋 가드(`nav_screen.dart:1234-1261`,
`1525-1528`)는 이번 세션에서 손대지 않았고 **코드상 여전히 그대로다.** 하지만
그 결함이 발현되려면 플랫폼뷰가 파괴·재생성돼야 하는데, 그걸 유발하던 유일한
확인 경로(PIP 진입 시 윈도우 리사이즈로 인한 네이티브 서피스 파괴)가 S3b에서
**메커니즘째 사라졌다.** 즉:

- **"고쳤다"가 아니라 "그 버그를 트리거하던 유일한 알려진 경로가 없어졌다"**다.
- 잠재 결함은 남아 있다 — 향후 다른 경로(실제 Activity 재생성, 화면 회전,
  OS 저메모리 강제 종료 후 재기동 등)로 플랫폼뷰가 파괴되는 상황이 생기면
  동일 버그가 재발할 수 있다. 근본 수정(가드를 재생성 시점에 리셋)은 여전히
  권장 사항으로 남긴다 — 이번 세션은 조사 전용이라 커밋하지 않았다.

**10-1-D. [관측] 메모리 압박 축 — OS가 자체 차단**

`am send-trim-memory <pid> RUNNING_MODERATE|LOW|CRITICAL`이 4회 전부
`IllegalArgumentException: Unable to set a background trim level on a
foreground process`로 거부됐다. `NavForegroundService`가 살아있는 한 프로세스가
foreground 우선순위로 유지돼 OS의 강제 trim 대상이 아니다 — 실사용 시나리오에서도
유사하게 보호받을 가능성을 시사한다(정황 증거, 확정 아님). 다수의 실제 무거운
백그라운드 앱을 띄워 진짜 OS 메모리 압박을 만드는 실험은 마스터 실사용 폰이라
이번 세션에서 시도하지 않았다 — 필요하면 다음 세션 과제로 남긴다.

**10-1-E. [관측·신규] 속도계 자리를 대신하는 카메라 경고 게이지는 정상 동작이다**

16회 반복 중 2회(라운드 4~5)에서 속도계 ink_ratio가 비정상적으로 높게(0.93~0.98)
찍혔다. 스크린샷 확인 결과 **백화가 아니라 로드맵 18번(후면단속카메라 안내) 기능이
실제로 발동**해 속도계 자리에 카메라 접근 경고 게이지("90 METER.")가 정상 표시된
것이었다. 판정기는 이를 올바르게 "백화 아님"으로 분류했다 — 향후 임계값 튜닝 시
이 케이스를 오탐으로 착각하지 않도록 기록해둔다.

**10-1-F. [관측·신규, 범위 밖] 미조사 새 크래시 — `StreamSink is bound to a stream`**

HOME 복귀 후 약 1분 37초 뒤 `crash_reporting.dart`가 잡은 신규 크래시 1건
(`Bad state: StreamSink is bound to a stream`). 재현 조건 미확정, 이번 세션에서
근본 원인 조사는 하지 않았다. `flutter_tts` 관련 스트림 충돌 의심
(`voice_pack_service.dart`에 이미 "flutter_tts 4.2.5 네이티브 결함" 기록 있음)이나
**추측일 뿐 확정 아니다.** S1b 범위 밖 — 별도 조사 항목으로 다음 세션 백로그에 남긴다.

### 10-2. 갱신된 판정 (§5 대체) — **[정정, 마스터 확인 2026-08-06]**

> 아래 표의 "17회 전부 재현 안 됨"을 처음엔 "해결/무결함"으로 읽었는데 **틀렸다.**
> **M32는 마스터의 실사용 폰이 아니라 유루나비 전용 공기계다.** 서버와 같은 WiFi에만
> 물려 있어 **5G/LTE 실통신이 없고, 설치 앱·백그라운드 동작이 거의 없다.** 반면
> 프로덕션 장애(567건 로그)는 **실제 도로 주행 + 실제 셀룰러망 + 그 폰에 평소 깔려
> 있던 앱들의 백그라운드 경쟁** 속에서 일어났다. 마스터 증거: 평소 앱 개수가 적고
> 백그라운드를 최소화한 개인폰(갤럭시 A34)이 **최신 갤럭시 플립7보다 오래 버텼다** —
> 앱 개수/백그라운드 점유가 실제 원인 변수라는 직접 증거다.
> → **M32에서의 클린 결과는 "이 기기가 실패조건을 구조적으로 재현 못 한다"는 뜻이지
> "버그가 없다"는 뜻이 아니다.** 아래 표는 그 전제로 읽어야 한다. §11에서 방향을
> 전환한다.

| 증상 | §5(구 판정) | §10(M32 재검증 — 실패조건 재현 불가 전제) |
|---|---|---|
| 지도 위치 퍽/핀 소실 | 원인 후보 확정적(§3), 실기 계측 대기 | M32의 통제된 17회 트리거로는 재현 안 됨. §3 결함은 코드에 남아있고, 유일하게 **확인된** 트리거(PIP)는 사라졌지만 **다른 미확인 경로**(저메모리 강제종료 후 재기동 등, 실제 셀룰러+백그라운드 경쟁 환경에서만 나타날 수 있음)는 배제 못 함 |
| 라이프사이클 오검출(`inactive`) | 확정 — 알림창→PIP→플랫폼뷰 파괴 | **S3에서 수정 확인됨.** 이건 M32에서도 유효한 결론이다 — 이 트리거는 환경(셀룰러/백그라운드 경쟁)과 무관한 순수 코드 로직이었기 때문 |
| 속도계·일출일몰 내용물 소실 | 미확정 | M32의 통제된 17회 트리거로는 재현 안 됨. **원인 메커니즘 자체가 여전히 미확정** — §11로 조사축 전환 |
| 메모리 압박 | 미시도 | OS가 foreground service 보유 프로세스의 강제 trim을 차단 — `am send-trim-memory`로는 이 축에 접근 자체가 안 됨. 진짜 압박(실제 무거운 백그라운드 앱 다수)은 M32 특성상 여전히 못 만듦 |

### 10-3. 산출물

- `loop/repro_s1b/real_trigger_repeat.sh` — S3b 이후 실제 트리거(HOME→오버레이탭)
  반복 왕복 스크립트. `loop/repro_s1b/pip_repeat.sh`(구 PIP 경로, 참고용으로 유지)와 별도.
- 임시 계측 로깅은 검증 후 `git checkout`으로 원상복구, 클린 release로 재빌드·재설치 완료.

### 10-4. 다음 세션 제안

1. **§3 가드 리셋을 실제로 커밋할지 마스터 판단 필요** — 트리거가 없어졌을 뿐 결함
   자체는 남아 있다. 예방적 수정(플랫폼뷰 재생성 시 `_locLayerReady`/`_destLayerReady`
   리셋)을 할지, 트리거가 사라졌으니 그대로 둘지는 기술적 판단이 아니라 우선순위 판단.
2. **StreamSink 크래시**(§10-1-F) 재현 조건 확립 — 별도 조사 항목.
3. **진짜 메모리 압박**(다수 백그라운드 앱) 축은 여전히 미시도.
4. **타일 캐시 1.65GB 실측**은 S2부터 계속 미수행으로 남아 있다.
5. Impeller A/B는 재현 자체가 안 되는 현재로선 실익이 없어 보류.

---

## 11. (같은 세션, 이어서) 메모리·GPU 메모리 감사로 조사축 전환 — 마스터 지시

**마스터 피드백(2026-08-06):** §10의 "M32에서 17회 무결함"을 "해결됨"으로 읽은 것은
틀렸다. **M32는 마스터의 실사용 폰이 아니라 유루나비 전용 공기계**다 — 서버와 같은
WiFi에만 물려 있고 5G/LTE 실통신이 없으며 설치 앱·백그라운드 동작이 거의 없다.
실제 장애는 **실도로 주행 + 실제 셀룰러망 + 그 폰에 평소 깔린 앱들의 백그라운드
경쟁** 속에서 일어나며, 앱 개수/백그라운드 점유가 클수록 심해진다(마스터 증거:
평소 앱이 적고 백그라운드를 최소화한 개인폰 갤럭시 A34가 최신 갤럭시 플립7보다
오래 버팀). → **M32로 환경을 흉내 내려 하지 말고, 앱 자체의 메모리·비디오
메모리(GPU 메모리) 사용량 — 용량·점유율·점유시간·효율성을 감사**하라는 지시.
이 축은 M32에서도 유효하다 — 누수는 코드 속성이지 환경 속성이 아니므로 부하 경쟁
없이도 장시간 실행 시 단조 증가 패턴으로 잡을 수 있다(단, "재현/차단"이 아니라
"증가 추세 유무"를 보는 것이며 배경 경쟁 자체는 여전히 대표 못 한다 — memory
`project-device-tier-target` 참조).

### 11-1. [관측] 정적 코드 감사 — Dart 레벨 리소스 해제는 전반적으로 깨끗함

- `StreamController` 직접 생성 **0건**. `.listen(` 직접 호출도 없고 전부 Riverpod
  `ref.listen`/`StreamProvider` 경유 — provider dispose 시 자동 취소됨.
  `nav_state_provider.dart:62-70`의 `ref.listen` + `Timer.periodic`도
  `ref.onDispose`에서 둘 다 정리됨(`sub.close()` + `_ticker?.cancel()`).
- `AnimationController` 6개 파일 전수 확인 — **전부 `dispose()`에서 해제됨**
  (`rear_camera_gauge.dart`의 믹스인 `_DigitBlinkMixin.disposeBlink()`도
  각 State의 `dispose()`에서 호출 확인).
- `Timer(`/`Timer.periodic` 5개 파일 — 육안 확인한 범위에서 누락 없음.
- **결론**: 이번 세션에서 찾은 Dart 위젯/프로바이더 레벨 리소스 누수는 없다.
  누수가 있다면 Dart GC가 못 보는 **네이티브/GPU 영역**(§11-2~4)일 가능성이 높다
  — `loop/testride_result/Gemini_error_analysis.md`도 이 방향을 짚었으나
  그 문서의 구체적 근거("Canvas로 POI를 그린다")는 틀렸다(memory
  `project-gemini-analysis-premise-wrong`). **방향은 맞고 근거는 틀렸던 셈** —
  이번 세션은 같은 방향을 코드·계측 양쪽에서 다시 검증했다.

### 11-2. [관측] `maplibre_gl` 플러그인 자체는 알려진 플랫폼뷰 누수를 이미 우회했다

`~/.pub-cache/hosted/pub.dev/maplibre_gl-0.26.1/.../MapLibreMapController.java:2225-2260`
확인 결과, 플러그인의 `dispose()`는 Flutter 엔진의 알려진 버그
([flutter/flutter#107297](https://github.com/flutter/flutter/issues/107297) —
엔진이 플랫폼뷰 폐기 시 `removeView`를 호출하지 않아 서피스가 누수되는 문제,
[maplibre/flutter-maplibre-gl#182](https://github.com/maplibre/flutter-maplibre-gl/issues/182))를
플러그인 자체 코드로 우회한다:

```java
private void destroyMapViewIfNecessary() {
  ...
  mapViewContainer.removeView(mapView);  // TextureView.onDetachedFromWindowInternal() 유발 필수
  mapView.onStop();
  mapView.onDestroy();
  mapView = null;
}
```

→ **[추론]** Flutter가 이 `dispose()`를 정상적으로 호출하는 경로(위젯 트리에서
`MapLibreMap`이 완전히 언마운트되는 경우)라면 서피스/텍스처는 제대로 해제된다.
남은 위험은 플러그인 코드가 아니라 **"Flutter가 이 dispose()를 실제로 호출하는가"**
쪽이다 — §3의 플랫폼뷰 파괴·재생성(`maplibre_gl_2`→`_4`)이 정상적인 위젯 언마운트
경로를 탔는지, 아니면 네이티브 서피스만 강제로 죽고 Flutter 쪽 컨트롤러/`dispose()`는
못 불린 채 남는 비정상 경로였는지는 **미확인**(§3 원래 가설과 같은 계열의 질문).
다음 세션 후보로 남긴다 — 이번 세션에서 확인한 건 "PIP 경로 자체가 사라졌다"는
사실뿐, 이 경로가 정상 dispose였는지는 알아내지 못했다.

### 11-3. [관측] 16분 vGPS 주행 — GPU 메모리(EGL/GL mtrack) 실측, 단조 누수 없음

`route.csv`(961pt, 약 16분) 재생 중 30초 간격으로 `dumpsys meminfo <pid>`를 샘플링
(`loop/repro_s1b/sample.sh`, 원본 데이터 `loop/repro_s1b/mem_gpu_samples_0806.csv`).

| 구간 | Graphics(KB) | EGL mtrack(KB) | GL mtrack(KB) | 해석 |
|---|---|---|---|---|
| t=0s (진입 직후) | 140,807 | 122,943 | 17,864 | 콜드스타트 |
| t=30~182s (초기 램프업) | 142k→152k | 123k→134k | 18k대 | 스타일·타일·아이콘 로드 — 정상 |
| **t=212~486s (정상 주행 중 평탄)** | **156,405 고정** | **138,289 고정** | **18,116 고정** | **274초간 완전 평탄 — 1Hz 위치 갱신에서 누수 없음** |
| **t=516s (재탐색 1건 발생 직후)** | 156,405→**178,949** (+22,544) | 거의 그대로(+800) | **18,116→40,660 (+22,544)** | **재탐색과 정확히 동시 — GL mtrack만 튐** |
| t=547~1124s (재탐색 이후 평탄) | 178~181k대 | 137~139k대 | 40.3k~41k대 | **577초간 새 수준에서 평탄 — 추가 증가 없음** |

t=516s의 점프(logcat `16:19:56.678 YNAV_GUIDE reroute steps=10` — 자동 재탐색
1건과 정확히 겹침)를 보고 "재탐색마다 GPU 메모리가 샌다"는 가설을 세워 **같은
세션에서 직접 검증**했다: 주행 종료 후 "재탐색" 버튼을 **수동으로 3회 연속** 눌러
매회 전후 `Graphics`/`EGL`/`GL mtrack`을 비교했다.

```
BEFORE_ANY_REROUTE  graphics=179623 egl=139091 gl=40532
AFTER_REROUTE_1      graphics=178821 egl=138289 gl=40532
AFTER_REROUTE_2      graphics=178343 egl=137487 gl=40856
AFTER_REROUTE_3      graphics=178821 egl=138289 gl=40532
```

**추가 재탐색 3회에서 증가 없음(±300KB 잡음 수준).** → **[결론, 이번 세션에서
확정]** t=516s의 22.5MB 점프는 **재탐색마다 반복되는 누수가 아니라, 첫 재탐색에서
더 크거나 복잡한 경로 지오메트리를 받으면서 GL 버텍스 버퍼가 새 상한(high-water
mark)으로 한 번 커진 뒤 그 크기를 재사용하는 정상적인 렌더링 엔진 동작**으로 보인다
(버퍼가 커진 뒤 줄어들지 않는 것 자체는 대부분의 GL 엔진에서 흔한 최적화이지
결함이 아니다 — 매 프레임 realloc을 피하기 위함).

**이번 세션 결론**: 16분 주행 + 재탐색 4회(자동 1 + 수동 3) 범위에서는 **GPU
메모리 단조 증가(누수) 징후를 찾지 못했다.** 콜드스타트 램프업과 최초 재탐색 시
1회성 버퍼 확장 외에는 완전히 평탄했다. **단, 이건 "16분·재탐색 4회 규모에서는
안 보인다"는 뜻이지 "10시간·수십 회 재탐색 규모에서도 안전하다"는 뜻이 아니다** —
표본 규모의 한계를 그대로 남긴다.

### 11-4. [관측] 타일 디스크 캐시(500MB)와 지도 GPU 캐시는 별개 시스템이다

`lib/services/map_cache_provider.dart:22`의 `maxCacheSize: 500MB`는
`flutter_map`(`NetworkTileProvider`)의 **디스크** 캐시 설정이다. 그런데 §7에서
언급된 "1.65GB 실측 배분" 미측정 항목과, 이번 §11-3에서 측정한 `EGL/GL mtrack`은
**둘 다 아니다** — 이건 MapLibre 네이티브 엔진(`maplibre_gl`)의 **GPU 텍스처
캐시**로 별도 시스템이다. `buildCachedTileProvider()`가 실제 내비 지도(MapLibre
플랫폼뷰)에 쓰이는지 아니면 다른 화면(예: 코스 미리보기)에 쓰이는지도 이번
세션에서 확인하지 않았다 — 세 캐시 시스템(디스크 500MB / 타일 1.65GB 미측정 /
GPU 텍스처 이번에 측정한 ~180MB)을 서로 혼동하지 않도록 다음 세션에 명시해둔다.

### 11-5. 산출물

- `loop/repro_s1b/sample.sh` — `dumpsys meminfo`에서 PSS/Graphics/EGL·GL mtrack을
  주기적으로 뽑아 CSV로 남기는 범용 스크립트(다음 장시간 주행 조사에도 재사용 가능).
- `loop/repro_s1b/mem_gpu_samples_0806.csv` — 이번 16분 주행의 원본 샘플 38행.

### 11-6. 다음 세션 제안 (§10-4에 추가)

1. **표본 규모를 키워라** — 16분·재탐색 4회로는 충분하지 않다. `route.csv`를
   반복 재생하거나 더 긴 CSV를 만들어 **1시간+ · 재탐색 10회+** 규모로 같은
   샘플링을 재현하면 "1회성 버퍼 확장" 결론이 더 큰 표본에서도 버티는지 알 수 있다.
2. **§11-2의 미확인 질문**: 플랫폼뷰가 파괴될 때(§3) 플러그인의 `dispose()`가
   실제로 불리는지, 아니면 네이티브 서피스만 죽고 Flutter 쪽 컨트롤러는 못 불린 채
   남는지 — 이건 §3의 가드 미리셋 결함과 같은 뿌리일 수 있다. 네이티브
   `Log.d`(`MapLibreMapController.dispose()`/`destroyMapViewIfNecessary()` 진입부)로
   직접 계측해야 확정된다.
3. **세 캐시 시스템 혼동 방지**(§11-4) — 디스크 500MB / 타일 1.65GB(미측정) / GPU
   텍스처(~180MB, 이번에 측정)를 각각 무엇이 관리하는지 한 문서에 정리할 것.
4. 마스터의 A34 vs 플립7 비교는 강력한 정황 증거이지만, **M32에서 재현 못 한
   "배경 앱 경쟁" 축 자체는 이번에도 접근 못 했다** — 진짜 답은 실제 배경 부하가
   있는 기기(플립7 같은 실사용 폰 또는 다수 앱을 깐 별도 테스트 기기)에서 같은
   `sample.sh`를 돌려보는 것이다.

---

## 12. (2026-08-06, 3회차) 조사축 재전환 — 실기기 재현 전면 취소, 레퍼런스 앱 비교 + Flutter 사례 조사

**마스터 지시 (2026-08-06 저녁 스티어링):**

1. **M32 가상GPS "실제 에러 재현"은 전면 취소.** 사유 3건 —
   ① 주입 GPS 궤적이 유루나비 안내 경로와 어긋나 **끝없이 Valhalla 재탐색을 유발**한다.
   ② 그 결과 **Valhalla 서버가 rate limit에 걸린다.** 마스터 판단: *"사용자가 여러 명이면
      이 정도 호출은 일상적인 건데 rate limit가 걸리는 건 문제가 아주 심각하다."*
      → **S1b 범위 밖의 독립 결함으로 승격. §12-7에 백로그로 남긴다.**
   ③ 스크린샷 캡처·분석이 컨텍스트를 채워 세션이 `ECONNRESET`로 반복 사망했다.
2. 대신 **OsmAnd / Organic Maps의 메모리·VRAM 관리 로직을 확인해 유루나비와 비교**하고,
   **Flutter에서 화면 asset이 표시되지 않는 사례를 조사**해 메모리·VRAM 누수 때문인지부터
   판별하라.

> 이 절은 **실기기를 전혀 쓰지 않았다.** 전부 (a) 기존 증거물 재분석,
> (b) 레퍼런스 앱 소스 직접 열람, (c) Flutter 이슈 트래커 조사, (d) 유루나비 정적 감사다.

---

### 12-1. [관측·신규] 증거 스크린샷 육안 재확인 — 실패 단위는 "글리프"가 아니라 **`Container`의 child 서브트리 통째**

`Screenshot_20260801_062518_Yurunavi.jpg`(1080×2340)의 좌측 영역을 2배 확대 +
**콘트라스트 6배 부스트**해 직접 봤다. §1은 판정기 수치만 봤고, 육안 확인은 이번이 처음이다.

**부스트 후에도 두 위젯 내부는 완전한 순백이다 — 희미한 잔상조차 없다.**
저투명도 렌더(예: `FadeTransition` 최저값 0.25)로도 설명되지 않는다.

| 요소 | 렌더됨 | 안 됨 |
|---|---|---|
| 속도계 `Container`(88×88 원형, 주황 테두리 + boxShadow) | **껍데기 ✅** (그림자 번짐까지 정상) | **child(Column/FadeTransition) ❌** |
| DaylightBar `Container`(38폭 알약, 흰 배경 + boxShadow) | **껍데기 ✅** | **child(Column) ❌** |
| 상단 카드1(`555m` `서동대로` + **SVG 유턴 아이콘**) | ✅ 전부 | — |
| 상단 카드2(`다음 우측…` + SVG 아이콘) | ✅ 전부 | — |
| 우측 버튼(현위치 타깃 · `Icons.add` · `Icons.remove`) | ✅ 전부 | — |
| 하단 ETA 카드(POI명·도착시각·거리·재탐색·종료) | ✅ 전부 | — |
| OSM attribution 텍스트(fontSize 9) | ✅ | — |
| 지도: 경로선·도로·도로라벨(`서동대로`)·POI 파란 점 | ✅ | — |
| 지도: 위치 퍽 · 목적지/경유지 핀 | — | ❌ (§3 별개 메커니즘) |

**[관측] 이것이 이번 세션의 핵심 신규 사실이다.**
소실된 두 위젯은 `Container(decoration: …, child: Column(…))` 구조이고,
**`decoration`(채우기 + 테두리 + boxShadow)은 그려졌는데 `child`만 통째로 안 그려졌다.**

이로써 **§5의 "글꼴 아틀라스 고갈" 가설은 완전히 배제된다** — 배제 사유가 §5보다 강해졌다:

- DaylightBar의 **게이지 막대는 글리프가 아니라 6px 단색 RRect**(`0xFFFFF59D`)인데 같이 사라졌다.
- 반대로 같은 프레임의 다른 텍스트·MaterialIcons 글리프·SVG는 전부 정상이다.

→ **[추론] 실패 단위는 개별 드로우 콜(글리프)이 아니라 "서브트리 하나가 통째로
누락되는 것"이다.** 즉 그 서브트리가 별도의 렌더 타깃/레이어로 처리되다가
그 자원 확보에 실패했을 때 나타나는 형태다. (Impeller가 offscreen을 잡는 경로 —
`saveLayer`/`Opacity`/래스터 캐시 계열.) 실제로 속도계 쪽은
`_Speedometer`가 GPS 미획득 시 **`FadeTransition`(= `Opacity` = `saveLayer`)** 로
내용물을 감싸고(`nav_screen.dart:2993-3003`), 바깥의 `RearCameraGaugeSwitcher`는
**`AnimatedSize`(= `Clip.hardEdge` 클립 레이어)** 와 **`ScaleTransition`(= Transform 레이어)**
안에 들어 있다(`nav_screen.dart:2185-2193`, `3018-3025`).
**단, DaylightBar 쪽에는 대응하는 레이어 생성 구문이 없다 — 이 비대칭은 아직 설명 못 한다.
확정하지 않고 [추론]으로 남긴다.**

---

### 12-2. [관측] Flutter 공식 이슈 트래커 — **똑같은 실패모드가 실재하고, 원인은 GPU 자원 확보 실패다**

"Flutter에서 화면 asset이 표시되지 않는 사례" 조사 결과. StackOverflow의 다수 사례는
`pubspec.yaml` 자산 선언 누락 같은 빌드 문제라 이 건과 무관했다. **의미 있는 건 전부
flutter/flutter 이슈 트래커의 Impeller/Android 계열이었다.**

| 이슈 | 증상 | 트리거 | 원인/상태 |
|---|---|---|---|
| [#159578](https://github.com/flutter/flutter/issues/159578) | **Android 앱의 모든 텍스트가 사라짐.** 레이아웃·버튼은 정상, 텍스트만 안 보임. 화면을 터치/스크롤하면 복구 | **화면 껐다 켜기(전원 버튼)** | Impeller+Vulkan. 엔진 로그: `Could not create valid atlas` → `Cannot render glyphs without prepared atlas`. **글리프 아틀라스 텍스처 재생성 실패**. `r: fixed` |
| [#163452](https://github.com/flutter/flutter/issues/163452) (=[#163730](https://github.com/flutter/flutter/issues/163730)) | UI가 깨져 보이고 **화면을 만지면 정상 복구** | 3.29 업그레이드 후 / 앱 최소화→복귀 | **P1 · c: regression · e: impeller · platform-android**, jonahwilliams 배정 |
| [#164605](https://github.com/flutter/flutter/issues/164605) / [#164606](https://github.com/flutter/flutter/issues/164606) | `Could not find glyph position in the atlas` | 앱 재실행·페이지 스와이프 | PR #164822·#164931로 수정 |
| [#133092](https://github.com/flutter/flutter/issues/133092) | 아틀라스가 **기기 텍스처 한도를 넘으면** 처리 못 함 | 텍스트 다양성 증가 | Typographer가 아틀라스 텍스처 다중 추적하도록 개선 |
| [#161861](https://github.com/flutter/flutter/issues/161861) | **[Android][Impeller] Graphics 메모리 누수** — 그래픽 무거운 위젯을 반복 재그리면 Graphics 메모리가 계속 증가, **절대 감소 안 함 → 프로세스 킬** | 3.26+ 회귀(3.24는 정상). 실기기에서만, 에뮬레이터 재현 안 됨 | `perf: memory` · PR #162171 · `r: fixed` |
| [#178264](https://github.com/flutter/flutter/issues/178264) | **지도 타일 앱**에서 Dart `ImageCache`는 0바이트인데 **`GL mtrack`이 3.9GB까지 증가 후 OOM 킬** | 지속적인 지도 패닝 | *"Impeller appears to retain textures and render targets far longer"* — **Impeller의 텍스처·렌더타깃 풀은 앱에서 볼 수도, 건드릴 수도 없다.** GPU 메모리 통계 노출 API와 수동 압박 훅 요청. **P2, 열려 있음** |

**[관측] #159578이 가장 중요하다.** 실패 문구가 `Could not create *valid* atlas` —
**"고갈"이 아니라 "생성 실패"**, 즉 **GPU 자원 할당 실패**다. 그리고 그 결과는
크래시가 아니라 **"그 드로우만 조용히 안 그려지고 나머지 프레임은 정상"** 이다.
증거 스크린샷의 형태와 정확히 같은 계열이다.

**[관측] #178264은 계측 방법론까지 이 조사와 겹친다.** 그쪽도 `dumpsys meminfo`의
`GL mtrack`을 봤고(§11-3과 동일 지표), Dart 쪽 `ImageCache` 수치는 0인데 GPU만 부풀었다.
**즉 "Dart 레벨 감사가 깨끗하다"(§11-1)는 사실은 GPU 누수를 전혀 배제하지 못한다.**

**[관측] 유루나비는 이 증거를 볼 수단이 아예 없다.** 실주행 진단로그
`loop/testride_result/log/*.log`(최대 7.7MB, 95k줄)를 `impeller|atlas|vulkan|
GL_OUT_OF_MEMORY|OutOfMemory|trim` 로 grep한 결과 **매치 0건**이다.
앱 진단로그가 Dart `debugPrint`만 캡처하고 **네이티브 로그(Impeller validation·Vulkan·
OOM)를 하나도 남기지 않기 때문**이다. → §12-5 B-1.

---

### 12-3. [관측] 3자 비교 — OsmAnd · Organic Maps · YuruNavi

레퍼런스 앱은 GitHub 원본을 직접 받아 읽었다(추측 아님).

#### (1) OS 메모리 압박 훅

| 앱 | 구현 |
|---|---|
| **Organic Maps** | `MwmActivity.onTrimMemory(level)` → `level >= TRIM_MEMORY_RUNNING_LOW && level != TRIM_MEMORY_UI_HIDDEN`일 때 `Framework.nativeMemoryWarning()` → `Framework::MemoryWarning()` → `ClearAllCaches()` + `SharedBufferManager::Instance().ClearReserved()` |
| **OsmAnd** | `OsmandApplication.onLowMemory()` → `ResourceManager.onLowMemory()` → `clearTiles()` + 주소DB 전체 `clearCache()` + `renderer.clearCache()` + `System.gc()` |
| **YuruNavi** | **없음.** `lib/`·`android/` 전체에 `didHaveMemoryPressure` **0건**, `onTrimMemory` **0건**. 유일한 `WidgetsBindingObserver`(`nav_screen.dart:131`)도 `didChangeAppLifecycleState`만 구현 |

#### (2) 백그라운드 진입 시 캐시 해제

| 앱 | 구현 |
|---|---|
| **Organic Maps** | `Framework::EnterBackground()` → `m_drapeEngine->OnEnterBackground()` + **`ClearAllCaches()`** (`libs/map/framework.cpp:1264-1276`). 즉 **백그라운드로 갈 때마다 무조건 캐시를 턴다** |
| **OsmAnd** | `onLowMemory` 경유 (전용 백그라운드 훅은 없음) |
| **YuruNavi** | **없음** |

#### (3) GPU 메모리 예산 상한

| 앱 | 구현 |
|---|---|
| **Organic Maps** | `dp::vulkan::VulkanMemoryManager` — **자원 타입별 하드 예산**<br>`kDesiredSizeInBytes = { Geometry 80MB, Uniform ∞, Storage ∞, Staging 20MB, Image 100MB }`.<br>해제 시 `m_sizes[type] > kDesiredSizeInBytes[type]`이면 **즉시 `vkFreeMemory`로 OS 반납**, 예산 이하면 free-block 풀에 넣어 재사용. `BeginDeallocationSession()`/`EndDeallocationSession()`으로 프레임 단위 일괄 회수 |
| **OsmAnd** | **화면 픽셀 수에 비례한** 비트맵 타일 캐시 상한 — `(w/256+2)*(h/256+2)*3` 장 (`ResourceManager.java:185-187`). 초과 시 `TilesCache.getRequestedTile()`이 `cache.size() > maxCacheSize` → `clearTiles()` |
| **YuruNavi** | **없음, 3중으로.** ① Impeller 내부 풀은 앱이 볼 수도 만질 수도 없다([#178264](https://github.com/flutter/flutter/issues/178264)) ② `ml.MapLibreMap` 위젯에 캐시 관련 옵션 미설정(`nav_screen.dart:1921-1933`) ③ Flutter `PaintingBinding.instance.imageCache` 튜닝 **0건** → **기본값 1000장 / 100MB 그대로**. RAM 3.7GB 기기 기준 과도하다 |

#### (4) GPU 컨텍스트·서피스 파괴/복구 계약

| 앱 | 구현 |
|---|---|
| **Organic Maps** | `Framework::OnDestroySurface()` / `OnRecoverSurface(w, h, recreateContextDependentResources)`.<br>`FrontendRenderer::OnContextDestroy()`가 컨텍스트 의존 자원을 전부 해제하고 **상태 플래그까지 전부 리셋한다** — `m_needRestoreSize = true`, `m_firstTilesReady = false`, **`m_finishTexturesInitialization = false`**. 각 렌더러도 `ClearContextDependentResources()` 일괄 호출 |
| **OsmAnd** | `renderer.clearAllResources()` (`ResourceManager.java:538, 902`) |
| **YuruNavi** | **깨져 있다.** `_locLayerReady`/`_destLayerReady`가 플랫폼뷰 재생성 시 리셋되지 않는다(§3, `nav_screen.dart:1234-1261`, `1525-1528`). **Organic Maps가 `OnContextDestroy()`에서 명시적으로 방어하는 바로 그 결함이다.** §10-1-C에서 "트리거만 사라졌고 결함은 남아 있다"고 판정한 항목 |

#### (5) 네이티브 핸들 명시 해제

| 앱 | 구현 |
|---|---|
| **Organic Maps** | RAII (`drape_ptr`/`unique_ptr`) — 스코프 이탈 시 결정론적 해제 |
| **OsmAnd** | Java GC + 명시적 `recycle`/`clearCache` |
| **YuruNavi** | **부분 결함 (신규 발견)** — `ui.Image`는 `dispose()`하는데 **`ui.Picture`는 3곳 전부 미해제**:<br>`lib/services/poi_icon_renderer.dart:56`, `:70`, `lib/features/tour_summary/tour_share_helper.dart:167`.<br>`ui.Picture`는 네이티브 디스플레이리스트를 붙들고 있고, `dispose()`하지 않으면 **Dart GC의 파이널라이저가 돌 때까지 네이티브 메모리가 잡혀 있다.** Dart GC는 네이티브 힙 압박을 못 느끼므로 회수가 늦다 — 마스터가 말한 *"GC가 제대로 되지 않아 garbage가 적체"* 와 정확히 같은 메커니즘이다.<br>규모: POI 아이콘 5종이 **스타일 재주입마다** 재생성된다(`nav_screen.dart:1565-1573`, 코드 주석에 "스타일 재주입마다 다시 등록해야 한다"고 명시) |

---

### 12-4. 판정 — **"누수"는 아직 증거 없음, "압박 시 할당 실패"는 근거 강함**

마스터 가설(*"CPU·메모리·VRAM·네트워크 과점유 + GC 불량으로 garbage 적체"*)을 세 갈래로 나눠 판정한다.

| 주장 | 판정 | 근거 |
|---|---|---|
| **(a) 단조 증가하는 누수(leak)가 있다** | **미입증** | §11-3의 16분 실측에서 GL mtrack 평탄(콜드스타트 램프업 + 최초 재탐색 1회성 버퍼 확장 외 증가 없음). Dart 레벨 자원 해제도 깨끗(§11-1). **단 표본이 16분·재탐색 4회뿐이고, `ui.Picture` 미해제(§12-3(5))라는 실제 누수 경로를 이번에 찾았다** |
| **(b) 메모리·VRAM 압박 순간에 GPU 자원 할당이 실패해 일부 드로우가 통째로 누락된다** | **근거 강함 — 현재 최유력 가설** | Flutter가 공식 이슈로 인정한 실재 실패모드([#159578](https://github.com/flutter/flutter/issues/159578)·[#163452](https://github.com/flutter/flutter/issues/163452)·[#178264](https://github.com/flutter/flutter/issues/178264)). 실패 문구가 `Could not create valid atlas` = **할당 실패**이고 결과가 **"조용한 부분 미렌더"** 라 §12-1의 형태와 일치. **마스터의 A34(앱 적음) > 플립7(앱 많음) 관찰도 이 가설로 자연스럽게 설명된다** — 자유 메모리가 많으면 할당이 성공하고, 적으면 실패한다. **M32가 17회 왕복에도 재현 못 한 이유도 같다**(§10-2 전제: 배경 경쟁 0) |
| **(c) 앱에 메모리 압박 대응 로직이 없다** | **확정 — 코드로 확인된 결함** | §12-3 (1)(2)(3) 전부 "없음". **OsmAnd·Organic Maps는 셋 다 갖고 있다** |

**한 줄 요약: 마스터의 방향은 맞다. 다만 정확히는 "새는 것"보다 "압박을 견딜 장치가 없는 것"이 문제다.**
유루나비는 OS가 메모리를 조여 올 때 스스로 줄일 수단이 하나도 없고, GPU 예산 상한도 없고,
백그라운드에서 캐시를 놓지도 않는다. 레퍼런스 앱 두 곳 모두 이 셋을 명시적으로 구현하고 있다.

**아직 설명 못 하는 것 (정직하게 남긴다):** DaylightBar의 6px 단색 막대가 왜 같이 사라졌는지.
글리프 아틀라스로도, 그 위젯에 없는 `saveLayer`로도 설명되지 않는다. §12-1의 "서브트리 단위
누락"이라는 관측은 확실하지만 **그 서브트리가 왜 별도 렌더 타깃으로 처리됐는지는 미확정이다.**

---

### 12-5. 권고 조치 (우선순위 순)

> 전부 **실기기 재현 없이** 할 수 있는 것들이다. 마스터 승인 전 커밋하지 않는다.

**A. 명백한 결함 — 저위험, 바로 고칠 것**

- **A-1. `ui.Picture.dispose()` 3곳 추가** — `poi_icon_renderer.dart:56,70`, `tour_share_helper.dart:167`.
  단독으로 백화를 설명하진 못하지만 **실재하는 네이티브 누수**이고 수정 비용이 거의 0이다.
- **A-2. `didHaveMemoryPressure()` 구현** — `WidgetsBindingObserver`에 오버라이드 추가,
  `imageCache.clear()` + `clearLiveImages()` + POI 캐시 축소. Organic Maps `MemoryWarning()` 대응물.
- **A-3. `imageCache` 상한을 기기 기준으로 축소** — 기본 1000장/100MB는 RAM 3.7GB 기기에 과하다.
  OsmAnd처럼 화면 픽셀 수/기기 메모리에서 역산할 것.
- **A-4. 백그라운드(`paused`) 진입 시 캐시 드롭** — Organic Maps `EnterBackground()`→`ClearAllCaches()` 대응물.
- **A-5. `_locLayerReady`/`_destLayerReady` 리셋**(§3, §10-4-1) — `onMapCreated`/`onStyleLoaded`에서 리셋.
  **레퍼런스 구현이 확보됐다**: Organic Maps `FrontendRenderer::OnContextDestroy()`가 정확히 이 패턴이다.
  §10-4에서 "기술 판단이 아니라 우선순위 판단"이라 했는데, **레퍼런스 앱이 둘 다 이걸 필수 계약으로
  취급한다는 근거가 생겼으므로 하는 쪽을 권고한다.**
- **A-6. `flutter_map` 의존성 제거** — §12-6 참조.

**B. 계측 보강 — 재현 없이 원인을 잡기 위한 필수 선행 작업**

- **B-1. 네이티브 로그를 진단로그에 포함시켜라 (최우선).** 지금 앱 로그는 Dart `debugPrint`만
  캡처해 **Impeller validation·Vulkan·OOM 로그가 통째로 안 남는다**(§12-2 실측: 95k줄에 매치 0건).
  `Could not create valid atlas` 한 줄이 잡히면 (b)가설이 **즉시 확정**된다.
  이건 재현 실험 100번보다 값싸고 결정적이다.
- **B-2. GPU 메모리 주기 스냅샷을 앱 자체 진단로그에 남겨라** — `loop/repro_s1b/sample.sh`가
  하는 일(`dumpsys meminfo`의 Graphics/EGL/GL mtrack)을 앱 내부화. 그러면 **마스터 실사용 폰의
  실주행에서** 시계열이 남는다. §11-6-1이 요구한 "표본 규모 확대"를 M32 없이 달성하는 길이다.

**C. 판별 실험 (마스터 실사용 폰에서, 실주행 1회)**

- **C-1. Impeller off A/B.** §12-2의 실패모드가 **전부 Impeller 계열**이다.
  `AndroidManifest.xml`에 `io.flutter.embedding.android.EnableImpeller=false` meta-data를 넣은
  빌드로 장거리 주행 1회. **§6에서 Flutter 3.44에도 이 스위치가 유효함을 이미 확인했다.**
  ⚠️ **끄는 것 자체를 해결책으로 커밋하지 마라 — 원인 판별용이다.**

---

### 12-6. [관측·확정] 부수 소득 — `flutter_map`은 **죽은 의존성**이다 (§11-4 미해결 항목 종결)

§11-4가 "세 캐시 시스템을 혼동하지 말라"며 남긴 미확인 항목을 이번에 확정했다.

- `FlutterMap(` 위젯: **`lib/` 전체에 사용 0건.**
- `buildCachedTileProvider()`: **정의만 있고 호출 0건** (`lib/services/map_cache_provider.dart:15`).
- `main_map_screen.dart`의 `import 'package:flutter_map/flutter_map.dart'`는 남아 있으나
  실제 지도는 `ml.MapLibreMap`(`:1836`)이다.

→ **`maxCacheSize: 500MB` 디스크 캐시는 애초에 동작한 적이 없다.**
세 캐시 시스템 중 **하나는 존재하지 않는다.** 남은 건 ① MapLibre 네이티브 GPU 텍스처 캐시
(§11-3에서 실측한 ~180MB) ② Flutter `imageCache`(기본값 방치) 둘뿐이다.
**§11-4의 "타일 캐시 1.65GB 미측정" 항목도 근거가 사라졌으므로 재정의가 필요하다** —
그 1.65GB가 무엇이었는지부터 다시 확인해야 한다.

부수적으로 [#178264](https://github.com/flutter/flutter/issues/178264)(flutter_map + Impeller에서
GL mtrack 3.9GB)은 **유루나비에 직접 적용되지 않는다** — 그쪽은 타일을 Flutter 위젯으로
그리는 경우다. 유루나비 지도는 네이티브 MapLibre다. **다만 "Impeller가 텍스처·렌더타깃을
오래 붙들고 앱은 그걸 볼 수도 만질 수도 없다"는 일반 결론은 그대로 유효하다.**

---

### 12-7. 다음 세션 백로그 (§10-4·§11-6 갱신)

1. **[신규·높음] Valhalla rate limit** — 마스터 지시대로 **독립 결함으로 승격**.
   *"사용자가 여러 명이면 이 정도 호출은 일상적인데 rate limit가 걸리는 건 아주 심각하다."*
   조사 축: ① 서버측 rate limit 설정값과 산정 근거 ② 클라이언트 재탐색 트리거의
   빈도 상한/디바운스 유무 ③ 다중 사용자 부하 추정. **S1b와 별개 세션으로 잡을 것.**
2. **[신규] 재탐색 폭주 자체** — 주입 GPS가 안내 경로를 벗어났을 때 재탐색이 무한 반복된다.
   가상GPS 궤적 문제이기도 하지만, **실주행에서 GPS가 튀면 같은 일이 난다.** 재탐색
   쿨다운/연속 실패 백오프가 있는지 확인 필요. §9의 "재탐색하며 코스가 마구 엉킴"과 같은 뿌리일 수 있다.
3. **[승격] §12-5 B-1 네이티브 로그 캡처** — 이걸 먼저 하지 않으면 백화 원인 확정은
   계속 추측에 머문다.
4. §10-1-F `StreamSink is bound to a stream` 크래시 — 여전히 미조사.
5. §11-4의 "타일 캐시 1.65GB"가 무엇이었는지 재정의(§12-6으로 전제가 무너졌다).
6. **M32 가상GPS 재현은 마스터 지시로 취소됨.** 위 1·2번이 해결되기 전에는 재개하지 마라.
