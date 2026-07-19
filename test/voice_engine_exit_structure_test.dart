import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/exit_landmark_service.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
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

  final withLandmark = ExitLandmarkService(const [
    ExitLandmarkPlace(name: '읍내리', classPriority: 1, lat: 37.5005, lon: 127.0),
  ]);

  ManeuverStep step({int type = 0, String? exitName, int beginShapeIdx = 0}) =>
      ManeuverStep(
        type: type,
        instruction: '',
        distanceKm: 0,
        exitName: exitName,
        beginShapeIdx: beginShapeIdx,
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

  group('E — exit 구조물(다리/터널) 인접 안내', () {
    test('right exit(type 20) + tunnel 인접 → exit_right structure 키, 터널', () {
      final engine = VoiceEngine(profile,
          exitStructureByManeuverIdx: {1: StructureType.tunnel});
      final steps = [step(), step(type: 20, beginShapeIdx: 0), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);

      expect(intents.length, 1);
      expect(intents[0].key, 'exit_right_approach_structure');
      expect(intents[0].vars['structure'], '터널');
    });

    test('left exit(type 21) + bridge 인접 → exit_left structure 키, 다리', () {
      final engine = VoiceEngine(profile,
          exitStructureByManeuverIdx: {1: StructureType.bridge});
      final steps = [step(), step(type: 21, beginShapeIdx: 0), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);

      expect(intents[0].key, 'exit_left_approach_structure');
      expect(intents[0].vars['structure'], '다리');
    });

    test('left exit(type 21) + overpass 인접 → exit_left structure 키, 고가도로', () {
      final engine = VoiceEngine(profile,
          exitStructureByManeuverIdx: {1: StructureType.overpass});
      final steps = [step(), step(type: 21, beginShapeIdx: 0), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);

      expect(intents[0].key, 'exit_left_approach_structure');
      expect(intents[0].vars['structure'], '고가도로');
    });

    test('right exit(type 20) + underpass 인접 → exit_right structure 키, 지하차도', () {
      final engine = VoiceEngine(profile,
          exitStructureByManeuverIdx: {1: StructureType.underpass});
      final steps = [step(), step(type: 20, beginShapeIdx: 0), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);

      expect(intents[0].key, 'exit_right_approach_structure');
      expect(intents[0].vars['structure'], '지하차도');
    });

    test('exitName이 있으면 structure보다 named가 우선한다', () {
      final engine = VoiceEngine(profile,
          exitStructureByManeuverIdx: {1: StructureType.tunnel});
      final steps = [
        step(),
        step(type: 20, exitName: '천호대교 북단', beginShapeIdx: 0),
        step(type: 4),
      ];
      final intents = drive(engine, 0, [600, 500], steps);

      expect(intents[0].key, 'exit_right_approach_named');
      expect(intents[0].vars['exit_name'], '천호대교 북단');
      expect(intents[0].vars.containsKey('structure'), isFalse);
    });

    test('structure가 있으면 landmark 폴백보다 structure가 우선한다', () {
      final engine = VoiceEngine(profile,
          landmarkService: withLandmark,
          exitStructureByManeuverIdx: {1: StructureType.tunnel});
      final steps = [step(), step(type: 20, beginShapeIdx: 0), step(type: 4)];
      final pts = [const LatLng(37.5, 127.0)];
      final intents = drive(engine, 0, [600, 500], steps, shapePoints: pts);

      expect(intents[0].key, 'exit_right_approach_structure');
      expect(intents[0].vars.containsKey('landmark'), isFalse);
    });

    test('구조물 매핑에 이 maneuver 인덱스가 없으면 기존 동작(landmark/plain) 유지', () {
      final engine = VoiceEngine(profile,
          exitStructureByManeuverIdx: {5: StructureType.tunnel});
      final steps = [step(), step(type: 20, beginShapeIdx: 0), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);

      expect(intents[0].key, 'exit_right_approach');
      expect(intents[0].vars.containsKey('structure'), isFalse);
    });

    test('exitStructureByManeuverIdx가 null(기본값)이어도 크래시 없이 기존 동작 유지', () {
      final engine = VoiceEngine(profile);
      final steps = [step(), step(type: 20, beginShapeIdx: 0), step(type: 4)];
      late List<SpeakIntent> intents;
      expect(() {
        intents = drive(engine, 0, [600, 500], steps);
      }, returnsNormally);
      expect(intents[0].key, 'exit_right_approach');
    });

    test('ramp 이벤트는 structure 폴백을 쓰지 않는다(exit 전용)', () {
      final engine = VoiceEngine(profile,
          exitStructureByManeuverIdx: {1: StructureType.tunnel});
      final steps = [step(), step(type: 17, beginShapeIdx: 0), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);

      expect(intents[0].key, 'ramp_straight_approach');
      expect(intents[0].vars.containsKey('structure'), isFalse);
    });

    test('imminent phase에서도 structure 키가 선택된다', () {
      final engine = VoiceEngine(profile,
          exitStructureByManeuverIdx: {1: StructureType.tunnel});
      final steps = [step(), step(type: 20, beginShapeIdx: 0), step(type: 4)];
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], steps);

      final imminent =
          intents.firstWhere((i) => i.key == 'exit_right_imminent_structure');
      expect(imminent.vars['structure'], '터널');
    });
  });
}
