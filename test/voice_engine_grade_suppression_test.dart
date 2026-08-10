import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // S10 — 등급 기반 회전/갈림길 음성 억제.
  final profile = GuidanceProfile(
    imminentM: 5,
    tiers: const [
      GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
      GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
      GuidanceTier(minEntryM: 30, pointsM: [100, 50]),
      GuidanceTier(minEntryM: 0, pointsM: []),
    ],
    enabledEvents: {
      'turn_left', 'turn_right', 'sharp_turn_left', 'sharp_turn_right',
      'keep', 'keep_left', 'keep_right', 'uturn', 'ramp', 'exit', 'merge',
      'roundabout_enter', 'destination',
    },
  );

  ManeuverStep step({int type = 0, int beginShapeIdx = 0}) => ManeuverStep(
        type: type,
        instruction: '',
        distanceKm: 0,
        beginShapeIdx: beginShapeIdx,
      );

  List<SpeakIntent> drive(
    VoiceEngine e,
    int stepIdx,
    List<double> dSeq,
    List<ManeuverStep> steps,
  ) {
    final out = <SpeakIntent>[];
    for (final d in dSeq) {
      out.addAll(e.onProgress(stepIdx, d, steps));
    }
    return out;
  }

  // 억제 대상 이벤트를 만드는 Valhalla type 매핑(voice_engine.eventForType 참조).
  const suppressibleTypes = {
    'turn_left': 15,
    'turn_right': 10,
    'sharp_turn_left': 14,
    'sharp_turn_right': 11,
    'keep': 22,
    'keep_left': 24,
    'keep_right': 23,
  };

  group('A — 억제 대상 이벤트, 등급 유지/상승 시 음성 억제', () {
    for (final entry in suppressibleTypes.entries) {
      test('${entry.key}(type ${entry.value}) + 등급 유지(primary→primary) → 빈 리스트', () {
        final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
          1: (entry: 'primary', exit: 'primary'),
        });
        final steps = [step(), step(type: entry.value), step(type: 4)];
        final intents = drive(engine, 0, [600, 500, 300, 50, 5], steps);
        expect(intents, isEmpty, reason: '${entry.key} 등급 유지는 억제돼야 함');
      });

      test('${entry.key}(type ${entry.value}) + 등급 상승(secondary→primary) → 빈 리스트', () {
        final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
          1: (entry: 'secondary', exit: 'primary'),
        });
        final steps = [step(), step(type: entry.value), step(type: 4)];
        final intents = drive(engine, 0, [600, 500, 300, 50, 5], steps);
        expect(intents, isEmpty, reason: '${entry.key} 등급 상승은 억제돼야 함');
      });
    }
  });

  group('B — 억제 대상 이벤트, 등급 하락 시 정상 안내', () {
    for (final entry in suppressibleTypes.entries) {
      test('${entry.key}(type ${entry.value}) + 등급 하락(primary→secondary) → 정상 SpeakIntent', () {
        final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
          1: (entry: 'primary', exit: 'secondary'),
        });
        final steps = [step(), step(type: entry.value), step(type: 4)];
        final intents = drive(engine, 0, [600, 500], steps);
        expect(intents, isNotEmpty, reason: '${entry.key} 등급 하락은 정상 안내돼야 함');
        expect(intents.first.key, startsWith(entry.key));
      });
    }
  });

  group('C — road_class 데이터 없음(fail-open) → 정상 안내(기존 동작 유지)', () {
    test('roadClassByManeuverIdx가 null(기본값)이어도 정상 안내', () {
      final engine = VoiceEngine(profile);
      final steps = [step(), step(type: 15), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      expect(intents.first.key, 'turn_left_approach');
    });

    test('roadClassByManeuverIdx에 해당 maneuver 인덱스가 없으면 정상 안내', () {
      final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
        99: (entry: 'primary', exit: 'primary'),
      });
      final steps = [step(), step(type: 15), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      expect(intents.first.key, 'turn_left_approach');
    });

    test('entry/exit 둘 다 null이어도(맵 엔트리는 있으나 값 결측) 정상 안내', () {
      final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
        1: (entry: null, exit: null),
      });
      final steps = [step(), step(type: 15), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      expect(intents.first.key, 'turn_left_approach');
    });
  });

  group('D — 억제 대상 밖 이벤트(ramp/exit/roundabout/uturn)는 등급 유지·상승이어도 억제되지 않는다', () {
    test('ramp_straight(type 17) + 등급 유지 → 정상 안내', () {
      final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
        1: (entry: 'primary', exit: 'primary'),
      });
      final steps = [step(), step(type: 17), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      expect(intents.first.key, 'ramp_straight_approach');
    });

    test('exit_right(type 20) + 등급 상승 → 정상 안내', () {
      final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
        1: (entry: 'secondary', exit: 'primary'),
      });
      final steps = [step(), step(type: 20), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      expect(intents.first.key, 'exit_right_approach');
    });

    test('exit_left(type 21) + 등급 유지 → 정상 안내', () {
      final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
        1: (entry: 'tertiary', exit: 'tertiary'),
      });
      final steps = [step(), step(type: 21), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      expect(intents.first.key, 'exit_left_approach');
    });

    test('roundabout_enter(type 26) + 등급 유지 → 정상 안내', () {
      final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
        1: (entry: 'primary', exit: 'primary'),
      });
      final steps = [step(), step(type: 26), step(type: 27), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      expect(intents.first.key, startsWith('roundabout'));
    });

    test('uturn(type 12) + 등급 유지 → 정상 안내', () {
      final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
        1: (entry: 'primary', exit: 'primary'),
      });
      final steps = [step(), step(type: 12), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      expect(intents.first.key, 'uturn_approach');
    });

    test('merge(type 25) + 등급 유지 → 정상 안내', () {
      final engine = VoiceEngine(profile, roadClassByManeuverIdx: {
        1: (entry: 'primary', exit: 'primary'),
      });
      final steps = [step(), step(type: 25), step(type: 4)];
      final intents = drive(engine, 0, [600, 500], steps);
      expect(intents, isNotEmpty);
      expect(intents.first.key, 'merge_approach');
    });
  });
}
