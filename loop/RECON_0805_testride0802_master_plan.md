# RECON — 260802 실주행(800km) 피드백 전수 분석 및 수정 계획

- 작성: 2026-08-05 · 브랜치 `verify/ride-0711` · HEAD `1703249`
- 입력: `loop/testride_result/260802_testride_result.md`, `Gemini_error_analysis.md`,
  Firebase/GitHub `.eml` 2건, `log/` 11개 세션 19MB
- **이 문서는 정찰·계획 전용이다. 코드 수정 없음.** 실제 수정은 §6 세션 분할표대로
  각각 별도 세션에서 수행한다.

---

## 0. 결론 먼저 (TL;DR)

**"심각한 오류" 11건 중 6건이 서로 다른 문제가 아니라, 단 3개의 결함에서 파생됐다.**

| # | 결함 | 위치 | 파생 증상 |
|---|---|---|---|
| **A** | `clamp()` 상한이 음수가 되어 매 프레임 예외 | `lib/core/widgets/daylight_bar.dart:109` | 백화·스프라이트 소실·속도계 증발·발열·배터리 |
| **B** | POI 조회에 디바운스/백오프 없음 → 초당 ~10회 요청, 전부 429 | `main_map_screen.dart:634`, `poi_service.dart:47/93` | 데이터 1.65GB·배터리 광탈·POI 미표시(고급휘발유 포함) |
| **C** | PIP 진입 트리거가 `AppLifecycleState.inactive` | `nav_screen.dart:460` | 알림창/캡쳐/엣지패널만 건드려도 PIP·안내 중단·히스토리 소실 |

이 3건은 전부 **국소 수정**이며, 아키텍처 개편이 필요 없다.

> **⚠️ Gemini 분석서에 대한 판정 — 핵심 권고는 이미 충족되어 있다.**
> Gemini는 "지도를 Flutter Canvas로 그리고 있는 게 근원"이라며 **MapLibre GL Native로
> 이관**하라고 결론냈다. 그러나 유루나비는 **이미 `maplibre_gl: ^0.26.1`(C++ MapLibre GL
> Native)를 쓰고 있고**(`pubspec.yaml:35`), POI도 Gemini가 처방한 그대로
> **GPU SymbolLayer + GeoJSON Source**로 그린다(`nav_screen.dart:1254 addSymbolLayer`,
> `setGeoJsonSource`). Flutter Canvas/CustomPainter로 타일이나 마커를 그리는 코드는 없다.
> **Gemini의 분석은 전제가 틀렸고, 그 위에 쌓인 "근원적 아키텍처 개편" 3대 권고는
> 이 프로젝트에 적용 대상이 아니다.** Kotlin/Swift 전면 이관은 물론, MapLibre 이관도
> 하지 마라 — 이미 되어 있다. 실제 원인은 위 A·B·C의 평범한 버그다.
> (Gemini 문서에서 살릴 값어치가 있는 건 §3 Thermal Governor 개념 정도 — S5에 반영.)

---

## 1. 로그 실측 증거

11개 세션, 총 19MB. 디바이스는 전부 `A346N`(**갤럭시 A34 5G**) — 마스터가 보고한
플립7(SM-F766N)은 이 로그에 없다(§8-1 참조).

```
YNAV_PROG    108,214    진행 틱
YNAV_POI      69,939    ← 이 중 69,875건이 HTTP 429
YNAV_CRASH    56,789    ← 전부 "Invalid argument(s): 0.0" 동일 예외
YNAV_TTS         791
YNAV_REROUTE     602
YNAV_PIP           3
```

### 1-1. 크래시 폭주

```
2026-08-02T08:05:18  YNAV_SESSION os=android release=true
2026-08-02T08:06:43  YNAV_CRASH fatal error=Invalid argument(s): 0.0   ← 세션 시작 85초 후
... 이후 초당 2~3회, 3시간 51분 동안 36,680회
```

세션별 크래시/전체 라인 비율:

| 세션 | 크래시 | 전체 | 비율 |
|---|---|---|---|
| 08-01T20:13 | 10,400 | 28,359 | 37% |
| 08-02T08:05 | 36,680 | 95,459 | 38% |
| 08-02T13:09 | 6,658 | 12,918 | **52%** |
| 08-02T16:04 | 72 | 73 | **99%** |

### 1-2. POI 요청 폭주

```
분당 429 응답 최대치: 581건 (09:07)  ≈ 9.7 req/s
연속 3시간 51분 동안 한 번도 멎지 않음
동일 밀리초대에 2건씩 나감 → 병렬 in-flight 요청 다수
엔드포인트별: fetchPois 28,934 / fetchPoisInBounds 41,005
```

### 1-3. 원형교차로 + 급커브 안내 중첩 (마스터 보고 그대로 재현)

```
20:33:30  roundabout_enter_approach   dist=300
20:33:34  sharp_turn_right_approach   dist=300   ← 4초 뒤 다른 엔진이 끼어듦
20:33:50  roundabout_enter_approach   dist=100
20:34:02  roundabout_enter_approach   dist=30
20:34:13  roundabout_enter_imminent   dist=10    ← "곧 진입" — 이미 진입 중
20:34:14  sharp_turn_right_approach   dist=50
20:34:55  sharp_turn_right_imminent   dist=10
20:34:57  roundabout_exit_approach    dist=20    ← 진출 안내 (마스터: 전부 빼라)
20:35:02  roundabout_exit_imminent_named dist=10
```

