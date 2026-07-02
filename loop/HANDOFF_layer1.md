# HANDOFF — YuruNavi Layer 1 인수인계

작성: 2026-06-28 (토요일 야간 세션 종료 시점, 새벽)
브랜치: `feat/layer1-progress` (미머지, main 머지 금지 — 아래 T3 사유)
직전 세션 요약: Layer 0 머지 → Layer 1 코어 구현 → 첫 실행 cold-start 결함 일괄 해결.

---

## ⛔ 새 세션이 가장 먼저 읽을 것 (엉뚱한 짓 방지)

1. **지금은 "구현 끝, 라이딩 검증 대기" 상태다.** 코드를 더 고치지 마라. 다음 행동은
   **마스터의 실주행 결과를 받는 것**이다. 라이딩 결과 없이 추가 커밋·리팩터 금지.
2. **`feat/layer1-progress`를 main에 머지하지 마라.** Layer 1은 T3(카드/도착/TTS 거동 변경).
   실주행 회귀(아래 §검증) 통과 전 머지 절대 금지.
3. **증상이 보고되면, 코드부터 고치지 말고 RECON부터.** 직전 세션에서 추측 패치로 두 번
   헛짚었다(getCurrentPosition, firstFix). 매번 **로그/grep 실물 → 원인 확정 → fix** 순서.
   "2회차는 되는데 1회차만" 같은 재현 조건 한 마디가 원인을 한 점으로 모은다 — 재현 패턴을 먼저 물어라.
4. **빌드/analyze 성공 ≠ 작동.** 폰 실측만이 증거. 특히 GPS·진행추적은 책상에서 거짓 통과한다.

---

## 현재 코드 상태 (feat/layer1-progress)

### 완료된 것 (이번 세션)
- **Layer 0** (이미 main 머지됨, `d8d4a64`): `navStateProvider` = 단일 운동학 SoT
  (pos/speedKmh/moving/headingDeg/firstFix/fixAt). 5/5 라이딩 통과 검증 완료.
- **Layer 1 코어** (3커밋):
  - `ManeuverStep`에 `beginShapeIdx`/`endShapeIdx` 추가 (routing_service). leg 누적
    오프셋으로 전역 인덱스 변환 — `_extractPoints`의 skip(1) 병합과 대응.
  - `routeProgressProvider` 신설 (route_progress_provider.dart): navState.pos를
    폴리라인에 **단조 스냅**(snapIdx 뒤로 안 감) → distToNextTurnM/distToDestM/arrived/offRoute
    파생. OsmAnd FollowedPolyline 패턴. window=50, offRoute=50m, arrival=25m.
  - nav_screen: 분리계산(_traveledDistM/_updateStepByDistance/_checkArrival 직선거리) 폐기,
    routeProgress 구독으로 전환. TTS 500/300/50m 각 1회(step 전환 시 리셋).
- **첫 실행 cold-start 결함 일괄 해결** (이번 세션 후반, 4개 fix):
  1. `fix(nav): defer setRoute to post-frame` — setRoute를 build/initState에서 호출하면
     Riverpod "modify provider while building" 빨간화면. addPostFrameCallback으로 미룸.
  2. `fix(map): _lastKnown fallback for origin gates` — 목적지/라우팅 게이트 4곳
     (_onMapTap:411, _applyDestination:497, 최근경로:649, Valhalla폴백:698)을
     `_origin ?? _lastKnown`으로. cold-start에서 navState 미충전이어도 캐시 좌표로 탐색.
  3. `_seed`의 getCurrentPosition 폴백 **제거** — 효과 없이 10초 블로킹 부작용. _lastKnown이 커버.
  4. **`fix(auth): invalidate dead location stream after permission grant`** ← 진짜 뿌리.
     splash `_requestPermissions`에서 권한 grant 후 `ref.invalidate(locationStreamProvider)`
     추가. 첫 실행 때 권한 denied 상태로 닫혀 keepAlive로 박제된 죽은 스트림을 폐기 → 재생성.
     "2회차는 되는데 1회차만 안 됨"의 원인이 이것. **이 한 줄로 첫 실행 GPS/검색중/현위치 전부 해결.**

### 검증 완료 (책상)
- 첫 실행(uninstall 후): 권한 허용 → 목적지 설정 → 경로 탐색 → 내비 진입 →
  "GPS 검색 중" 풀리고 속도 표시 → 현위치 버튼 작동. **모두 정상 확인.**
- 턴 카드 "Nm 좌회전" 표시, 경로 폴리라인 렌더 정상.

### ⚠️ 알려진 잔여 (무해, 손대지 말 것)
- analyze warning 2건: route_progress_provider.dart `_dest`, `_kBackToleranceM` 미사용.
  SPEC verbatim 스텁. **Layer 3(heading 재탐색)에서 활용 예정.** 지금 지우지 마라.
- settings_screen Radio deprecated info 2건 — Layer 1 이전부터 존재, 무관.

---

## ▶ 다음 할 일 (순서 고정)

### 1. push 확인
```bash
cd /data/projects/yurunavi
git status
git log --oneline -8   # 위 4개 fix + Layer1 코어 3커밋이 보여야
git push origin feat/layer1-progress
```

