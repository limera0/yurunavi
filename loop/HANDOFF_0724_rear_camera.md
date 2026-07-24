GOAL: 후면단속카메라 접근 시 사이버포뮬러 스타일 게이지 + "단속중" 오버레이로 안내 (18번)

---

# HANDOFF — 18번 후면단속카메라 안내 (2026-07-24)

## 배경

오토바이는 앞번호판이 없어 전방카메라에는 잡히지 않고 **후면단속카메라에만 잡힌다.**
즐거운 투어링 중 과태료를 맞으면 분노 2배 → 후면카메라만 선별 안내한다.

데이터 출처: 공공데이터포털 경찰청 무인교통단속카메라 현황
(https://www.data.go.kr/data/15028200/standard.do)

---

## 브랜치

`verify/ride-0711` (현재 브랜치 그대로)

---

## 아키텍처 결정

| 항목 | 결정 | 근거 |
|------|------|------|
| 데이터 저장 | Flutter asset JSON (`assets/data/rear_cameras.json`) | 카메라 위치는 정적, 수백~수천 건 규모 → 앱 번들 내 임베드가 오프라인·속도 모두 유리 |
| 탐지 방식 | GPS 하버사인 반경 + 진행방향 필터(±60°) | route shape 기반보다 단순, 카메라 밀도 낮아 충분 |
| 감지 주체 | `route_progress_provider.dart` (기존 패턴 유지) | structureZone/curveZone과 동일한 per-tick 계산 |
| 서버 의존 | 없음 | 오프라인 내비 중에도 동작해야 함 |

---

## 거리·상태 정의

```
── 500m 접근 ──── 300m ──── 50m ──── 카메라 지점 ──── +100m 이후
│               │         │         │                │
│ 게이지 표시    │ 강조색   │ 극강조  │   "단속중"       │  해제
│ (파랑→노랑)   │ (주황)  │ (빨강)  │   빨강 + 맥박    │
```

- **접근 구간 (500m → 0m)**: 호 게이지가 0% → 100%로 채워짐
- **단속 구간 (카메라 지점 ±100m)**: 호 100% + "단속중" 레이블 + 맥박 애니메이션
- 이후 +100m 초과 → 위젯 사라짐

---

## Phase 0 — 데이터 수집 및 가공

### 0-1. 다운로드 및 확인
1. https://www.data.go.kr/data/15028200/standard.do 에서 파일 다운로드
2. 필드 구조 파악 (필드명은 실제 파일 확인 후 확정):
   - 카메라종류 / 카메라유형 (예: "후면단속", "이동식", "고정식" 등)
   - 위도 / 경도
   - 제한속도 (있으면 활용)
   - 설치도로명 (참고용)

3. "후면단속" 해당 행만 필터

### 0-2. 가공 스크립트
Python 또는 Dart 스크립트로 CSV/Excel → JSON 변환:

```json
// assets/data/rear_cameras.json
[
  {"lat": 37.1234, "lng": 127.5678, "speed": 60},
  {"lat": 37.2345, "lng": 127.6789, "speed": 80},
  ...
]
```

필드:
- `lat`, `lng`: 위도/경도 (double)
- `speed`: 제한속도 km/h (int, 없으면 0)

### 0-3. pubspec.yaml 등록
```yaml
assets:
  - assets/data/rear_cameras.json
```

**완료 기준**: JSON 파일 생성, 후면단속 카메라만 포함 여부 수동 확인, `flutter pub get` PASS

---

## Phase 1 — 탐지 엔진

### 1-1. RearCamera 모델 (`lib/features/navigation/models/rear_camera.dart`)

```dart
class RearCamera {
  final double lat;
  final double lng;
  final int speedKmh;
  const RearCamera({required this.lat, required this.lng, required this.speedKmh});

  factory RearCamera.fromJson(Map<String, dynamic> j) => RearCamera(
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    speedKmh: (j['speed'] as num? ?? 0).toInt(),
  );
}
```

### 1-2. 로더 (`lib/features/navigation/providers/rear_camera_loader.dart`)

```dart
// 앱 시작 시 or 내비 시작 시 1회 로드 (OnceLock 패턴)
Future<List<RearCamera>> loadRearCameras() async {
  final s = await rootBundle.loadString('assets/data/rear_cameras.json');
  final list = jsonDecode(s) as List;
  return list.map((e) => RearCamera.fromJson(e as Map<String, dynamic>)).toList();
}
```

### 1-3. RouteProgress 확장 (`route_progress_provider.dart`)

추가 필드:
```dart
class RouteProgress {
  // ... 기존 필드 ...
  final double distToNextCameraM;  // 다음 후면카메라까지 직선 거리. 없으면 ∞
  final int nextCameraSpeedKmh;    // 해당 카메라의 제한속도 (표시용)
  final bool inCameraZone;         // 카메라 지점 ±100m 이내 (단속중 표시)
}
```

탐지 로직 (per-tick, 기존 `_tick()` 내부):
```dart
({double distM, int speedKmh, bool inZone}) _nearestCameraFields(
    LatLng pos, double headingDeg, List<RearCamera> cameras) {
  const kThresholdM = 600.0;
  const kZoneM = 100.0;

  RearCamera? best;
  double bestDist = double.infinity;

  for (final cam in cameras) {
    final camPos = LatLng(cam.lat, cam.lng);
    final dist = PoiService.haversineMeters(pos, camPos); // 기존 util 재사용
    if (dist > kThresholdM + kZoneM) continue;

    // 진행 방향 필터: 카메라 방위각이 현재 헤딩 ±70° 이내
    final bearing = _bearingTo(pos, camPos);
    final angleDiff = ((bearing - headingDeg + 540) % 360) - 180;
    if (angleDiff.abs() > 70) continue;

    if (dist < bestDist) {
      bestDist = dist;
      best = cam;
    }
  }

  if (best == null) return (distM: double.infinity, speedKmh: 0, inZone: false);

  // 카메라 지점을 지나쳤는지 판단 (헤딩 기준 후방 100m 이내 = 단속중)
  final bearing = _bearingTo(pos, LatLng(best.lat, best.lng));
  final angleDiff = ((bearing - headingDeg + 540) % 360) - 180;
  final inZone = bestDist < kZoneM; // 100m 이내

  return (
    distM: inZone ? bestDist : bestDist,
    speedKmh: best.speedKmh,
    inZone: inZone,
  );
}

// 방위각 계산 헬퍼
double _bearingTo(LatLng from, LatLng to) {
  // 표준 하버사인 bearing 공식
  final dLng = (to.longitude - from.longitude) * pi / 180;
  final lat1 = from.latitude * pi / 180;
  final lat2 = to.latitude * pi / 180;
  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}
```

**완료 기준**: `flutter analyze` PASS, 탐지 로직 단위테스트 1건 (카메라 정면 500m → 탐지됨, 후방 → 미탐지)

---

## Phase 2 — 게이지 UI (사이버포뮬러 스타일)

### 위젯: `_CameraApproachGauge` (`nav_screen.dart` 하단 private 위젯)

**레이아웃 (nav_screen 기존 `_StructureCurveAlert`과 같은 위치에 표시)**:

```
┌──────────────────────────────────────────────────────┐
│  (지도 위 오버레이, 화면 중앙 상단)                    │
│                                                      │
│         ╭──────────────────────────────╮             │
│         │   ╭────────────────────╮    │             │
│         │   │   ⚠  RADAR        │    │             │
│         │   │                    │    │             │
│         │   │    ◯ 60km/h        │    │             │  ← 제한속도
│         │   │                    │    │             │
│         │   │     327 m          │    │             │  ← 거리
│         │   ╰────────────────────╯    │             │
│         │      (호 게이지 테두리)       │             │
│         ╰──────────────────────────────╯             │
└──────────────────────────────────────────────────────┘
```

**CustomPainter 명세**:
- 중앙 원 + 그 주위를 감싸는 호(arc) — 반시계 상단(-150°)에서 시계 방향으로 300° 스윕
- progress 0.0(500m) → 1.0(0m): 호 채워짐
- 색상 보간:
  - 0.0~0.4 (500→300m): `Color(0xFF00BCD4)` 청록 → `Color(0xFFFFEB3B)` 노랑
  - 0.4~0.8 (300→100m): 노랑 → `Color(0xFFFF5722)` 주황
  - 0.8~1.0 (100→0m): 주황 → `Color(0xFFD50000)` 진빨강
- strokeWidth: 8px, lineCap: round
- 게이지 배경 호: 흰색 불투명도 0.15, 동일 경로

**"단속중" 상태 (inCameraZone == true)**:
- 호 100% 고정 (빨강)
- 중앙 텍스트를 거리 → "단속중" 으로 교체
- 텍스트 + 아이콘이 1초 주기로 fade 맥박 (`AnimationController` repeat + Curves.easeInOut)
- 아이콘: `Icons.camera_alt` 빨강

**진입/퇴장 애니메이션**:
- 등장: `ScaleTransition` 0.7→1.0, 200ms, 커브 easeOut
- 소멸: `FadeTransition` 1.0→0.0, 300ms

### nav_screen.dart 연동

```dart
// 기존 _StructureCurveAlert과 동일한 스택 레이어에 추가
if (progress.distToNextCameraM <= 500 || progress.inCameraZone)
  _CameraApproachGauge(
    distM: progress.distToNextCameraM,
    speedKmh: progress.nextCameraSpeedKmh,
    inZone: progress.inCameraZone,
  ),
```

**완료 기준**: 기기에서 500m 접근부터 게이지가 채워지고, "단속중" 맥박 표시됨

---

## Phase 3 — TTS 안내

기존 구조물 TTS 패턴 (`_announcedStructureZoneIdx`) 그대로 복제:

```dart
int _announcedCameraZoneIdx = -1;  // 이미 안내한 카메라 식별자

// _tick() 내부
if (progress.distToNextCameraM <= 500 && !progress.inCameraZone) {
  final camIdx = _cameraIdxFromDist(progress); // 카메라 인덱스
  if (camIdx != _announcedCameraZoneIdx) {
    _announcedCameraZoneIdx = camIdx;
    final dist = progress.distToNextCameraM;
    final label = dist <= 100 ? '전방 후면단속 카메라' :
                  dist <= 300 ? '${dist.round()}미터 앞 후면단속 카메라' :
                                '500미터 앞 후면단속 카메라';
    _tts(label);
  }
}
```

- 500m, 300m, 100m 구간 진입마다 1회씩 (재진입 안내 방지)
- "단속중" 구간 진입 시: "후면단속 카메라입니다" (단 1회)

**완료 기준**: 로그에서 TTS 발화 타이밍 확인 (vGPS 또는 시뮬레이션)

---

## 실행 순서

```
Phase 0 (데이터)      → 즉시 착수 가능. 공공데이터포털 파일 다운로드 필요
      │
Phase 1 (탐지)        → Phase 0 완료 후 (JSON 필드명 확정 필요)
      │
Phase 2 (UI 게이지)   → Phase 1 병행 가능 (임시 더미 데이터로 선개발 가능)
      │
Phase 3 (TTS)         → Phase 1 완료 후
```

---

## CLAUDE.md 프로토콜

- 각 Phase 완료 후 `flutter analyze` PASS → code-auditor → 커밋
- `git push` 금지
- Phase 0은 데이터 가공 스크립트 커밋 + JSON 에셋 커밋 (2건)

---

## 완료 기준 (전체)

- [ ] `assets/data/rear_cameras.json` 생성, 후면단속 카메라만 포함
- [ ] `flutter analyze` PASS
- [ ] 500m 접근 시 게이지 등장, 색상 변화 (청록→노랑→주황→빨강)
- [ ] 카메라 지점 ±100m 에서 "단속중" 맥박 표시
- [ ] TTS 500m / 300m / 100m / 진입 시 안내
- [ ] 기존 구조물/커브 경보와 동시 표시 가능 (겹칠 경우 카메라 우선)

---

## 19번 — 실시간 최저가 주유소 (별도 핸드오프)

API 키 발급 완료 후 착수. 별도 HANDOFF_0724_gas_station.md 작성 예정.

진입점:
- 내비 화면 "주유소 찾기" 버튼
- 지도 검색창 "주유소" 버튼

범위: 현위치 반경 5km, 유종 설정(휘발유/고급휘발유) 연동
API: 한국석유공사 오피넷 (공공데이터포털) → navi 서버 프록시
