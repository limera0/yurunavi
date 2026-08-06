import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // Standard fallback-equivalent profile (tiers sorted descending).
  // roundabout_enter replaces the old 'roundabout' key following S4b split.
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

  group('A — 먼턴 우회전 (d=600)', () {
    test('emits 500→300→50 approach then 5 imminent', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 10), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_right_approach',
        'turn_right_approach',
        'turn_right_approach',
        'turn_right_imminent',
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
        'turn_left_imminent',
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
        'turn_left_imminent',
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
        'turn_left_imminent',
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
        'turn_left_imminent',
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
      expect(intents[0].key, 'turn_right_imminent');
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
        'keep', 'merge', 'roundabout_enter', 'destination',
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

    test('turn_left 600→500→300→50 emits approach, approach, then imminent ("곧~") at 50 (speedKmh=0)', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_left_approach',
        'turn_left_approach',
        'turn_left_imminent',
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
        'turn_left_imminent',
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
        'keep', 'merge', 'roundabout_enter', 'destination',
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
      expect(intents[0].key, 'turn_left_imminent');
      expect(intents[0].vars['dist'], '40');
    });

    test('turn_left first detected at entryD=0 (maneuver already reached) fires immediately', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = engine.onProgress(0, 0, steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_left_imminent');
      expect(intents[0].vars['dist'], '0');
    });

    test('turn_right first detected at 45m fires immediately once; no double-fire on later calls at 30 then 5', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 10), step0(type: 4)];
      final intents = drive(engine, 0, [45, 30, 5], steps);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_right_imminent');
      expect(intents[0].vars['dist'], '45');
    });

    test('normal (non-dead-zone) turn_left case at entryD=600 is unchanged', () {
      final engine = VoiceEngine(prodShapeProfile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50], steps);
      expect(intents.map((i) => i.key).toList(), [
        'turn_left_approach',
        'turn_left_approach',
        'turn_left_imminent',
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
      expect(intents[0].key, 'turn_left_imminent');
      expect(intents[0].vars['dist'], '50');
    });
  });

  group('L — 경유지 vs 최종목적지 dest_word 분기 (2026-07-15 실주행 회귀 가드)', () {
    // steps[turnIdx]=steps[1] is a segment-end maneuver (type 4/5/6) — this is
    // exactly the shape produced at the end of a sub-route to a waypoint, not
    // just the final destination.
    test('isFinalDestination default(true): dest_word=목적지', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      for (final it in intents) {
        expect(it.key.startsWith('destination_'), isTrue);
        expect(it.vars['dest_word'], '목적지');
      }
    });

    test('isFinalDestination=false (경유지 구간): dest_word=경유지', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 4)];
      final out = <SpeakIntent>[];
      for (final d in <double>[600, 500]) {
        out.addAll(engine.onProgress(0, d, steps, isFinalDestination: false));
      }
      expect(out, isNotEmpty);
      for (final it in out) {
        expect(it.key.startsWith('destination_'), isTrue);
        expect(it.vars['dest_word'], '경유지');
      }
    });
  });

  group('M — 거리 반전 감지 (동일 step, d가 30m+ 증가 시 pending 비움)', () {
    test('300에서 approach 발화 후 d가 갑자기 400으로 오르면 pending 비워져 50 approach 미발화', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      // 정상 접근: 450 → 300 approach 발화
      final phase1 = drive(engine, 0, [450, 300], steps);
      expect(phase1.map((i) => i.key).toList(), ['turn_left_approach']);
      // 반전: 300에서 d가 400으로 뜀 (30m 이상) → pending 비워짐
      final phase2 = drive(engine, 0, [400], steps);
      expect(phase2, isEmpty, reason: '반전 후 pending이 비워졌으면 이미 통과한 300이 재발화되지 않아야 한다');
      // 50 approach가 다시 안 나와야 한다 — pending이 비워졌으므로
      final phase3 = drive(engine, 0, [50], steps);
      expect(phase3, isEmpty,
          reason: 'pending이 비워졌으면 50 approach도 나오지 않아야 한다');
    });

    test('30m 미만 증가는 반전으로 간주하지 않는다', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      // 300 approach 발화
      drive(engine, 0, [450, 300], steps);
      // 29m 증가 — 반전 미해당
      drive(engine, 0, [329], steps);
      // 50 approach는 여전히 나와야 한다
      final result = drive(engine, 0, [50], steps);
      expect(result.map((i) => i.key).toList(), ['turn_left_approach'],
          reason: '29m 증가는 반전이 아니므로 50 approach가 정상 발화돼야 한다');
    });

    test('step 전환 직후 첫 틱에서 오탐 없음 (_prevD가 step 전환 시 리셋됨)', () {
      final engine = VoiceEngine(profile);
      final steps = [step0(), step0(type: 15), step0(type: 4)];
      // step=0, d=100으로 시작 (150-30 구간)
      final phase1 = drive(engine, 0, [100, 50, 5], steps);
      expect(phase1.length, greaterThanOrEqualTo(1));
      // step=1 전환 (새 step), d=600 — 이때 _prevD가 600으로 리셋되므로
      // 다음 틱 d=500이 600보다 작아도 반전 오탐이 없어야 한다
      final steps2 = [step0(), step0(), step0(type: 15), step0(type: 4)];
      final engine2 = VoiceEngine(profile);
      // step=0 먼저 소진
      drive(engine2, 0, [100, 50, 5], steps2);
      // step=1으로 전환, d=600 (_prevD를 600으로 리셋하는 효과만 확인)
      engine2.onProgress(1, 600, steps2);
      // step=1, d=500 (정상 감소) — 반전 아님
      final phase3 = engine2.onProgress(1, 500, steps2);
      expect(phase3, isNotEmpty,
          reason: 'step 전환 후 d 감소는 정상 주행이므로 반전으로 오인하면 안 된다');
    });
  });
}