**92초 동안 한 교차로에 9회 발화.** "주절주절주절"의 실체.

### 1-4. 기타 로그 신호

- `MissingPluginException(source#setGeoJson)` **431건**, `camera#move` **136건**
  → 지도 플랫폼뷰가 떨어진 상태(PIP·백그라운드)에서 지도 API를 계속 호출.
- `YNAV_LIFECYCLE state=inactive` → 즉시 `YNAV_PIP enter ok` (3쌍 전부 이 패턴).
- TTS `dist=` 값에 4, 6, 9, 11, 13, 37, 43, 49 같은 **비정형 값**이 섞임
  → "43미터 앞 우회전입니다" 식 발화 (§4-4).

---

## 2. 근본원인 A — 백화/스프라이트 소실/다운

### 2-1. 확정된 메커니즘

`lib/core/widgets/daylight_bar.dart:109`

```dart
final totalH = constraints.maxHeight;
final handleY = (totalH * progress.clamp(0.0, 1.0)) - 8;
...
top: handleY.clamp(0.0, totalH - 24),   // ← totalH < 24 이면 상한 < 하한
```

Dart SDK `num.clamp` 구현은 상한 < 하한일 때 **`throw ArgumentError(lowerLimit)`** 한다.
`lowerLimit`이 `0.0`이므로 `toString()`이 정확히:

```
Invalid argument(s): 0.0
```

로그의 56,789건과 **문자열까지 일치**한다. Firebase 크래시 리포트도 독립적으로 같은 지점을
지목한다:

> `package:yurunavi/core/widgets/daylight_bar.dart - DaylightBar.build…`
> `FlutterError - Invalid argu…` · **장애 362건 / 사용자 6명** (1.0.1(2))

→ **가설 아님. 확정.**

### 2-2. 왜 "하얗게" 보이는가

`build()`가 던지면 Flutter는 해당 서브트리를 `ErrorWidget`으로 대체한다. 릴리스 빌드
기본 `ErrorWidget.builder`는 **회색/흰 박스**를 그린다. 게이지·속도계 자리가 통째로
흰 판이 되는 마스터 보고와 정확히 일치.

### 2-3. 왜 배터리·발열까지 가는가

초당 2~3회 예외마다 ① 스택트레이스 생성 ② 로그 파일 **디스크 append** ③ Crashlytics
**네트워크 업로드** ④ 서브트리 재빌드가 반복된다. 4시간 세션 = 36,680회. 이것만으로도
CPU가 idle로 못 내려간다.

### 2-4. 기하학적 트리거 (요검증)

호출부는 두 곳:

- `main_map_screen.dart:1928` — `top: H*0.30 + 100, bottom: _showCourseSheet ? 380 : 160`
- `nav_screen.dart:2225` — `top: H*0.30 + 100, bottom: 160`

위젯 내부 고정 크롬(아이콘 18 + 라벨 ~9 + 패딩·간격)이 상하 합계 **약 94px**를 먹으므로,
`Positioned`가 주는 높이가 **118px 미만**이면 게이지가 24px 아래로 내려가 예외가 난다.

가용높이 = `화면높이 - (H*0.30 + 100) - bottom`

| 상황 | 가용높이(A34 기준) | 게이지 | 판정 |
|---|---|---|---|
| 홈, 코스시트 닫힘 | ~310px | 216 | 안전 |
| **홈, 코스시트 열림** | **~90px** | **-4** | **크래시** |
| PIP 미니창 | 매우 작음 | 음수 | 크래시 |
| 가로모드 | ~28px | -66 | 크래시 |

> **판단**: 코스시트 열림 경로가 가장 유력하지만, `MediaQuery.size`가 서피스 재생성
> 중 축소값을 반환하는 경로도 배제 못 한다. **정확한 트리거는 §7 재현 매트릭스로
> 확정한다. 다만 수정은 트리거와 무관하게 동일하다** — 방어 + 최소높이 보장.

### 2-5. 같은 계열 잠복 결함 (전수 감사 필요)

`.clamp(0, xxx.length - 1)` 패턴은 **리스트가 비면 상한 -1** → 동일 예외. 재탐색 중
경로가 일시적으로 비는 순간에 터진다 → 마스터 보고 "재탐색 시 경로 표시가 마구 엉킴"의
유력 후보.

```
route_progress_provider.dart:320   i.clamp(0, _pts.length - 1)
route_progress_provider.dart:374   .clamp(0, _cumFromStartM.length - 1)
routing_service.dart:935/941       .clamp(0, cumFromStartM.length - 1)
nav_screen.dart:563/850/1700/1785/1800
main_map_screen.dart:1362/1530/1556
waypoint_management_sheet.dart:49
```

추가로 `nav_screen.dart:3031` — `.clamp(0.0, p.nextCameraPostZoneM.toDouble())`도
음수 가능성 확인 필요.

---

## 3. 근본원인 B — 데이터 1.65GB · 배터리 광탈

### 3-1. 홈 화면: 디바운스가 **아예 없다**

`main_map_screen.dart:634` 주석이 전제를 그대로 적어놨다:

```dart
// 로컬 SQLite 기반 POI라 서드파티 API 쿼터 부담이 없다 — onCameraIdle마다
// 무조건 재조회한다.
```

