import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../services/routing_service.dart'
    show RoutingService, ManeuverStep, StructureType, StructureZone, CurveDirection, SharpCurveZone;
import 'nav_state_provider.dart';

@immutable
class RouteProgress {
  final int snapIdx;            // 폴리라인 상 현재 세그먼트 시작 인덱스 (단조 증가)
  final int activeStepIdx;      // 현재 진행 중 maneuver 인덱스
  final double distToNextTurnM; // snap → 다음 turn(beginShapeIdx)까지 폴리라인 누적
  final double distToDestM;     // snap → 폴리라인 끝까지 누적
  final bool arrived;
  final bool offRoute;          // 스냅 실패(코리도 밖). 재탐색 트리거용
  final int structureZoneIdx;   // _zones 인덱스, "현재 안내 대상 구조물" 식별. 없으면 -1
  final double distToNextStructureM; // snap → 다음 구조물 진입(beginShapeIdx)까지 누적. 없으면 ∞
  final StructureType? nextStructureType; // 다음 구조물 타입. 없으면 null
  final int curveZoneIdx;       // _curves 인덱스, "현재 안내 대상 급커브" 식별. 없으면 -1
  final double distToNextCurveM; // snap → 다음 급커브 진입(beginShapeIdx)까지 누적. 없으면 ∞
  final CurveDirection? nextCurveDirection; // 다음 급커브 방향. 없으면 null
  const RouteProgress({
    required this.snapIdx,
    required this.activeStepIdx,
    required this.distToNextTurnM,
    required this.distToDestM,
    required this.arrived,
    required this.offRoute,
    required this.structureZoneIdx,
    required this.distToNextStructureM,
    required this.nextStructureType,
    required this.curveZoneIdx,
    required this.distToNextCurveM,
    required this.nextCurveDirection,
  });
}

final routeProgressProvider =
    NotifierProvider<RouteProgressNotifier, RouteProgress?>(
        RouteProgressNotifier.new);

class RouteProgressNotifier extends Notifier<RouteProgress?> {
  // ── 경로 컨텍스트 (setRoute로 주입) ──
  List<LatLng> _pts = const [];
  List<ManeuverStep> _maneuvers = const [];
  List<StructureZone> _zones = const [];
  List<SharpCurveZone> _curves = const [];

  // ── 사전계산 ──
  List<double> _segLenM = const [];  // _pts[i]→_pts[i+1] 길이
  List<double> _cumFromStartM = const []; // _pts[0]→_pts[i] 누적
  double _totalM = 0.0;

  // exit(type 20/21) maneuver 인덱스 → 인접 구조물 타입. setRoute()/
  // setStructureZones() 호출 시마다 재계산되는 정적 파생 데이터라 _maneuvers/
  // _zones 자신처럼 per-tick RouteProgress state에는 포함하지 않는다.
  Map<int, StructureType> _exitStructureByManeuverIdx = const {};

  // 온-루트(trace_attributes/_zones)로는 못 찾은 exit maneuver에 한해, 그
  // 시작점 근방을 Valhalla /locate로 조회해 "옆길로 우회 중인" 구조물을 찾은
  // 결과(setOffRouteStructures로 주입). _recomputeExitStructureMap에서
  // 온-루트 결과가 없을 때만 폴백으로 사용된다 — 온-루트가 항상 우선.
  Map<int, StructureType> _offRouteStructureByManeuverIdx = const {};

  /// [_exitStructureByManeuverIdx]의 읽기 전용 노출.
  Map<int, StructureType> get exitStructureByManeuverIdx =>
      _exitStructureByManeuverIdx;

  // ── 진행 상태 ──
  int _snapIdx = 0;
  double _traveledM = 0.0; // snap 세그먼트 내 실제 진행거리 포함, 폴리라인 시작 기준 누적거리

  // ── 튜닝 상수 ──
  static const _kSnapWindow = 50;       // 앞쪽 탐색 세그먼트 수
  static const _kOffRouteM = 50.0;      // 코리도 이탈 임계(최근접 세그먼트 거리)
  static const _kArrivalM = 25.0;       // 도착 반경(폴리라인 잔여)

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
    _zones = const []; // 구조물 구간은 setStructureZones로 비동기 별도 주입
    _offRouteStructureByManeuverIdx = const {}; // 새 경로엔 이전 옆길 조회 결과가 무의미
    // 급커브는 순수 geometry 계산이라 fetchStructureZones처럼 비동기 HTTP
    // 응답을 기다릴 필요가 없다 — setRoute 시점에 바로 계산해 반영한다.
    _curves = RoutingService.detectSharpCurves(points, maneuvers);
    _snapIdx = 0;
    _traveledM = 0.0;

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

