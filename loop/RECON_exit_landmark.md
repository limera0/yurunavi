# RECON — EXIT-LANDMARK (2026-07-11 밤)

BACKLOG.md의 EXIT-LANDMARK 항목 실행 전 조사. 대상: OSM `sign.exit_name_elements`가
없는 고속화도로/자동차전용도로 출구에서 "{인근 지명} 방면 {좌/우}측 출구입니다" 발화.

## 1. 좌/우 방향 필드 (검증 완료, 별도 조사 불필요)

`nav_screen.dart:1477-1478` `_labelForType()`에 이미 매핑되어 있음:
- Valhalla maneuver `type == 20` → "우측 출구" (kExitRight)
- Valhalla maneuver `type == 21` → "좌측 출구" (kExitLeft)

`voice_engine.dart`의 `eventForType()`도 `case 20: case 21: return 'exit';` — 이미 방향 정보가
type 자체에 있으므로 `ManeuverStep`에 새 필드 불필요. `steps[turnIdx].type == 21 ? '좌' : '우'`.

## 2. 랜드마크 데이터 소스 — 오프라인 mbtiles place 레이어 추출 (신규 결정)

기존 세션 추정("MapLibre `queryRenderedFeaturesInRect`로 재사용 가능")은 **틀렸음**:
그 API는 화면(스크린) 좌표 rect + 현재 렌더된 뷰포트 기준 쿼리라 지리적 반경 검색이 아니고,
내비 카메라가 도로 줌(16~18)일 때 3km 밖 지명은애초에 렌더되지 않아 못 찾음.

대신 서버의 `/data/tiles/data/korea.mbtiles`(OpenMapTiles `place` 레이어, minzoom0~maxzoom14)를
**빌드 시점에 1회 추출**해 앱에 번들: `scripts/build_place_index.py` →
`assets/data/kr_places.json` (지명 5,412개: city 85 / town 1,412 / village 3,915, 426KB).

- 추출 줌: z10 (534타일, 전수 처리) — city/town/village 밀도와 처리량의 균형점.
  z8은 부족(빌리지 다수 누락), z12+는 hamlet까지 폭발적으로 늘어 랜드마크로 부적합.
- MVT point 좌표를 tile-local px/py → lon/lat 변환 시, **버퍼(타일 경계 밖 중복 사본)
  좌표를 반드시 제외**해야 함(`0<=px<extent && 0<=py<extent` 필터). 안 걸러내면 같은
  지명(예: 서울특별시)이 인접 타일에 최대 0.5도(약 55km) 어긋난 좌표로 중복 추출됨 —
  버그 재현/수정 과정 `scripts/build_place_index.py` 주석 참조.
- mbtiles 선언 bbox(124.32~132.34E, 32.36~38.65N) 밖으로 계산되는 잔여 오차(동해안 DMZ
  인접 7건, 최대 0.2도)는 최종 bbox 필터로 제거.
- 이름 필드: `PoiNameResolver`와 동일 관례로 `name:nonlatin` → `name` fallback(한국어 전용
  보이스팩이라 latin 변형은 저장 안 함).

## 3. 검색 로직

- 출구 maneuver 위치: `RouteResult.points[step.beginShapeIdx]` (nav_screen `_routePoints`에
  이미 보관 중, voice_engine에 새 파라미터로 전달 필요).
- 반경 3km 이내 후보 중 **class 우선순위(city>town>village) 먼저, 동급이면 최근접**을 선택.
  ("주요" 지명 우선 — 500m 거리의 리 단위 마을보다 2.9km의 읍내가 있으면 읍내를 말함.)
- 후보 없으면 기존처럼 이름 없는 "진출"/"진입" 그대로 유지(회귀 없음).
- 우선순위: `exitName`(OSM, feat/exit-name-voice) > `landmark`(오프라인 폴백, 본 작업) > 평문.

## 4. 구현 위치

- `lib/services/exit_landmark_service.dart` (신규) — `VoicePackService.load()`와 동일하게
  앱 시작 시 1회 비동기 로드 후 동기 `nearestLandmark(LatLng)` 제공. haversine 선형 스캔
  5,412건 — 출구 maneuver 진입 시(스텝 전환 1회)만 호출하므로 공간 인덱스 불필요.
- `voice_engine.dart` — `_voiceStepIdx` 전환 시점(스텝당 1회)에 랜드마크 조회해 캐싱,
  매 progress tick마다 재스캔하지 않음.
- 기존 테스트 호환: `VoiceEngine` 생성자·`onProgress()` 모두 신규 파라미터를 **named
  optional**로 추가(하위호환, 기존 67개 테스트 무수정).

## 5. 브랜치 전략

`feat/exit-landmark-voice` = `feat/exit-name-voice` 기반(그 브랜치의 `exitName` 파싱이
선행조건). T3이므로 라이딩 검증 전 main 머지 금지 — `verify/ride-0711` 통합 브랜치로
osm-road-style 등 이번 밤 다른 T3 산출물과 함께 묶어 APK 1회 빌드.
