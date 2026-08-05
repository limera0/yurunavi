import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../services/poi_service.dart' show PoiService;
import '../../../services/routing_service.dart'
    show RoutingService, ManeuverStep, StructureType, StructureZone, CurveDirection, SharpCurveZone;
import '../models/rear_camera.dart';
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
  final double distToNextCameraM; // GPS 직선거리 기준 추적 중인 후면단속카메라까지(또는 통과 후엔
                                   // 통과 지점으로부터의) 거리. 추적 대상 없으면 ∞.
  final int nextCameraSpeedKmh;   // 추적 중인 카메라의 제한속도. 없으면 0.
  final int nextCameraPostZoneM;  // 추적 중인 카메라의 사후구간 범위. 없으면 0.
  final bool inPostZone;          // 카메라를 통과해 사후구간(postZoneM 이내) 안에 있는 상태.
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
    required this.distToNextCameraM,
    required this.nextCameraSpeedKmh,
    required this.nextCameraPostZoneM,
    required this.inPostZone,
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

  // bridge zone 인덱스 중 "갈림길이 있는" 것만 alert 대상으로 필터링하기 위한 집합.
  // null = 비자명 maneuver가 하나도 없어 필터 비활성(모든 bridge 표시).
  // 빈 Set = maneuver는 있지만 bridge 인근에 갈림길 없음(모든 bridge 억제).
  Set<int>? _forkBridgeZoneIndices;

  // 후면단속카메라 전체 목록. 경로(route)와 무관한 정적 데이터라 setRoute와
  // 별개로 setRearCameras(앱/내비 시작 시 1회)로 주입된다.
  List<RearCamera> _cameras = const [];

  // 현재 접근 중이거나(전방) 막 통과해 사후구간을 추적 중인(후방) 카메라.
  // structureZone/curveZone과 달리 GPS 직선거리+헤딩 기반 판정이라 route
  // geometry 인덱스가 아닌 카메라 자체를 틱 간에 들고 있어야 통과 순간
  // 전방→후방 전환을 놓치지 않는다.
  RearCamera? _trackedCamera;

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
  // bridge zone 진입점 기준, 이 거리 이내에 갈림길 maneuver가 있으면 "선택 필요 다리"로 판정.
  static const _kForkBridgeBufferM = 20.0;
  // 후면단속카메라 1차 후보 필터 반경(전방 탐색). 게이지 표시 임계(150m)보다
  // 넉넉히 잡아 접근 초기부터 안정적으로 같은 카메라를 추적한다.
  static const _kCameraSearchM = 600.0;
  // 카메라 방위각과 진행 헤딩의 최대 허용 편차(전방 판정).
  static const _kCameraAngleToleranceDeg = 70.0;
  // 이 편차를 넘으면 "후방 전환(통과)"으로 판정.
  static const _kCameraBehindAngleDeg = 90.0;

  static const _distance = Distance();

  @override
  RouteProgress? build() {
    // navState.pos 구독 → 매 fix advance.
    final sub = ref.listen<NavigationState?>(navStateProvider, (_, next) {
      final p = next?.pos;
      if (p != null) _advance(p, next?.headingDeg);
    });
    ref.onDispose(sub.close);
    return null;
  }

  /// 후면단속카메라 전체 목록 주입(앱/내비 시작 시 1회, RearCamera.loadAll 결과).
  /// route와 무관한 정적 데이터라 setRoute와 별개 — 즉시 재계산은 하지 않고
  /// 다음 GPS fix(_advance)부터 반영된다.
  void setRearCameras(List<RearCamera> cameras) {
    _cameras = cameras;
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
      // 아직 GPS fix가 없어(pos 없음) 카메라 판정 불가 — 다음 _advance부터 반영.
      distToNextCameraM: double.infinity,
      nextCameraSpeedKmh: 0,
      nextCameraPostZoneM: 0,
      inPostZone: false,
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
      // 카메라도 이 메서드와 무관(GPS 기반, _advance에서만 갱신) — 기존 값 통과.
      distToNextCameraM: current.distToNextCameraM,
      nextCameraSpeedKmh: current.nextCameraSpeedKmh,
      nextCameraPostZoneM: current.nextCameraPostZoneM,
      inPostZone: current.inPostZone,
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
  void _advance(LatLng pos, double? headingDeg) {
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
    final cameraFields = _cameraFieldsFor(pos, headingDeg);
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
      distToNextCameraM: cameraFields.distM,
      nextCameraSpeedKmh: cameraFields.speedKmh,
      nextCameraPostZoneM: cameraFields.postZoneM,
      inPostZone: cameraFields.inPostZone,
    );
  }

  // ── 헬퍼 ──

  // _pts가 비어 있으면(재탐색 중 경로 일시 소멸) 상한이 -1이 되어 clamp가
  // ArgumentError를 던진다 — 0을 반환한다. 이 반환값으로 `_pts[idx]`를 직접
  // 인덱싱하는 호출부는 없다(전부 `_cumFromStartM.isEmpty` 등으로 먼저
  // 가드된 뒤에만 이 값을 쓴다).
  int _clampIdx(int i) => _pts.isEmpty ? 0 : i.clamp(0, _pts.length - 1);

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
    _forkBridgeZoneIndices = _computeForkBridgeZoneIndices();
  }

  /// bridge zone 중 갈림길이 있는 것의 인덱스 집합을 반환한다.
  /// 비자명 maneuver(type != 0/2/4)가 하나도 없으면 null을 반환해 필터를 비활성화한다.
  /// null = 모든 bridge 표시, 빈 Set = 인근 갈림길이 없어 모든 bridge 억제.
  Set<int>? _computeForkBridgeZoneIndices() {
    if (_cumFromStartM.isEmpty || _zones.isEmpty) return null;
    final hasNonTrivial = _maneuvers.any(
        (m) => m.type != 0 && m.type != 2 && m.type != 4);
    if (!hasNonTrivial) return null; // 비자명 maneuver 없음 — 필터 비활성
    final result = <int>{};
    for (int i = 0; i < _maneuvers.length; i++) {
      final m = _maneuvers[i];
      if (m.type == 0 || m.type == 2 || m.type == 4) continue;
      final mBeginM =
          _cumFromStartM[m.beginShapeIdx.clamp(0, _cumFromStartM.length - 1)];
      for (int z = 0; z < _zones.length; z++) {
        if (_zones[z].type != StructureType.bridge) continue;
        final zBeginM = _cumFromStartM[
            _zones[z].beginShapeIdx.clamp(0, _cumFromStartM.length - 1)];
        if ((mBeginM - zBeginM).abs() <= _kForkBridgeBufferM) {
          result.add(z);
        }
      }
    }
    return result;
  }

  /// snap 세그먼트 기준, 아직 지나지 않은 다음 구조물(zone) 인덱스.
  /// _zones는 buildStructureZones 계약에 따라 beginShapeIdx 오름차순 정렬됨.
  /// 모두 지났거나(또는 비어 있으면) -1.
  // ignore: unused_element
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
    for (int i = 0; i < _zones.length; i++) {
      final zone = _zones[i];
      if (zone.endShapeIdx <= seg) continue; // 이미 지난 zone
      // bridge: _forkBridgeZoneIndices가 non-null이면 갈림길 있는 경우만 alert.
      // null = 비자명 maneuver 없음 → 필터 비활성, 모든 bridge 표시.
      if (zone.type == StructureType.bridge &&
          _forkBridgeZoneIndices != null &&
          !_forkBridgeZoneIndices!.contains(i)) {
        continue;
      }
      final cumBegin = _cumFromStartM.isEmpty
          ? 0.0
          : _cumFromStartM[_clampIdx(zone.beginShapeIdx)];
      return (
        idx: i,
        distM: (cumBegin - traveledM).clamp(0.0, double.maxFinite),
        type: zone.type,
      );
    }
    return (idx: -1, distM: double.infinity, type: null);
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

  /// 현재 위치·헤딩 기준 추적 대상 후면단속카메라의 (거리, 제한속도, 사후구간,
  /// 사후구간진입여부)를 계산한다. structureZone/curveZone과 달리 route
  /// geometry가 아닌 GPS 직선거리+진행방향(헤딩)만으로 판정하는 독립적인
  /// 로직이다(HANDOFF_0724/0728 Phase 1 설계).
  ///
  /// - 헤딩 기준 ±[_kCameraAngleToleranceDeg] 이내의 최근접 카메라를 "전방
  ///   접근 중" 카메라로 선택한다([_kCameraSearchM] 반경으로 1차 필터링).
  /// - 한 번 선택된 카메라는 [_trackedCamera]로 틱 간 유지되어, 지나쳐서
  ///   방위각이 [_kCameraBehindAngleDeg]를 넘어 "후방"으로 전환되는 순간을
  ///   포착한다 — 그 시점부터 postZoneM 이내인 동안 inPostZone=true.
  /// - 추적 카메라가 사후구간(postZoneM)마저 벗어나면 추적을 해제하고 다음
  ///   전방 후보를 다시 탐색한다.
  /// - 헤딩이 없으면(GPS 미확보 등) 진행방향 판정이 불가능하므로 추적을
  ///   리셋하고 "탐지 없음"을 반환한다.
  ({double distM, int speedKmh, int postZoneM, bool inPostZone})
      _cameraFieldsFor(LatLng pos, double? headingDeg) {
    if (_cameras.isEmpty || headingDeg == null) {
      _trackedCamera = null;
      return (distM: double.infinity, speedKmh: 0, postZoneM: 0, inPostZone: false);
    }

    // 이미 추적 중인 카메라가 있으면 그 카메라 자체의 현재 거리/방위각으로만
    // 판정한다 — [_kCameraAngleToleranceDeg](전방 탐지용, 70°)보다 느슨한
    // [_kCameraBehindAngleDeg](통과 확정용, 90°) 문턱을 여기서 함께 쓰면
    // angleDiff가 70°~90° 사이인 카메라 바로 옆(예: 오프셋 8m 기준 약
    // 2.5~3m 전방) 구간에서 아래 fresh 탐색 루프(70° tolerance)가 이 카메라를
    // 탈락시켜 "카메라 없음"으로 잘못 보고하거나, 근접한 다른 카메라로
    // 바뀌치기될 수 있다. 따라서 아직 통과 확정 전(angleDiff <= 90)이면 fresh
    // 탐색으로 넘어가지 않고 추적 카메라 자신의 값을 바로 반환한다.
    if (_trackedCamera != null) {
      final tracked = _trackedCamera!;
      final camPos = LatLng(tracked.lat, tracked.lng);
      final dist = PoiService.haversineMeters(pos, camPos);
      final angleDiff = PoiService.bearingDiff(
          PoiService.bearing(pos, camPos), headingDeg);
      if (angleDiff > _kCameraBehindAngleDeg) {
        if (dist <= tracked.postZoneM) {
          return (
            distM: dist,
            speedKmh: tracked.speedKmh,
            postZoneM: tracked.postZoneM,
            inPostZone: true,
          );
        }
        _trackedCamera = null; // 사후구간도 벗어남 — 추적 해제
      } else {
        // 아직 전방(통과 확정 전) — 이 카메라를 계속 추적하며 현재 값을 반환.
        return (
          distM: dist,
          speedKmh: tracked.speedKmh,
          postZoneM: tracked.postZoneM,
          inPostZone: false,
        );
      }
    }

    // 전방 tolerance 이내에서 최근접 카메라를 새로 탐색한다. _trackedCamera가
    // 없을 때(최초 탐지, 또는 사후구간을 벗어나 추적 해제된 직후)만 실행된다.
    RearCamera? best;
    double bestDist = double.infinity;
    for (final cam in _cameras) {
      final camPos = LatLng(cam.lat, cam.lng);
      final dist = PoiService.haversineMeters(pos, camPos);
      if (dist > _kCameraSearchM) continue;
      final angleDiff =
          PoiService.bearingDiff(PoiService.bearing(pos, camPos), headingDeg);
      if (angleDiff > _kCameraAngleToleranceDeg) continue;
      if (dist < bestDist) {
        bestDist = dist;
        best = cam;
      }
    }

    if (best != null) {
      _trackedCamera = best;
      return (
        distM: bestDist,
        speedKmh: best.speedKmh,
        postZoneM: best.postZoneM,
        inPostZone: false,
      );
    }

    return (distM: double.infinity, speedKmh: 0, postZoneM: 0, inPostZone: false);
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
