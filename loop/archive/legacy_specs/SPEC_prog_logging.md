# SPEC_prog_logging — Layer 1 진행추적 계측 (additive, 동작 무변경)

작성: 2026-06-28
브랜치: `feat/layer1-progress`
선행 RECON: `RECON_prog_logging.md` FINDINGS (삽입점 확정).
목적: ②③ 증상을 숫자로 판정. 특히 ③ = **H2(distToNextTurnM 과대)** 가설을
`YNAV_ROUTE`(offset 무결성) + `YNAV_PROG/STEP/TTS`(런타임 거리)로 확정.

## ⛔ 범위·규율 (엄수)
- **순수 additive 계측.** 라우팅·진행·발화 **로직 한 줄도 변경 금지.** 로그문만 삽입.
- **커밋 분할**: 파일 1개 = 커밋 1개.
  - C1: `route_progress_provider.dart` (YNAV_ROUTE/PROG/STEP/ARR)
  - C2: `nav_screen.dart` (YNAV_TTS)
  - 각 커밋 `flutter analyze` 새 에러 0.
- **로그 호출 방식**: 기존 `SPD` 로그와 **동일 메커니즘**을 그대로 따른다.
  먼저 확인: `grep -rn "SPD " lib/ | head -1` 로 SPD가 `print(`인지 `debugPrint(`인지 `dev.log(`인지
  보고, **같은 함수**로 찍어 같은 `I flutter :` 채널에 실리게 한다. (임의 변경 금지)
- **ASCII 고정**: 모든 필드는 숫자/영문. maneuver는 한글 방향어 말고 **타입 식별자**(enum name 또는
  Valhalla type 정수)로 찍어 mojibake 차단.
- 거리값은 `.toStringAsFixed(1)`. bool은 `true/false`.
- 모호하면 중단·보고.

---

## C1 — route_progress_provider.dart

### L1) YNAV_ROUTE — 경로 로드 1회 (offset 무결성, ★타기 전 책상 확인용)
**위치**: 새 route/steps가 provider에 세팅되어 병합 폴리라인(`pts`)과 steps가 **둘 다 확정되는 지점**
(route 초기화/주입부). per-fix 루프 **밖**, 1회만.
```
YNAV_ROUTE legs=<legCount> steps=<steps.length> pts=<polyline.length> lastBegin=<steps.last.beginShapeIdx> lastEnd=<steps.last.endShapeIdx>
```
- `legCount`: leg 수(없으면 생략 가능). `pts`: 병합 폴리라인 포인트 수.
- **판정식**: `lastEnd == pts-1` 정상. 아니면 누적 오프셋 결함 → H2 확정.

### L2) YNAV_PROG — 매 fix (line 142 진행 갱신 직후)
**위치**: `route_progress_provider.dart:142` — `bestSeg/activeStep/distToNext/distToDest/offRoute`
로컬 확정된 직후, emit/return 직전.
```
YNAV_PROG snap=<bestSeg> step=<activeStep> next=<distToNext.1f> dest=<distToDest.1f> off=<offRoute> perp=<bestPerp.1f>
```
- 1Hz라 SPD와 동급 빈도 — throttle 불필요.
- ①(snap/next 단조)·③(next 궤적)·⑤(dest)·⑥(off/perp) 전부 여기서.

### L3) YNAV_STEP — step 증가 시 1회 (line 134-141 전환 구간)
**위치**: `route_progress_provider.dart:134-141` activeStep 증가가 확정되는 분기 내부.
이전 step→새 step 전환 시에만(매 fix 아님).
```
YNAV_STEP from=<prevStep> to=<newStep> maneuver=<newStep.typeId> beginShape=<newStep.beginShapeIdx> endShape=<newStep.endShapeIdx>
```
- ②(턴마다 +1, 통과 maneuver 잔존/스킵)·step별 shape 인덱스 정합.

### L4) YNAV_ARR — 도착 판정 시 1회 (line 134-141 arrived 분기)
**위치**: 같은 구간, `arrived=true` 확정 분기.
```
YNAV_ARR dest=<distToDest.1f> snap=<bestSeg> lastShape=<polyline.length-1>
```
- ⑤ 폴리라인 끝 도달 도착인지 직선 오판인지.

---

## C2 — nav_screen.dart

### L5) YNAV_TTS — speak() 직전 (line 244-246, ★③ 이벤트)
**위치**: `nav_screen.dart:244-246` 각 `speak()` 호출 **직전**. `thr/next/step/maneuver` 모두 스코프 내.
**txt는 찍지 않는다** — D에서 템플릿 확정(thr+maneuver로 재구성 가능). voice_pack_service 결합 회피.
```
YNAV_TTS thr=<thr> next=<next.1f> step=<step> maneuver=<maneuverTypeId>
```
- 각 임계(500/300/50) 발화 분기마다 동일 포맷 1줄. thr엔 그 분기의 임계 상수(500/300/50).
- ③: 이 라인의 timestamp ↔ 직후 YNAV_STEP(턴 실제 통과) timestamp 간격 × 주행속도 = **발화 시점 실거리**.
  "300m 앞" 발화 후 ~10초(≈83m@30km/h) 만에 턴 통과면 → 실거리 ~83m였다 = H2 과대 ~217m.
- ④: step당 YNAV_TTS ≤3, 중복/누락 검출.

---

## 검증 절차 (계측 박은 뒤)

### 0단계 — 책상에서 offset 먼저 거르기 (라이딩 불요)
빌드·설치 후, **타지 말고** 앱에서 목적지만 한 번 찍어 경로 계산 → logcat에서 `YNAV_ROUTE` 한 줄 확인:
```cmd
cmd /c "adb logcat -d -s flutter:I > route_check.log"
```
- `lastEnd == pts-1` 이면 offset 정상 → 라이딩으로 distToNext 궤적 확인 필요.
- **`lastEnd != pts-1` 이면 H2 = offset 결함 확정.** 라이딩 없이 fix SPEC 직행.

### 1단계 — 라이딩 (offset 정상일 때만)
주행 전: `adb logcat -G 16M` → `adb logcat -c` → 폰 분리 → 한 바퀴 → 귀가 재연결:
```cmd
cmd /c "adb logcat -d -s flutter:I > ride.log"
```
`ride.log` 그대로 업로드 → YNAV_PROG `next=` 궤적 vs 실도로, YNAV_TTS↔YNAV_STEP 간격으로 H2 정량 확정.

## 산출
- 2커밋(C1/C2), 각 analyze 클린. push.
- **머지 금지** — 이건 계측이지 fix 아님. H2 확정 후 별도 fix SPEC.
