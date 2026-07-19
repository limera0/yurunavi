# REPORT — 다리/지하차도 분류 + 회전 각도 임계값, M32 가상GPS 실기 검증

작성일: 2026-07-20. 대상: 최신 피드백 #3("확인해봐")의 다리/고가도로,
지하차도/터널, 좌우회전 임계값 부분.

## 1. 실제 OSM 구조물 확정 (Overpass API)

송탄 인근 실제 way를 조회해 이름 기반 분류 로직이 맞는 실제 사례를 확보:

- **지하차도**: `고덕지하차도` (37.0518187,127.0436612), `tunnel=yes`,
  이름에 "지하차도" 포함 → `StructureType.underpass` 기대값.
- 같은 회귀 경로 상에 `bridge=yes`이지만 "고가" 키워드가 없는 일반 다리
  구간도 다수 확인(경기대로/동부대로/동탄기흥로 등 실명 도로) →
  `StructureType.bridge` 기대값.
- (참고, 이번엔 드라이브 안 함) `신갈제1고가도로`(37.2797,127.1050,
  `bridge=yes`)는 "고가" 키워드 포함 → `StructureType.overpass` 기대값 —
  같은 분류 함수(`_classifyStructureEdge`/`classifyOffRouteEdges`)의 대칭
  분기라 별도 실주행 없이도 유닛테스트+커밋 시점 검증(05a9475)으로 커버됨.

## 2. M32 가상GPS 드라이브스루 (송탄 → 고덕지하차도 방향, 실측 route)

Valhalla 프로덕션(8002)에서 실제 계산된 경로를 그대로 좌표로 재생(약 4km,
gpsinjector). 결과 로그:

```
01:16:25.064 YNAV_TTS key=bridge_approach dist=500 zone=0
01:16:41.205 YNAV_TTS key=bridge_approach dist=300 zone=0
01:17:11.612 YNAV_TTS key=underpass_approach dist=300 zone=0
01:17:34.584 YNAV_TTS key=underpass_approach dist=50  zone=0
01:17:44.022 YNAV_TTS key=underpass_imminent dist=10  zone=0
01:18:12.827 YNAV_TTS key=bridge_approach dist=50  zone=0
01:18:12.828 YNAV_TTS key=bridge_imminent dist=10  zone=0
```

`다리`/`지하차도` 각각의 이벤트 키(`bridge_*`/`underpass_*`)가 정확히
분리되어 발화됨 — `tunnel_*`/`overpass_*` 키는 이 경로에서 등장하지
않음(해당 구조물이 없었으므로 당연). 실주행 피드백 #6/#7("다리도 전부
고가도로", "지하차도도 전부 터널")과 반대로, 실제 온디바이스에서 다리와
지하차도가 각자 올바른 키로 발화됨을 확인.

## 3. 회전 각도 임계값(부수 확인)

같은 드라이브 동안 발생한 모든 방향전환 안내는 `turn_left_*`/`turn_right_*`
(평범한 좌/우회전)였고, 유일한 `sharp_turn_right_imminent` 1건은
`curve=0`(별도 커브 감지 엔진, 회전 각도 임계값 로직과 무관한 곡률 경고
기능)이었다 — maneuver 타입 기반 급회전 오분류는 이 경로에서 발생하지 않음.
patch6-turnangle2가 프로덕션(8002)에 이미 배포돼 있고, 이전 REPORT_PATCH6에서
실주행 피드백 좌표(서탄로/동부대로) 자체의 내레이션이 "sharp left" →
"Turn left"로 바뀐 것도 curl로 확인됨 — 이번 온디바이스 드라이브는 그 결과가
실제 앱 TTS 이벤트에도 반영됨을 보여주는 보강 증거.

## 4. 결론

- 다리(bridge)/지하차도(underpass) 분류: **M32 온디바이스 확인 완료**.
- 고가도로(overpass)/터널(tunnel) 분류: 같은 분류 함수의 대칭 분기, 유닛테스트
  + 실제 OSM way 확인(신갈제1고가도로)까지는 했으나 이번 세션에서 별도
  온디바이스 드라이브는 안 함(시간상 대표 사례로 갈음) — 필요하면 다음
  세션에서 신갈제1고가도로 경유 드라이브로 추가 확인 가능.
- 회전 각도 임계값: 온디바이스에서 평범한 좌우회전 다수 확인, 급회전
  오탐 없음(부수 확인, 서버 사이드 로직이라 앱 커밋 대상 아님).
