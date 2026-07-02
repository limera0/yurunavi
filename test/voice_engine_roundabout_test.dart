import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // Standard fallback-equivalent profile (tiers sorted descending).
  final profile = GuidanceProfile(
    imminentM: 5,
    tiers: const [
      GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
      GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
      GuidanceTier(minEntryM: 30,  pointsM: [100, 50]),
      GuidanceTier(minEntryM: 0,   pointsM: []),
    ],
    enabledEvents: {
      'turn_left', 'turn_right', 'uturn', 'ramp', 'exit',
      'keep', 'merge', 'roundabout', 'destination',
    },
  );

  ManeuverStep step0({int type = 0}) =>
      ManeuverStep(type: type, instruction: '', distanceKm: 0);

  List<SpeakIntent> drive(VoiceEngine e, int stepIdx,
      List<double> dSeq, List<ManeuverStep> steps) {
    final out = <SpeakIntent>[];
    for (final d in dSeq) {
      out.addAll(e.onProgress(stepIdx, d, steps));
    }
    return out;
  }

  group('A — eventForType 회전교차로', () {
    test('type=26 returns roundabout_enter', () {
      expect(eventForType(26), 'roundabout_enter');
    });

    test('type=27 returns roundabout_exit', () {
      expect(eventForType(27), 'roundabout_exit');
    });
  });

  group('B — 회전교차로 진입 (exit count present)', () {
    test('emits roundabout_enter_* with exit var', () {
      final engine = VoiceEngine(profile);
      final steps = [
        step0(),
        ManeuverStep(type: 26, instruction: '', distanceKm: 0, roundaboutExitCount: 2),
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_enter_approach',
        'roundabout_enter_imminent',
      ]);
      expect(intents[0].vars['exit'], '2');
      expect(intents[1].vars['exit'], '2');
    });
  });

  group('C — 회전교차로 진입 (exit count null, fallback)', () {
    test('falls back to generic roundabout_* without exit var', () {
      final engine = VoiceEngine(profile);
      final steps = [
        step0(),
        ManeuverStep(type: 26, instruction: '', distanceKm: 0),
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_approach',
        'roundabout_imminent',
      ]);
      expect(intents[0].vars.containsKey('exit'), isFalse);
      expect(intents[1].vars.containsKey('exit'), isFalse);
    });
  });

  group('D — 회전교차로 진출', () {
    test('emits roundabout_exit_*', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 27), step0(type: 4)];
      final intents = drive(engine, 0, [200, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_exit_approach',
        'roundabout_exit_imminent',
      ]);
    });
  });
}
