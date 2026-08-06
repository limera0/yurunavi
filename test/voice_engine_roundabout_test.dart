import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // roundabout_enter: enabled, roundabout_exit: NOT in set (disabled).
  // This mirrors the production guidance_profile.json after the S4b split.
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
      'keep', 'merge', 'roundabout_enter', 'destination',
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

  group('D — 회전교차로 진출 (roundabout_exit disabled → 0건)', () {
    test('roundabout_exit는 enabled가 아니므로 intents를 내지 않는다', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 27), step0(type: 4)];
      final intents = drive(engine, 0, [200, 50, 5], steps);
      expect(intents, isEmpty,
          reason: 'roundabout_exit는 프로필에서 비활성화되어 있어야 한다');
    });
  });

  group('E — 회전교차로 진출 (출구번호 있어도 disabled → 0건)', () {
    test('roundabout_exit_imminent_named도 내지 않는다', () {
      final engine = VoiceEngine(profile);
      final steps = [
        step0(),
        ManeuverStep(type: 26, instruction: '', distanceKm: 0, roundaboutExitCount: 3),
        step0(type: 27),
        step0(type: 4),
      ];
      // stepIdx=1: turnIdx=2 (exit maneuver)
      final intents = drive(engine, 1, [200, 50, 5], steps);
      expect(intents, isEmpty,
          reason: 'roundabout_exit는 disabled이므로 출구번호 있어도 silent');
    });
  });

  group('F — roundabout_exit enabled 프로필에서는 intents가 나온다 (회귀 가드)', () {
    // roundabout_exit가 활성화된 별도 프로필로 검증
    final profileWithExit = GuidanceProfile(
      imminentM: 5,
      tiers: const [
        GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
        GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
        GuidanceTier(minEntryM: 30,  pointsM: [100, 50]),
        GuidanceTier(minEntryM: 0,   pointsM: []),
      ],
      enabledEvents: {
        'turn_left', 'turn_right', 'uturn', 'ramp', 'exit',
        'keep', 'merge', 'roundabout_enter', 'roundabout_exit', 'destination',
      },
    );

    test('roundabout_exit approach+imminent 나온다 (출구번호 없는 경우)', () {
      final engine = VoiceEngine(profileWithExit);
      final steps = [step0(), step0(type: 27), step0(type: 4)];
      final intents = drive(engine, 0, [200, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_exit_approach',
        'roundabout_exit_imminent',
      ]);
      expect(intents[1].vars.containsKey('exit'), isFalse);
    });

    test('직전 enter step에 출구번호 있으면 imminent에 roundabout_exit_imminent_named + exit var', () {
      final engine = VoiceEngine(profileWithExit);
      final steps = [
        step0(),
        ManeuverStep(type: 26, instruction: '', distanceKm: 0, roundaboutExitCount: 3),
        step0(type: 27),
        step0(type: 4),
      ];
      final intents = drive(engine, 1, [200, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_exit_approach',
        'roundabout_exit_imminent_named',
      ]);
      expect(intents[0].vars.containsKey('exit'), isFalse);
      expect(intents[1].vars['exit'], '3');
    });
  });
}