이 전제는 **틀렸다**. 자체 서버라도 앞단 Cloudflare 터널이 429를 뱉는다. 주행 중엔
카메라가 GPS를 따라 계속 움직여 `onCameraIdle`이 끊임없이 발화한다.

### 3-2. 내비 화면: 디바운스가 있으나 **우회된다**

`nav_screen.dart:1412`

```dart
final sameTypes = /* 이전 조회 타입과 동일한가 */;
if (sameTypes) {
  ... 200m 이동 OR 15초 경과 조건 ...
  if (!movedEnough && !staleEnough) return;
}
// sameTypes == false 이면 조건 검사 없이 곧장 네트워크로 나간다
```

`_lastAmbientFetchTypes`는 **fetch 성공 경로 끝(1506행)에서만** 갱신된다. 429로 실패해도
그 앞에서 리턴되지 않으므로 갱신은 되지만, 줌 임계값 근처에서 타입 집합이 흔들리면
디바운스를 통째로 건너뛴다.

### 3-3. 캐시가 주행 중엔 절대 적중하지 않는다

`PoiRegionCache.tryGet`(`poi_service.dart:433`)의 적중 조건은 **저장 영역이 요청 영역을
완전히 포함**할 것:

```dart
entry.south <= south && entry.north >= north &&
entry.west  <= west  && entry.east  >= east
```

bbox는 `center ± 0.02°`로 만들어지므로 **1m만 움직여도 포함 관계가 깨진다.**
정지 상태 외에는 캐시 적중률이 사실상 0.

### 3-4. 실패 응답을 정상 캐시에 넣는다

`fetchPoisInBounds`는 429에서 `return []`(122행) → 호출부가 그 `[]`를 **정상 결과로
`put()`** 한다(`nav_screen.dart:1486`). 5분 TTL 동안 "이 지역엔 POI 없음"으로 굳는다.
→ **"고급휘발유 주유소 정보가 안 나옴"의 직접 원인일 가능성이 높다.** 429 폭주 중엔
어떤 주유소도 못 받아온다.

### 3-5. 취소되지 않는 요청

`_ambientFetchGen`은 **응답을 버릴 뿐 HTTP 요청을 취소하지 않는다.** 겹친 요청이
전부 30초 타임아웃까지 살아서 대역폭과 라디오를 붙잡는다. 로그의 "같은 밀리초에 2건"이
그 증거.

### 3-6. GPS 전력 설정

`map_providers.dart:73`

```dart
ref.keepAlive();                                    // 앱 생애 내내 안 죽음
Geolocator.getPositionStream(locationSettings: AndroidSettings(
  accuracy: LocationAccuracy.bestForNavigation,     // 최고 전력 모드
  intervalDuration: Duration(milliseconds: 1000),   // 1Hz 고정
  distanceFilter: 0,                                // 정지 중에도 매초 전달
  foregroundNotificationConfig: ...(enableWakeLock: true),
));
```

- `keepAlive()` 때문에 **홈/설정 화면에서도** bestForNavigation 1Hz가 계속 돈다.
- `distanceFilter: 0` + 정지 상태 → GPS 지터가 그대로 흘러들어 §5-1 재탐색 폭주로 연결.
- geolocator 자체 포그라운드 서비스 + `NavForegroundService.kt` + `WakelockPlus`
  → **wakelock 3중**, 알림도 2개.

### 3-7. 1.65GB 배분 (추정 — 실측 필요)

429 응답 69,875건 × Cloudflare 오류 페이지(수 KB) + TLS 핸드셰이크 + 타일 + 크래시
업로드. **정확한 배분은 §7 계측으로 확정한다.** 단, 요청 건수 자체가 비정상이라는 건
확정이다.

---

## 4. 근본원인 C 및 안내 계열

### 4-1. PIP 오진입 — `nav_screen.dart:455`

```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
    _maybeEnterPip();     // ← inactive가 너무 넓다
  }
}
```

`inactive`는 **알림창 내림 / 스크린샷 / 엣지패널 / 수신전화 다이얼로그**에서도 발화한다.
마스터 보고와 완전 일치.

정작 올바른 신호인 `onUserLeaveHint`(홈·최근앱 버튼)는 **이미 네이티브에서
`nav_pip_hint` 채널로 포워딩되어 있다**(`nav_screen.dart:381-397`, `MainActivity.kt`).
`inactive` 분기는 "화면 꺼짐 보완용" 폴백인데, 그게 오검출의 전부다.

### 4-2. 안내 10분 후 종료 · 히스토리 소실

세 요인이 겹친다:

1. PIP 오진입(4-1) → PIP 창 닫힘 = 액티비티 파괴 → 내비 종료.
2. `NavForegroundService.kt:68` `return START_NOT_STICKY` → 죽으면 재시작 안 함.
3. §2-3 크래시 폭주로 CPU가 계속 물려 삼성 배터리 관리자의 킬 대상이 됨.

`TourRecoveryService`는 **고아 트랙을 히스토리로 복구**하는 기능은 있다
(`tour_recovery_service.dart:12-21`). 마스터가 요청한 **"이어서 안내하기"(내비 재개)는
없다** — 별개 기능이다(§6 S8).

### 4-3. 음성 안내가 서로 중재되지 않는다 — 구조적 결함

`voice_engine.dart`에 **독립된 엔진이 4개** 있고, 각자 자기 pending 큐를 갖고
`SpeakIntent`를 뱉는다:

