import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // Standard fallback-equivalent profile (tiers sorted descending), extended
  // with the 'continue' event so isEnabled()/tiersForEvent() fall back to
  // the same common tiers as turn_left/turn_right.
  final profile = GuidanceProfile(
    imminentM: 5,
    tiers: const [
      GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
      GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
      GuidanceTier(minEntryM: 30,  pointsM: [100, 50]),
      GuidanceTier(minEntryM: 0,   pointsM: []),
    ],
    enabledEvents: {
      'turn_left', 'turn_right', 'uturn', 'ramp', 'exit', 'keep',
      'keep_left', 'keep_right', 'merge',
      'roundabout_enter', 'destination', 'continue',
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

  group('A — 직진 (type 8), continue.enabled=true', () {
    test('event resolves to continue, imminent key is continue_imminent', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 8), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'continue_approach',
        'continue_approach',
        'continue_approach',
        'continue_imminent',
      ]);
    });
  });

  group('B — 프로필 게이트: continue.enabled=false', () {
    test('type 8 resolves to event but emits no SpeakIntent when disabled', () {
      final disabledProfile = GuidanceProfile(
        imminentM: 5,
        tiers: const [
          GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
          GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
          GuidanceTier(minEntryM: 30,  pointsM: [100, 50]),
          GuidanceTier(minEntryM: 0,   pointsM: []),
        ],
        enabledEvents: {
          'turn_left', 'turn_right', 'uturn', 'ramp', 'exit', 'keep',
          'keep_left', 'keep_right',
          'merge', 'roundabout_enter', 'destination',
        },
      );
      final engine = VoiceEngine(disabledProfile);
      final steps = [step0(), step0(type: 8), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], steps);
      expect(intents, isEmpty);
    });
  });

  group('C — 회귀 가드: 일반 회전 (type 9/10/15/16) 영향 없음', () {
    test('type 9 (slight right) still resolves to turn_right_* (not continue_*)', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 9), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('turn_right_'));
      }
      expect(intents.last.key, 'turn_right_imminent');
    });

    test('type 10 (right) still resolves to turn_right_* (not continue_*)', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 10), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('turn_right_'));
      }
      expect(intents.last.key, 'turn_right_imminent');
    });

    test('type 15 (left) still resolves to turn_left_* (not continue_*)', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('turn_left_'));
      }
      expect(intents.last.key, 'turn_left_imminent');
    });

    test('type 16 (slight left) still resolves to turn_left_* (not continue_*)', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 16), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('turn_left_'));
      }
      expect(intents.last.key, 'turn_left_imminent');
    });
  });

  group('D — 회귀 가드: keep (type 22/23/24) continue와 구분', () {
    test('type 22 (keep straight) still emits plain keep_*, not continue_*', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 22), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('keep_'));
      }
      expect(intents.last.key, 'keep_imminent');
    });

    test('type 23 (keep right — kStayRight) still emits plain keep_*, not continue_*', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 23), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('keep_right_'));
      }
      expect(intents.last.key, 'keep_right_imminent');
    });

    test('type 24 (keep left — kStayLeft) still emits plain keep_*, not continue_*', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 24), step0(type: 4)];
      final intents = drive(engine, 0, [600, 5], steps);
      for (final i in intents) {
        expect(i.key, startsWith('keep_left_'));
      }
      expect(intents.last.key, 'keep_left_imminent');
    });
  });
}
