GOAL: 로드맵 9번(앱 아이콘 확정) — 시안 제안 및 마스터 피드백 반영, 최종 확정 전 세션 종료

## 이번 세션 요약 (2026-07-29 저녁)

`loop/STATUS.md` → 로드맵 9번(앱 아이콘 확정) 착수. 시작 전 두 가지를 마스터에게
먼저 확인함(직전 세션 핸드오프 `HANDOFF_0729_session_end.md`가 "임의로 정하지
말 것"으로 명시해둔 지점):

1. **아이콘 범위**: 스킨(A/B/C)별로 다르게 가져가지 않고 **앱 전체 아이콘 하나로
   고정**하기로 확정.
2. **진행 방식**: 바로 하나로 확정하지 않고 **시안 2~3개 먼저 제안** → 마스터가
   고르는 방식으로 진행.

### 시안 3개 제안 (Artifact)

A안(유루캠 무드, 로드맵 8번 확정) 팔레트(코랄 `#E2896F` / 크림 `#FBF1E7` / 모스그린
`#8CA283` / 다크브라운 `#4A3B33`) 기준, "한국·일본 vs 서양 감각" 축(브랜드 정체성
결정, [[project_brand_identity]] 참고)에 맞춰 서양풍 엠블럼 대신 단순 선·도형 위주로
3안 작성:

- **시안 A** — 구불구불 도로 (펀로드 커브 스코어링을 직접 도형화)
- **시안 B** — 굽이길 이정표 (내비 핀 안에 굽이 도로를 새겨 "안내+커브" 결합)
- **시안 C** — 라이더 실루엣 (오토바이 옆모습 MUJI 픽토그램풍)

48/72/112px 축소 인식성, iOS 스퀴클/Android 원형 마스크 미리보기, 밝은/어두운
홈 화면 목업까지 포함해 Claude Artifact로 제작:
**https://claude.ai/code/artifact/74aea6b9-388f-404b-bed1-2a444a60c09d**
(마스터 계정 소유 — 다음 세션은 `Artifact` 툴 `action: "list"`로 찾아서
`url` 파라미터로 이어서 갱신할 것. 리포에는 아무것도 커밋되어 있지 않음 — 이
URL이 유일한 원본 소재.)

### 마스터가 시안 B를 골라 직접 다듬음 — 아직 미확정

마스터가 시안 B(굽이길 이정표) 방향을 골라, 도로 부분에 **입체감**을 넣은
이미지를 직접 그려서(생성 도구 추정, 원본 벡터 파일 유무 불명) 채팅에 올림.
Claude가 스크린샷을 보고 SVG로 두 차례 재현 시도:

1. **1차 재현(B-v2)**: 두께를 얇음→굵음→얇음 좌우 대칭으로 재현 →
   마스터가 "완전히 다르다"고 반려. 원인 확인 질문 결과 **"도로 모양·굵기
   방향 자체가 다름"**으로 확인됨.
2. **2차 재현(B-v3)**: 한쪽 끝에서 다른 쪽 끝으로 **한 방향으로만 계속
   굵어지는** 단일 곡선(원근감 있는 도로가 가까워질수록 넓어지는 느낌)으로
   재작업, Artifact에 반영 완료. **마스터 확인 전에 세션 종료** —
   이 버전도 스크린샷 기반 근사치이며 아직 승인받지 못함.

### 다음 세션이 할 일

1. Artifact를 열어(위 URL, 또는 `Artifact` 툴로 목록에서 검색) B-v3가
   마스터의 원본과 맞는지부터 확인. 안 맞으면 어느 부분이 다른지 구체적으로
   물어서 반영(마스터는 비개발자라 좌표·베지어 언어 대신 "위/아래 반대다",
   "꺾이는 지점이 다르다" 같은 평범한 말로 확인할 것).
2. **벡터 원본 파일(Figma/AI/SVG 등)이 있는지 다시 한번 물어볼 가치 있음** —
   있으면 근사 재현보다 압도적으로 정확함.
3. 도형 확정되면: 1024×1024 원본 다듬기 → `pubspec.yaml`에
   `flutter_launcher_icons` 추가 → 설정(yaml) → 실행해서 Android(mipmap 전
   해상도 + adaptive icon foreground/background)·iOS(`AppIcon.appiconset`
   전 해상도) 자산 생성·커밋.
4. 로드맵 9번은 **아직 DONE 아님** — 이번 세션은 리포에 커밋된 파일이 하나도
   없음(전부 외부 Artifact에서만 작업). `RELEASE_ROADMAP.md`를 섣불리 완료로
   갱신하지 말 것.

### 세션 시작 시 주의 — 다른 세션 동시 작업 중

세션 종료 시점 `git status` 기준, **이번 세션이 만들지 않은** 아래 변경들이
작업트리에 있음 — 손대지 말 것(소유 세션 불명, 이번 대화와 무관):

- `docs/privacy_policy.md`, `docs/terms_of_service.md`,
  `lib/features/settings/presentation/terms_screen.dart`, `native/src/main.rs`
  (수정됨, 미커밋)
- `assets/data/Opinet_API_Free.pdf`, `assets/data/cctv.json`,
  `assets/images/speedcam1.webp`, `assets/images/speedcam2.webp`,
  `loop/HANDOFF_0728_multi_stop_ux.md`, `loop/MORNING_REPORT_0728_multi_stop_ux.md`,
  `loop/Screenshot_20260726_124125.jpg`, `scripts/scrape_rear_camera_notices.py`
  (미추적)

세션 중 HEAD가 `0792d76`(세션 시작 시점 STATUS.md 기준)에서 `817103b`로
이동함(다른 세션이 후면단속카메라 원본 데이터 정리 커밋) — `loop/STATUS.md`는
이 커밋을 아직 반영 못 했을 수 있으니 `git log`로 실제 상태 재확인할 것.