### 2. Layer 1 라이딩 회귀 (T3, main 머지 전 필수) — SPEC_guidance_p1 §5
실주행으로만 확인 가능. 합격선은 **1·2·3** (나머지는 무회귀 확인):
```
□ 1. 카드 단조      턴 접근 시 잔여거리 단조 감소 (518m 고착·역행 없음)
□ 2. step 전환      턴 통과 후 다음 maneuver로 정확 전환 (통과 maneuver 잔존 없음)
□ 3. 거리 정확도    "300m 앞 좌회전"이 실제 ~300m에서 발화 (증상3 해소)  ★핵심
□ 4. TTS 1회        500/300/50m 각 1회 (중복·누락 없음)
□ 5. 도착          폴리라인 끝 도달 시 도착 (직선 오판 없음)
□ 6. 이탈          경로 벗어나면 재탐색 트리거 (heading 미고려는 Layer 3)
□ 7. Layer 0 무회귀 속도계·카메라 5/5 유지
```
디버그로그: `adb logcat | grep "YNAV_GUIDE\|snapIdx\|RoutingService"`.
오프셋 정합도 실주행 때 확인: `RoutingService` 로그의 `lastEnd == pts-1`.

### 3. 라이딩 통과 시 → main 머지
```bash
git checkout main && git pull
git merge --no-ff feat/layer1-progress -m "merge: Layer 1 — shape_index monotonic progress tracking"
git push origin main
```

### 4. 그 다음 레이어 (라이딩 통과 후)
- **Layer 2** (verbal 턴정보): Valhalla 응답에 이미 존재 확인됨 —
  `verbal_pre/post/succinct_transition_instruction`, `verbal_multi_cue`. 파싱 복원 →
  nav_screen `_TurnStep._labelForType` 하드코딩 대체. **Valhalla 포크 무관, Dart만.**
  street_names/lanes는 중간 maneuver로 존재 재확인 후.
- **Layer 3** (heading 재탐색): `bearing_after`(응답 존재 확인) + navState.headingDeg →
  유턴 감지. offRoute를 거리 기반에서 heading 인식으로 고도화. `_kBackToleranceM`/`_dest`
  스텁이 여기서 쓰임.

---

## 🔒 워크플로 원칙 (반드시 준수)

- **RECON → SPEC → 실행 → 폰 검증** 단계 분리. 각 단계 별도 세션/호출.
  - Claude Desktop(이 채팅): 계획·RECON·SPEC 작성.
  - Claude Code (`claude -p`, westinx): 실제 코드 변경 실행.
- **헤드리스 발사**: 지시 파일 **단독** 전달. `tick.md` 절대 동봉 금지(BACKLOG 오실행).
  출력은 `--verbose` 단독.
- **커밋**: 파일 1개 = 커밋 1개 = 논리 변경 1개. 각 커밋 `flutter analyze` 새 에러 0.
- **편집 사고 방지**: 여러 곳 동시 수정 시 **한 곳씩 → 매번 analyze**. 직전 세션에서
  4곳 동시 편집하다 중괄호 1개 딸려 들어가 빌드 붕괴 → 한 줄씩 갔으면 즉시 잡혔을 것.
- **모호하면 추측 말고 중단·보고.** grep 결과는 `file:line` 인용. 검증 없는 추측 금지.
- **레퍼런스 우선**: OsmAnd, Organic Maps (아키텍처 레퍼런스 확인 완료). 반복 시도-오류 대신
  검증된 오픈소스 기반 1회 해결.
- 커밋 메시지·코드 식별자 영문. 프롬프트·문서 한국어.

---

## 환경 메모
- 서버: westinx (Ubuntu), `/data/projects/yurunavi`, `claude -p`, `micro` 에디터, tmux.
- 빌드: `flutter build apk --debug` (서버) → scp → Windows `c:\platform-tools\` → `adb install -r`.
- 첫 실행 재현: **반드시 `adb uninstall` 후 install** (권한 리셋돼야 cold-start 재현).
- 폰: 삼성 업무폰(EMM/MDM 있음, 단 위치 정책 0건 — 권한 무관 확인됨).
  user 150 = 보안폴더(앱과 무관, `pm clear`가 거기서 막히니 uninstall/install 사용).
- 스택: Flutter+Riverpod+MapLibre 0.26.1 / Valhalla 3.7 포크 / Rust 스코어링 / latlong2가
  도메인 통화(MapLibre LatLng는 렌더 경계에서만 변환).

---

## 핵심 교훈 (다음 세션이 같은 실수 안 하도록)
- 모든 주행 결함의 근본은 **분리 계산**. 단일 위치 소스 → 단조 진행 포인터에서 파생이 정답
  (OsmAnd/OM 둘 다 이 구조). Layer 0/1이 이 토대를 깔았다.
- "첫 실행만 안 됨" = 권한/스트림 타이밍. Riverpod `keepAlive`된 provider는 죽으면
  `invalidate` 없이 안 살아난다. `listen`은 죽은 인스턴스를 깨우지 못한다.
- cold-start에서 `getLastKnownPosition`은 null일 수 있고(첫 설치), `getCurrentPosition`은
  위성 lock 실패 시 10초 블로킹. 능동 fix 폴백은 부작용 크다 — `_lastKnown` 캐시 폴백이 안전.
