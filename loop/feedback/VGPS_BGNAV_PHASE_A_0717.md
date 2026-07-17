# 2026-07-17 가상 GPS 실주행 검증 — 백그라운드 내비게이션 Phase A(Foreground Service)

`HANDOFF_0717_launch_priorities.md` 3순위("백그라운드/오버레이 내비게이션") 착수분.
승인된 계획은 `/home/limera/.claude/plans/generic-beaming-wadler.md`. 이 문서는 Phase A
(Foreground Service로 화면 이탈 중에도 TTS 안내 지속) 실기기 검증 결과.

## 절차

1. `flutter build apk --debug` → `adb install -r`로 커밋 `b883ee5`(Phase A 전체) 반영.
2. `android/gpsinjector/`(GPS+NETWORK+FUSED 3-provider 모킹, 기존 인프라 재사용)로
   고덕/송탄 서비스 지역 내 임의 좌표(37.03875,127.04904 → 37.0707,127.05753) 간
   Valhalla `/route`(costing=auto) 폴리라인을 15m 간격으로 리샘플링해 15m/s(54km/h)
   CSV 생성(365 포인트, ~7분 분량, 세션 스크래치패드 스크립트 — 미보존, 기존 관례와 동일).
3. 메인 앱 디버그 E2E 하네스(`--es e2e_dest_lat/lon`)로 목적지 설정 후 내비 자동 시작.
4. gpsinjector 재생 시작 → 약 1분 주행 후 `adb shell input keyevent KEYCODE_HOME`으로
   백그라운드 전환 → 15초간 로그/서비스 상태 관찰 → 포그라운드 복귀 → 내비 종료.

## 결과 — 전부 정상

- **서비스/알림**: 내비 시작 시 `NavForegroundService` `isForeground=true`(채널
  `nav_foreground_channel`, id=1001)로 정상 기동, `lastStartId=20`까지 진행 확인(update
  호출이 실제로 반복 반영됨).
- **백그라운드 지속**: `dumpsys window`로 `mCurrentFocus=com.sec.android.app.launcher`
  (런처가 실제 포그라운드)인 상태에서도 `YNAV_PROG`가 초당 계속 틱하고
  `YNAV_TTS key=destination_approach`/`YNAV_TTS key=tunnel_approach` 등 음성 안내
  이벤트가 정상 발화 — 화면을 벗어나도 GPS구독·진행판정·TTS 로직이 전부 살아있음을
  확인. 서비스(`isForeground=true`)와 알림(id=1001) 모두 백그라운드 15초 동안 유지.
- **포그라운드 복귀**: 크래시 없이 내비 화면 정상 렌더(턴카드/속도계/경로 갱신 확인,
  스크린샷 대조).
- **종료 정리**: 내비 종료(종료 버튼 탭) 후 `dumpsys activity services`에
  `NavForegroundService` 항목 자체가 사라짐(정지 확인), 알림 id=1001도 제거됨,
  `AndroidRuntime`/`FATAL` 로그 없음.

주행 경로가 실제 계산된 route와 달라(gpsinjector 좌표가 E2E 하네스가 잡은 실제
origin과 어긋남) 내내 `off=true`(이탈)로 찍혔지만, 이번 검증 목적(백그라운드 지속
자체)과는 무관 — 오히려 이탈 상태에서도 로직이 계속 도는 걸 추가로 확인한 셈이다.

## 다음

Phase B(PiP 플로팅 미니창) 착수. 코드 변경 없음(이 문서만 추가).
