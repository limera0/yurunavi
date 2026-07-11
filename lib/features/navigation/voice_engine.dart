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
    case 22: case 23: case 24: return 'keep';
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

  List<SpeakIntent> onProgress(
    int step,
    double d,
    List<ManeuverStep> steps, {
    double speedKmh = 0,
    List<LatLng> shapePoints = const [],
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
      final pts = [...tier.pointsM, imminentM];
      _pendingPoints = pts.where((p) => p < entryD).toList()
        ..sort((a, b) => b.compareTo(a));

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
      final isImminent = point == imminentM;
      if (profile.isEnabled(_profileEventKey(event))) {
        final phase = isImminent ? 'imminent' : 'approach';
        final suffix = isImminent &&
                speedKmh >= 20 &&
                (event == 'turn_left' || event == 'turn_right')
            ? '_fast'
            : '';
        final vars = {'dist': point.toStringAsFixed(0)};
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
  }
}
