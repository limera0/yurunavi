import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // Standard fallback-equivalent profile (tiers sorted descending), extended
  // with the two new sharp-curve events so isEnabled()/tiersForEvent() fall
  // back to the same common tiers as turn_left/turn_right.
  final profile = GuidanceProfile(
    imminentM: 5,
    tiers: const [
      GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
      GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
      GuidanceTier(minEntryM: 30,  pointsM: [100, 50]),
      GuidanceTier(minEntryM: 0,   pointsM: []),
    ],
    enabledEvents: {
      'turn_left', 'turn_right', 'sharp_turn_left', 'sharp_turn_right',
      'uturn', 'ramp', 'exit', 'keep', 'merge', 'roundabout', 'destination',
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

  group('A — 급우회전 (type 11)', () {
    test('event resolves to sharp_turn_right, imminent key is sharp_turn_right_imminent', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 11), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'sharp_turn_right_approach',
        'sharp_turn_right_approach',
        'sharp_turn_right_approach',
        'sharp_turn_right_imminent',
      ]);
      expect(intents.last.key, isNot('turn_right_imminent'));
    });
  });

  group('B — 급좌회전 (type 14)', () {
    test('event resolves to sharp_turn_left, imminent key is sharp_turn_left_imminent', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 14), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'sharp_turn_left_approach',
        'sharp_turn_left_approach',
        'sharp_turn_left_approach',
        'sharp_turn_left_imminent',
      ]);
      expect(intents.last.key, isNot('turn_left_imminent'));
    });
  });

  group('C — 회귀 가드: 완만한 우회전 (type 9/10)', () {
    test('type 9 (slight right) still emits plain turn_right_*', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 9), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('turn_right_'));
      }
      expect(intents.last.key, 'turn_right_imminent');
    });

    test('type 10 (right) still emits plain turn_right_*', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 10), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('turn_right_'));
      }
      expect(intents.last.key, 'turn_right_imminent');
    });
  });

  group('D — 회귀 가드: 완만한 좌회전 (type 15/16)', () {
    test('type 15 (left) still emits plain turn_left_*', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('turn_left_'));
      }
      expect(intents.last.key, 'turn_left_imminent');
    });

    test('type 16 (slight left) still emits plain turn_left_*', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 16), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('turn_left_'));
      }
      expect(intents.last.key, 'turn_left_imminent');
    });
  });

  group('E — 급커브는 _fast 축약 대상 제외', () {
    // Profile matching production values after C1 (imminentM=10).
    // Entry distance 15m → falls into minEntryM=0 tier (pointsM=[]) → only
    // imminentM=10 pending — mirrors voice_engine_speed_test.dart's fixture.
    final speedProfile = GuidanceProfile(
      imminentM: 10,
      tiers: const [
        GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
        GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
        GuidanceTier(minEntryM: 30, pointsM: [100, 50]),
        GuidanceTier(minEntryM: 0, pointsM: []),
      ],
      enabledEvents: {
        'turn_left', 'turn_right', 'sharp_turn_left', 'sharp_turn_right',
        'uturn', 'ramp', 'exit', 'keep', 'merge', 'roundabout', 'destination',
      },
    );

    test('speedKmh=30 on type-11 (sharp_turn_right) imminent does NOT append _fast', () {
      final engine = VoiceEngine(speedProfile);
      final steps = [step0(), step0(type: 11), step0(type: 4)];
      final out = <SpeakIntent>[];
      out.addAll(engine.onProgress(0, 15, steps, speedKmh: 30));
      out.addAll(engine.onProgress(0, 10, steps, speedKmh: 30));
      expect(out.length, 1);
      expect(out[0].key, 'sharp_turn_right_imminent');
      expect(out[0].key, isNot(contains('_fast')));
    });
  });
}
