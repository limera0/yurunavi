# MORNING REPORT — S10 회전 안내 등급 억제 · S12 도로 색상

- 작성 2026-08-07 (저녁 대화형 세션) · 브랜치 `verify/ride-0711`
- 지시서: [HANDOFF_0807_S10_grade_based_turn_suppression.md](HANDOFF_0807_S10_grade_based_turn_suppression.md)
- 체크리스트: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S10, §S12
- 착수 전 S10~S13 전체를 마스터에게 4개 질문으로 확인 후 진행(범위/타이밍/색상매핑/
  스코프 예외 여부) — S11은 **보류**, S13은 **이번 스코프 제외** 결정.

---

## S12 · 도로 등급별 색상 분리

커밋 `45580bd`. 마스터 첨부 `loop/testride_result/road_color.jpg`(네이버지도)에서
고속도로/국도 라인 픽셀을 직접 샘플링해 색상 추출, 마스터가 최종 매핑 확정.

- `trunk`+`primary`(국도) = `#F8D49A`
- `secondary`(지방도) = `#FDF0B4`
- `tertiary`+`minor`/`service`/`track`(나머지) = `#FFFFFF`
- `motorway`(고속도로)는 색상·굵기 **미변경**
- 본선(line)+케이싱(casing)+터널+교량 레이어 전부 통일 적용, `highway-link`(ramp,
  기존엔 전 등급이 `#fea` 단일색 공유)도 등급별 `case` 분기로 교체

로컬 tileserver-gl(`http://localhost:8080`, `korea.mbtiles`)에서 실제 벡터타일을
가져와 새 색상으로 렌더링한 미리보기로 위계를 확인했다(스타일 파일 자체는 앱
번들 asset이라 서버 쪽 파일은 건드리지 않고 읽기 전용으로만 사용).

**잔여**: OSMAND·네이버지도 육안 대조는 마스터 몫으로 남김(실기기).

---

## S10 · 회전 안내 등급 기반 억제

커밋 `35d29e1`. 마스터 확인: **모든 회전 방향**(좌/우/직진 갈림 전부, 체크리스트
제목의 "좌회전"보다 넓은 범위)에 적용.

### 착수 전 계약 확인 (curl 실측)

- `/route`의 `maneuvers`엔 `road_class`가 없다.
- `/trace_attributes`의 `edges`엔 `edge.road_class`를 요청하면 포함된다 — **기존에
  다리/터널 판정용으로 이미 호출 중인 그 trace_attributes**에 속성 하나만 추가해
  재사용(신규 HTTP 호출 없음, S2 429 사고 재발 방지).
- Valhalla `RoadClass` enum 순서 확인(`/data/projects/valhalla-src` 로컬 소스
  대조): motorway(0) > trunk(1) > primary(2) > secondary(3) > tertiary(4) >
  unclassified(5) > residential(6) > service_other(7).

### 구현

- `routing_service.dart`: `buildRoadClassByManeuverIdx`(edges→maneuver별 진입/진출
  등급), `isGradeDowngrade`(등급 하락 여부, 데이터 없으면 **fail-open=정상 안내**),
  `fetchStructureZones` 시그니처 확장(zones + roadClasses 레코드 반환, HTTP 호출은
  그대로 1회).
- `route_progress_provider.dart`: `exitStructureByManeuverIdx`와 동일한 별도-맵
  패턴으로 `roadClassByManeuverIdx` 추가, `setRoute()`에서 리셋.
- `voice_engine.dart`: `onProgress`에 `_gradeSuppressible` = {turn_left, turn_right,
  sharp_turn_left, sharp_turn_right, keep, keep_left, keep_right}에 대해서만 등급
  유지·상승 시 억제. ramp/exit/roundabout/uturn/merge/destination/continue는
  등급 무관 항상 정상 안내.
- `ManeuverStep`엔 필드를 추가하지 않았다 — trace_attributes 비동기 도착 타이밍
  문제가 구조물(zone)과 동일해, 기존 `exitStructureByManeuverIdx` 패턴을 그대로
  재사용하는 쪽이 불변 클래스에 필드를 추가하는 것보다 적합하다고 판단(HANDOFF에
  근거 기록).

### 의도적 스코프 제한

**음성만 억제, 화면 상단 턴 카드(`_TurnStep`)는 그대로.** 등급 유지 갈림길에서
카드는 계속 "좌회전"을 보여주지만 음성은 조용하다. 카드까지 고치려면 거리
재계산·"현재 안내" 포커스 로직까지 건드려야 해서 이번 스코프(안내="음성" 억제)를
넘어선다 — 숨기지 않고 체크리스트에 별도 미완료 항목으로 남김.

### 검증

- `flutter analyze`: 이슈 0
- `flutter test`: **675건 전건 통과** (신규 46건 포함: `routing_service_road_class_test.dart`,
  `voice_engine_grade_suppression_test.dart`)
- code-auditor: **1차 PASS**. 특히 확인된 항목 — fail-open 정확성, 이벤트 스코프
  정확히 7종만, trace_attributes 호출 여전히 1회, 진입/진출 shape-index 매칭
  방향 정확, `ManeuverStep` 불변 유지, `setRoute()` 리셋 확인. 감사가 지적한
  비차단 사항 1건(작업 중이던 `loop/STATUS.md`를 커밋에 섞지 말 것)은 커밋 시
  6개 대상 파일만 정확히 스테이징해 반영.

### 잔여

- **화면 카드 미반영** (위 스코프 제한 참조) — 후속 검토 필요 시 별도 항목화.
- **실기기 검증 대기**: 국도→지방도 갈림길(등급 하락, 안내 나와야 함) vs 지방도
  내 등급 유지 갈림길(안내 없어야 함) 실주행 확인 — 38번 지방도 인근 등 마스터가
  아는 지점 활용 가능.

---

## S11 · 보류, S13 · 스코프 제외 (참고)

- **S11**(고급휘발유 미표시): 착수 조건이 "S2 완료 후 재현 확인"인데 S2(429
  서킷브레이커)가 아직 마스터 실기기 검증 대기 상태라 마스터가 **보류**를
  선택. 이번 세션에서 손대지 않음.
- **S13**(Valhalla CI "Clear S3 cache" 워크플로 비활성화): 대상이 이 저장소가
  아니라 별도 로컬 체크아웃(`/data/projects/valhalla-src`, backup 리모트
  `limera0/valhalla-yurunavi-fork`)이라 CLAUDE.md "이 저장소로 범위 고정" 하드룰과
  충돌 — 마스터가 **이번 스코프 제외**를 선택. 우선순위 최하이기도 해 후순위로
  남김.

---

**목표 달성 판정:**
- S12(도로 등급별 색상): 원래 목표 — 국도/지방도/나머지를 참고 이미지 기반으로
  구분. / 달성: **코드 완료 — yes**(마스터가 색상 매핑을 직접 확정한 스펙 그대로
  구현). 실기기 육안 대조는 **마스터 대기**.
- S10(회전 안내 등급 억제): 원래 목표 — 등급 유지·상승 회전 안내 억제, 하락 시만
  안내. / 달성: **코드 완료 — yes**(마스터가 확정한 "모든 방향" 범위 그대로,
  code-auditor 1차 PASS). 화면 카드 반영은 **의도적 스코프 밖**, 실기기 시나리오
  검증은 **마스터 대기**.
- S11: 착수하지 않음 — **보류**(마스터 결정, S2 검증 선행 필요).
- S13: 착수하지 않음 — **스코프 제외**(마스터 결정, 저장소 범위 하드룰 충돌).