| 엔진 | 행 | 담당 |
|---|---|---|
| `VoiceEngine` | 47 | maneuver(회전·로터리·진출입) |
| `StructureVoiceEngine` | 182 | 교량·터널·지하차도 |
| `CurveVoiceEngine` | 255 | geometry 급커브 |
| `RearCameraVoiceEngine` | 329 | 후면단속카메라 |

**서로의 존재를 모른다.** 우선순위도, 상호 억제도, 최소 발화 간격도 없다.
`VoicePackService.speak`의 큐는 **직렬화만** 할 뿐(먼저 온 순서대로 전부 읽음), 버리지
않는다. → §1-3의 9연발.

**이건 설정 조정으로 못 고친다. 중재기(arbiter)를 신설해야 한다.**

### 4-4. 안내 거리 — 대부분 JSON 설정으로 해결 가능 ✅

`assets/config/guidance_profile.json`이 티어를 전부 데이터로 갖고 있다.

```json
"turn_right": { "imminent_m": 50, "tiers": [{"min_entry_m":500,"points_m":[500,300]}, ...] }
"roundabout": { "tiers": [{"min_entry_m":300,"points_m":[300,100,30]},
                          {"min_entry_m":80, "points_m":[80,20]},
                          {"min_entry_m":0,  "points_m":[20]}] }
"imminent_m": 10     // 전역 — 사실상 "해당 지점 0m 안내"
```

마스터 요구 대응:

| 요구 | 방법 | 난이도 |
|---|---|---|
| 모든 안내 50m 앞당김 (500→550, 300→350, 50→100) | `points_m`·`imminent_m` 값 수정 | **JSON만** |
| 0m(해당 지점) 안내 삭제 | 전역 `imminent_m: 10` 제거/상향 | **JSON만** |
| 원형교차로 진출 안내 전부 삭제 | `roundabout_exit` 이벤트 분리 후 비활성 | 소량 코드 |
| 원형교차로 진입 안내 횟수 축소 | `roundabout` tier 축소 | **JSON만** |

⚠️ 단, `_profileEventKey()`(`voice_engine.dart:41`)가 `roundabout_enter`와
`roundabout_exit`를 **같은 `roundabout` 키로 합쳐버린다.** 진출만 끄려면 이 매핑을
먼저 분리해야 한다.

### 4-5. "300미터"를 "천백미터"로 읽는 문제

- 음성팩 `source: "tts"` — **기기 한국어 TTS 엔진**이 `"300미터 앞 우회전입니다"`
  문자열을 읽는다(`voice_pack_service.dart`, `default_ko.json:16`).
- **로그 전수 확인 결과, 앱이 1100 같은 이상값을 내보낸 적은 없다.**
  실제 발화된 `dist` 값 집합: 0,4,6,8,9,10,…,300,400,500,1000.
  → 앱의 숫자 계산 오류는 **아님**. 기기 TTS 엔진의 숫자 읽기 문제로 좁혀진다.
- **결정론적 해법**: 템플릿에 아라비아 숫자를 넘기지 말고 **한글 수사로 미리
  렌더링**한다(`300 → "삼백"`, `1000 → "일 킬로미터"`). 엔진 의존성이 사라진다.
- 부수 효과로 §1-4의 "43미터 앞 우회전입니다"(비정형 값)도 함께 정리된다 —
  `_immediatePoint = entryD`(`voice_engine.dart:94`)가 원거리 실수값을 그대로 넣는
  경로이므로, 발화 전 **50m 단위 스냅**이 필요하다.

### 4-6. 지방도→동네길 좌회전 오안내

Valhalla가 도로 등급 변화를 무시하고 기하학적 각도만으로 `turn_left`(type 15/16)를
낸다. 억제 규칙이 앱에 **전혀 없다**(`eventForType`은 type→이벤트 단순 매핑).

**설계 방향**: `ManeuverStep`에 진입/진출 도로 등급(`road_class`)을 실어서, **등급이
유지되거나 올라가는 회전은 안내를 억제**하고 **낮은 등급으로 빠질 때만 안내**한다.
Valhalla 응답에 `road_class`가 오는지 먼저 계약 확인 필요(§7).

### 4-7. 원형교차로 출구 번호 오류

기존 조사 `loop/RECON_roundabout.md` §4에 **curl 실측**이 이미 있다:

```
type=26 "Enter 검단회전교차로 and take the 2nd exit"  →  roundabout_exit_count: 2
```

**Valhalla는 정상 값을 준다.** 따라서 "무조건 2번째 출구"는 앱 파싱 버그가 아니라
아래 둘 중 하나다:

- (a) 해당 지점 OSM 데이터에 미매핑 출구가 있어 Valhalla 카운트가 실제와 어긋남
- (b) 한국 회전교차로가 `highway=mini_roundabout`(노드)로 매핑되어 Valhalla가
  **type 26을 아예 안 내고 일반 우회전(type 9/10)으로 처리** → "원형교차로인데
  우회전이라고 안내함"이 이 경우다

**→ 추측 금지. 실주행 GPS 트랙에서 문제 지점 좌표를 뽑아 실제 Valhalla 응답 +
OSM 원본 태그를 대조하는 현장 데이터 조사가 선행되어야 한다(§6 S6a).**

