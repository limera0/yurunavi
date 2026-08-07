import 'package:latlong2/latlong.dart';

import '../../../services/exit_landmark_service.dart';
import '../../../services/poi_service.dart';
import '../../../services/routing_service.dart';
import 'guidance_profile.dart';

class SpeakIntent {
  final String key;
  final Map<String, String> vars;
  const SpeakIntent(this.key, this.vars);
}

String? eventForType(int type) {
  switch (type) {
    case 15: case 16:          return 'turn_left';
    case 14:                   return 'sharp_turn_left';
    case 9:  case 10:          return 'turn_right';
    case 11:                   return 'sharp_turn_right';
    case 12: case 13:          return 'uturn';
    case 17:                   return 'ramp_straight';
    case 18:                   return 'ramp_right';
    case 19:                   return 'ramp_left';
    case 20:                   return 'exit_right';
    case 21:                   return 'exit_left';
    case 22:                   return 'keep';
    case 23:                   return 'keep_right';
    case 24:                   return 'keep_left';
    case 25: case 37: case 38: return 'merge';
    case 26:                   return 'roundabout_enter';
    case 27:                   return 'roundabout_exit';
    case 4:  case 5:  case 6:  return 'destination';
    case 8:                    return 'continue';
    default:                   return null;
  }
}

/// 거리(미터)를 50m 단위로 스냅한 뒤 한글 수사로 변환한다.
///
/// - 50m 미만은 50으로 올림(clamp), 1000m 초과도 1000으로 내림.
/// - 1000m → '일 킬로' (템플릿에서 "일 킬로미터 앞"이 됨)
/// - 그 외 → 백 단위 + 오십 접미사 조합
///   예: 50→'오십', 100→'백', 150→'백오십', 300→'삼백', 550→'오백오십'
String _distToKorean(double distM) {
  final m = ((distM / 50).round() * 50).clamp(50, 1000);
  if (m >= 1000) return '일 킬로';
  const h = ['', '백', '이백', '삼백', '사백', '오백', '육백', '칠백', '팔백', '구백'];
  final hundreds = m ~/ 100;
  final hasFifty = (m % 100) >= 50;
  return h[hundreds] + (hasFifty ? '오십' : '');
}

/// 가이던스 프로필(거리 티어/imminent 거리/on-off)은 방향별로 나뉘지 않고
/// ramp/exit 하나로 공유한다 — 세분화된 이벤트 키(ramp_right 등)는 TTS 문구
/// 선택에만 쓰이고, 접근 타이밍 설정은 기존 'ramp'/'exit' 항목을 그대로 참조.
String _profileEventKey(String event) {
  if (event == 'roundabout_enter') return 'roundabout_enter';
  if (event == 'roundabout_exit') return 'roundabout_exit';
  if (event.startsWith('roundabout_')) return 'roundabout';
  if (event.startsWith('ramp_')) return 'ramp';
  if (event.startsWith('exit_')) return 'exit';
  return event;
}

/// `steps[turnIdx]`(roundabout_enter, type 26)의 진입 방위각과 짝을 이루는
/// 바로 다음 스텝(`steps[turnIdx+1]`, roundabout_exit, type 27)의 진출
/// 방위각으로 좌/직/우 방향을 계산한다. 짝 maneuver가 없거나 타입이 다르거나
/// shape 인덱스가 경계를 벗어나면 null(호출자가 방향 없는 일반 문구로
/// 폴백한다).
RoundaboutDirection? _computeRoundaboutDirection(
  int turnIdx,
  List<ManeuverStep> steps,
  List<LatLng> shapePoints,
) {
  final beginIdx = steps[turnIdx].beginShapeIdx;
  if (beginIdx < 1 || beginIdx >= shapePoints.length) return null;
  final entryBearing = PoiService.bearing(
    shapePoints[beginIdx - 1],
    shapePoints[beginIdx],
  );

  final exitStepIdx = turnIdx + 1;
  if (exitStepIdx >= steps.length || steps[exitStepIdx].type != 27) {
    return null;
  }
  final exitStep = steps[exitStepIdx];
  final endIdx = exitStep.endShapeIdx;
  if (endIdx < 1 ||
      endIdx >= shapePoints.length ||
      endIdx - 1 < exitStep.beginShapeIdx) {
    return null;
  }
  final exitBearing = PoiService.bearing(
    shapePoints[endIdx - 1],
    shapePoints[endIdx],
  );

  final signedTurn = PoiService.signedBearingDiff(entryBearing, exitBearing);
  return RoutingService.classifyRoundaboutDirection(signedTurn);
}

