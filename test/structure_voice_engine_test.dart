import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';
import 'package:yurunavi/features/navigation/voice_engine.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // Fallback-equivalent profile (tiers sorted descending), extended with
  // bridge/tunnel so isEnabled()/tiersForEvent() fall back to the same
  // common tiers/imminentM used by guidance_profile.json's global defaults.
  final profile = GuidanceProfile(
    imminentM: 10,
    tiers: const [
      GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
      GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
      GuidanceTier(minEntryM: 30, pointsM: [100, 50]),
      GuidanceTier(minEntryM: 0, pointsM: []),
    ],
    enabledEvents: {'bridge', 'tunnel'},
  );

  List<SpeakIntent> drive(
      StructureVoiceEngine e, int zoneIdx, List<double> dSeq, StructureType type) {
    final out = <SpeakIntent>[];
    for (final d in dSeq) {
      out.addAll(e.onProgress(zoneIdx, d, type));
    }
    return out;
  }

  group('A — 고가도로(bridge)', () {
    test('zoneIdx 0을 [600,500,300,50,5]로 접근: approach ×3 + imminent', () {
      final engine = StructureVoiceEngine(profile);
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], StructureType.bridge);
      expect(intents.map((i) => i.key).toList(), [
        'bridge_approach',
        'bridge_approach',
        'bridge_approach',
        'bridge_imminent',
      ]);
    });
  });

  group('B — 터널(tunnel)', () {
    test('zoneIdx 0을 [600,500,300,50,5]로 접근: approach ×3 + imminent', () {
      final engine = StructureVoiceEngine(profile);
      final intents = drive(engine, 0, [600, 500, 300, 50, 5], StructureType.tunnel);
      expect(intents.map((i) => i.key).toList(), [
        'tunnel_approach',
        'tunnel_approach',
        'tunnel_approach',
        'tunnel_imminent',
      ]);
    });
  });

  group('C — 두 번째 구조물(zoneIdx 1)로 전환 시 pending points 리셋', () {
    test('zoneIdx 0의 잔여 pending points를 버리고 zoneIdx 1에서 새로 시작한다', () {
      final engine = StructureVoiceEngine(profile);
      // zoneIdx 0: 600에서 시작해 500만 소비하고 [300,50,10]을 남겨둔다.
      final firstZoneOut = drive(engine, 0, [600, 500], StructureType.bridge);
      expect(firstZoneOut.map((i) => i.key).toList(), ['bridge_approach']);

      // zoneIdx 1로 전환, entryD=100 → tier(minEntry30)=[100,50] → filtered=[50,10]
      // (100은 100<100이 아니므로 제외). zoneIdx 0에 남아있던 300이 새어나오지
      // 않아야 한다.
      final secondZoneOut = drive(engine, 1, [100, 50, 5], StructureType.tunnel);
      expect(secondZoneOut.map((i) => i.key).toList(), [
        'tunnel_approach',
        'tunnel_imminent',
      ]);
      expect(secondZoneOut.map((i) => i.vars['dist']).toList(), ['50', '10']);
    });
  });

  group('D — 비활성 이벤트는 안내를 생성하지 않는다', () {
    test("enabledEvents에 'bridge'가 없으면 거리 0까지 감소해도 아무것도 발화하지 않는다", () {
      final disabledProfile = GuidanceProfile(
        imminentM: 10,
        tiers: profile.tiers,
        enabledEvents: {'tunnel'}, // bridge 제외
      );
      final engine = StructureVoiceEngine(disabledProfile);
      final intents = drive(engine, 0, [600, 500, 300, 50, 10, 0], StructureType.bridge);
      expect(intents, isEmpty);
    });
  });

  group('E — reset()', () {
    test('reset 후 같은 zoneIdx라도 새 접근 사이클로 취급한다', () {
      final engine = StructureVoiceEngine(profile);
      drive(engine, 0, [600, 500], StructureType.bridge);
      engine.reset();
      final out = drive(engine, 0, [400], StructureType.bridge);
      // reset 후 zoneIdx 0을 다시 처음 보는 것으로 취급 → entryD=400 tier(150)=[300,50]
      // filtered = {300,50,10}.where(<400) = [300,50,10], d=400에서는 아무것도 배출 안 함
      // (400 <= 300 아님).
      expect(out, isEmpty);
    });
  });
}