### 4-8. 주유소 경유지 마커 미표시 — 원인 확정

`nav_screen.dart:1512`

```dart
Future<void> _initDestLayer() async {
  if (ctrl == null || _destLayerReady) return;
  _destLayerReady = true;                    // ← 1회만 실행
  for (final wp in widget.waypoints) { ... } // ← 불변 ctor 필드를 읽음
}
```

주석까지 명시적이다: *"목적지/경유지는 widget 생명주기 동안 불변이므로 1회만 설정한다"*.
그런데 실제로는 **주행 중 주유소를 경유지로 추가하는 기능이 있고**, 그 결과는
`_liveWaypoints`(가변 필드, `nav_screen.dart:378`)에 들어간다. `widget.waypoints`는
안 바뀌므로 **새 경유지 마커가 영원히 안 그려진다.** → 확정.

### 4-9. 자동차전용도로 — 소프트 패널티라 뚫린다

`routing_service.dart:157`

```dart
'use_highways': 0.0,
'highway_classes': { '0': 100 },   // motorway 회피 (penalty)
// '1' trunk 제거: use_highways:0.0이 이미 trunk 회피 처리
```

두 가지 문제:

1. **패널티는 금지가 아니다.** 대안이 없으면 Valhalla는 뚫고 지나간다.
   오토바이는 배기량 무관 **법적으로 통행 불가**(memory: 오토바이 법적 제약)이므로
   **하드 배제(`exclude`)여야** 한다.
2. **38번 지방도 사례의 핵심**: 한국의 자동차전용도로 상당수는
   `highway=motorway`도 `trunk`도 아닌 **`motorroad=yes` 태그가 붙은 일반 도로**다.
   `use_highways`/`highway_classes`는 **이 태그를 전혀 보지 않는다.**
   → Valhalla 포크의 코스팅 단계에서 `motorroad=yes`를 배제하도록 손대야 하며,
   이는 **`native/`(Rust)가 아니라 Valhalla 포크(C++) 작업**이다.

참고 자료로 마스터가 준 나무위키 자동차전용도로 목록은 **검증용 좌표 목록**으로 쓴다.

### 4-10. 터널 GPS 상실

`nav_state_provider.dart:216`에 속도 외삽은 있으나(`vCur + slope * sinceFix`),
**GPS 완전 상실 시 경로 위를 계속 전진시키는 추측항법(dead reckoning)은 없다.**
마스터 제안(직전 1분 평균속도 × 1.05로 터널 끝까지 보간)이 타당하다. 구조물 zone 데이터
(`StructureType.tunnel`)가 이미 있으므로 **터널 진입 인지 → GPS 끊김 감지 → 경로 shape를
따라 시간적분으로 위치 전진**이 구현 가능하다.

### 4-11. 시스템바 색상

현재 `main.dart:47`과 `nav_screen.dart:362`가 **둘 다 `kSystemBarColor`(불투명)**를
설정한다. 마스터 요구는:

| 화면 | statusBar | navigationBar |
|---|---|---|
| 홈 | 투명 | 투명 |
| 내비 | 투명 | 검정 |

단순 값 수정 + `dispose()` 복원 경로(`nav_screen.dart:488`) 동기화.

### 4-12. Google API 결제

**코드베이스에 유료 Google API 클라이언트는 없다.** 확인 결과:

| 의존성 | 과금 |
|---|---|
| `google_fonts` | 무료 (fonts.gstatic.com) |
| `geocoding: ^5.0.0` | Android 플랫폼 Geocoder — 무료 |
| `firebase_core/crashlytics/auth`, `google_sign_in` | 무료 티어 |
| `maplibre_gl` | 자체 타일서버 |

Google Maps SDK·Places API·Directions API **없음**. 매니페스트에 `com.google.android.geo.API_KEY`
**없음**.

**→ 이건 코드로 판정 불가.** 마스터가 GCP 콘솔에서 **결제 상세의 SKU 라인아이템**을
확인해 알려주면 그때 대응한다. 유력 후보: Firebase Blaze 요금제 전환 후의 부수 과금
(Cloud Storage / Identity Platform MAU / Crashlytics 대량 이벤트 전송).
**참고: 크래시 56,789건이 Crashlytics로 올라갔다** — 이것부터 멎으면 줄 수도 있다.

### 4-13. Valhalla CI 실패 (.eml)

```
Workflow: "Clear S3 cache (master on workflow_dispatch)"
Job: "Clear ccache on branch" failed — Duration 10.0s
```

**앱과 무관.** 업스트림 Valhalla 리포지토리에 딸려온 GitHub Actions 워크플로가
포크에 없는 S3 자격증명을 요구해 즉시 실패하는 것. 10초 만에 죽는 건 인증 실패의
전형. **조치: 포크에서 해당 워크플로 비활성화.** 우선순위 최하.

---

## 5. 재탐색 계열

### 5-1. 정지 상태 재탐색 폭주

`YNAV_REROUTE` 분당 최대 **151건**(06:31). 쿨다운은 있으나(`nav_screen.dart:802`
`cooldown skip`) 근본적으로 **정지 판정 자체가 없다.**

§3-6의 `distanceFilter: 0` + `bestForNavigation`이 정지 중에도 매초 지터 좌표를
흘려보내 오프루트 판정을 유발한다.