class VoiceEngine {
  final GuidanceProfile profile;
  final ExitLandmarkService? landmarkService;
  /// exit(type 20/21) maneuver 인덱스(steps 상의 인덱스, 즉 turnIdx) → 인접
  /// 구조물 타입. RouteProgressNotifier.exitStructureByManeuverIdx를 그대로
  /// 참조받아 조회한다. 경로가 바뀌거나(재탐색) trace_attributes 응답이
  /// 뒤늦게 도착할 때마다 값이 갱신되므로 final이 아닌 settable 필드 —
  /// 호출자가 매 onProgress 호출 전 최신 값으로 갱신해야 한다.
  Map<int, StructureType>? exitStructureByManeuverIdx;
  VoiceEngine(this.profile,
      {this.landmarkService, this.exitStructureByManeuverIdx});

  int _voiceStepIdx = -1;
  List<double> _pendingPoints = [];
  String? _landmarkForStep;
  double? _immediatePoint;
  double _prevD = double.infinity;

  List<SpeakIntent> onProgress(
    int step,
    double d,
    List<ManeuverStep> steps, {
    List<LatLng> shapePoints = const [],
    bool isFinalDestination = true,
  }) {
    final turnIdx = step + 1;
    if (turnIdx >= steps.length) return const [];
    final event = eventForType(steps[turnIdx].type);
    if (event == null) return const [];

    final imminentM = profile.imminentForEvent(_profileEventKey(event));
    if (step != _voiceStepIdx) {
      _voiceStepIdx = step;
      _prevD = d;
      final entryD = d;
      final eventTierList = profile.tiersForEvent(_profileEventKey(event));
      final tier = eventTierList.firstWhere(
        (t) => entryD >= t.minEntryM,
        orElse: () => eventTierList.last,
      );
      final filtered = {...tier.pointsM, imminentM}
          .where((p) => p < entryD)
          .toList()
        ..sort((a, b) => b.compareTo(a));
      if (filtered.isEmpty && entryD >= 0) {
        // Every configured checkpoint — including the imminent one — is already
        // behind the vehicle by the time this maneuver is first seen (e.g. two
        // corners closer together than the imminent distance). Announce
        // immediately instead of leaving this turn with no voice cue at all.
        filtered.add(entryD);
        _immediatePoint = entryD;
      } else {
        _immediatePoint = null;
      }
      _pendingPoints = filtered;

      // 출구명(exitName)이 없을 때만 오프라인 랜드마크 폴백 조회 — 스텝당 1회.
      _landmarkForStep = null;
      final exitName = steps[turnIdx].exitName;
      final begin = steps[turnIdx].beginShapeIdx;
      if (event.startsWith('exit_') &&
          (exitName == null || exitName.isEmpty) &&
          landmarkService != null &&
          begin >= 0 &&
          begin < shapePoints.length) {
        _landmarkForStep = landmarkService!.nearestLandmark(shapePoints[begin]);
      }
    }

    // 동일 step에서 거리가 30m 이상 커지면(= 지점 통과 후 step이 아직 미전환)
    // 오래된 pending 포인트를 버린다.
    if (step == _voiceStepIdx && d > _prevD + 30) {
      _pendingPoints = [];
    }
    _prevD = d;

    final out = <SpeakIntent>[];
    while (_pendingPoints.isNotEmpty && d <= _pendingPoints.first) {
      final point = _pendingPoints.removeAt(0);
      final isImminent = point == imminentM || point == _immediatePoint;
      if (profile.isEnabled(_profileEventKey(event))) {
        final phase = isImminent ? 'imminent' : 'approach';
        final vars = {'dist': _distToKorean(point)};
        if (event == 'destination') {
          vars['dest_word'] = isFinalDestination ? '목적지' : '경유지';
        }
        var key = '${event}_$phase';
        if (event == 'roundabout_enter') {
          // roundaboutExitCount(출구 번호)는 Valhalla 자체가 신뢰 불가 값을
          // 반환함이 확인돼(HANDOFF_0807_S6 — 업스트림 포함 검단 회전교차로
          // 6개 조합 전부 오답) 더 이상 쓰지 않는다. 대신 진입/진출 shape
          // 방위각 차이로 좌/직/우 방향을 직접 계산한다.
          final direction = _computeRoundaboutDirection(turnIdx, steps, shapePoints);
          if (direction != null) {
            vars['direction'] = direction.labelKo;
          } else {
            key = 'roundabout_$phase';
          }
        }
        if (event.startsWith('ramp_') || event.startsWith('exit_')) {
          final exitName = steps[turnIdx].exitName;
          StructureType? nearbyStructure;
          if (event.startsWith('exit_')) {
            nearbyStructure = exitStructureByManeuverIdx?[turnIdx];
          }
          if (exitName != null && exitName.isNotEmpty) {
            vars['exit_name'] = exitName;
            key = '${event}_${phase}_named';
          } else if (event.startsWith('exit_') && nearbyStructure != null) {
            // 구조물 인접 맥락이 일반 랜드마크 폴백보다 라이더에게 더
            // 유용하므로 우선한다.
            vars['structure'] = nearbyStructure.labelKo;
            key = '${event}_${phase}_structure';
          } else if (event.startsWith('exit_') && _landmarkForStep != null) {
            vars['landmark'] = _landmarkForStep!;
            key = '${event}_${phase}_landmark';
          }
        }
        out.add(SpeakIntent(key, vars));
      }
    }
    return out;
  }

