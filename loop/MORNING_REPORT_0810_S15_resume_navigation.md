# MORNING REPORT — S15 이어서 안내하기 + 투어 히스토리 병합

- 작성 2026-08-10 (저녁 대화형 세션) · 브랜치 `verify/ride-0711`
- 체크리스트: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S15
- 설계 전문: [HANDOFF_0810_S15_resume_navigation.md](HANDOFF_0810_S15_resume_navigation.md)
- 진행 전 마스터에게 미확정 사항 2건(오탐 방지 임계치, 재개 방식) + 원목적지 확보
  방식(신규 저장 vs RecentRoute 재활용) + S11 미완료 상태에서 S15 예외 착수 여부까지
  총 4건 확인 후 착수

---

## 뭐가 됐나

4청크 전부 code-auditor PASS, `flutter analyze` 이슈 0, `flutter test` **714/714 전건
통과**.

| 커밋 | 청크 | 내용 |
|---|---|---|
| `2d7839e` | 1 | `ActiveTourDestinationStore` 신설(`tours/tour_<id>.dest.json`)로 내비 시작 시점 목적지를 즉시 저장. `TourLog.resumedFromId`로 중단/재개 구간 연결. `TourRecoveryService`에 재개-가능 판정(임계치+사이드카 존재 → finalize 스킵) + `findResumableOrphan`/`finalizeAsInterrupted` 신설 — 기존 코드에 적혀 있던 "향후 자동 재개 기능이 생기면 경합할 수 있다" 경고를 해소 |
| `0450f89` | 2 | `resumeThresholdHoursProvider`(설정 shared_prefs 키 `resume_threshold_hours_v1`, 기본 2시간) + 설정화면 1~24시간 선택 UI |
| `6b44c60` | 3 | `main.dart`의 fire-and-forget `recoverOrphans()` 호출을 스플래시로 이동(완료를 기다려야 재개 판정이 가능하므로). 스플래시에서 재개 가능한 고아 조회 → "이어서 안내할까요?" 확인 다이얼로그 → 수락 시 현재위치(이미 확보된 `bootLocationProvider` 재사용, 새 GPS 요청 없음) → 원목적지 재탐색 → `NavScreen` 진입(`resumedFromId` 연결). 거절/재탐색 실패 양쪽 다 `finalizeAsInterrupted`를 먼저 호출해 데이터 유실 없이 정상 히스토리로 저장 |
| `33d37d9` | 4 | `groupResumedTourLogs`로 `resumedFromId` 체인을 id 기준 정확히 연결(리스트 순서·날짜 그룹 경계 무관, 3단 이상 체인·끊긴 링크 방어). 히스토리 목록에 "이어서 안내됨" 배지 + 합산 거리/시간 병합 카드. 원본 `TourLog` 레코드는 저장소에서 합치지 않음(표시 전용) |

## 진행 전 확인한 미확정 사항 (전부 마스터 승인)

1. **오탐 방지 임계치** — 설정에서 시간 단위 선택, 기본 2시간·최대 24시간.
2. **재개 방식** — 원경로 유지 아님, 현재위치→원목적지 재탐색으로 확정(제안대로).
3. **원목적지 확보** — 기존 데이터(트랙 파일)에는 목적지가 전혀 없어 재탐색 자체가
   불가능했던 걸 조사 중 발견. RecentRoute 휴리스틱 재활용안 대신 **신규 직접 저장안**
   채택(추천안).
4. **S11 미완료 상태에서 S15 예외 착수** — 확정 원칙(P0~P2 잔여 5건 완료 후 P3)과
   달리 S11(고급휘발유 미표시)만 남은 채로 오늘 S15 진행 지시 확인.

## 진행 중 발생한 이슈 — API 월 사용량 한도

청크3(스플래시 재개 트리거)·청크4(히스토리 병합 UI)를 병렬 위임했던 flutter-coder
서브에이전트 2건이 작업 중간에 **"You've hit your monthly spend limit"** 에러로 강제
종료됐다. 재시도 대신(반복 실패로 한도를 더 깎을 위험) 컨트롤 세션이 두 청크를 직접
마무리했다 — 청크1·2에서 이미 확정된 API(`ResumableOrphan`/`findResumableOrphan`/
`finalizeAsInterrupted`/`resumeThresholdHoursProvider`)를 그대로 사용해 설계와 어긋남
없이 구현. 이후 code-auditor 서브에이전트는 정상 동작해 감사는 계획대로 진행했다.

## 검증

- `flutter analyze`: 이슈 0
- `flutter test`: 전체 스위트 **714건 전건 통과**(청크4의 신규 그룹핑 테스트 5건 포함)
- code-auditor:
  - 청크1: 1차 PASS (코더가 스스로 보고한 편차 1건 — `resumedFromId`를 지오코딩
    `try` 블록 밖으로 옮긴 것 — 검증해 안전함을 확인)
  - 청크2: 1차 PASS
  - 청크3+4: **1차 FAIL** — 스플래시 `_runSequence()`의 `findResumableOrphan` await
    직후 `mounted` 체크 누락 1건(실제 크래시 가능성 있는 실질적 지적). 한 줄 수정 후
    재감사 **PASS**

## 잔여 — 마스터 확인 필요 (전부 실기기 검증, 코드 작업 없음)

- 주행 중 강제 종료 → 임계치(기본 2시간) 이내 재실행 → "이어서 안내할까요?" 프롬프트
  노출 확인 → 수락 시 현재위치 기준 재탐색 경로로 정상 진입하는지
- 종료 후 히스토리 화면에서 "이어서 안내됨" 병합 카드가 올바르게 표시되는지
- 임계치 초과 케이스(설정 1시간으로 낮추고 1시간+ 대기 후 재실행) — 프롬프트 없이
  일반 히스토리로만 저장되는지
- S1b(렌더링 자원고갈) 재현 시나리오를 재개 QA에도 그대로 활용 가능(동일 중단 상황)

## MVP 스코프 제한 (의도적, 목표달성 판정에 반영)

- 재탐색 코스는 3개 옵션 중 **첫 번째(시골길)를 자동 선택** — 중단 전 실제로 어떤
  코스로 달리고 있었는지는 저장하지 않으므로 사용자 재선택 UI는 없음.
- 히스토리 병합은 **목록 카드 표시 전용** — 카드 탭 시 상세 화면은 여전히 개별 leg
  단위(primary leg로 이동), 두 구간을 합친 상세 화면은 스코프 밖.
- 병합 카드에는 삭제 아이콘을 두지 않음(어느 leg를 지울지 모호해지는 것을 피함).

## S11(고급휘발유 미표시) — 여전히 잔여

이번 세션은 마스터 지시로 S15를 예외적으로 먼저 진행했을 뿐, S11이 완료된 것은
아니다. 다음 세션에서 이어갈 것.

---

**목표 달성 판정:** 원래 목표: 중단된 투어를 앱 재시작 시 자동 감지해 재개 제안,
수락 시 현재위치→원목적지 재탐색으로 내비게이션 재개, 히스토리에 병합 표시 /
달성: **코드 완료 — yes**. 실기기/가상GPS 검증만 **마스터 대기**.