    // 재탐색 등으로 _zones가 위에서 이미 비워졌으므로(직전 route의 zone은 새
    // maneuver의 shape 인덱스와 무관), 여기서도 재계산해 stale 매핑이 남지
    // 않게 한다. trace_attributes 응답이 도착하면 setStructureZones()가 다시
    // 갱신한다.
    _recomputeExitStructureMap();

    if (maneuvers.isNotEmpty) {
      debugPrint('YNAV_ROUTE steps=${maneuvers.length} pts=${points.length} lastBegin=${maneuvers.last.beginShapeIdx} lastEnd=${maneuvers.last.endShapeIdx}');
    }

    final structFields = _structureFieldsFor(0, 0.0);
    final curveFields = _curveFieldsFor(0, 0.0);
    state = RouteProgress(
      snapIdx: 0,
      activeStepIdx: 0,
      distToNextTurnM: _distToShapeIdx(0, _nextTurnShapeIdx(0)),
      distToDestM: _totalM,
      arrived: false,
      offRoute: false,
      structureZoneIdx: structFields.idx,
      distToNextStructureM: structFields.distM,
      nextStructureType: structFields.type,
      curveZoneIdx: curveFields.idx,
      distToNextCurveM: curveFields.distM,
      nextCurveDirection: curveFields.direction,
    );
  }

  /// 다리/터널 구간 주입. trace_attributes HTTP 호출이 setRoute 이후 비동기로
  /// 완료되므로 별도 메서드로 분리 — 라이더가 이미 주행 중일 수 있어 현재
  /// _snapIdx 기준으로 즉시 재계산해 state를 다시 emit한다.
  void setStructureZones(List<StructureZone> zones) {
    _zones = zones;
    _recomputeExitStructureMap();
    final current = state;
    if (current == null) return; // 아직 경로 없음 — 다음 setRoute에서 반영
    final structFields = _structureFieldsFor(_snapIdx, _traveledM);
    state = RouteProgress(
      snapIdx: current.snapIdx,
      activeStepIdx: current.activeStepIdx,
      distToNextTurnM: current.distToNextTurnM,
      distToDestM: current.distToDestM,
      arrived: current.arrived,
      offRoute: current.offRoute,
      structureZoneIdx: structFields.idx,
      distToNextStructureM: structFields.distM,
      nextStructureType: structFields.type,
      // 급커브는 이 메서드와 무관(순수 geometry, setRoute에서 이미 계산됨) —
      // 기존 값을 그대로 통과시킨다.
      curveZoneIdx: current.curveZoneIdx,
      distToNextCurveM: current.distToNextCurveM,
      nextCurveDirection: current.nextCurveDirection,
    );
  }

  /// 온-루트(trace_attributes/_zones)로 못 찾은 exit maneuver에 한해, 그
  /// 시작점 근방 /locate 조회로 찾은 "옆길로 우회 중인" 구조물 결과를
  /// 주입한다(호출자는 nav_screen — HANDOFF_0716 §3 참조). RouteProgress
  /// state의 다른 필드(온-루트 zone 관련)는 건드리지 않으므로 재emit하지
  /// 않는다 — exitStructureByManeuverIdx는 getter로 직접 조회되는 파생
  /// 데이터라 호출자가 필요하면 직접 UI를 다시 그린다(setStructureZones와
  /// 동일 패턴, nav_screen._loadOffRouteStructures 참조).
  void setOffRouteStructures(Map<int, StructureType> byManeuverIdx) {
    _offRouteStructureByManeuverIdx = byManeuverIdx;
    _recomputeExitStructureMap();
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
    _traveledM = traveledM;

    // active step: snap이 지난 maneuver를 제외한 다음 턴
    final activeStep = _activeStepFor(bestSeg);
    final nextTurnShape = _nextTurnShapeIdx(bestSeg);

    final distToNext = (_cumFromStartM[_clampIdx(nextTurnShape)] - traveledM)
        .clamp(0.0, double.maxFinite);
    final distToDest = (_totalM - traveledM).clamp(0.0, double.maxFinite);
    final arrived = distToDest <= _kArrivalM;

    if (activeStep != (state?.activeStepIdx ?? -1) && activeStep < _maneuvers.length) {
      final m = _maneuvers[activeStep];
      debugPrint('YNAV_STEP from=${state?.activeStepIdx ?? -1} to=$activeStep maneuver=${m.type} beginShape=${m.beginShapeIdx} endShape=${m.endShapeIdx}');
    }
    if (arrived && !(state?.arrived ?? false)) {
      debugPrint('YNAV_ARR dest=${distToDest.toStringAsFixed(1)} snap=$bestSeg lastShape=${_pts.length - 1}');
    }
    debugPrint('YNAV_PROG snap=$bestSeg step=$activeStep next=${distToNext.toStringAsFixed(1)} dest=${distToDest.toStringAsFixed(1)} off=$offRoute perp=${bestPerp.toStringAsFixed(1)}');

    final structFields = _structureFieldsFor(bestSeg, traveledM);
    final curveFields = _curveFieldsFor(bestSeg, traveledM);
    state = RouteProgress(
      snapIdx: bestSeg,
      activeStepIdx: activeStep,
      distToNextTurnM: distToNext,
      distToDestM: distToDest,
      arrived: arrived,
      offRoute: offRoute,
      structureZoneIdx: structFields.idx,
      distToNextStructureM: structFields.distM,
      nextStructureType: structFields.type,
      curveZoneIdx: curveFields.idx,
      distToNextCurveM: curveFields.distM,
      nextCurveDirection: curveFields.direction,
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

  /// _maneuvers/_zones/_cumFromStartM 기준으로 exit(type 20/21) maneuver별
  /// 인접 구조물 타입을 재계산해 [_exitStructureByManeuverIdx]에 캐싱한다.
  /// setRoute()(새 경로 주입), setStructureZones()(zone 비동기 도착),
  /// setOffRouteStructures()(옆길 /locate 비동기 도착) 세 곳 모두에서
  /// 호출된다 — 어느 하나만으로는 이 셋이 모두 준비된 시점을 보장할 수 없다.
  /// 온-루트(structureNearExit) 결과가 항상 우선이고, 그게 null일 때만
  /// _offRouteStructureByManeuverIdx로 폴백한다 — 실제로 그 구조물을 타는
  /// 경로라면 옆길 조회 결과와 무관하게 정확한 온-루트 판정을 써야 한다.
  void _recomputeExitStructureMap() {
    final map = <int, StructureType>{};
    for (int i = 0; i < _maneuvers.length; i++) {
      final m = _maneuvers[i];
      if (m.type != 20 && m.type != 21) continue;
      final onRoute =
          RoutingService.structureNearExit(m, _zones, _cumFromStartM);
      final type = onRoute ?? _offRouteStructureByManeuverIdx[i];
      if (type != null) map[i] = type;
    }
    _exitStructureByManeuverIdx = map;
  }

  /// snap 세그먼트 기준, 아직 지나지 않은 다음 구조물(zone) 인덱스.
  /// _zones는 buildStructureZones 계약에 따라 beginShapeIdx 오름차순 정렬됨.
  /// 모두 지났거나(또는 비어 있으면) -1.
  int _nextZoneIdxFor(int seg) {
    for (int i = 0; i < _zones.length; i++) {
      if (_zones[i].endShapeIdx > seg) return i;
    }
    return -1;
  }

  /// snap 세그먼트 기준 다음 구조물의 (인덱스, 진입까지 거리, 타입).
  /// 다음 구조물이 없으면 (-1, ∞, null).
  /// [traveledM]은 세그먼트 시작점이 아닌, 세그먼트 내 실제 진행거리까지 포함한
  /// 폴리라인 시작 기준 누적거리(= _advance()의 로컬 traveledM / _traveledM)여야
  /// 정확하다. 세그먼트 시작점만 쓰면 세그먼트 길이만큼 과대평가된다.
  ({int idx, double distM, StructureType? type}) _structureFieldsFor(
      int seg, double traveledM) {
    final idx = _nextZoneIdxFor(seg);
    if (idx < 0) return (idx: -1, distM: double.infinity, type: null);
    final cumBegin = _cumFromStartM.isEmpty
        ? 0.0
        : _cumFromStartM[_clampIdx(_zones[idx].beginShapeIdx)];
    return (
      idx: idx,
      distM: (cumBegin - traveledM).clamp(0.0, double.maxFinite),
      type: _zones[idx].type,
    );
  }

  /// snap 세그먼트 기준, 아직 지나지 않은 다음 급커브(curve) 인덱스.
  /// _curves는 detectSharpCurves 계약에 따라 beginShapeIdx 오름차순 정렬됨.
  /// 모두 지났거나(또는 비어 있으면) -1.
  int _nextCurveIdxFor(int seg) {
    for (int i = 0; i < _curves.length; i++) {
      if (_curves[i].endShapeIdx > seg) return i;
    }
    return -1;
  }

  /// snap 세그먼트 기준 다음 급커브의 (인덱스, 진입까지 거리, 방향).
  /// 다음 급커브가 없으면 (-1, ∞, null).
  ({int idx, double distM, CurveDirection? direction}) _curveFieldsFor(
      int seg, double traveledM) {
    final idx = _nextCurveIdxFor(seg);
    if (idx < 0) return (idx: -1, distM: double.infinity, direction: null);
    final cumBegin = _cumFromStartM.isEmpty
        ? 0.0
        : _cumFromStartM[_clampIdx(_curves[idx].beginShapeIdx)];
    return (
      idx: idx,
      distM: (cumBegin - traveledM).clamp(0.0, double.maxFinite),
      direction: _curves[idx].direction,
    );
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