  void reset() {
    _voiceStepIdx = -1;
    _pendingPoints = [];
    _landmarkForStep = null;
    _immediatePoint = null;
    _prevD = double.infinity;
  }
}

/// 고가도로/터널/지하차도 등 구조물(zone) 진입 음성 안내.
/// [VoiceEngine]의 tiered "pending points, drain as distance decreases" 방식을
/// 그대로 따르되 maneuver step이 아닌 구조물 zone 인덱스/거리/타입 기반으로 동작한다.
/// 회전 관련 로직(출구명/랜드마크, 로터리 출구 번호 등)은 없다.
class StructureVoiceEngine {
  final GuidanceProfile profile;
  StructureVoiceEngine(this.profile);

  int _zoneIdx = -1;
  List<double> _pendingPoints = [];
  double? _immediatePoint;

  List<SpeakIntent> onProgress(int zoneIdx, double d, StructureType? type) {
    if (type == null || zoneIdx < 0) {
      // 모든 구조물 통과(zoneIdx=-1) 후에도 _zoneIdx를 갱신해두지 않으면,
      // 재탐색 후 새 경로의 첫 구간이 우연히 같은 인덱스를 재사용할 때
      // "이미 본 구간"으로 오인해 안내가 조용히 스킵될 수 있다.
      _zoneIdx = zoneIdx;
      _pendingPoints = [];
      _immediatePoint = null;
      return const [];
    }
    final event = switch (type) {
      StructureType.bridge => 'bridge',
      StructureType.overpass => 'overpass',
      StructureType.tunnel => 'tunnel',
      StructureType.underpass => 'underpass',
    };
    final imminentM = profile.imminentForEvent(event);
    if (zoneIdx != _zoneIdx) {
      _zoneIdx = zoneIdx;
      final entryD = d;
      final tierList = profile.tiersForEvent(event);
      final tier = tierList.firstWhere(
        (t) => entryD >= t.minEntryM,
        orElse: () => tierList.last,
      );
      final filtered = {...tier.pointsM, imminentM}
          .where((p) => p < entryD)
          .toList()
        ..sort((a, b) => b.compareTo(a));
      if (filtered.isEmpty && entryD >= 0) {
        // 이 구조물을 처음 관측한 시점에 이미 imminent 지점까지도 지나쳐
        // 있는 경우(짧은 간격의 연속 구조물, 또는 비동기 zone 조회가 늦게
        // 도착한 경우) — 안내가 아예 없는 대신 즉시 1회 안내한다.
        // VoiceEngine._immediatePoint와 동일한 처리.
        filtered.add(entryD);
        _immediatePoint = entryD;
      } else {
        _immediatePoint = null;
      }
      _pendingPoints = filtered;
    }

    final out = <SpeakIntent>[];
    while (_pendingPoints.isNotEmpty && d <= _pendingPoints.first) {
      final point = _pendingPoints.removeAt(0);
      if (!profile.isEnabled(event)) continue;
      final isImminent = point == imminentM || point == _immediatePoint;
      final phase = isImminent ? 'imminent' : 'approach';
      out.add(SpeakIntent('${event}_$phase', {'dist': _distToKorean(point)}));
    }
    return out;
  }

  void reset() {
    _zoneIdx = -1;
    _pendingPoints = [];
    _immediatePoint = null;
  }
}

/// 교차로가 아닌 곳에서 geometry로 감지된 급커브 진입 음성 안내.
/// [StructureVoiceEngine]의 tiered "pending points, drain as distance
/// decreases" 방식을 그대로 따르되 구조물이 아닌 커브 zone 인덱스/거리/방향
/// 기반으로 동작하며, Valhalla maneuver 기반 sharp_turn_left/right와 동일한
/// 기존 이벤트/음성 템플릿을 재사용한다.
class CurveVoiceEngine {
  final GuidanceProfile profile;
  CurveVoiceEngine(this.profile);

  int _zoneIdx = -1;
  List<double> _pendingPoints = [];
  double? _immediatePoint;

