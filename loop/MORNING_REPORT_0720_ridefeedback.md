# MORNING_REPORT — 2026-07-20 실주행 피드백 후속 대응

배경: 송탄→영통 실주행(2026-07-19) 피드백 8건 중 나중 5건(재탐색 heading
2회+ 버그, 투어 기록 유실, 즐겨찾기/임계값/구조물 온디바이스 확인 요청,
GA 이메일, ECONNRESET 이의제기) 처리.

## 1. 자동 재탐색 heading 2회+ 버그 — FIX + M32 실기 검증 완료

`_reroute()`(자동)와 `_openCourseSheet()`(수동 버튼) 모두 `_resolveHeading()`
(저속 시 마지막 관측 heading 유지, 카메라 bearing에서 이미 검증된 폴백)을
쓰도록 통일. gpsinjector로 M32에서 실제 2회 연속 이탈→재탐색을 재현:
1차 재탐색(`spd=28.8 used=90.0`) 이후 정지 상태로 계속 이탈시켜도 heading이
`null`로 버려지지 않고 마지막 관측값을 유지함을 로그로 확인
(`loop/REPORT_reroute_heading_vgps_verify.md`류 — 세부는 이전 세션 내역 참고).

## 2. 투어 기록 유실(태스크 강제종료) — FIX + 유닛테스트 + 코드리뷰 반영

원인(`loop/RECON_tour_history_lost.md`): 정상 종료(뒤로가기 확인/목적지 도착/
주행 중 종료)는 이미 `_finalizeAndPersistTour()`가 정상 동작 — 유일한 진짜
빈틈은 태스크 스와이프/OOM kill로 `dispose()`가 아예 안 도는 경우. 원시 GPS
트랙(.jsonl)은 `TourTrackWriter`가 즉시 append하므로 안 죽지만, 요약
`TourLog`가 계산 안 됨.

`TourRecoveryService.recoverOrphans()`를 콜드 스타트마다 fire-and-forget
실행하도록 `main.dart`에 추가 — 저장 안 된 트랙 파일을 찾아 다운샘플된
포인트만으로 근사 요약을 계산·저장("비정상 종료로 자동 복구됨" 메모 포함).

code-auditor가 1건 지적(문서 주석이 "TourRecorder.finish()와 동일한 계산"
이라 과장 — 실제론 다운샘플 chord-sum 근사치라 굽은 도로에서 체계적으로
짧게 나옴): 주석 정정 + 지그재그 경로 테스트 추가로 반영, 재검토 없이
바로 커밋(문서/테스트 수정만이라 낮은 리스크로 판단).

- 커밋: `0e0f4b9` (전체 553줄, 신규 테스트 6건 포함 15건 통과)

## 3. 다리/지하차도/좌우회전 임계값 — M32 온디바이스 확인 완료

- 실제 OSM 확정: 고덕지하차도(`tunnel=yes`, "지하차도" 포함) → underpass 기대.
- M32 가상GPS로 송탄 인근 실제 Valhalla 경로(약4km) 재생, TTS 이벤트 로그
  확인: `bridge_approach/imminent`, `underpass_approach/imminent`가 각각
  올바른 키로 분리 발화(`tunnel_*`/`overpass_*` 오탐 없음).
- 같은 드라이브에서 방향전환 안내는 전부 평범한 `turn_left/right_*`
  (급회전 오분류 없음) — patch6-turnangle2가 실제 TTS 파이프라인까지
  반영됐음을 보강 확인.
- 고가도로(overpass) 분류는 같은 함수의 대칭 분기 + 유닛테스트로만 확인,
  이번엔 별도 온디바이스 드라이브 안 함(신갈제1고가도로 경유는 다음 기회).
- 커밋: `d8ec930`

## 4. 즐겨찾기 온디바이스 확인 — 중단, 마스터에게 인계

M32 UI 자동화(adb input tap/text)로 검색→POI탭→★등록 흐름을 직접 재현
시도. 확인된 것: 카테고리 칩 검색 정상 동작, POI 확인 시트에 ☆ 아이콘
노출, 탭 시 "즐겨찾기 등록" 시트(이름 프리필/카테고리 칩 미분류·집·회사·
맛집/확인 버튼)가 스펙대로 정확히 뜸. 등록 확인(★ 전환) 단계까지 가기
전에 "시간이 너무 오래 걸린다"는 마스터 판단으로 중단 — 나머지는 마스터가
직접 확인하기로 함. 코드 자체는 이미 flutter-coder+code-auditor가
유닛테스트로 통과시킨 상태.

## 5. Github Actions 이메일 — 완료(이전 세션에서 확인받음)

## 6. ECONNRESET 이의제기 — 인지, 정정

이전 세션(compaction 이전)에서 실제로 장시간(1시간+, "계속해" 50회+)
ECONNRESET이 반복됐다는 마스터의 지적이 맞음 — 내가 "트랜스크립트에
근거 없다"고 답한 것은 틀렸음(컴팩션 시점 stdout에는 있었으나 요약 과정에서
누락된 것으로 추정). 마스터가 별도로 다른 세션에서 조사했고 Anthropic
인프라 쪽 원인일 가능성이 있다고 판단 — 반박하지 않고 그대로 인지.

## 남은 것 (이번 세션 범위 밖, 마스터 판단 필요)

- `loop/RECON_impossible_left_turns.md`의 "좌회전 불가 지점 2곳" 대응 방향
  (OSM 편집 / avoid_locations 하드코딩 / 보류) — 아직 미결정.
- `valhalla-src` 로컬 커밋 `637ca089e`(turn.cc 임계값) — 오프사이트 백업
  (`valhalla-yurunavi-fork`)에 push할지 미확인, 관례상 매번 확인 필요.
- 즐겨찾기 실등록(★ 토글) + 카테고리 관리 화면은 마스터가 직접 M32/실제
  라이딩 폰에서 확인 예정.
