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

    if (maneuvers.isNotEmpty) {
      debugPrint('YNAV_ROUTE steps=${maneuvers.length} pts=${points.length} lastBegin=${maneuvers.last.beginShapeIdx} lastEnd=${maneuvers.last.endShapeIdx}');
    }

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

    if (activeStep != (state?.activeStepIdx ?? -1) && activeStep < _maneuvers.length) {
      final m = _maneuvers[activeStep];
      debugPrint('YNAV_STEP from=${state?.activeStepIdx ?? -1} to=$activeStep maneuver=${m.type} beginShape=${m.beginShapeIdx} endShape=${m.endShapeIdx}');
    }
    if (arrived && !(state?.arrived ?? false)) {
      debugPrint('YNAV_ARR dest=${distToDest.toStringAsFixed(1)} snap=$bestSeg lastShape=${_pts.length - 1}');
    }
    debugPrint('YNAV_PROG snap=$bestSeg step=$activeStep next=${distToNext.toStringAsFixed(1)} dest=${distToDest.toStringAsFixed(1)} off=$offRoute perp=${bestPerp.toStringAsFixed(1)}');

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
