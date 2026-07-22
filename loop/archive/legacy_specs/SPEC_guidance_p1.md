# SPEC_guidance_p1.md — Layer 1: shape_index 단조 진행추적 (구현 명세)

작성일: 2026-06-28 (토요일 야간, Layer 0 머지 후)
근거: loop/RECON_guidance_p1.md, Valhalla 응답 실측, OsmAnd FollowedPolyline 패턴.
대상: `lib/services/routing_service.dart`,
      신설 `lib/features/navigation/providers/route_progress_provider.dart`,
      `lib/features/navigation/presentation/nav_screen.dart`.
분류: **T3 (라이딩 회귀 필수)** — 카드/도착/TTS 전면 변경.
브랜치: `feat/layer1-progress` (main 기준, Layer 0 머지 후).

> 구현 철칙: 아래 코드는 **그대로 구현**한다. 스냅/누적거리 알고리즘을 임의 재설계하지 않는다.
> 시그니처 불확실 시 추측 말고 중단·보고. 빌드/analyze 성공 ≠ 작동, 폰 실측이 증거.

---

## §1. routing_service.dart — shape_index 파싱 복원 (C1)

### 1-1. ManeuverStep 확장
기존 클래스(routing_service:31~44)에 필드 2개 추가. 기존 필드/생성자 보존, 추가만.
```dart
class ManeuverStep {
  final int type;
  final String instruction;
  final double distanceKm;
  final int beginShapeIdx;   // 전역 인덱스 (leg 오프셋 적용 후)
  final int endShapeIdx;     // 전역 인덱스
  const ManeuverStep({
    required this.type,
    required this.instruction,
    required this.distanceKm,
    this.beginShapeIdx = 0,
    this.endShapeIdx = 0,
  });
}
```

### 1-2. 파싱 — 전역 인덱스 변환 (헬퍼로 추출)
파싱이 **2곳**(메인 :316~328, balanced 교체 :383~395)이라 동일 로직 중복. 헬퍼로 묶어
양쪽에서 호출(중복 제거 + 일관성).
```dart
/// leg별 maneuvers를 전역 shape 인덱스로 변환해 수집.
/// Valhalla begin/end_shape_index는 leg 내부 기준 → leg 누적 오프셋을 더한다.
/// 오프셋 누적은 _extractPoints의 skip(1) 병합과 정확히 대응(leg당 points-1).
static List<ManeuverStep> _collectManeuvers(List legs) {
  final out = <ManeuverStep>[];
  int shapeOffset = 0;
  for (final leg in legs) {
    for (final m in (leg['maneuvers'] as List? ?? [])) {
      final b = (m['begin_shape_index'] as num?)?.toInt() ?? 0;
      final e = (m['end_shape_index'] as num?)?.toInt() ?? 0;
      out.add(ManeuverStep(
        type: (m['type'] as num?)?.toInt() ?? 0,
        instruction: (m['instruction'] as String?) ?? '',
        distanceKm: (m['length'] as num?)?.toDouble() ?? 0.0,
        beginShapeIdx: shapeOffset + b,
        endShapeIdx: shapeOffset + e,
      ));
    }
    final legPts = _decodePolyline6(leg['shape'] as String? ?? '');
    shapeOffset += legPts.isEmpty ? 0 : legPts.length - 1;
  }
  return out;
}
```
- 메인 파싱(:317~325 루프) → `final maneuvers = _collectManeuvers(legs);` 로 교체.
- balanced 파싱(:383~395 루프) → 동일하게 `_collectManeuvers(legs);` 로 교체.
- **검증 포인트(구현자 필수)**: `_collectManeuvers` 후 마지막 maneuver의 endShapeIdx가
  `_extractPoints(legs).length - 1`과 일치해야 함. 불일치면 오프셋 로직 오류 → 중단·보고.
  (dev.log로 `lastEnd=${out.last.endShapeIdx} pts=${_extractPoints(legs).length}` 출력해 확인.)

---

## §2. route_progress_provider.dart — 신설 (C2)

전체 신규 파일. navStateProvider.pos를 폴리라인에 단조 스냅하고 파생값 산출.