**설계**: 속도 < N km/h가 T초 이상 지속되면 **"정차 모드"**로 전환 — 재탐색·POI 조회·
카메라 추종을 전부 정지, GPS도 저전력으로 다운시프트. 마스터 요구
("주유소·편의점에서 쉴 때는 내비도 멈출 것")와 일치하고, 배터리에도 직접 기여한다.

### 5-2. 재탐색 origin

현재 로그: `YNAV_REROUTE off origin hdg=129.0 d=40` → **heading 방향 40m 오프셋이
이미 구현되어 있다**(`nav_screen.dart:842`, 근거: `RECON_heading_reroute.md §3`).
마스터 요구는 50m. **상수 하나 변경**(40 → 50)으로 끝난다.

### 5-3. "경로 표시가 마구 엉킴"

§2-5의 빈 리스트 `clamp` 예외가 재탐색 중 터지면 경로 레이어 갱신이 중간에 끊긴다.
`MissingPluginException(source#setGeoJson)` 431건도 같은 창에서 발생.
**A 수정 후 재측정하여 잔존 여부를 판단한다** — 별도 원인일 수도 있으므로 선입견 금지.

---

## 6. 수정 계획 — 세션 분할표

각 세션은 **독립적으로 완결·커밋 가능**하도록 잘랐다. CLAUDE.md 워크루프(목표게이트 →
코더 위임 → code-auditor → 커밋)를 세션마다 그대로 적용한다.

### 🔴 P0 — 출시 차단급 (이번 주)

| 세션 | 목표 | 범위 | 위임 | 예상 |
|---|---|---|---|---|
| **S0** | **앱 시작 시 내 위치 표시** (§8-5) | 스플래시에서 위치 선확보 → `initialCameraPosition`에 주입 + 첫 fix 도착 시 카메라 자동 이동 + `kInitialMapView` 최후폴백 격하 | flutter-coder | 반나절 |
| **S1** | 백화·크래시 완전 정지 | `daylight_bar.dart:109` 방어 + `clamp` 전수 감사(§2-5 12곳) + 릴리스 `ErrorWidget.builder` 폴백 + 위젯 최소높이 보장 | flutter-coder | 반나절 |
| **S2** | 네트워크 폭주 차단 | POI 디바운스 통일 + 429 서킷브레이커/지수백오프 + **실패를 캐시에 넣지 않기** + bbox 그리드 스냅(캐시 적중률) + in-flight 취소(`http.Client`) | flutter-coder | 1일 |
| **S3** | 라이프사이클 정상화 | PIP 트리거를 `onUserLeaveHint` 전용으로 + `inactive` 분기 제거 + FGS `START_REDELIVER_INTENT` + wakelock/알림 3중 정리 + PIP 중 지도 API 호출 가드 | flutter-coder | 1일 |

> **S1→S2→S3 순서를 지켜라.** S1이 크래시를 멎게 해야 S2·S3의 전력/데이터 측정이
> 의미를 갖는다.

### 🟠 P1 — 주행 품질 (다음 주)

| 세션 | 목표 | 범위 | 위임 |
|---|---|---|---|
| **S4a** | 안내 거리 재조정 | `guidance_profile.json` 값만 수정 (50m 앞당김, 0m 안내 삭제, 로터리 티어 축소) | 직접 편집 |
| **S4b** | **안내 중재기 신설** | `GuidanceArbiter` — 4개 엔진 출력 통합, 우선순위·최소간격(예 4초)·상호억제. 로터리 진출 안내 제거(`_profileEventKey` 분리 선행) | flutter-coder |
| **S4c** | TTS 숫자 한글화 | 거리 50m 스냅 + 한글 수사 렌더링 + 1000m→"일 킬로미터" | flutter-coder |
| **S5** | 정차 모드 + 전력 | 정차 감지 → 재탐색·POI·추종 정지, GPS 다운시프트. `keepAlive()` 재검토, 재탐색 오프셋 40→50m | flutter-coder |
| **S6** | **로터리 안내 재설계** (§8-3 원인 확정 — 조사 단계 불필요) | 출구 번호 발화 **폐기** → 진입/진출 방위차로 방향 직접 계산. `{exit}` 쓰는 템플릿 4종 교체 | flutter-coder |
| **S7** | 터널 추측항법 | 터널 zone 진입 + GPS 상실 감지 → 직전 1분 평균속도×1.05로 경로 shape 따라 위치 전진 | flutter-coder |
| **S8** | UI 잔여 | 시스템바 색상, 주유소 경유지 마커(`_initDestLayer` 재실행), 하단 카드 남은거리, 현위치 3초 교대 표시 | flutter-coder |

### 🟡 P2 — 데이터·라우팅 (Valhalla 포크 작업 포함)

| 세션 | 목표 | 비고 |
|---|---|---|
| **S9** | **자동차전용도로 하드 배제** | `motorroad=yes` 배제 — **Valhalla 포크(C++) 수정 필요.** 나무위키 목록으로 검증셋 구성 | 
| **S10** | 지방도 좌회전 억제 | `road_class` 계약 확인 → 등급 하락 시에만 안내 |
| **S11** | 고급휘발유 | S2 이후 재현되는지 먼저 확인 (429가 원인이면 이미 해결) |
| **S12** | 도로 색상 | 스타일 JSON — 국도만 노란색, 지방도 흰색 |

### 🟢 P3 — 기능개선 (별도 트랙, 출시 후 가능)

