import '../../../services/routing_service.dart';
import 'guidance_profile.dart';

class SpeakIntent {
  final String key;
  final Map<String, String> vars;
  const SpeakIntent(this.key, this.vars);
}

String? eventForType(int type) {
  switch (type) {
    case 14: case 15: case 16: return 'turn_left';
    case 9:  case 10: case 11: return 'turn_right';
    case 12: case 13:          return 'uturn';
    case 17: case 18: case 19: return 'ramp';
    case 20: case 21:          return 'exit';
    case 22: case 23: case 24: return 'keep';
    case 25: case 37: case 38: return 'merge';
    case 26:                   return 'roundabout_enter';
    case 27:                   return 'roundabout_exit';
    case 4:  case 5:  case 6:  return 'destination';
    default:                   return null;
  }
}

String _profileEventKey(String event) =>
    event.startsWith('roundabout_') ? 'roundabout' : event;

class VoiceEngine {
  final GuidanceProfile profile;
  VoiceEngine(this.profile);

  int _voiceStepIdx = -1;
  List<double> _pendingPoints = [];

  List<SpeakIntent> onProgress(int step, double d, List<ManeuverStep> steps, {double speedKmh = 0}) {
    final turnIdx = step + 1;
    if (turnIdx >= steps.length) return const [];
    final event = eventForType(steps[turnIdx].type);
    if (event == null) return const [];

    if (step != _voiceStepIdx) {
      _voiceStepIdx = step;
      final entryD = d;
      final eventTierList = profile.tiersForEvent(_profileEventKey(event));
      final tier = eventTierList.firstWhere(
        (t) => entryD >= t.minEntryM,
        orElse: () => eventTierList.last,
      );
      final pts = [...tier.pointsM, profile.imminentM];
      _pendingPoints = pts.where((p) => p < entryD).toList()
        ..sort((a, b) => b.compareTo(a));
    }

    final out = <SpeakIntent>[];
    while (_pendingPoints.isNotEmpty && d <= _pendingPoints.first) {
      final point = _pendingPoints.removeAt(0);
      final isImminent = point == profile.imminentM;
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
        out.add(SpeakIntent(key, vars));
      }
    }
    return out;
  }

  void reset() {
    _voiceStepIdx = -1;
    _pendingPoints = [];
  }
}
