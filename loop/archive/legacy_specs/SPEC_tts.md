# SPEC_tts — 유루나비 음성안내 사양 (단일 출처)

확정일: 2026-06-16 | 상태: 확정 사양.
충돌 시 우선순위: 이 SPEC > RECON > 현 구현.
(현 하드코딩 cc55f8e/903715f는 이 SPEC으로 대체될 quick-fix)

## 1. 확정 동작 (변경 시 마스터 승인 필요)

### 1-1. 출발 멘트
- 발화: "출발합니다"
- 거리/방향/도로명 읽지 않음.
- 대체 대상(버그): 현 '안내를 시작합니다'(cc55f8e), 이전 'X분XX초 앞 출발'

### 1-2. 거리 임계 사전 안내
- 임계값: 500m, 300m, 50m
- 각 임계값은 maneuver 이벤트당 정확히 1회 발화 (이벤트별 상태 추적, 중복 금지)
- 대체 대상: 현 400m 단일 임계 (RECON: nav_screen :432)
- 50m 문구: "곧 {direction}" (확정 2026-06-17)

### 1-3. 핵심 설계 제약 ★
- 멘트 문자열 하드코딩 금지.
- 음성안내는 '음성 팩'으로 모듈화 — 별도 다운로드·교체 가능.
- 팩 = 멘트 템플릿 + 오디오/TTS 소스. 소스 교체 가능 구조.
- 사업 의도: 유료 음성팩 다운로드 모델 가능성 → 구조가 막지 않아야 함.

## 2. 팩 구조 (제안 — 구현 전 마스터 확정)

음성 이벤트 키 (코드는 이 키로만 발화 요청, 문자열 모름):
- departure     (변수 없음)
- approach_500  ({direction})
- approach_300  ({direction})
- approach_50   ({direction})
- reroute       (변수 없음)
- arrival       (변수 없음)  ← 확정 필요

매니페스트 예 (assets/voice_packs/default_ko.json):
{
  "id": "default_ko", "name": "기본 (한국어)", "lang": "ko",
  "version": 1, "source": "tts",
  "templates": {
    "departure":    "출발합니다",
    "approach_500": "500m 앞 {direction}",
    "approach_300": "300m 앞 {direction}",
    "approach_50":  "곧 {direction}",
    "reroute":      "경로를 재탐색했습니다",
    "arrival":      "목적지에 도착했습니다"
  }
}
- source=tts: templates를 TTS 엔진에 넘김.
- source=audio: 같은 키로 오디오 클립 매핑. 변수 이벤트는 클립 조합 또는 TTS 폴백(방식 확정 필요).

## 3. 확정 (2026-06-17 마스터 결정)
- approach_50 문구: "곧 {direction}"
- arrival 이벤트: 포함. 문구 "목적지에 도착했습니다" (무변수)
- {direction} 소스: 기존 _labelForType 재사용 (type별 레이블 매핑 활용, 일관성)
- audio 팩 변수 이벤트 처리: 본 작업 범위 밖. source=tts만 구현, source=audio 스키마는 매니페스트에 자리만 두고 미구현(추후).

## 4. 수용 기준
- 코드에 발화 문자열 리터럴 없음 (grep '출발'/'재탐색' → SPEC/팩 파일에만 존재)
- departure/reroute/arrival 무변수, approach_*는 {direction} 치환
- 500/300/50 각 이벤트당 1회, 중복 없음
- 팩 JSON 교체만으로 전체 멘트 교체 (코드 변경 없이)