```dart
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../services/routing_service.dart' show ManeuverStep;
import 'nav_state_provider.dart';

@immutable
class RouteProgress {
  final int snapIdx;            // 폴리라인 상 현재 세그먼트 시작 인덱스 (단조 증가)
  final int activeStepIdx;      // 현재 진행 중 maneuver 인덱스
  final double distToNextTurnM; // snap → 다음 turn(beginShapeIdx)까지 폴리라인 누적
  final double distToDestM;     // snap → 폴리라인 끝까지 누적
  final bool arrived;
  final bool offRoute;          // 스냅 실패(코리도 밖). 재탐색 트리거용
  const RouteProgress({
    required this.snapIdx,
    required this.activeStepIdx,
    required this.distToNextTurnM,
    required this.distToDestM,
    required this.arrived,
    required this.offRoute,
  });
}

final routeProgressProvider =
    NotifierProvider<RouteProgressNotifier, RouteProgress?>(
        RouteProgressNotifier.new);

class RouteProgressNotifier extends Notifier<RouteProgress?> {
  // ── 경로 컨텍스트 (setRoute로 주입) ──
  List<LatLng> _pts = const [];
  List<ManeuverStep> _maneuvers = const [];
  LatLng? _dest;

  // ── 사전계산 ──
  List<double> _segLenM = const [];  // _pts[i]→_pts[i+1] 길이
  List<double> _cumFromStartM = const []; // _pts[0]→_pts[i] 누적
  double _totalM = 0.0;

  // ── 진행 상태 ──
  int _snapIdx = 0;

  // ── 튜닝 상수 ──
  static const _kSnapWindow = 50;       // 앞쪽 탐색 세그먼트 수
  static const _kOffRouteM = 50.0;      // 코리도 이탈 임계(최근접 세그먼트 거리)
  static const _kArrivalM = 25.0;       // 도착 반경(폴리라인 잔여)
  static const _kBackToleranceM = 10.0; // 뒤로 약간 허용(GPS 흔들림)

  static const _distance = Distance();

  @override
  RouteProgress? build() {
    // navState.pos 구독 → 매 fix advance.
    final sub = ref.listen<NavigationState?>(navStateProvider, (_, next) {
      final p = next?.pos;
      if (p != null) _advance(p);
    });
    ref.onDispose(sub.close);
    return null;
  }

  /// 내비 진입/재탐색 시 경로 주입. snapIdx 리셋.
  void setRoute({
    required List<LatLng> points,
    required List<ManeuverStep> maneuvers,
    required LatLng destination,
  }) {
    _pts = points;
    _maneuvers = maneuvers;
    _dest = destination;
    _snapIdx = 0;

    // 세그먼트 길이 + 누적 사전계산 (O(n) 1회)
    final n = points.length;
    final seg = List<double>.filled(n > 0 ? n - 1 : 0, 0.0);
    final cum = List<double>.filled(n, 0.0);
    double acc = 0.0;
    for (int i = 0; i < n - 1; i++) {
      final d = _distance(points[i], points[i + 1]);
      seg[i] = d;
      acc += d;
      cum[i + 1] = acc;
    }
    _segLenM = seg;
    _cumFromStartM = cum;
    _totalM = acc;

    state = RouteProgress(
      snapIdx: 0,
      activeStepIdx: 0,
      distToNextTurnM: _distToShapeIdx(0, _nextTurnShapeIdx(0)),
      distToDestM: _totalM,
      arrived: false,
      offRoute: false,
    );
  }

  /// 점 pos를 [_snapIdx, _snapIdx+window] 범위 세그먼트에 스냅(단조).
  void _advance(LatLng pos) {
    if (_pts.length < 2 || _segLenM.isEmpty) return;

    final start = _snapIdx;
    final end = math.min(_snapIdx + _kSnapWindow, _pts.length - 2);

    double bestPerp = double.maxFinite;
    int bestSeg = _snapIdx;
    double bestAlongM = 0.0; // bestSeg 시작점 기준 세그먼트 내 진행거리

    for (int i = start; i <= end; i++) {
      final r = _projectOntoSegment(pos, _pts[i], _pts[i + 1]);
      if (r.perpM < bestPerp) {
        bestPerp = r.perpM;
        bestSeg = i;
        bestAlongM = r.alongM;
      }
    }

    // 코리도 이탈 판정
    final offRoute = bestPerp > _kOffRouteM;

    // 단조 보장: 뒤로 가는 스냅은 소폭(_kBackTolerance)만 허용
    if (bestSeg < _snapIdx) {
      // 같은 세그먼트 내 미세 후퇴는 무시, 세그먼트 자체가 뒤면 고정
      bestSeg = _snapIdx;
      bestAlongM = 0.0;
    }
    _snapIdx = bestSeg;

    // 현재 위치의 폴리라인 누적거리
    final traveledM = _cumFromStartM[bestSeg] + bestAlongM;

    // active step: snap이 지난 maneuver를 제외한 다음 턴
    final activeStep = _activeStepFor(bestSeg);
    final nextTurnShape = _nextTurnShapeIdx(bestSeg);

    final distToNext = (_cumFromStartM[_clampIdx(nextTurnShape)] - traveledM)
        .clamp(0.0, double.maxFinite);
    final distToDest = (_totalM - traveledM).clamp(0.0, double.maxFinite);
    final arrived = distToDest <= _kArrivalM;

    state = RouteProgress(
      snapIdx: bestSeg,
      activeStepIdx: activeStep,
      distToNextTurnM: distToNext,
      distToDestM: distToDest,
      arrived: arrived,
      offRoute: offRoute,
    );
  }

  // ── 헬퍼 ──

  int _clampIdx(int i) => i.clamp(0, _pts.length - 1);

  /// snap 세그먼트 기준, 아직 지나지 않은 첫 maneuver 인덱스.
  int _activeStepFor(int seg) {
    for (int s = 0; s < _maneuvers.length; s++) {
      if (_maneuvers[s].endShapeIdx > seg) return s;
    }
    return _maneuvers.isEmpty ? 0 : _maneuvers.length - 1;
  }

  /// 다음 턴이 시작되는 shape 인덱스(= active maneuver의 beginShapeIdx의 끝점).
  /// 카드 "Nm 앞 좌회전"의 N 기준점.
  int _nextTurnShapeIdx(int seg) {
    final s = _activeStepFor(seg);
    if (s >= _maneuvers.length) return _pts.length - 1;
    // 다음 턴 지점 = 현재 active maneuver의 종료 shape(그 지점에서 회전)
    return _clampIdx(_maneuvers[s].endShapeIdx);
  }

  double _distToShapeIdx(int fromSeg, int toShape) {
    final from = _cumFromStartM.isEmpty ? 0.0 : _cumFromStartM[_clampIdx(fromSeg)];
    final to = _cumFromStartM.isEmpty ? 0.0 : _cumFromStartM[_clampIdx(toShape)];
    return (to - from).clamp(0.0, double.maxFinite);
  }

  /// pos를 세그먼트 a-b에 투영. perpM=수직거리, alongM=a로부터 진행거리.
  ({double perpM, double alongM}) _projectOntoSegment(
      LatLng pos, LatLng a, LatLng b) {
    // 평면 근사(짧은 세그먼트라 충분). 위경도를 m로 환산.
    final latRef = (a.latitude + b.latitude) / 2 * math.pi / 180.0;
    final mPerLat = 111320.0;
    final mPerLon = 111320.0 * math.cos(latRef);
    double dx(double lon) => lon * mPerLon;
    double dy(double lat) => lat * mPerLat;

    final ax = dx(a.longitude), ay = dy(a.latitude);
    final bx = dx(b.longitude), by = dy(b.latitude);
    final px = dx(pos.longitude), py = dy(pos.latitude);

    final vx = bx - ax, vy = by - ay;
    final wx = px - ax, wy = py - ay;
    final segLen2 = vx * vx + vy * vy;
    double t = segLen2 > 0 ? (wx * vx + wy * vy) / segLen2 : 0.0;
    t = t.clamp(0.0, 1.0);

    final projx = ax + t * vx, projy = ay + t * vy;
    final perp = math.sqrt((px - projx) * (px - projx) + (py - projy) * (py - projy));
    final along = math.sqrt(segLen2) * t;
    return (perpM: perp, alongM: along);
  }
}
```

