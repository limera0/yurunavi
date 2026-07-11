import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';
import 'package:yurunavi/services/voice_pack_service.dart';

void main() {
  // Profile matching production values after C1 (imminentM=10).
  // Entry distance 15m → falls into minEntryM=0 tier (pointsM=[]) → only imminentM=10 pending.
  final profile = GuidanceProfile(
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
  );

  ManeuverStep step({int type = 0}) =>
      ManeuverStep(type: type, instruction: '', distanceKm: 0);

  // Drive engine at constant speedKmh from 15m to 10m so only the imminent
  // point fires, then return the resulting intents.
  List<SpeakIntent> driveToImminent(
    VoiceEngine e,
    List<ManeuverStep> steps, {
    double speedKmh = 0,
  }) {
    final out = <SpeakIntent>[];
    out.addAll(e.onProgress(0, 15, steps, speedKmh: speedKmh));
    out.addAll(e.onProgress(0, 10, steps, speedKmh: speedKmh));
    return out;
  }

  group('R1 — turn imminent key is unconditionally _fast (speed no longer matters)', () {
    test('turn_left speed 25 → turn_left_imminent_fast', () {
      final engine = VoiceEngine(profile);
      final steps = [step(), step(type: 15), step(type: 4)]; // 15=turn_left
      final intents = driveToImminent(engine, steps, speedKmh: 25);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_left_imminent_fast');
    });

    test('turn_left speed 10 → turn_left_imminent_fast (unconditional now)', () {
      final engine = VoiceEngine(profile);
      final steps = [step(), step(type: 15), step(type: 4)];
      final intents = driveToImminent(engine, steps, speedKmh: 10);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_left_imminent_fast');
    });

    test('turn_right speed 30 → turn_right_imminent_fast', () {
      final engine = VoiceEngine(profile);
      final steps = [step(), step(type: 10), step(type: 4)]; // 10=turn_right
      final intents = driveToImminent(engine, steps, speedKmh: 30);
      expect(intents.length, 1);
      expect(intents[0].key, 'turn_right_imminent_fast');
    });
  });

  group('R1 — pack fallback (_fast key absent)', () {
    test('resolveTemplate falls back to base imminent when _fast key absent', () {
      final templates = {
        'turn_left_imminent': '좌회전입니다',
        'turn_right_imminent': '우회전입니다',
        // no _fast variants — simulates older voice pack
      };
      expect(
        VoicePackService.resolveTemplate(templates, 'turn_left_imminent_fast'),
        '좌회전입니다',
      );
      expect(
        VoicePackService.resolveTemplate(templates, 'turn_right_imminent_fast'),
        '우회전입니다',
      );
    });
  });

  group('C — pack fallback (_named key absent)', () {
    test('resolveTemplate falls back to base approach when _named key absent', () {
      final templates = {
        'exit_approach': '{dist}미터 앞 진출',
        'ramp_imminent': '진입입니다',
        // no _named variants — simulates older voice pack
      };
      expect(
        VoicePackService.resolveTemplate(templates, 'exit_approach_named'),
        '{dist}미터 앞 진출',
      );
      expect(
        VoicePackService.resolveTemplate(templates, 'ramp_imminent_named'),
        '진입입니다',
      );
    });
  });
}
