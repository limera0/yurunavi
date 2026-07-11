import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/services/exit_landmark_service.dart';

void main() {
  group('ExitLandmarkService.nearestLandmark', () {
    test('returns null when no candidate within radius', () {
      final svc = ExitLandmarkService(const [
        ExitLandmarkPlace(name: '먼마을', classPriority: 2, lat: 37.6, lon: 127.6),
      ]);
      // ~11km away (0.1 deg lat) — outside default 3km radius.
      expect(svc.nearestLandmark(const LatLng(37.5, 127.0)), isNull);
    });

    test('returns the sole candidate within radius', () {
      final svc = ExitLandmarkService(const [
        ExitLandmarkPlace(name: '동네리', classPriority: 2, lat: 37.501, lon: 127.001),
      ]);
      expect(svc.nearestLandmark(const LatLng(37.5, 127.0)), '동네리');
    });

    test('prefers higher class (city) over nearer lower class (village)', () {
      final svc = ExitLandmarkService(const [
        ExitLandmarkPlace(name: '가까운리', classPriority: 2, lat: 37.5005, lon: 127.0), // village, ~55m
        ExitLandmarkPlace(name: '먼읍내시', classPriority: 0, lat: 37.52, lon: 127.0), // city, ~2.2km
      ]);
      expect(svc.nearestLandmark(const LatLng(37.5, 127.0)), '먼읍내시');
    });

    test('same class → picks nearest', () {
      final svc = ExitLandmarkService(const [
        ExitLandmarkPlace(name: '먼리', classPriority: 2, lat: 37.515, lon: 127.0),
        ExitLandmarkPlace(name: '가까운리', classPriority: 2, lat: 37.505, lon: 127.0),
      ]);
      expect(svc.nearestLandmark(const LatLng(37.5, 127.0)), '가까운리');
    });

    test('custom radiusKm narrows the search', () {
      final svc = ExitLandmarkService(const [
        ExitLandmarkPlace(name: '동네리', classPriority: 2, lat: 37.51, lon: 127.0), // ~1.1km
      ]);
      expect(svc.nearestLandmark(const LatLng(37.5, 127.0), radiusKm: 3.0), '동네리');
      expect(svc.nearestLandmark(const LatLng(37.5, 127.0), radiusKm: 0.5), isNull);
    });
  });
}
