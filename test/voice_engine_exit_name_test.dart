import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // Same tier/imminent shape as voice_engine_test.dart's global profile.
  final profile = GuidanceProfile(
    imminentM: 5,
    tiers: const [
      GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
      GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
      GuidanceTier(minEntryM: 30, pointsM: [100, 50]),
      GuidanceTier(minEntryM: 0, pointsM: []),
    ],
    enabledEvents: {
      'turn_left', 'turn_right', 'uturn', 'ramp', 'exit',
      'keep', 'merge', 'roundabout', 'destination',
    },
  );

  ManeuverStep step({int type = 0, String? exitName}) =>
      ManeuverStep(type: type, instruction: '', distanceKm: 0, exitName: exitName);

  List<SpeakIntent> drive(VoiceEngine e, int stepIdx,
      List<double> dSeq, List<ManeuverStep> steps) {
    final out = <SpeakIntent>[];
    for (final d in dSeq) {
      out.addAll(e.onProgress(stepIdx, d, steps));
    }
    return out;
  }

  group('C — exit-name named-variant guidance', () {
    test('exit with exitName present → exit_approach_named + vars[exit_name]', () {
      final engine = VoiceEngine(profile);
      final steps = [step(), step(type: 20, exitName: '천호대교 북단'), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'exit_approach_named');
      expect(intents[0].vars['exit_name'], '천호대교 북단');
    });

    test('exit with exitName null → key unchanged (exit_approach)', () {
      final engine = VoiceEngine(profile);
      final steps = [step(), step(type: 20, exitName: null), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'exit_approach');
      expect(intents[0].vars.containsKey('exit_name'), isFalse);
    });

    test('ramp with exitName empty string → named not applied (ramp_approach)', () {
      final engine = VoiceEngine(profile);
      final steps = [step(), step(type: 17, exitName: ''), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'ramp_approach');
      expect(intents[0].vars.containsKey('exit_name'), isFalse);
    });
  });
}
