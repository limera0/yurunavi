# REPORT — 음성/카드 문구 전면 개편 + Valhalla 회전각 재조정 (2026-07-18)

작성일: 2026-07-18

---

## 1. 목표

`loop/VOICE_MESSAGES_KO_REVIEW.csv`로 내비게이션 이벤트별 카드 상단 메세지 + TTS 메세지를
전수 CSV화해 사용자가 검토·교정 → 그 결과를 코드에 반영. 검토 과정에서 파생된 두 가지
추가 작업(ramp/exit 방향별 세분화, Valhalla 회전각 임계값 재조정)도 같은 세션에서 처리.

## 2. 변경 내역

### 2-1. 음성/카드 엔진 로직 (yurunavi, `verify/ride-0711`, 커밋 `2a77e4e`)

- **imminent_fast 개념 완전 삭제** — turn_left/right의 imminent는 속도 무관하게 항상
  "곧 ~"(예전엔 `speedKmh>=20` 조건부 `_fast` 접미사였다가, 이전 세션에 이미 무조건화된
  상태였는데 이번에 아예 별도 키 자체를 없앰). 더 이상 안 쓰는 `VoiceEngine.onProgress`의
  `speedKmh` 파라미터와 호출부(`nav_screen.dart`) 인자도 같이 제거.
- **ramp(유형17/18/19)·exit(유형20/21)을 방향별 이벤트로 분리**: `eventForType`이
  `ramp`/`exit` 하나로 뭉치던 걸 `ramp_straight`/`ramp_right`/`ramp_left`,
  `exit_right`/`exit_left`로 분리. 거리 티어/imminent 설정(`guidance_profile.json`)은
  `_profileEventKey`가 다시 `ramp`/`exit`로 매핑해 공유 — JSON 설정 변경 없이 텍스트
  키만 세분화됨. `direction`/`direction_word` 변수는 방향이 이벤트 키 자체에 들어가므로
  삭제.
- **roundabout_exit이 직전 enter maneuver의 출구번호를 이어받음**: 진출 maneuver
  자체엔 출구번호 데이터가 없어서(Valhalla 응답 확인됨, `loop/RECON_roundabout_direction.md`
  §1/§5) `steps[turnIdx-1]`(직전 enter step)에서 읽어와 `roundabout_exit_imminent_named`
  키("곧 N번째 출구입니다")로 발화. 출구번호를 모르면 기존 `roundabout_exit_imminent`
  ("곧 진출입니다")로 자동 폴백(`VoicePackService.resolveTemplate`의 `_named` 폴백 재사용).
- **underpass(지하차도)가 tunnel 이벤트로 잘못 안내되던 버그 수정**: `StructureVoiceEngine`이
  `type == bridge ? 'bridge' : 'tunnel'`로 이분법이었던 걸 bridge/tunnel/underpass 3분기로
  수정. `guidance_profile.json`에 `"underpass": {"enabled": true}` 추가.
- **카드 라벨 전면 교정** (`nav_screen.dart` `_labelForType`): 완만한 좌·우회전(9/16),
  급한 좌·우회전(11/14), 우측·좌측으로 진입(18/19)·진출(20/21), 우측·좌측 차선(23/24,
  기존 "우회전"/"좌회전"으로 갈 뻔했으나 실제 회전이 아니라 갈림길 차선선택이라 혼동
  우려로 사용자가 최종 반려), 합류구간(25) 등. 도착배너 텍스트는 "목적지 도착"으로 축약
  (TTS는 "목적지에 도착했습니다" 그대로 유지).
- **TTS 문구 전체 재작성** (`default_ko.json`, version 2→3): "~입니다" 종결 통일,
  ramp/exit 12+16개 신규 키, underpass 2개 신규 키.
- 관련 테스트 9개 갱신 + `voice_engine_speed_test.dart` 삭제(다루던 개념 자체가 없어짐,
  유효한 `_named` 폴백 테스트만 `voice_engine_exit_name_test.dart`로 이관) + roundabout
  출구번호 이어받기/underpass 분리 신규 회귀 테스트 추가.
- **검증**: `flutter analyze` 0 issues, `flutter test` 246/246.

### 2-2. Valhalla 회전각 임계값 재조정 (`valhalla-src`, `yurunavi-fork`, 커밋 `6e374e021`)

CSV 검토 중 "유형9/16(약간 좌·우회전)을 카드에서 어떻게 표기할지" 논의에서, 사용자가
"완만한 좌·우회전 문구는 유지하되 대신 Valhalla의 각도 분류 기준 자체를 조정하자"고 결정.

`src/baldr/turn.cc`의 `Turn::GetType` 룩업테이블(0~359° 룩업)을 재조정, 0°/180° 축 기준
좌우 대칭 유지:

| | 기존 | 신규 |
|---|---|---|
| SlightRight | 11-44° | **11-19°** |
| Right | 45-135° | **20-99°** |
| SharpRight | 136-159° | **100-159°** |
| SharpLeft | 201-224° | **201-260°** |
| Left | 225-315° | **261-340°** |
| SlightLeft | 316-349° | **341-349°** |

