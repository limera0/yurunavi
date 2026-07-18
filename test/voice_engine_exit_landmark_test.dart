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
  final empty = ExitLandmarkService(const []);

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

  group('D — exit landmark fallback guidance', () {
    test('right exit (type 20), no exitName, landmark within radius → exit_right landmark key', () {
      final engine = VoiceEngine(profile, landmarkService: withLandmark);
      final steps = [step(), step(type: 20, beginShapeIdx: 0), step(type: 4)];
      final pts = [const LatLng(37.5, 127.0)];
      final intents = drive(engine, 0, [600, 500], steps, shapePoints: pts);
      expect(intents.length, 1);
      expect(intents[0].key, 'exit_right_approach_landmark');
      expect(intents[0].vars['landmark'], '읍내리');
    });

    test('left exit (type 21) → exit_left landmark key', () {
      final engine = VoiceEngine(profile, landmarkService: withLandmark);
      final steps = [step(), step(type: 21, beginShapeIdx: 0), step(type: 4)];
      final pts = [const LatLng(37.5, 127.0)];
      final intents = drive(engine, 0, [600, 500], steps, shapePoints: pts);
      expect(intents[0].key, 'exit_left_approach_landmark');
      expect(intents[0].vars['landmark'], '읍내리');
    });

    test('exitName present takes precedence over landmark', () {
      final engine = VoiceEngine(profile, landmarkService: withLandmark);
      final steps = [
        step(),
        step(type: 20, exitName: '천호대교 북단', beginShapeIdx: 0),
        step(type: 4),
      ];
      final pts = [const LatLng(37.5, 127.0)];
      final intents = drive(engine, 0, [600, 500], steps, shapePoints: pts);
      expect(intents[0].key, 'exit_right_approach_named');
      expect(intents[0].vars['exit_name'], '천호대교 북단');
      expect(intents[0].vars.containsKey('landmark'), isFalse);
    });

    test('no landmark within radius → falls back to plain exit_right template', () {
      final engine = VoiceEngine(profile, landmarkService: empty);
      final steps = [step(), step(type: 20, beginShapeIdx: 0), step(type: 4)];
      final pts = [const LatLng(37.5, 127.0)];
      final intents = drive(engine, 0, [600, 500], steps, shapePoints: pts);
      expect(intents[0].key, 'exit_right_approach');
      expect(intents[0].vars.containsKey('landmark'), isFalse);
    });

    test('landmarkService null → falls back to plain exit_right template, no crash', () {
      final engine = VoiceEngine(profile);
      final steps = [step(), step(type: 20, beginShapeIdx: 0), step(type: 4)];
      final pts = [const LatLng(37.5, 127.0)];
      late List<SpeakIntent> intents;
      expect(() {
        intents = drive(engine, 0, [600, 500], steps, shapePoints: pts);
      }, returnsNormally);
      expect(intents[0].key, 'exit_right_approach');
    });

    test('beginShapeIdx out of range → falls back to plain exit_right template', () {
      final engine = VoiceEngine(profile, landmarkService: withLandmark);
      final steps = [step(), step(type: 20, beginShapeIdx: 99), step(type: 4)];
      final pts = [const LatLng(37.5, 127.0)];
      final intents = drive(engine, 0, [600, 500], steps, shapePoints: pts);
      expect(intents[0].key, 'exit_right_approach');
    });

    test('ramp event does not use landmark fallback (scoped to exit only)', () {
      final engine = VoiceEngine(profile, landmarkService: withLandmark);
      final steps = [step(), step(type: 17, beginShapeIdx: 0), step(type: 4)];
      final pts = [const LatLng(37.5, 127.0)];
      final intents = drive(engine, 0, [600, 500], steps, shapePoints: pts);
      expect(intents[0].key, 'ramp_straight_approach');
      expect(intents[0].vars.containsKey('landmark'), isFalse);
    });
  });
}
