GOAL: 실기기 재현을 전면 취소하고, OsmAnd·Organic Maps의 메모리/VRAM 관리 로직과 Flutter의 렌더 소실 사례를 조사해 백화가 메모리·VRAM 누수 때문인지부터 판별한다.

# MORNING REPORT — S1b 3회차 · 메모리/VRAM 감사 (조사 전용)

- 2026-08-06 · 브랜치 `verify/ride-0711` · HEAD `4338adf`
- 상세 기록: [RECON_0805_render_resource.md](RECON_0805_render_resource.md) **§12**
- 선행: §10(M32 재검증) · §11(GPU 메모리 실측) — 같은 파일

---

## 목표 변경 (마스터 저녁 스티어링)

[HANDOFF_0806_S1b_continue.md](HANDOFF_0806_S1b_continue.md)의 원래 목표는
*"실기기 계측으로 확정/반증"* 이었으나, 마스터가 **M32 가상GPS 재현을 전면 취소**하고
조사축을 바꿨다. 취소 사유 3건:

1. 주입 GPS 궤적이 안내 경로와 어긋나 **끝없이 Valhalla 재탐색을 유발**
2. 그 결과 **Valhalla가 rate limit에 걸림** — 마스터: *"사용자가 여러 명이면 이 정도
   호출은 일상적인데 rate limit가 걸리는 건 아주 심각하다"* → **독립 결함으로 승격**
3. 스크린샷 캡처·분석이 컨텍스트를 채워 세션이 `ECONNRESET`로 반복 사망

**이번 세션은 실기기를 전혀 쓰지 않았다.** 증거물 재분석 + 레퍼런스 앱 소스 열람 +
Flutter 이슈 조사 + 유루나비 정적 감사만으로 진행했다.

---

## done

1. **증거 스크린샷 육안 재확인** (§12-1) — 콘트라스트 6배 부스트 확대.
   **실패 단위가 "글리프"가 아니라 "`Container`의 child 서브트리 통째"임을 확정.**
   껍데기(채우기+테두리+boxShadow)는 그려졌고 child만 완전 부재 — 희미한 잔상조차 없다.
   → **§5의 글꼴 아틀라스 가설 완전 배제**(사라진 것 중에 글리프가 아닌 6px 단색 막대가 있다).
