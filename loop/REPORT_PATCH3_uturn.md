# REPORT_PATCH3 — Valhalla Fork Patch #3 (모터사이클 U턴 페널티)

작성일: 2026-07-11

---

## 1. 목표

`feat/reroute-heading`의 dest-behind heading drop 픽스가 "제자리 U턴 강요" 문제의 실제 해결책이
아님이 0711 밤 실주행 로그로 판명(재탐색 29건 중 heading 유무 무관하게 maneuver=13 11회 발생).
`loop/RECON_uturn_costing.md`(read-only recon)가 지목한 진짜 원인을 valhalla-src 포크에서 수정.

## 2. 근본 원인

- `AddUturnPenalty`(valhalla/sif/dynamiccost.h:883)는 `MotorcycleCost::TransitionCost`/
  `TransitionCostReverse`(motorcyclecost.cc) 안에서 `if (stopimpact > 0 && !shortest_)` 블록
  **안에서만** 호출됨 — stopimpact=0인 도로(주로 저교차 밀도/저등급 도로)에서는 U턴 페널티 자체가
  통째로 스킵.
- 블록 안에서도 `has_reverse` 케이스는 `kTCUnfavorableUturn`(600) 또는 이름 불일치 시
  `kTCNameInconsistentUturn`(10)만 가산 — `stopimpact` 배율(`seconds *= stopimpact`)에 따라
  희석되어 사실상 약한 페널티.
- 소스 주석(motorcyclecost.cc:562) "Motorcycles should be able to make uturns on short internal
  edges..." — 오토바이 costing이 원래 U턴에 관대하게 설계됨.

## 3. C++ 패치 내역

### motorcyclecost.cc

**상수 (kTCReverse 근처):**
```cpp
constexpr float kMotoUturnPenalty = 5000.0f;
```

**TransitionCost / TransitionCostReverse 둘 다, `stopimpact>0` 게이트 밖(turntype 판정 직후)에 추가:**
```cpp
const auto turntype = edge->turntype(idx);
if (turntype == baldr::Turn::Type::kReverse) {
  c.cost += kMotoUturnPenalty;
}
```
- 게이트 밖이므로 stopimpact=0 도로에서도 무조건 적용.
- `c.cost`만 가산(휘발유용 `sec`/ETA는 불변) — 순수 회피용 페널티, 경로 소요시간 왜곡 없음.
- 다른 costing 모델(auto/truck/bus 등)은 미변경 — `AddUturnPenalty`가 공유 inline이라도
  이번 패치는 motorcyclecost.cc 로컬 상수/조건이라 모터사이클 costing에만 적용됨.

## 4. 빌드

| 항목 | 내용 |
|------|------|
| 이미지 태그 | `valhalla-fork:patch3-uturn` |
| 기반 | `docker/Dockerfile.fork` (patch1/patch2와 동일, Python 비활성화) |
| 빌드 커맨드 | `docker build -t valhalla-fork:patch3-uturn --build-arg CONCURRENCY=2 -f docker/Dockerfile.fork .` |
| 캐시 | 이번 빌드는 전 레이어 미스(캐시 없이 처음부터, apt까지 재설치) — 컴파일 자체는 정상 완료, 에러 0건 |

## 5. 검증 (포트 8015, `valhalla-fork-p3`, 검증 후 제거됨)

- 회귀: 핸드오프가 준 curl 포함 16개 이상의 다양한 OD(도심/시골, 랜덤 산간 14쌍)로 비교 — **모든
  정상 경로에서 8002(패치 전)와 8015(패치 후) `cost`/경로 100% 동일**. 회귀 없음.
- **긍정 검증(패치가 실제 U턴을 억제하는지)은 curl만으로 확정 못함.** 시도한 모든 "type=13(U턴)"
  응답에서 8002/8015 `cost`가 소수점까지 동일 — 즉 이 tile 셋에서 정상적으로 탐색되는 narrative
  U턴은 대부분 196m~881m짜리 **다중 엣지 유턴차로/스위치백 형태**(진짜 필요한 우회)였고, 패치가
  타겟하는 **단일 엣지 `turntype()==kReverse` 전이**는 한 번도 트리거되지 않음.
  - `RECON_uturn_costing.md` Q3(thor `Expand()`가 dead-end가 아니면 U턴 확장 자체를 안 함)와
    일치 — 정상 교차로에서 단일 엣지 즉시반전은 애초에 드묾.
  - 실제 "제자리 U턴 강요" 재현에는 재탐색 시점의 실제 origin GPS 좌표가 필요하나, 앱 파일로그
    (`ynav_*.log`)는 상대 진행률만 기록하고 원시 lat/lon을 남기지 않아 이번 세션에서는 확보 불가.
- 패치 자체는 RECON이 지목한 정확한 코드 경로를 정확히 수정했고, 회귀 0건이 확인된 상태로
  **마스터 판단에 따라 운영(8002) 즉시 교체 진행**(2026-07-11).

## 6. 배포

- `docker/docker-compose.yml`의 `image:` → `valhalla-fork:patch3-uturn`로 변경, 커밋 예정.
- `docker compose down valhalla && docker compose up -d valhalla`로 운영 컨테이너 교체 완료,
  헬스체크(정상 경로 curl) 통과.
- 검증 컨테이너(`valhalla-fork-p3`, 8015)는 교체 후 제거함.

## 7. 남은 일 / 후속 세션 참고

- [ ] **실주행 재확인 필요.** curl로 긍정 검증을 못했으므로, 다음 라이딩에서 재탐색 시 U턴이
      실제로 줄었는지 `adb logcat -d | grep "YNAV_STEP.*maneuver=13"` 로 발생 빈도 비교
      (0711 밤 기준선: 재탐색 29건 중 11건).
- [ ] 만약 실주행에서도 여전히 U턴이 발생한다면, 다음 가설(RECON_uturn_costing.md Q4)로 이전:
      재탐색 origin의 `heading` 필드 부재/부정확으로 인해 loki가 반대방향 엣지를 후보로 채택하는
      경우 — 이건 valhalla-src가 아니라 yurunavi 클라이언트(`nav_screen.dart`/
      `routing_service.dart`) 쪽 origin heading 계산 로직 검토가 필요.
- [ ] 원시 GPS 좌표 로깅(file_logger 확장)을 고려하면 다음 실주행에서 진짜 재현 좌표를 확보해
      curl로 직접 A/B 가능해짐 — 우선순위는 마스터 판단.