kStraight(0-10/350-359)·kReverse(160-200)는 변경 없음. 자체 유닛 테스트(`test/turn.cc`)도
새 경계값에 맞게 갱신.

**부수 발견**: 이 룩업테이블은 나레이션 분류뿐 아니라 Valhalla 스톡 코드의 표준
교차로 회전비용 테이블(`motorcyclecost.cc`의 `kRightSideTurnCosts`/`kLeftSideTurnCosts` —
YuruNavi 고유 로직 아님)에도 쓰임. 다만 영향은 턴당 초 단위(0.5~3.5초×stopimpact)이고,
실제 곡률 기반 fun-road 스코어링(`curvature_penalty_`/`edge->curvature()`)은 완전히
별개 메커니즘이라 이번 변경과 무관.

## 3. 빌드

| 항목 | 내용 |
|---|---|
| 이미지 태그 | `valhalla-fork:patch4-turnangles` |
| 기반 | `docker/Dockerfile.fork` (patch1~3과 동일) |
| 빌드 커맨드 | `docker build -t valhalla-fork:patch4-turnangles --build-arg CONCURRENCY=2 -f docker/Dockerfile.fork .` |
| 결과 | 에러 0건, 923MB |

## 4. 검증 (포트 8015, `valhalla-fork-p4`, 검증 후 제거됨)

4개 실경로(신장동 로터리, 고덕좌교로, 평택 시내 A/B)로 8002(패치 전) vs 8015(패치 후)
A/B curl:

- **회귀 없음**: 4개 경로 전부 `time`/`length` 완전 동일(0.00초 차이) — 각도 재분류가
  실제 경로 선택·소요시간에는 영향 없음.
- **긍정 검증**: 4개 중 3개 경로에서 maneuver `type` 시퀀스가 실제로 달라짐(예: 신장동
  로터리에서 9→10, "약간 우회전"이 새 기준상 "우회전"으로 재분류) — 의도한 변경이
  정확히 작동함을 확인. 1개(고덕좌교로)는 그 경로의 회전각이 재분류 경계와 무관해 변화
  없음(정상).

## 5. 배포

- `docker/docker-compose.yml`의 `image:` → `valhalla-fork:patch4-turnangles` 변경.
- `docker compose down valhalla && docker compose up -d valhalla`로 운영 컨테이너 교체.
- 헬스체크: 로컬(8002)/공개 도메인(`valhalla.westinx.com`, Cloudflare Tunnel 경로)/의존
  서비스(`navi.westinx.com`) 전부 정상. 실제 경로 요청도 패치 전과 동일한 time/length
  응답 확인.
- 검증 컨테이너(`valhalla-fork-p4`) 및 예전 세션이 남긴 정지 상태 컨테이너(`valhalla-fork-p2`,
  `valhalla-fork-test`) 정리.

## 6. 커밋/푸시

| 저장소 | 브랜치 | 커밋 | 내용 |
|---|---|---|---|
| yurunavi | `verify/ride-0711` | `2a77e4e` | 음성/카드 문구 전면 개편 |
| yurunavi | `verify/ride-0711` | `c8bace1` | 로드맵 16번(구조물/급커브 카드 UI) 등록 |
| valhalla-src | `yurunavi-fork` | `6e374e021` | 회전각 임계값 재조정 |

- yurunavi `verify/ride-0711` → `origin`(`github.com/limera0/yurunavi`, 사용자 소유)
  push 완료.
- valhalla-src `yurunavi-fork`는 `origin`(공식 `valhalla/valhalla.git`, 사용자 비소유)엔
  push 안 함 — 대신 사용자가 새로 만든 private 저장소
  `github.com/limera0/valhalla-yurunavi-fork`를 `backup` remote로 추가해 전체 히스토리
  (공식 valhalla 14,529커밋 + `cbf9a425b`/`6e374e021`) push 완료. `docker/INFRA.md` §3
  갱신함 — 앞으로 이 브랜치에 새 커밋 시 `git push backup yurunavi-fork`도 같이 실행할 것.

## 7. 남은 일 / 후속 세션 참고

- **[ ] 실주행 재확인 권장** — 이번 세션은 curl A/B로 회귀 없음만 확인했고, 완만한/급한
  회전 재분류 체감·roundabout 출구번호 이어받기·ramp/exit 방향별 문구가 실제 라이딩에서
  자연스러운지는 다음 라이딩에서 확인 필요.
- **[ ] `loop/RELEASE_ROADMAP.md` 16번**: 구조물(고가도로/터널/지하차도)·지오메트리
  급커브 카드 UI 신설 — 이번 세션엔 TTS 문구 교정 + underpass/tunnel 분리 버그 수정까지만
  하고 카드 UI는 보류. 상세는 로드맵 문서 16번 항목 참조.
- **[ ] `loop/VOICE_MESSAGES_KO_REVIEW.csv`**: 이번에 전량 반영 완료. 추가 교정이 필요하면
  같은 파일을 다시 수정해서 전달하는 방식으로 반복 가능.