2. **Flutter 이슈 트래커 조사** (§12-2) — 동일 실패모드 6건 확보.
   핵심: [#159578](https://github.com/flutter/flutter/issues/159578)
   (`Could not create valid atlas` → 텍스트 전멸, 터치하면 복구),
   [#163452](https://github.com/flutter/flutter/issues/163452)(P1, e: impeller),
   [#161861](https://github.com/flutter/flutter/issues/161861)(Android Impeller Graphics 메모리 누수),
   [#178264](https://github.com/flutter/flutter/issues/178264)(Impeller가 텍스처·렌더타깃을
   오래 붙들고 앱은 볼 수도 만질 수도 없음, GL mtrack 3.9GB → OOM 킬).
3. **OsmAnd · Organic Maps 소스 직접 열람 후 3자 비교표** (§12-3) — 5개 축 전부.
4. **유루나비 정적 감사** — 신규 결함 2건 발견:
   - `ui.Picture` **미해제 3곳** (`poi_icon_renderer.dart:56,70`, `tour_share_helper.dart:167`)
   - **`imageCache` 기본값 방치**(1000장/100MB), **메모리 압박 훅 0건**
5. **§11-4 미해결 항목 종결** (§12-6) — **`flutter_map`은 죽은 의존성**이다.
   `FlutterMap(` 사용 0건, `buildCachedTileProvider()` 호출 0건.
   → 500MB 디스크 캐시는 **애초에 동작한 적이 없다.**

## 판정 (§12-4)

| 마스터 가설 | 판정 |
|---|---|
| (a) 단조 증가하는 **누수**가 있다 | **미입증** — §11-3 16분 실측 평탄. 단 `ui.Picture` 미해제라는 실제 누수 경로를 이번에 발견 |
| (b) **압박 순간 GPU 자원 할당 실패**로 일부 드로우가 통째로 누락된다 | **근거 강함 · 현재 최유력** — Flutter 공식 이슈로 인정된 실재 실패모드. `Could not create valid atlas`는 "고갈"이 아니라 **할당 실패**이고 결과가 **조용한 부분 미렌더**다. 마스터의 A34(앱 적음) > 플립7(앱 많음) 관찰과, M32(배경 경쟁 0)가 17회 왕복에도 재현 못 한 것을 **같은 논리로 동시에 설명한다** |
| (c) 앱에 **메모리 압박 대응 로직이 없다** | **확정** — `didHaveMemoryPressure` 0건, `onTrimMemory` 0건, GPU 예산 0건, 백그라운드 캐시 드롭 0건. **OsmAnd·Organic Maps는 셋 다 구현하고 있다** |

**요약: 마스터의 방향은 맞다. 정확히는 "새는 것"보다 "압박을 견딜 장치가 없는 것"이 문제다.**

## 미확정으로 남긴 것

- **DaylightBar의 6px 단색 막대가 왜 같이 사라졌는지 설명 못 한다.** 글리프 아틀라스로도,
  그 위젯에 존재하지 않는 `saveLayer`로도 설명 안 된다. 서브트리 단위 누락이라는 **관측**은
  확실하나, 왜 별도 렌더 타깃으로 처리됐는지는 **미확정**이다. 추측하지 않고 남긴다.
- §3의 가드 미리셋 결함은 코드에 여전히 존재(§10-1-C에서 확인, 이번에도 미수정).

## blocked

- **네이티브 로그가 없어서 (b)를 확정할 수 없다.** 앱 진단로그가 Dart `debugPrint`만
  캡처해 Impeller validation·Vulkan·OOM 로그를 하나도 안 남긴다.
  실주행 로그 95k줄 grep 결과 `impeller|atlas|vulkan|OutOfMemory` **매치 0건**.
  → **§12-5 B-1(네이티브 로그 캡처)이 다음 세션 최우선.** `Could not create valid atlas`
  한 줄이면 (b)가 즉시 확정된다.

## 권고 조치 (§12-5, 마스터 승인 대기 — 이번 세션은 조사 전용이라 코드 미수정)

- **A(저위험 즉시)**: `ui.Picture.dispose()` 3곳 · `didHaveMemoryPressure()` 구현 ·
  `imageCache` 상한 기기 기준 축소 · 백그라운드 캐시 드롭 · **`_locLayerReady` 리셋** ·
  `flutter_map` 제거
  - `_locLayerReady` 리셋은 §10-4에서 "우선순위 판단"으로 미뤘던 항목인데,
    **Organic Maps `FrontendRenderer::OnContextDestroy()`가 정확히 이 패턴을 필수 계약으로
    구현하고 있다는 레퍼런스가 확보됐으므로 하는 쪽을 권고한다.**
- **B(계측)**: 네이티브 로그 캡처(최우선) · GPU 메모리 스냅샷 앱 내부화
- **C(판별)**: Impeller off A/B — 마스터 실사용 폰 실주행 1회.
  ⚠️ 끄는 것 자체를 해결책으로 커밋하지 말 것

## 다음 세션 백로그 (§12-7)

1. **[신규·높음] Valhalla rate limit** — 별도 세션. 서버 설정값 근거 / 클라이언트 재탐색
   빈도 상한·디바운스 / 다중 사용자 부하 추정
2. **[신규] 재탐색 폭주** — GPS가 경로를 벗어나면 무한 재탐색. 실주행에서 GPS가 튀어도
   같은 일이 난다. §9의 "재탐색하며 코스가 마구 엉킴"과 같은 뿌리일 수 있다
3. 네이티브 로그 캡처(위 B-1)
4. §10-1-F `StreamSink is bound to a stream` 크래시 — 여전히 미조사
5. §11-4 "타일 캐시 1.65GB"가 무엇이었는지 재정의(§12-6으로 전제가 무너졌다)

## 토큰/세션 노트

실기기·스크린샷 루프를 쓰지 않아 이전 두 세션을 죽인 컨텍스트 폭증이 재발하지 않았다.
증거 스크린샷은 **1장만, 크롭·축소해서** 봤다.

---

**목표 달성 판정:** 원래 목표(실기기 계측으로 확정/반증)는 **마스터 지시로 취소**되고
새 목표(레퍼런스 앱 비교 + Flutter 사례 조사로 메모리·VRAM 원인 여부 판별)로 대체됐다.

`Goal: 백화가 메모리·VRAM 누수 때문인지 판별 / Met: partial — "누수"는 미입증(반증도 아님),
"압박 시 GPU 할당 실패"가 최유력 가설로 좁혀졌고 앱의 압박 대응 부재는 확정. 최종 확정에는
네이티브 로그 캡처가 선행돼야 한다.`
