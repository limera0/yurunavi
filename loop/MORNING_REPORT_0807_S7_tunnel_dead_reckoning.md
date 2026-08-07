# MORNING REPORT — S7 터널 추측항법

- 작성 2026-08-07 (저녁 대화형 세션) · 브랜치 `verify/ride-0711`
- 지시서: [HANDOFF_0807_S7_tunnel_dead_reckoning.md](HANDOFF_0807_S7_tunnel_dead_reckoning.md)
- 체크리스트: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S7

---

## 뭐가 됐나

커밋 `d7f88f3`. 터널에서 GPS가 끊겨도 마스터가 제안한 "직전 1분 평균속도 × 1.05로
경로 shape 따라 위치 시간적분 전진"을 구현했다.

- `NavigationState`에 `stale` 필드 신설 — 기존 `_kStaleMs=8000`(8초) 상수를 그대로
  재사용해 "GPS 상실" 판정 기준을 앱 전체가 공유하게 했다.
- 로직은 `route_progress_provider.dart`(`RouteProgressNotifier`)에 배치했다 — 경로
  shape·구조물 zone·진행거리를 이미 다 아는 provider라서다. `NavStateNotifier`는
  경로를 모르는 순수 GPS 계층이라 거기 넣으면 관심사 경계가 무너진다고 판단했다.
- 진입 조건: `stale == true` **그리고** 현재 위치가 `StructureType.tunnel` zone 범위
  안일 때만(다른 구조물 타입이나 무조건 stale로는 진입 안 함).
- 60초 롤링 평균속도 버퍼(실측 fix만 반영 — 추정 tick이 자기 평균을 오염시키지 않음)로
  `avgSpeed × 1.05`를 구하고, 500ms 타이머로 `_traveledM`을 전진시킨다. 터널 끝
  누적거리에 도달하면 그 자리에서 멈추고 더 추정하지 않는다(모른다를 인정하는 쪽이
  억지 추정보다 낫다는 판단).
- `_pointAtCumulativeM`(누적거리→좌표 역변환) 신설 — 지금까지는 좌표→누적거리 방향만
  있었다.
- `RouteProgress`에 `deadReckoning`/`estimatedPos` 노출, `nav_screen.dart`의
  `_triggerReroute()`에 S5의 `isStationaryProvider` 게이트 옆에 한 줄만 추가해
  추측항법 중 자동 재탐색을 막았다(감사로 정확히 그 한 줄만 추가됐음을 diff로 확인).
- **알려진 리스크 대응**: ×1.05로 일부러 넉넉하게 추정하므로, 터널을 빠져나와 실측
  fix가 돌아왔을 때 그 위치가 추정이 밀어둔 `_snapIdx`보다 뒤쳐질 수 있다(기존 스냅
  로직은 앞쪽만 탐색하는 단조 전진이라 이 경우를 못 잡는다). 추측항법 직후 첫 실측
  fix에 한해 스냅 탐색창을 뒤로도 1회 확장하고(`_pendingBackwardSnap`), 그 다음
  fix부터는 정상적인 전진전용 탐색으로 복귀하는 방식으로 해결했다 — 감사에서 "한 번만
  작동하고 정상 복귀"까지 직접 확인됨.

## 검증

- `flutter analyze`: 이슈 0
- `flutter test`: **456건 전건 통과**(신규 7건 — 터널 밖 stale 시 미진입, 터널 안 진입 +
  비례 전진, 터널 끝 도달 후 정지, 실측 fix 복귀 시 역방향 스냅 보정 1회 + 그 다음
  fix부터 정상 복귀 등)
- code-auditor: **1차 PASS**(수정 없이) — `NavigationState` 생성부 4곳 전부 `stale:`
  채워짐 확인, 속도버퍼가 추정 tick으로 오염 안 됨을 코드 추적으로 확인, `pubspec.yaml`
  diff가 `fake_async` transitive→direct 승격 하나뿐임을 확인

## 참고 — S6과 병행 진행

S6(로터리 방향)과 파일이 겹치지 않아(voice_engine.dart/poi_service.dart/
routing_service.dart vs nav_state_provider.dart/route_progress_provider.dart) 병렬로
위임·감사·커밋했다. S8(UI 잔여)은 이 S7과 `nav_screen.dart`를 공유해 순차 진행으로
미뤘다.

## 잔여

- **검증**: 가상GPS로 터널 구간 GPS 드롭 시나리오 재생 — memory `project_vgps_testing`
  하네스(3-provider 모킹) 필요. 이번 세션에서 직접 재생을 시도하지 않았다 —
  **마스터 실기기/가상GPS 검증 대기**로 남긴다.
- `estimatedPos`를 카메라 추종/위치 마커에 실제로 연결하는 건(터널 안에서도 화면상
  위치가 전진하는 걸 보여주는 것) 이번엔 스킵했다 — S8이 `nav_screen.dart`를 깨끗한
  상태에서 이어받게 하려는 목적이 컸다. 필요하면 별도 후속 작업으로.

---

**목표 달성 판정:** 원래 목표: 터널 구간에서 GPS 신호가 끊겨도 직전 1분 평균속도×1.05로
경로 shape를 따라 위치를 시간적분 전진시켜, 안내 타이밍과 재탐색 판정이 GPS 공백 동안에도
안정적으로 유지되게 한다. / 달성: **코드 완료 — yes**. 가상GPS 실측 재생은
**마스터 검증 대기**.
