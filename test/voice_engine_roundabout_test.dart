import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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

  ManeuverStep step0({int type = 0, int beginShapeIdx = 0, int endShapeIdx = 0}) =>
      ManeuverStep(
        type: type,
        instruction: '',
        distanceKm: 0,
        beginShapeIdx: beginShapeIdx,
        endShapeIdx: endShapeIdx,
      );

  List<SpeakIntent> drive(
    VoiceEngine e,
    int stepIdx,
    List<double> dSeq,
    List<ManeuverStep> steps, {
    List<LatLng> shapePoints = const [],
  }) {
    final out = <SpeakIntent>[];
    for (final d in dSeq) {
      out.addAll(e.onProgress(stepIdx, d, steps, shapePoints: shapePoints));
    }
    return out;
  }

  // 정확히 정방위(N/E/S/W)로 뻗은 4점 합성 shape — entry/exit 구간을
  // 조합해 좌/직/우 각각의 signed turn을 만든다.
  // idx: 0(entry approach) → 1(entry point, begin) →
  //      2(exit approach, exit maneuver의 begin) → 3(exit point, end)
  const north = LatLng(37.0010, 127.0000); // idx1: (idx0→idx1) bearing ≈ 0
  const farNorth = LatLng(37.0020, 127.0000); // (idx2→idx3) bearing ≈ 0 (계속 직진)
  const east = LatLng(37.0010, 127.0012); // (idx2→idx3) bearing ≈ 90 (idx2=idx1 위치 기준)
  const west = LatLng(37.0010, 126.9988); // (idx2→idx3) bearing ≈ 270

  List<LatLng> shapeFor({required LatLng entryEnd, required LatLng exitEnd}) => [
        const LatLng(37.0000, 127.0000), // idx0: entry approach origin
        entryEnd, // idx1: entry point (steps[turnIdx].beginShapeIdx)
        entryEnd, // idx2: exit maneuver begin (== entry point, 로터리 안 통과)
        exitEnd, // idx3: exit point (steps[turnIdx+1].endShapeIdx)
      ];

  group('A — eventForType 회전교차로', () {
    test('type=26 returns roundabout_enter', () {
      expect(eventForType(26), 'roundabout_enter');
    });

    test('type=27 returns roundabout_exit', () {
      expect(eventForType(27), 'roundabout_exit');
    });
  });

  group('B — 회전교차로 진입: 진입/진출 shape 방위각으로 방향 계산', () {
    test('북→서(좌회전 형상) → direction=좌측, exit var 없음', () {
      final engine = VoiceEngine(profile);
      final shapePoints = shapeFor(entryEnd: north, exitEnd: west);
      final steps = [
        step0(),
        ManeuverStep(
            type: 26, instruction: '', distanceKm: 0,
            beginShapeIdx: 1, endShapeIdx: 1),
        ManeuverStep(
            type: 27, instruction: '', distanceKm: 0,
            beginShapeIdx: 2, endShapeIdx: 3),
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps, shapePoints: shapePoints);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_enter_approach',
        'roundabout_enter_imminent',
      ]);
      expect(intents[0].vars['direction'], '좌측');
      expect(intents[1].vars['direction'], '좌측');
      expect(intents[0].vars.containsKey('exit'), isFalse);
      expect(intents[1].vars.containsKey('exit'), isFalse);
    });

    test('북→동(우회전 형상) → direction=우측', () {
      final engine = VoiceEngine(profile);
      final shapePoints = shapeFor(entryEnd: north, exitEnd: east);
      final steps = [
        step0(),
        ManeuverStep(
            type: 26, instruction: '', distanceKm: 0,
            beginShapeIdx: 1, endShapeIdx: 1),
        ManeuverStep(
            type: 27, instruction: '', distanceKm: 0,
            beginShapeIdx: 2, endShapeIdx: 3),
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps, shapePoints: shapePoints);
      expect(intents[0].vars['direction'], '우측');
      expect(intents[1].vars['direction'], '우측');
    });

    test('북→북(진입/진출 방위각 동일, 직진 형상) → direction=직진', () {
      final engine = VoiceEngine(profile);
      // idx0→idx1(entry)과 idx2→idx3(exit)가 둘 다 north 방향이면 signed
      // diff = 0 → straight.
      final shapePoints = shapeFor(entryEnd: north, exitEnd: farNorth);
      final steps = [
        step0(),
        ManeuverStep(
            type: 26, instruction: '', distanceKm: 0,
            beginShapeIdx: 1, endShapeIdx: 1),
        ManeuverStep(
            type: 27, instruction: '', distanceKm: 0,
            beginShapeIdx: 2, endShapeIdx: 3),
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps, shapePoints: shapePoints);
      expect(intents[0].vars['direction'], '직진');
      expect(intents[1].vars['direction'], '직진');
    });
  });

  group('C — 회전교차로 진입: 폴백 (짝 maneuver 없음/경계 밖) → 방향 없는 일반 문구', () {
    test(r'shapePoints가 비어있으면 roundabout_$phase로 폴백', () {
      final engine = VoiceEngine(profile);
      final steps = [
        step0(),
        ManeuverStep(
            type: 26, instruction: '', distanceKm: 0,
            beginShapeIdx: 1, endShapeIdx: 1),
        ManeuverStep(
            type: 27, instruction: '', distanceKm: 0,
            beginShapeIdx: 2, endShapeIdx: 3),
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps); // shapePoints 기본값(빈 리스트)
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_approach',
        'roundabout_imminent',
      ]);
      expect(intents[0].vars.containsKey('direction'), isFalse);
      expect(intents[0].vars.containsKey('exit'), isFalse);
    });

    test('다음 스텝이 roundabout_exit(type 27)이 아니면 폴백', () {
      final engine = VoiceEngine(profile);
      final shapePoints = shapeFor(entryEnd: north, exitEnd: west);
      final steps = [
        step0(),
        ManeuverStep(
            type: 26, instruction: '', distanceKm: 0,
            beginShapeIdx: 1, endShapeIdx: 1),
        step0(type: 9), // 다음 스텝이 로터리 진출이 아님 (평범한 우회전)
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps, shapePoints: shapePoints);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_approach',
        'roundabout_imminent',
      ]);
      expect(intents[0].vars.containsKey('direction'), isFalse);
    });

    test('beginShapeIdx가 0(직전 인덱스 없음)이면 폴백', () {
      final engine = VoiceEngine(profile);
      final shapePoints = shapeFor(entryEnd: north, exitEnd: west);
      final steps = [
        step0(),
        ManeuverStep(
            type: 26, instruction: '', distanceKm: 0,
            beginShapeIdx: 0, endShapeIdx: 0), // beginIdx-1 = -1, out of bounds
        ManeuverStep(
            type: 27, instruction: '', distanceKm: 0,
            beginShapeIdx: 2, endShapeIdx: 3),
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps, shapePoints: shapePoints);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_approach',
        'roundabout_imminent',
      ]);
      expect(intents[0].vars.containsKey('direction'), isFalse);
    });

    test('endShapeIdx가 shapePoints 범위를 벗어나면 폴백', () {
      final engine = VoiceEngine(profile);
      final shapePoints = shapeFor(entryEnd: north, exitEnd: west); // length 4 (idx 0..3)
      final steps = [
        step0(),
        ManeuverStep(
            type: 26, instruction: '', distanceKm: 0,
            beginShapeIdx: 1, endShapeIdx: 1),
        ManeuverStep(
            type: 27, instruction: '', distanceKm: 0,
            beginShapeIdx: 2, endShapeIdx: 99), // out of bounds
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps, shapePoints: shapePoints);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_approach',
        'roundabout_imminent',
      ]);
      expect(intents[0].vars.containsKey('direction'), isFalse);
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

  group('E — {exit} 주입 경로 완전 폐기 회귀 가드', () {
    // roundaboutExitCount가 설정돼 있어도 더 이상 어떤 vars에도 반영되지
    // 않아야 한다 (S6 목표: 출구 번호 발화 완전 폐기).
    test('roundaboutExitCount가 있어도 vars에 exit 키가 생기지 않는다', () {
      final engine = VoiceEngine(profile);
      final shapePoints = shapeFor(entryEnd: north, exitEnd: west);
      final steps = [
        step0(),
        ManeuverStep(
            type: 26, instruction: '', distanceKm: 0,
            beginShapeIdx: 1, endShapeIdx: 1, roundaboutExitCount: 3),
        ManeuverStep(
            type: 27, instruction: '', distanceKm: 0,
            beginShapeIdx: 2, endShapeIdx: 3),
        step0(type: 4),
      ];
      final intents = drive(engine, 0, [200, 50, 5], steps, shapePoints: shapePoints);
      for (final i in intents) {
        expect(i.vars.containsKey('exit'), isFalse);
      }
      expect(intents[0].vars['direction'], '좌측');
    });
  });

  group('F — roundabout_exit enabled 프로필: 방향/출구번호 없는 일반 문구만 나온다', () {
    // roundabout_exit 이벤트 자체는 S4b로 guidance_profile.json에서
    // 비활성화되어 있지만(프로덕션 경로 불가), VoiceEngine 코드 자체에
    // 방향/출구 로직이 남아있지 않은지 별도 프로필로 직접 확인한다
    // (S6 이전엔 roundabout_exit_imminent_named + {exit}를 냈던 경로 —
    // 이번에 그 블록을 통째로 삭제했으므로 이제 일반 문구만 나와야 한다).
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

    test('roundabout_exit approach+imminent 나온다 (exit var/named variant 없음)', () {
      final engine = VoiceEngine(profileWithExit);
      final steps = [step0(), step0(type: 27), step0(type: 4)];
      final intents = drive(engine, 0, [200, 50, 5], steps);
      expect(intents.map((i) => i.key).toList(), [
        'roundabout_exit_approach',
        'roundabout_exit_imminent',
      ]);
      expect(intents[1].vars.containsKey('exit'), isFalse);
    });

    test('직전 enter step에 roundaboutExitCount가 있어도 더 이상 이어받지 않는다', () {
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
        'roundabout_exit_imminent',
      ]);
      expect(intents[0].vars.containsKey('exit'), isFalse);
      expect(intents[1].vars.containsKey('exit'), isFalse);
    });
  });
}
