import 'dart:convert';
import 'package:flutter/services.dart';

class GuidanceTier {
  final double minEntryM;
  final List<double> pointsM;

  const GuidanceTier({required this.minEntryM, required this.pointsM});

  factory GuidanceTier.fromJson(Map<String, dynamic> json) => GuidanceTier(
        minEntryM: (json['min_entry_m'] as num).toDouble(),
        pointsM: (json['points_m'] as List).map((e) => (e as num).toDouble()).toList(),
      );
}

class GuidanceProfile {
  final double imminentM;
  final List<GuidanceTier> tiers;
  final Set<String> enabledEvents;
  final Map<String, List<GuidanceTier>> eventTiers;
  final Map<String, double> eventImminentM;

  const GuidanceProfile({
    required this.imminentM,
    required this.tiers,
    required this.enabledEvents,
    this.eventTiers = const <String, List<GuidanceTier>>{},
    this.eventImminentM = const <String, double>{},
  });

  static GuidanceProfile get _fallback => GuidanceProfile(
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

  static Future<GuidanceProfile> load(String assetPath) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final imminentM = (json['imminent_m'] as num).toDouble();
      final rawTiers = (json['tiers'] as List)
          .map((e) => GuidanceTier.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.minEntryM.compareTo(a.minEntryM));
      final rawEvents = json['events'] as Map<String, dynamic>;
      final enabledEvents = rawEvents.entries
          .where((e) => (e.value as Map<String, dynamic>)['enabled'] == true)
          .map((e) => e.key)
          .toSet();
      final eventTiersMap = <String, List<GuidanceTier>>{};
      final eventImminentMap = <String, double>{};
      for (final entry in rawEvents.entries) {
        final eventData = entry.value as Map<String, dynamic>;
        if (eventData['tiers'] is List) {
          eventTiersMap[entry.key] = (eventData['tiers'] as List)
              .map((e) => GuidanceTier.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.minEntryM.compareTo(a.minEntryM));
        }
        if (eventData['imminent_m'] is num) {
          eventImminentMap[entry.key] = (eventData['imminent_m'] as num).toDouble();
        }
      }
      return GuidanceProfile(
          imminentM: imminentM,
          tiers: rawTiers,
          enabledEvents: enabledEvents,
          eventTiers: eventTiersMap,
          eventImminentM: eventImminentMap);
    } catch (_) {
      return _fallback;
    }
  }

  GuidanceTier tierFor(double entryD) =>
      tiers.firstWhere((t) => entryD >= t.minEntryM,
          orElse: () => tiers.last);

  List<GuidanceTier> tiersForEvent(String event) => eventTiers[event] ?? tiers;

  double imminentForEvent(String event) => eventImminentM[event] ?? imminentM;

  bool isEnabled(String event) => enabledEvents.contains(event);
}
