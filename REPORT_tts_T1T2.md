# REPORT — T1/T2 TTS 수정 (phase1/startup-accuracy)

날짜: 2026-06-16  
브랜치: phase1/startup-accuracy  
작업자: Claude Sonnet 4.6 (오케스트레이터)

---

## 요약

RECON_startup_accuracy.md + RECON_guidance_redesign.md 분석 결과 도출한 TTS 발화 버그 2건 수정.  
각각 별도 브랜치에서 구현 → analyze 게이트 통과 → phase1/startup-accuracy 에 머지.

---

## T1 — 출발 TTS 발화 개선

**증상**: 내비 시작 시 "2.3km 앞 출발" 발화. 거리 접두사가 부자연스러움.

**원인**: `_announceStep(idx)` 에 출발 maneuver 전용 분기 없음.  
→ type 1/2/3 (label='출발') 도 일반 step과 동일하게 `'${step.dist} 앞 ${step.label}'` 포맷 사용.

**수정** (`lib/features/navigation/presentation/nav_screen.dart:529-532`):
```dart
// 출발 maneuver(type 1~3): 거리 없이 출발 안내
if (step.label == '출발') {
  _tts?.speak('안내를 시작합니다');
  return;
}
```

**결과**: 내비 진입 시 "안내를 시작합니다" 발화. 거리 없음.

**브랜치/커밋**: `fix/tts-departure` → cc55f8e  
**analyze**: No issues ✅

---

## T2 — 재탐색 TTS 맥락 구분

**증상**: 경로 이탈 후 재탐색 완료 시에도 "안내를 시작합니다" 발화 (T1 적용 후 더 명확해지는 문제).

**원인**: `_reroute()` 내에서도 `_announceStep(0)` 호출 → 출발 step 발화.  
재탐색 맥락과 최초 출발 맥락이 TTS 상 구분되지 않음.

**수정** (`lib/features/navigation/presentation/nav_screen.dart:499-501`):
```dart
// 재탐색 맥락 구분: '안내를 시작합니다' 대신 재탐색 메시지 발화
_tts?.speak('경로를 재탐색했습니다');
_lastAnnouncedIdx = 0; // 출발 step 중복 방지
```

`_lastAnnouncedIdx = 0` 수동 설정으로 이후 GPS 진행 시 출발 step 재발화 방지.

**결과**: 재탐색 완료 시 "경로를 재탐색했습니다" 발화. 이후 400m 예비 발화부터 정상 흐름 재개.

**브랜치/커밋**: `fix/tts-reroute` → 903715f  
**analyze**: No issues ✅

---

## T3 — RIDING_QUEUE 이관

2단 안내 카드 재설계 (RECON_guidance_redesign.md §2단 카드 얹을 지점) 는  
실기기 주행 검증 필수 + 전체 카드 위젯 재작성으로 리스크 큼 → RIDING_QUEUE.md 에 기록 후 보류.

---

## 이미 수정됨 (이번 세션 前)

| 항목 | 커밋 |
|------|------|
| Seoul 카메라 flicker | initState 162-167 (이전 세션) |
| type 18 아이콘 좌우 반전 | 65528b7 |
| type 17 아이콘↔레이블 불일치 | 65528b7 |
| 카드 upcoming off-by-one | 2048379 |
| 카드 거리 live remaining 바인딩 | 0195e6d |

---

## git 복원점

| 커밋 | 내용 |
|------|------|
| 6da373f | 복원점1 — T1/T2 적용 전 (RECON 20건 포함) |
| T1 merge | merge(T1): departure TTS + BACKLOG.md |
| T2 merge | merge(T2): reroute TTS + RIDING_QUEUE.md |
| 833989e | 복원점2 — T1/T2 적용 완료 |

---

## 사용자 확인 사항 (폰 실기기)

1. 목적지 설정 → 내비 진입 시: **"안내를 시작합니다"** 들리면 T1 정상
2. 주행 중 경로 이탈 → 재탐색 후: **"경로를 재탐색했습니다"** 들리면 T2 정상
3. 이후 400m/50m TTS 정상 발화 여부 (기존 로직 회귀 없는지)

---

## 다음 단계 (BACKLOG.md 참조)

- T3 (RIDING_QUEUE): 2단 안내 카드 재설계 — 실기기 주행 테스트 가능한 세션에서 착수
- phase1/startup-accuracy 완료 후 main 머지 여부는 마스터 판단