> 알고리즘 주석:
> - **단조성**: 탐색 시작이 항상 `_snapIdx` → 뒤 세그먼트 탐색 안 함. bestSeg < snapIdx면 고정.
>   자기교차·평행구간에서 최근접점이 뒤로 튀던 518m 고착의 원인을 제거.
> - **window**: 앞 50세그먼트만 → O(window). GPS 점프해도 코리도 안이면 흡수, 밖이면 offRoute.
> - **누적거리**: 사전계산 `_cumFromStartM`로 O(1) 조회. 매 fix 전체순회(_traveledDistM) 폐기.
> - **거리는 latlong2 Distance()** (Haversine). 세그먼트 투영만 평면근사(짧아서 오차 무시).

---

## §3. nav_screen.dart — progress 소비 전환 (C3)

### 3-1. 제거 대상 (분리계산 폐기)
- `_traveledDistM`(:239~253) **삭제**.
- `_updateStepByDistance`(:255~) **삭제** — 발화/step전환 로직은 §3-3으로 이관.
- `_computeStepEndDistances`(:213~220) + `_stepEndDistM`(:82) **삭제**.
- `_checkArrival`(:388~399)의 직선거리 판정 **삭제** (도착은 progress.arrived).
  단 `_fetchNearbyPois`/`_showArrivalDialog` 호출부는 유지(도착 후 동작).
