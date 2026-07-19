# REPORT_PATCH6 — 재탐색 버튼 heading 누락 + 좌/우회전 임계값 재조정

작성일: 2026-07-19. 배경: 송탄→팔당 실주행(1/3 지점 수원 영통까지) 피드백 8건 중 2건(#4, #5) 처리.

## 1. `_openCourseSheet()`(재탐색 버튼) heading 오프셋 누락 — fix

`_reroute()`(이탈 시 자동 재탐색)는 `offsetOrigin(heading, 40)`으로 origin을 진행방향
40m 앞으로 밀어서 Valhalla가 반대편(뒤쪽) 엣지에 스냅하지 않도록 하는데, 사용자가 직접
누르는 "재탐색" 버튼(`_openCourseSheet()`, 코스 재선택 시트)은 이 오프셋 없이 raw GPS
좌표를 그대로 보내고 있었다 — 두 함수가 같은 상황(주행 중 재탐색)을 처리하는데 한쪽만
보정이 빠진 불일치. 사용자 피드백 "재탐색 버튼을 눌러도 heading은 무시하고 뒤로 돌아가는
길을 안내함"과 정확히 일치.

`nav_screen.dart:_openCourseSheet()`에 `_reroute()`와 동일한 heading 오프셋 로직 추가.

**주의(범위 밖으로 확인된 부분)**: `loop/RECON_heading_reroute.md`(기존 recon)는 Valhalla
`heading`/`type`/`preferred_side` 파라미터 자체는 이 포크에서 이미 효과가 없음을 curl로
확인해뒀다 — 즉 origin 오프셋 트릭도 만능은 아니다(분리대 있는 도로에서 목적지 쪽 U턴은
오프셋으로 못 없앤 사례 있음). 이번 수정은 "두 재탐색 경로의 동작을 일치시키는" 수준이고,
Valhalla 자체의 heading 무시 문제(§Q4)는 여전히 미해결 — 필요시 별도 세션에서 loki/thor
레벨 조사 이어갈 것.

## 2. 좌/우회전 각도 임계값 재조정 — turn.cc

기존(patch4, 2026-07-18): Right 20-99° / SharpRight 100-159° (Left/SharpLeft 대칭 미러).
일반 사거리(~90-100°) 좌회전 2건이 "급좌회전"으로 오분류됨(37.07458,127.05609 서탄로,
그리고 동부대로→밀머리로 구간) — 마스터 요청으로 Right 20-119° / SharpRight 120-159°로
확장(Left/SharpLeft 대칭 이동).

- 이미지: `valhalla-fork:patch6-turnangle2` (`docker/Dockerfile.fork`, patch5 위에 누적)
- 회귀 검증: 송탄→팔당, 송탄→(동부대로 인근 OD) 2쌍 모두 patch5(8002)와 patch6(8016) length/
  time 완전 동일 (narration-only, patch4 때와 동일한 결론 재확인)
- 실제 확인: 같은 OD에서 patch5는 "Make a sharp left onto 서탄로" / "Make a sharp left onto
  동부대로"였던 것이 patch6에서 "Turn left onto 서탄로" / "Turn left onto 동부대로"로 변경됨
- 프로덕션(8002) 교체 완료, `docker/docker-compose.yml` 이미지 태그 갱신, 임시 테스트
  컨테이너(8016) 제거 완료
- `valhalla-src`(yurunavi-fork 브랜치) 로컬 커밋 `637ca089e` — origin push 안 함,
  오프사이트 백업(`valhalla-yurunavi-fork`)에 올릴지는 기존 관례대로 마스터 확인 필요

## 3. 남은 것 (#1 관련, 별도 조사 필요)

사용자가 지적한 "좌회전 자체가 물리적으로 불가능한 곳"(37.09172,127.09205 / 37.13696,
127.07838, 중앙분리대로 막힌 곳)은 이번 임계값 조정과는 별개 문제 — 각도 재조정은
"급좌회전 표현이 과했다"는 것만 고치고, "그 방향으로 꺾는 것 자체가 불가능하다"는
issue는 여전히 남아있다. 동부대로→밀머리로 구간은 좌표상 이번 회귀테스트 OD의
목적지와 일치하는 것으로 확인됨 — 이어서 조사 예정.
