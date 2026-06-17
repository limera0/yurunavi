# RECON_tts_pack — 음성 팩 구조 착수 전 정찰

작성: 2026-06-16 | 대상 커밋: phase1/startup-accuracy HEAD

---

## §A 현재 발화 지점 전수

| # | 함수/위치 | 파일:줄 | 발화 내용 | SPEC 키 |
|---|-----------|---------|-----------|---------|
| 1 | `_initTts()` → `_announceStep(0)` | nav_screen.dart:520 | (아래 2번으로 연결) | departure |
| 2 | `_announceStep()` — '출발' 분기 | nav_screen.dart:530 | `'안내를 시작합니다'` (하드코딩) | departure |
| 3 | `_updateStepByDistance()` — 400m 분기 | nav_screen.dart:432 | `'${remaining}미터 앞 ${next.label}'` (하드코딩) | approach_500 / approach_300 (현재 단일 임계값 400m) |
| 4 | `_updateStepByDistance()` — 50m 분기 → `_announceStep()` | nav_screen.dart:435-439 | 다음 step의 `'${step.dist} 앞 ${step.label}'` | approach_50 |
| 5 | `_announceStep()` — 일반 경우 | nav_screen.dart:533-537 | `'${step.dist} 앞 ${step.label}'` | approach_* (진입 시) |
| 6 | `_reroute()` | nav_screen.dart:500 | `'경로를 재탐색했습니다'` (하드코딩) | reroute |
| 7 | 카드 탭 (`GestureDetector.onTap`) | nav_screen.dart:933 | `_announceStep(_stepIdx)` | (수동) |
| 8 | arrival | nav_screen.dart:545-548 | TTS 없음. 다이얼로그만 표시 | arrival (미구현) |

### 하드코딩 문자열 리터럴 목록
- `'안내를 시작합니다'` — :530 (SPEC departure 키 대체 대상)
- `'$distStr ${next.label}'` — :432 (distance 보간 포함 하드코딩 템플릿)
- `'경로를 재탐색했습니다'` — :500 (SPEC reroute 키 대체 대상)
- `'${step.dist} 앞 ${step.label}'` — :534 (approach_* 일반 템플릿)

---

## §B SPEC과 현 구현의 차이

| 항목 | 현 구현 | SPEC §1 |
|------|---------|---------|
| departure 문구 | `'안내를 시작합니다'` | `'출발합니다'` |
| 임계값 | 400m (1개) | 500m / 300m / 50m (3개) |
| 임계값별 상태 추적 | `_preAnnounced` (bool 1개) | 이벤트별 독립 상태 필요 (bool 3개) |
| 문자열 위치 | 코드 내 리터럴 | 팩 JSON 템플릿 |
| {direction} 소스 | `_TurnStep.label` (= `_labelForType(type)`) | 미확정(§3) |
| arrival TTS | 없음 | SPEC §3 미확정 |

---

## §C 팩 도입 시 변경 파일·줄

**변경이 필요한 파일: 1개**  
`lib/features/navigation/presentation/nav_screen.dart`

변경 줄 목록:

| 현재 | 변경 내용 |
|------|-----------|
| :94 `FlutterTts? _tts;` | 팩 로더 / 발화 추상화 클래스 추가 (또는 팩-래퍼 클래스 분리) |
| :97 `bool _preAnnounced = false;` | `bool _pre500=false, _pre300=false, _pre50=false;` 로 교체 |
| :392 `_preAnnounced = false;` | 3개 플래그 리셋으로 교체 |
| :428-433 400m 분기 전체 | 500m / 300m 각각 독립 분기로 교체 + 팩 키 호출 |
| :435-436 `_preAnnounced = false;` | 3개 리셋으로 교체 |
| :514-521 `_initTts()` 전체 | 팩 로드 → TTS 초기화 → departure 발화로 교체 |
| :523-538 `_announceStep()` 전체 | 팩 키 조회 → 템플릿 치환 → speak 로 교체 |
| :500 `_tts?.speak('경로를 재탐색했습니다')` | 팩 키 `reroute` 조회로 교체 |

새 파일 (선택):
- `assets/voice_packs/default_ko.json` — 팩 매니페스트 (SPEC §2)
- `lib/services/voice_pack_service.dart` — 팩 로드·치환 로직 (단일 책임 분리 권장)

---

## §D 단일 커밋 가능 여부 판정

**불가** — 권장 최소 분할: 2커밋

1. **커밋 1 (T2-팩 구조)**: `voice_pack_service.dart` 신설 + `default_ko.json` 추가  
   스코프: 신규 파일만, nav_screen 미수정
2. **커밋 2 (T2-연결)**: `nav_screen.dart` 내 `_initTts` / `_announceStep` / `_updateStepByDistance` / `_reroute` 발화 지점 전부를 팩 키 호출로 교체, 임계값 3개로 확장

단일 커밋으로 묶으면 `nav_screen.dart`와 신규 파일이 동시에 변경되어 리뷰 가독성이 낮고  
code-auditor `파일:줄` 대조 범위가 과도하게 넓어진다.

---

## §E 미확정 사항 (SPEC §3 — 착수 금지)

- `{direction}` 소스: `_labelForType` 재사용 여부 → 마스터 결정 필요
- `approach_50` 문구: `"곧 {direction}"` vs `"{direction}"` → 마스터 결정 필요
- `arrival` 이벤트 존재/문구 → 마스터 결정 필요

---

## §F 관련 파일 참조

- 발화 전체 집중 파일: `lib/features/navigation/presentation/nav_screen.dart`
- `_labelForType`: nav_screen.dart:1269-1295 (direction 소스 후보)
- SPEC 우선: `loop/SPEC_tts.md`
