import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/models/saved_route.dart';

void main() {
  group('SavedRoute type safety', () {
    final sample = SavedRoute(
      id: 'r-1',
      name: 'test route',
      points: const [RoutePoint(37.5, 127.0), RoutePoint(37.6, 127.1)],
      type: RouteType.national,
      savedAt: DateTime.utc(2026, 5, 26),
      distanceKm: 12.3,
    );

    test('round-trips through JSON without losing element type', () {
      final encoded = sample.toJsonString();
      final decoded = SavedRoute.fromJsonString(encoded);

      expect(decoded, isA<SavedRoute>());
      expect(decoded.id, sample.id);
      expect(decoded.name, sample.name);
      expect(decoded.type, sample.type);
      expect(decoded.distanceKm, sample.distanceKm);
      expect(decoded.points.length, sample.points.length);
      expect(decoded.points.first.lat, sample.points.first.lat);
    });

    test('spread with typed empty fallback yields List<SavedRoute>', () {
      // Reproduces the pattern used inside SavedRoutesNotifier.add when
      // state.value is null. The typed empty list keeps the resulting
      // collection a List<SavedRoute>, not a List<dynamic>.
      const List<SavedRoute>? maybeNull = null;
      final next = <SavedRoute>[...(maybeNull ?? <SavedRoute>[]), sample];

      expect(next, isA<List<SavedRoute>>());
      expect(next, isNot(isA<List<dynamic>>().having(
        (l) => l.runtimeType.toString(),
        'runtimeType',
        equals('List<dynamic>'),
      )));
      expect(next.length, 1);
      expect(next.first, same(sample));
    });

    test('filter with typed empty fallback yields List<SavedRoute>', () {
      // Reproduces the pattern used inside SavedRoutesNotifier.remove.
      const List<SavedRoute>? maybeNull = null;
      final next =
          (maybeNull ?? <SavedRoute>[]).where((r) => r.id != 'x').toList();

      expect(next, isA<List<SavedRoute>>());
      expect(next, isEmpty);
    });

    test('casting from raw JSON list returns List<SavedRoute>', () {
      final List<dynamic> rawList = [sample.toJsonString()];
      final hydrated = rawList
          .map((s) => SavedRoute.fromJsonString(s as String))
          .toList();

      expect(hydrated, isA<List<SavedRoute>>());
      expect(hydrated.single.id, sample.id);
    });
  });
}
