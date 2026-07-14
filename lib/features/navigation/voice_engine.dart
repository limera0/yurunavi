import 'package:latlong2/latlong.dart';

import '../../../services/exit_landmark_service.dart';
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
    case 17: case 18: case 19: return 'ramp';
    case 20: case 21:          return 'exit';
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

String _profileEventKey(String event) =>
    event.startsWith('roundabout_') ? 'roundabout' : event;

class VoiceEngine {
  final GuidanceProfile profile;
  final ExitLandmarkService? landmarkService;
  VoiceEngine(this.profile, {this.landmarkService});

  int _voiceStepIdx = -1;
  List<double> _pendingPoints = [];
  String? _landmarkForStep;
  double? _immediatePoint;

  List<SpeakIntent> onProgress(
    int step,
    double d,
    List<ManeuverStep> steps, {
    double speedKmh = 0,
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
      if (event == 'exit' &&
          (exitName == null || exitName.isEmpty) &&
          landmarkService != null &&
          begin >= 0 &&
          begin < shapePoints.length) {
        _landmarkForStep = landmarkService!.nearestLandmark(shapePoints[begin]);
      }
    }

    final out = <SpeakIntent>[];
    while (_pendingPoints.isNotEmpty && d <= _pendingPoints.first) {
      final point = _pendingPoints.removeAt(0);
      final isImminent = point == imminentM || point == _immediatePoint;
      if (profile.isEnabled(_profileEventKey(event))) {
        final phase = isImminent ? 'imminent' : 'approach';
        final suffix = isImminent && (event == 'turn_left' || event == 'turn_right')
            ? '_fast'
            : '';
        final vars = {'dist': point.toStringAsFixed(0)};
        if (event == 'destination') {
          vars['dest_word'] = isFinalDestination ? '목적지' : '경유지';
        }
        var key = '${event}_$phase$suffix';
        if (event == 'roundabout_enter') {
          final exitCount = steps[turnIdx].roundaboutExitCount;
          if (exitCount != null) {
            vars['exit'] = exitCount.toString();
          } else {
            key = 'roundabout_$phase$suffix';
          }
        }
        if (event == 'ramp' || event == 'exit') {
          final exitName = steps[turnIdx].exitName;
          if (exitName != null && exitName.isNotEmpty) {
            vars['exit_name'] = exitName;
            key = '${event}_${phase}_named$suffix';
          } else if (event == 'exit' && _landmarkForStep != null) {
            vars['landmark'] = _landmarkForStep!;
            vars['direction'] = steps[turnIdx].type == 21 ? '좌' : '우';
            key = 'exit_${phase}_landmark$suffix';
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
  }
}

/// 고가도로/터널 등 구조물(zone) 진입 음성 안내.
/// [VoiceEngine]의 tiered "pending points, drain as distance decreases" 방식을
/// 그대로 따르되 maneuver step이 아닌 구조물 zone 인덱스/거리/타입 기반으로 동작한다.
/// 회전 관련 로직(_fast 축약, 출구명/랜드마크, 로터리 출구 번호 등)은 없다.
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
    final event = type == StructureType.bridge ? 'bridge' : 'tunnel';
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
      out.add(SpeakIntent('${event}_$phase', {'dist': point.toStringAsFixed(0)}));
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
    final event =
        direction == CurveDirection.left ? 'sharp_turn_left' : 'sharp_turn_right';
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
      out.add(SpeakIntent('${event}_$phase', {'dist': point.toStringAsFixed(0)}));
    }
    return out;
  }

  void reset() {
    _zoneIdx = -1;
    _pendingPoints = [];
    _immediatePoint = null;
  }
}