오프라인 지도 다운로드 / 투어 히스토리 병합 / 통합 검색 / 최근검색 리스트 /
점포명 거리순 정렬 / **이어서 안내하기** / 경로 색상·화살표 / 코스 공유(QR) /
지도 정보밀도 / OSMAND·Organic Maps 벤치마킹

> **모듈화 + Rust/C++ 이관 검토(마스터 항목 22번)에 대한 권고:**
> §0에서 밝혔듯 **지금 하지 마라.** 지도 렌더링은 이미 MapLibre Native(C++)가
> 담당하고 있고, 이번 실주행 결함 중 언어·아키텍처가 원인인 건 **하나도 없다.**
> P0~P2를 끝내고 재측정한 뒤, 그때도 남는 병목이 있으면 그 병목만 대상으로
> 판단하는 게 옳다.

---

## 7. 검증 방법

### 7-1. S1 — 크래시 검증 (플립7 로그 없이 결정론적으로, §8-1)

**(a) 위젯 테스트 — 주 검증 수단.** `DaylittBar`를 높이별 `ConstrainedBox`에 넣고
예외 발생 여부를 단정한다:

```
높이 = [0, 10, 24, 90, 118, 120, 285, 300, 800] px
합격 = 전 케이스 tester.takeException() == null
```

285px는 플립7 커버화면 논리높이 근사치 — **기기 없이 커버된다.**

**(b) 실기기 강제 리사이즈 — 보조.** A34에서
`adb shell wm size 720x748` + `wm density` 로 커버화면 치수를 흉내내 실렌더 확인.
종료 후 `adb shell wm size reset` 필수.

**(c) 조합 확인.** 세로/가로 × 코스시트 열림/닫힘 × 일반/PIP/분할화면에서
`Invalid argument(s): 0.0` **0건**.

### 7-2. S2/S3 — 전력·데이터 계측

가상GPS 하네스(memory: `project_vgps_testing` — GPS/NETWORK/FUSED 3-provider 모킹 필수)로
**동일 경로 1시간 자동주행**을 수정 전/후 각 1회:

```
측정: 설정>배터리>앱별 사용량 · 설정>데이터 사용량 · YNAV_POI 건수 · YNAV_CRASH 건수
합격: POI 요청 < 60건/시간, 429 = 0, CRASH = 0
```

### 7-3. S4 — 음성 로그 판정

동일 코스 재생 후 `YNAV_TTS` 라인만 뽑아 검사:

- 한 교차로당 발화 **3회 이하**
- 연속 발화 간격 **4초 이상**
- `roundabout_exit_*` **0건**
- `dist=` 값이 전부 50 배수

### 7-4. S6 — 로터리 방향 안내

§8-3 프로브 스크립트를 회귀 테스트로 재사용한다. 검단회전교차로 6개 조합에 대해
**앱이 계산한 방향(좌/직/우)이 실제 진입-진출 방위차와 일치**하는지 단정.
출구 번호는 더 이상 발화하지 않으므로 `exit_count` 값과 무관해야 한다.

### 7-5. S0 — 시작 위치

콜드 스타트(앱 강제종료 후 재실행) 10회 중 **10회 모두** 지도가 내 위치에서 열려야 한다.
"내 위치" 버튼을 누를 필요 없음. 기내모드/실내 등 fix 지연 상황에서도
폴백(청남대)에 머무르지 않고 **첫 fix 도착 시 자동 이동**하는지 확인.

---

## 8. 마스터 회신 반영 (2026-08-05, 확인 완료)

### 8-1. 플립7 로그 — 확보 불가로 확정, 대체 검증법으로 전환

플립7(SM-F766N)은 **동행한 반장의 폰**이며, 그 사건 이후 **유루나비 사용을 중단**했다
(사용자 이탈 1명 발생 — S1 우선순위 근거가 더 강해졌다). 로그 확보 확률 낮음.

**→ S1 검증을 로그 의존에서 떼어낸다.** 어차피 §2-1에서 메커니즘이 확정됐고,
크래시 조건은 순수 기하학이므로 **디바이스 없이 결정론적으로 재현 가능**하다:

1. **위젯 테스트** — `DaylightBar`를 높이 `[0, 10, 24, 90, 118, 120, 300]`px
   `ConstrainedBox`에 넣고 `expect(tester.takeException(), isNull)` 검사.
   플립7 커버화면(논리높이 ~285px)도 숫자로 커버된다.
2. **A34 실기기 강제 리사이즈** — `adb shell wm size 720x748` / `wm density`로
   플립7 커버화면 치수를 흉내내 실제 렌더 확인. 끝나면 `wm size reset`.

플립7 로그는 있으면 좋지만 **더 이상 블로커가 아니다.**

### 8-2. Google 결제 — 종결

**7월 5일 발생분, LLM-Wiki 작업으로 확인됨. 유루나비와 무관.** 스코프에서 제외한다.

### 8-3. 로터리 — 원인 확정 ✅ (앱 버그 아님)

마스터 회신: **"거의 모든 로터리에서 다 발생"**. 이 "체계적"이라는 정보가 결정타였다.
자체 Valhalla 서버에 직접 질의해 **재현 완료**.

**검단회전교차로(인천 37.5988,126.6506) 6개 경로 프로브 결과:**

