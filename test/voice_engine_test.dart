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

  group('A — 먼턴 우회전 (d=600)', () {
    test('emits 500→300→50 approach then 5 imminent', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 10), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_right_approach',
        'turn_right_approach',
        'turn_right_approach',
        'turn_right_imminent_fast',
      ]);
      expect(intents.map((i) => i.vars['dist']).toList(), ['500', '300', '50', '5']);
    });
  });

  group('B — 중턴-상 좌회전 (d=450)', () {
    test('emits 300→50 approach then imminent', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [450, 300, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_left_approach',
        'turn_left_approach',
        'turn_left_imminent_fast',
      ]);
      expect(intents.map((i) => i.vars['dist']).toList(), ['300', '50', '5']);
    });
  });

  group('C — 중턴-하 좌회전 (d=200, 300 스킵)', () {
    test('300 is skipped; emits 50 approach then imminent', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [200, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_left_approach',
        'turn_left_imminent_fast',
      ]);
      expect(intents.map((i) => i.vars['dist']).toList(), ['50', '5']);
    });
  });

  group('D — 근턴 좌회전 (d=120)', () {
    test('emits 100→50 approach then imminent', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [120, 100, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_left_approach',
        'turn_left_approach',
        'turn_left_imminent_fast',
      ]);
      expect(intents.map((i) => i.vars['dist']).toList(), ['100', '50', '5']);
    });
  });

  group('E — 근턴-진입내 좌회전 (d=80, 100 스킵)', () {
    test('100 is skipped; emits 50 approach then imminent', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [80, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_left_approach',
        'turn_left_imminent_fast',
      ]);
      expect(intents.map((i) => i.vars['dist']).toList(), ['50', '5']);
    });
  });

  group('F — 초근접 우회전 (d=25)', () {
    test('only imminent emitted (close-turn gap closed)', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 10), step0(type: 4)];
      final intents = drive(engine, 0, [25, 5], steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_right_imminent_fast');
      expect(intents[0].vars['dist'], '5');
    });
  });

  group('G — 방향정확 (step+1=우, step현재=좌)', () {
    test('event is turn_right (step+1), not turn_left (step)', () {
      final engine = VoiceEngine(profile);
      // steps[0].type=15(left), steps[1].type=10(right)
      final steps = [step0(type: 15), step0(type: 10), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_right_approach');
    });
  });

  group('H — type=0 (kNone)', () {
    test('no intent emitted', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 0), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300], steps);
      expect(intents, isEmpty);
    });
  });

  group('I — 도착 (turnIdx >= len)', () {
    test('returns empty without crash', () {
      final engine = VoiceEngine(profile);
      // Only 1 step → step+1 = 1 >= length 1
      final steps = [step0(type: 4)];
      expect(() => engine.onProgress(0, 100, steps), returnsNormally);
      expect(engine.onProgress(0, 100, steps), isEmpty);
    });
  });

  group('J — 실서비스 프로필 shape (eventImminentM/eventTiers, turn_left/turn_right imminent_m=50)', () {
    // Mirrors the production assets/config/guidance_profile.json shape after
    // the 50m-only-fast-cue change: turn_left/turn_right get their own
    // imminent_m=50 and tiers without a trailing 50 (imminent point is
    // supplied automatically), while the old 10m imminent point is gone.
    final prodShapeProfile = GuidanceProfile(
      imminentM: 10,
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
      eventTiers: {
        'turn_left': const [
          GuidanceTier(minEntryM: 500, pointsM: [500, 300]),
          GuidanceTier(minEntryM: 150, pointsM: [300]),
          GuidanceTier(minEntryM: 30, pointsM: [100]),
          GuidanceTier(minEntryM: 0, pointsM: []),
        ],
        'turn_right': const [
          GuidanceTier(minEntryM: 500, pointsM: [500, 300]),
          GuidanceTier(minEntryM: 150, pointsM: [300]),
          GuidanceTier(minEntryM: 30, pointsM: [100]),
          GuidanceTier(minEntryM: 0, pointsM: []),
        ],
      },
      eventImminentM: {'turn_left': 50, 'turn_right': 50},
    );

    test('turn_left 600→500→300→50 emits approach, approach, then unconditional _fast at 50 (speedKmh=0)', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_left_approach',
        'turn_left_approach',
        'turn_left_imminent_fast',
      ]);
      expect(intents.map((i) => i.vars['dist']).toList(), ['500', '300', '50']);
    });

    test('turn_left continuing past 50 down to 10m emits nothing further (old 10m imminent point is gone)', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50, 10], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_left_approach',
        'turn_left_approach',
        'turn_left_imminent_fast',
      ]);
    });
  });

  group('K — dead-zone safety net (imminent_m=50 turn first seen already inside 50m)', () {
    // Same production-shaped profile as group J: turn_left/turn_right have
    // their own imminent_m=50 and tiers without a trailing 50.
    final prodShapeProfile = GuidanceProfile(
      imminentM: 10,
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
      eventTiers: {
        'turn_left': const [
          GuidanceTier(minEntryM: 500, pointsM: [500, 300]),
          GuidanceTier(minEntryM: 150, pointsM: [300]),
          GuidanceTier(minEntryM: 30, pointsM: [100]),
          GuidanceTier(minEntryM: 0, pointsM: []),
        ],
        'turn_right': const [
          GuidanceTier(minEntryM: 500, pointsM: [500, 300]),
          GuidanceTier(minEntryM: 150, pointsM: [300]),
          GuidanceTier(minEntryM: 30, pointsM: [100]),
          GuidanceTier(minEntryM: 0, pointsM: []),
        ],
      },
      eventImminentM: {'turn_left': 50, 'turn_right': 50},
    );

    test('turn_left first detected at 40m (inside 30-150 tier, points [100] all filtered) fires immediately', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = engine.onProgress(0, 40, steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_left_imminent_fast');
      expect(intents[0].vars['dist'], '40');
    });

    test('turn_left first detected at entryD=0 (maneuver already reached) fires immediately', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = engine.onProgress(0, 0, steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_left_imminent_fast');
      expect(intents[0].vars['dist'], '0');
    });

    test('turn_right first detected at 45m fires immediately once; no double-fire on later calls at 30 then 5', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 10), step0(type: 4)];
      final intents = drive(engine, 0, [45, 30, 5], steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_right_imminent_fast');
      expect(intents[0].vars['dist'], '45');
    });

    test('normal (non-dead-zone) turn_left case at entryD=600 is unchanged', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_left_approach',
        'turn_left_approach',
        'turn_left_imminent_fast',
      ]);
      expect(intents.map((i) => i.vars['dist']).toList(), ['500', '300', '50']);
    });

    test('dedupe: tier point coinciding with imminentM fires only ONE intent, not two', () {
      final dedupeProfile = GuidanceProfile(
        imminentM: 50,
        tiers: const [
          GuidanceTier(minEntryM: 0, pointsM: [50]),
        ],
        enabledEvents: {'turn_left'},
      );
      final engine = VoiceEngine(dedupeProfile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [60, 50], steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_left_imminent_fast');
      expect(intents[0].vars['dist'], '50');
    });
  });
}