- `_stepIdx` 거리 자동진행(`_stepIdx++`) **삭제**.

### 3-2. setRoute 주입
`_applyRouteGuidance`(:222) 또는 진입 시점에서, maneuvers/polyline/dest를 progress에 주입:
```dart
// 내비 진입 + 재탐색(:346 newPoints 교체) 양쪽에서 호출
ref.read(routeProgressProvider.notifier).setRoute(
  points: _routePoints,
  maneuvers: widget.maneuvers,   // beginShapeIdx 포함된 ManeuverStep
  destination: widget.destination!,
);
```
`_steps`(_TurnStep, 표시용 아이콘/라벨)는 유지 — 거리/진행은 progress가 소유, 라벨만 _steps.

### 3-3. progress 구독 (navState 구독 핸들러 내부)
nav_screen:191의 `_locationSub`(navStateProvider 구독) 핸들러에서, 운동학(카메라)은
그대로 두고 **진행 파생은 progress에서 읽음**:
```dart
final prog = ref.read(routeProgressProvider);
if (prog != null) {
  setState(() {
    _cardRemainingM = prog.distToNextTurnM;
    _stepIdx = prog.activeStepIdx.clamp(0, _steps.length - 1);
  });
  _handleVoice(prog);      // §3-4
  if (prog.arrived && !_arrived) {
    _arrived = true;
    _vps?.speak('arrival');
    _fetchNearbyPois(widget.destination!).then((pois) {
      if (mounted) _showArrivalDialog(pois);
    });
  }
  if (prog.offRoute) _triggerReroute();  // 기존 재탐색 경로 재사용
}
```
> 주의: progress 구독을 navState 핸들러에 합치지 말고 **별도 listen**으로 둘지는 구현 판단.
> 단 progress는 navState 변경에 의해 갱신되므로(같은 fix), navState 핸들러에서 `ref.read`로
> 최신 progress를 읽으면 1-fix 지연 가능 → **routeProgressProvider를 직접 listen** 권장.
> (정확성 우선: progress를 ref.listen으로 구독, navState 핸들러는 카메라/속도만.)