| 진입 → 진출 | `roundabout_exit_count` |
|---|---|
| 남 → 동 | **2** |
| 남 → 북 | **2** |
| 남 → 서 | **2** |
| 북 → 남 | **2** |
| 동 → 서 | **2** |
| 서 → 북 | **2** |

프로브 4지점이 실제로 **서로 다른 way에 스냅**됨을 `/locate`로 확인
(`95158945` / `469981558` / `237078717` / `37405036`) — 즉 진짜로 다른 진입로다.
**같은 진입로(남)에서 세 방향으로 나가는데 셋 다 "2번째 출구"** → 최소 2개는 명백히 틀렸다.

**공개 업스트림 Valhalla(FOSSGIS)도 동일하게 `exit_count=2` 반환.**
→ **우리 포크의 결함이 아니다.** 업스트림 Valhalla + 한국 OSM 로터리 데이터 조합의
구조적 한계다. 포크를 고쳐 해결할 문제가 아니다.

**결론: 앱은 `roundabout_exit_count`를 신뢰하면 안 된다.**
앱은 Valhalla가 준 값을 충실히 읽어 발화했을 뿐이고, 파싱 버그는 없다
(`voice_engine.dart:126`, `routing_service.dart:798` 모두 정상).

**→ 대응 방향 전환 (S6 재정의):** 출구 번호 발화를 **폐기**하고, 경로 shape의
**진입 방위 vs 진출 방위 차이로 방향을 직접 계산**해 안내한다
("회전교차로에서 우측 방향으로 나갑니다"). 근거:

- 앱은 이미 shape/방위 계산을 갖고 있다(`native_engine.dart`, `PoiService.bearing`).
- memory `feedback_accurate_maneuver_wording` — **틀린 출구 번호를 말하느니 안 말하는 게 낫다.**
- 라이더가 실제로 필요한 정보는 "몇 번째 출구"가 아니라 "어느 방향으로 빠지냐"다.

> 잔여 항목: "원형교차로인데 우회전이라고 안내함"은 **별개 증상**이다
> (Valhalla가 type 26 대신 9/10을 냄 — `highway=mini_roundabout` 가설).
> 위 대응을 하면 방향 안내는 어차피 맞으므로 **우선순위가 크게 낮아진다.**

### 8-4. P1 순서 — 승인됨

**S4a(guidance_profile.json 값만 수정) 먼저** 진행한다.

### 8-5. 신규 결함 — 앱 실행 시 '청남대'가 뜬다 · 원인 확정 ✅

`main_map_screen.dart:62`

```dart
/// Last-resort map framing: first install + no last-known position.
const LatLng kInitialMapView = LatLng(36.5, 127.5); // 한국 지리 중심
```

**위도 36.5 / 경도 127.5 = 대청호 청남대 자리다.** 의도는 "최후의 폴백"이었으나
실제로는 **매 실행마다 여기가 걸린다.**

`main_map_screen.dart:1665`

```dart
initialCameraPosition: ml.CameraPosition(
  target: _toMl(_origin ?? _lastKnown ?? kInitialMapView),   // ← 첫 빌드 때 셋 다 평가
```

첫 빌드 시점에 `_origin`(GPS 스트림)도 `_lastKnown`(`getLastKnownPosition()`, `:254`에서
**비동기**로 채워짐)도 **아직 null**이라 폴백이 선택된다. 그리고 MapLibre의
`initialCameraPosition`은 **최초 1회만 읽힌다** — 이후 위치가 도착해도 카메라는
안 움직인다. 그래서 마스터가 직접 "내 위치" 버튼을 눌러야 한다.

**스플래시는 이미 1.7초 이상 놀고 있다** (`splash_screen.dart:50-52`:
200ms + 800ms 애니메이션 + 700ms). 그런데 위치는 **한 번도 요청하지 않는다** —
`_requestPermissions()`(`:63`)는 권한만 받고 스트림 provider를 invalidate할 뿐이다.

**→ 수정 방향 (S0, 마스터 요구 그대로):**

1. 스플래시 로고 애니메이션과 **동시에**(추가 지연 0) 위치 확보를 시작:
   `getLastKnownPosition()` 즉시 → `getCurrentPosition()`을 예산 2~3초로 대기
2. 확보한 좌표를 provider에 넣어 `MainMapScreen`의 `initialCameraPosition`이
   **첫 빌드부터 실제 내 위치**를 쓰게 한다
3. 그래도 못 얻었으면: 첫 실측 fix 도착 시 카메라가 아직 폴백에 있으면 **자동으로
   내 위치로 이동**시킨다 (현재는 영영 안 움직임)
4. `kInitialMapView`는 **권한 거부 + 마지막 위치 없음**일 때만 쓰이는 진짜 최후 폴백으로
   격하

---

## 8-A. 남은 블로커

없음. 위 5건 전부 회신 완료 — **S0/S1부터 즉시 착수 가능.**

---

## 9. 인접 참고 문서

- `loop/RECON_roundabout.md` — 로터리 Valhalla 계약 curl 실측 (§4-7 근거)
- `loop/RECON_heading_reroute.md` — 재탐색 heading 오프셋 설계 (§5-2)
- `loop/RECON_guidance_engine.md`, `RECON_guidance_redesign.md` — 안내 엔진 이력
- `loop/RECON_tour_history_lost.md` — 히스토리 소실 (§4-2)
- `loop/feedback/BUGFIX_progress.md` — 이전 실주행 피드백 진행표