  List<SpeakIntent> onProgress(int zoneIdx, double d, CurveDirection? direction) {
    if (direction == null || zoneIdx < 0) {
      // 모든 커브 통과(zoneIdx=-1) 후에도 _zoneIdx를 갱신해두지 않으면,
      // 재탐색 후 새 경로의 첫 구간이 우연히 같은 인덱스를 재사용할 때
      // "이미 본 구간"으로 오인해 안내가 조용히 스킵될 수 있다.
      _zoneIdx = zoneIdx;
      _pendingPoints = [];
      _immediatePoint = null;
      return const [];
    }
    final event = direction == CurveDirection.left
        ? 'sharp_turn_left'
        : 'sharp_turn_right';
    final imminentM = profile.imminentForEvent(event);
    if (zoneIdx != _zoneIdx) {
      _zoneIdx = zoneIdx;
      final entryD = d;
      final tierList = profile.tiersForEvent(event);
      final tier = tierList.firstWhere(
        (t) => entryD >= t.minEntryM,
        orElse: () => tierList.last,
      );
      final filtered = {...tier.pointsM, imminentM}
          .where((p) => p < entryD)
          .toList()
        ..sort((a, b) => b.compareTo(a));
      if (filtered.isEmpty && entryD >= 0) {
        // 이 커브를 처음 관측한 시점에 이미 imminent 지점까지도 지나쳐
        // 있는 경우 — 안내가 아예 없는 대신 즉시 1회 안내한다.
        // VoiceEngine._immediatePoint와 동일한 처리.
        filtered.add(entryD);
        _immediatePoint = entryD;
      } else {
        _immediatePoint = null;
      }
      _pendingPoints = filtered;
    }

    final out = <SpeakIntent>[];
    while (_pendingPoints.isNotEmpty && d <= _pendingPoints.first) {
      final point = _pendingPoints.removeAt(0);
      if (!profile.isEnabled(event)) continue;
      final isImminent = point == imminentM || point == _immediatePoint;
      final phase = isImminent ? 'imminent' : 'approach';
      out.add(SpeakIntent('${event}_$phase', {'dist': _distToKorean(point)}));
    }
    return out;
  }

  void reset() {
    _zoneIdx = -1;
    _pendingPoints = [];
    _immediatePoint = null;
  }
}

/// 후면단속카메라(18번) 접근/사후구간 음성 안내.
///
/// 다른 Voice Engine과 달리 카메라에는 고유 인덱스가 없다 —
/// route_progress_provider의 후면카메라 추적은 구조물/커브 zone처럼
/// maneuver나 geometry 상의 인덱스에 묶이지 않고 GPS 직선거리로 "가장 가까운
/// 카메라"를 매 tick 재평가하는 방식이라 StructureVoiceEngine의 zoneIdx 같은
/// 식별자를 붙일 수 없다. 대신 "이번 접근 사이클에서 이미 안내했는지"를
/// 불리언 플래그 2개(150m/50m)로 추적하고, distM이 다시 150m 초과 +
/// inPostZone=false(완전 idle)로 돌아가는 순간 리셋해 다음 카메라에서
/// 재발화되게 한다.
class RearCameraVoiceEngine {
  /// [CameraApproachGauge.kThresholdM](rear_camera_gauge.dart)과 동일한 값.
  /// 이 파일은 순수 Dart 로직이라 Flutter 위젯 파일을 import하지 않고 값만
  /// 복제한다 — 값이 바뀌면 양쪽 다 갱신해야 한다.
  static const double kApproachAnnounceM = 150.0;
  static const double kFinalAnnounceM = 50.0;

  bool _approachAnnounced = false;
  bool _finalAnnounced = false;

  List<SpeakIntent> onProgress(double distM, bool inPostZone) {
    final active = inPostZone || distM <= kApproachAnnounceM;
    if (!active) {
      // 완전히 idle로 복귀(추적 카메라 없음) — 다음 카메라를 위해 리셋.
      _approachAnnounced = false;
      _finalAnnounced = false;
      return const [];
    }
    final out = <SpeakIntent>[];
    if (!inPostZone) {
      // 사후구간에서는 재차 거리가 늘었다 줄었다 해도 새 안내를 내지 않는다
      // (요구사항: 50m 안내는 접근 사이클 중 1회뿐).
      if (!_approachAnnounced && distM <= kApproachAnnounceM) {
        _approachAnnounced = true;
        out.add(const SpeakIntent('rear_camera_approach', {}));
      }
      if (!_finalAnnounced && distM <= kFinalAnnounceM) {
        _finalAnnounced = true;
        out.add(const SpeakIntent('rear_camera_final_countdown', {}));
      }
    }
    return out;
  }

  void reset() {
    _approachAnnounced = false;
    _finalAnnounced = false;
  }
}