### 3-4. TTS — distToNextTurnM 기준, step별 1회 (메모리 사양)
```dart
// 상태: 마지막 발화한 stepIdx별 임계 플래그
int _voiceStepIdx = -1;
bool _said500 = false, _said300 = false, _said50 = false;

void _handleVoice(RouteProgress prog) {
  final step = prog.activeStepIdx;
  if (step != _voiceStepIdx) {       // step 바뀌면 리셋
    _voiceStepIdx = step;
    _said500 = _said300 = _said50 = false;
  }
  if (step + 1 >= _steps.length) return; // 마지막 = 도착, 턴 발화 없음
  final dir = _steps[step].label;        // 다음 턴 라벨
  final d = prog.distToNextTurnM;
  if (d <= 500 && !_said500) { _said500 = true; _vps?.speak('approach_500', vars: {'direction': dir}); }
  if (d <= 300 && !_said300) { _said300 = true; _vps?.speak('approach_300', vars: {'direction': dir}); }
  if (d <=  50 && !_said50)  { _said50  = true; _vps?.speak('approach_50',  vars: {'direction': dir}); }
}
```
> 메모리 TTS 사양 준수: 임계 500/300/50m, 각 1회. 출발 멘트("출발합니다")는 기존 위치 유지.
> 음성 모듈화(_vps 음성팩) 구조는 유지 — 하드코딩 추가 금지.

---

## §4. 커밋 분할 (3커밋, 각 analyze 통과)
- **C1** `feat(routing): parse maneuver shape indices with leg offset`
  — routing_service §1. 미사용이라 단독 컴파일 OK. **오프셋 검증 dev.log 포함**.
- **C2** `feat(nav): add routeProgressProvider monotonic snap tracker`
  — route_progress_provider.dart 신설 §2. 화면 미연결.
- **C3** `refactor(nav): consume routeProgress, drop split distance tracking`
  — nav_screen §3. 최근접탐색·직선도착·자동진행 제거, progress 구독.
각 커밋 `flutter analyze` 새 에러 0(settings 경고 2 허용) + code-auditor 7/7.
C3가 큰 변경이라 단독 분리 유지(C2까지는 미연결이라 안전).

---

## §5. 검증

### 정적
- 각 커밋 `flutter analyze` 새 에러 0. `flutter build apk --debug` 성공.
- C1 후 dev.log로 `lastEnd == pts.length-1` 확인(오프셋 정합).

### 스모크 (라이딩 불필요)
- 경로 탐색 → 내비 진입 → 카드에 첫 turn·거리 표시.
- YNAV_GUIDE tick 로그로 snapIdx **단조 증가**, distToNextTurnM **단조 감소** 확인(정지 상태에서도 비역행).

### 라이딩 회귀 (T3 — main 머지 전 필수)
1. **카드 단조**: 턴 접근 시 잔여거리 단조 감소(518m 고착·역행 없음).
2. **step 전환**: 턴 통과 후 다음 maneuver로 정확 전환(통과 maneuver 잔존 없음).
3. **거리 정확도**: "300m 앞 좌회전"이 실제 ~300m에서 발화(증상3 해소).
4. **TTS 1회**: 500/300/50m 각 1회(중복·누락 없음).
5. **도착**: 폴리라인 끝 도달 시 도착(직선 오판 없음).
6. **이탈**: 경로 벗어나면 offRoute=true → 재탐색 트리거(heading 미고려는 Layer 3).
7. **Layer 0 무회귀**: 속도계·카메라 5/5 유지.

---

## §6. 미결 / 다음
- **window=50, offRoute=50m, arrival=25m**: 초기값. 라이딩 1·6에서 튜닝.
  자기교차 잦은 와인딩 코스에서 window 과대 시 오판 가능 → 작게 시작.
- **재탐색 heading**: 이번엔 offRoute 거리 기반만. Layer 3에서 bearing_after + headingDeg.
- **Layer 2**: verbal_*/multi_cue 파싱 → _labelForType 하드코딩 대체.
- **평면근사 한계**: 세그먼트 투영만 평면. 초장거리 단일 세그먼트(>수 km)는 오차 →
  Valhalla 폴리라인은 조밀해 실무상 무시 가능. 라이딩 3에서 거리정확도로 확인.
- main_map `_selectedManeuvers` 전달은 필드 추가라 하위호환(무변경 확인만).
