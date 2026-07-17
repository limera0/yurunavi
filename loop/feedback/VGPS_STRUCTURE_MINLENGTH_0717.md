# 2026-07-17 가상 GPS 실주행 검증 — `minLengthM` 100→30m 완화 확인

`RIDE_RESULTS_0716.md` "6-잔여"(구조물 진입 안내가 아예 발화하지 않던 문제) 수정
커밋 이후, 실제로 진입 안내(`bridge_approach`/`bridge_imminent`)가 발화하는지
가상 GPS로 검증한 결과. 대상은 사용자가 지정한 실측 짧은 구조물 3곳 — 옛
`minLengthM=100` 아래에서는 전부 버려졌을 길이(37~71m)다.

## 대상 및 결과

| 구조물 | 길이 | 속도 | zones | 결과 |
|---|---|---|---|---|
| 고덕좌교로 | 51m | 70km/h | 1 | ✅ `bridge_approach dist=50` → `bridge_imminent dist=10` |
| 고덕국제2로 | 71m | 70km/h | 1 | ✅ `bridge_approach dist=50` → `bridge_imminent dist=10` |
| 고덕갈평4로 | 37m | 70km/h | 1 | ✅ `bridge_approach dist=50` → `bridge_imminent dist=10` (재시도 후, 아래 §2 참조) |

3곳 모두 `YNAV_STRUCT zones=1`로 구조물 zone이 정상 생성됐고, 진입 음성
(`bridge_approach`/`bridge_imminent`)이 정확히 발화했다. 옛 `minLengthM=100`
기준이었다면 이 3곳 전부 `zones=0`으로 조용히 버려져 어떤 안내도 없었을 구간이다.

## 0. 경로 준비 방법

실제 origin/destination 좌표가 문서화돼 있지 않아, 서비스 지역(고덕/송탄)
Valhalla `/locate` 격자 샘플링(minLengthM 완화 커밋 조사 때 수집한 것)에서
확보한 각 구조물의 `edge_info.shape`(정밀도 6 인코딩 폴리라인)를 디코딩해 정확한
좌표를 얻고, 진입/진출 방향 bearing으로 전후 buffer(250m, 37m 구간은 80m —
버퍼가 크면 인접한 별도 지하차도까지 같이 걸려 단일 구조물 격리가 안 됨)만큼
외삽한 지점을 origin/destination으로 삼아 Valhalla `/route`(앱과 동일하게
`selectedRouteIdx=2`="국도" costing_options)로 실제 경로를 뽑았다. 각 경로는
`/trace_attributes`로 목표 구조물 1개만 단독으로 포함되는지 사전 확인 후
사용(스크립트는 세션 스크래치패드, 미보존 — `route_gen.py`/`build_route.py`
패턴 재사용 가능).

## 1. 테스트 인프라

기존 인프라 그대로 재사용(`HANDOFF_0716_structure_bypass_exit.md` §4,
메모리 `project_vgps_testing.md`) — `android/gpsinjector/`(GPS+NETWORK+FUSED
3-provider 모킹) + 메인 앱 디버그 전용 E2E 하네스(`--es e2e_dest_lat/lon`).
**이번 세션 전에 오늘 커밋(`minLengthM` 100→30)이 반영된 debug APK를
재빌드·재설치**(`flutter build apk --debug --dart-define-from-file=env.json`)
— 재검증이므로 최신 코드가 기기에 있는지가 핵심.

## 2. 짧은 경로(37m)에서 겪은 테스트 인프라 함정 — 코드 버그 아님

고덕갈평4로(37m) 경로는 origin→destination 직선거리가 168m로 매우 짧아
70km/h 기준 총 주행시간이 8초 정지 + 약 9초 주행 = 17초뿐이었다. gpsinjector는
CSV 타임라인대로 **실시간으로 독립적으로** 재생을 시작하는데, 앱 쪽
E2E 하네스(목적지 설정 → 경로 계산 대기 → 내비 시작)가 완료되는 데 걸리는
지연이 이 17초보다 길어서, 내비 화면이 실제로 GPS 갱신을 받기 시작했을
땐 이미 gpsinjector가 목적지 좌표까지 재생을 끝낸 뒤였다 — 결과적으로 첫
`YNAV_PROG`가 `destination_imminent`만 찍고 구조물 진입 안내는 관측되지
않음(1차 시도 로그: `zones=1`은 찍혔지만 `bridge_*` TTS 없음).

**해결**: 정지 유지 시간을 8초→25초로 늘려(도로/구조물 좌표는 그대로, 순수
타이밍 버퍼만 추가) 재시도 — 정상적으로 `bridge_approach`/`bridge_imminent`
둘 다 발화 확인. 51m/71m 경로는 애초에 버퍼 250m라 주행시간이 충분히
길어(약 30~40초) 8초 정지로도 문제없었다. **다음에 이런 아주 짧은(≲200m)
구간을 가상 GPS로 테스트할 땐 정지 유지 시간을 20초 이상으로 잡을 것.**

## 3. 검증

- `flutter analyze` / `flutter test`: 코드 변경 없음(재검증 세션이라 커밋
  `815a925`의 검증 결과 그대로 유효).
- 가상 GPS 3회(51m/71m/37m, 각 70km/h 1회): 전부 `bridge_approach`+
  `bridge_imminent` 정상 발화, `YNAV_STRUCT zones=1`.
- push 여부: 이 문서만 추가 커밋, 그 외 코드 변경 없음. push는 이전과 동일하게
  보류(사용자 명시 지시 시 진행).
