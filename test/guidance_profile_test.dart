import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/guidance_profile.dart';

void main() {
  // IC/exit per-event tiers: 1000, 400, 120 breakpoints
  final icTiers = [
    const GuidanceTier(minEntryM: 1000, pointsM: [1000, 500, 150]),
    const GuidanceTier(minEntryM: 400, pointsM: [400, 150]),
    const GuidanceTier(minEntryM: 120, pointsM: [120, 50]),
    const GuidanceTier(minEntryM: 0, pointsM: []),
  ];

  // Global tiers: max minEntryM is 500
  const globalTiers = [
    GuidanceTier(minEntryM: 500, pointsM: [500, 300, 50]),
    GuidanceTier(minEntryM: 150, pointsM: [300, 50]),
    GuidanceTier(minEntryM: 30, pointsM: [100, 50]),
    GuidanceTier(minEntryM: 0, pointsM: []),
  ];

  final profile = GuidanceProfile(
    imminentM: 5,
    tiers: globalTiers,
    enabledEvents: {'turn_left', 'ramp', 'exit', 'destination'},
    eventTiers: {'ramp': icTiers, 'exit': icTiers},
  );

  test('1. ramp → per-event tiers include 1000 tier', () {
    final tiers = profile.tiersForEvent('ramp');
    expect(tiers.any((t) => t.minEntryM == 1000), isTrue);
  });

  test('2. turn_left → global tiers (no 1000 tier, has 500)', () {
    final tiers = profile.tiersForEvent('turn_left');
    expect(tiers.any((t) => t.minEntryM == 1000), isFalse);
    expect(tiers.any((t) => t.minEntryM == 500), isTrue);
  });

  test('3. destination (not in eventTiers) → global fallback', () {
    final tiers = profile.tiersForEvent('destination');
    expect(tiers.any((t) => t.minEntryM == 1000), isFalse);
    expect(tiers.first.minEntryM, equals(500));
  });

  test('4. profile with empty eventTiers → all events return global', () {
    const noEventTiersProfile = GuidanceProfile(
      imminentM: 5,
      tiers: globalTiers,
      enabledEvents: {'turn_left', 'ramp'},
    );
    final rampTiers = noEventTiersProfile.tiersForEvent('ramp');
    expect(rampTiers.any((t) => t.minEntryM == 1000), isFalse);
    expect(rampTiers.first.minEntryM, equals(500));
    final leftTiers = noEventTiersProfile.tiersForEvent('turn_left');
    expect(leftTiers.first.minEntryM, equals(500));
  });
}
