import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // Fallback-equivalent profile (tiers sorted descending), extended with
  // sharp_turn_left/right so isEnabled()/tiersForEvent() fall back to the
  // same common tiers/imminentM used by guidance_profile.json's global
  // defaults (sharp_turn_left/right have no per-event tiers override there).
  final profile = GuidanceProfile(
    imminentM: 10,
    tiers: const [
      GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
      GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
      GuidanceTier(minEntryM: 30, pointsM: [100, 50]),
      GuidanceTier(minEntryM: 0, pointsM: []),
    ],
    enabledEvents: {'sharp_turn_left', 'sharp_turn_right'},
  );

  List<SpeakIntent> drive(
      CurveVoiceEngine e, int zoneIdx, List<double> dSeq, CurveDirection direction) {
    final out = <SpeakIntent>[];
    for (final d in dSeq) {
      out.addAll(e.onProgress(zoneIdx, d, direction));
    }
    return out;
  }

  group('A — 급좌커브(sharp_turn_left)', () {
    test('zoneIdx 0을 [600,500,300,50,5]로 접근: approach ×3 + imminent', () {
      final engine = CurveVoiceEngine(profile);
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], CurveDirection.left);
      expect(intents.map((i) => i.key).toList(), [
        'sharp_turn_left_approach',
        'sharp_turn_left_approach',
        'sharp_turn_left_approach',
        'sharp_turn_left_imminent',
      ]);
    });
  });

  group('B — 급우커브(sharp_turn_right)', () {
    test('zoneIdx 0을 [600,500,300,50,5]로 접근: approach ×3 + imminent', () {
      final engine = CurveVoiceEngine(profile);
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], CurveDirection.right);
      expect(intents.map((i) => i.key).toList(), [
        'sharp_turn_right_approach',
        'sharp_turn_right_approach',
        'sharp_turn_right_approach',
        'sharp_turn_right_imminent',
      ]);
    });
  });

  group('C — 두 번째 커브(zoneIdx 1)로 전환 시 pending points 리셋', () {
    test('zoneIdx 0의 잔여 pending points를 버리고 zoneIdx 1에서 새로 시작한다', () {
      final engine = CurveVoiceEngine(profile);
      // zoneIdx 0: 600에서 시작해 500만 소비하고 [300,50,10]을 남겨둔다.
      final firstZoneOut = drive(engine, 0, [600, 500], CurveDirection.left);
      expect(firstZoneOut.map((i) => i.key).toList(), ['sharp_turn_left_approach']);

      // zoneIdx 1로 전환, entryD=100 → tier(minEntry30)=[100,50] → filtered=[50,10]
      // (100은 100<100이 아니므로 제외). zoneIdx 0에 남아있던 300이 새어나오지
      // 않아야 한다.
      final secondZoneOut = drive(engine, 1, [100, 50, 5], CurveDirection.right);
      expect(secondZoneOut.map((i) => i.key).toList(), [
        'sharp_turn_right_approach',
        'sharp_turn_right_imminent',
      ]);
      expect(secondZoneOut.map((i) => i.vars['dist']).toList(), ['50', '10']);
    });
  });

  group('D — 비활성 이벤트는 안내를 생성하지 않는다', () {
    test("enabledEvents에 'sharp_turn_left'가 없으면 거리 0까지 감소해도 아무것도 발화하지 않는다", () {
      final disabledProfile = GuidanceProfile(
        imminentM: 10,
        tiers: profile.tiers,
        enabledEvents: {'sharp_turn_right'}, // sharp_turn_left 제외
      );
      final engine = CurveVoiceEngine(disabledProfile);
      final intents = drive(engine, 0, [600, 500, 300, 50, 10, 0], CurveDirection.left);
      expect(intents, isEmpty);
    });
  });

  group('E — reset()', () {
    test('reset 후 같은 zoneIdx라도 새 접근 사이클로 취급한다', () {
      final engine = CurveVoiceEngine(profile);
      drive(engine, 0, [600, 500], CurveDirection.left);
      engine.reset();
      final out = drive(engine, 0, [400], CurveDirection.left);
      // reset 후 zoneIdx 0을 다시 처음 보는 것으로 취급 → entryD=400 tier(150)=[300,50]
      // filtered = {300,50,10}.where(<400) = [300,50,10], d=400에서는 아무것도 배출 안 함
      // (400 <= 300 아님).
      expect(out, isEmpty);
    });
  });

  group('F — direction null(zoneIdx -1)은 즉시 상태를 리셋한다', () {
    test('직전 접근 중이던 pending points를 폐기하고 빈 리스트를 반환한다', () {
      final engine = CurveVoiceEngine(profile);
      drive(engine, 0, [600, 500], CurveDirection.left);
      final out = engine.onProgress(-1, double.infinity, null);
      expect(out, isEmpty);

      // 이후 같은 zoneIdx(0)가 재사용되어도 "이미 본 구간"으로 오인하지 않고
      // 새 접근 사이클로 다시 안내한다.
      final resumed = drive(engine, 0, [400], CurveDirection.left);
      expect(resumed, isEmpty); // 400 <= 300 아니므로 아직 배출 없음(정상)
      final continued = drive(engine, 0, [300], CurveDirection.left);
      expect(continued.map((i) => i.key).toList(), ['sharp_turn_left_approach']);
    });
  });
}
