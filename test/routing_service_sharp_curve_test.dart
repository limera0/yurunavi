import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  group('A — 직선 경로', () {
    test('방위각 변화 없는 직선 → 커브 0개', () {
      const metersPerDegreeLon = 111320.0;
      const lat = 0.0;
      const baseLon = 127.0;
      const stepM = 10.0;
      final stepDeg = stepM / metersPerDegreeLon;
      final points = List<LatLng>.generate(
          21, (i) => LatLng(lat, baseLon + i * stepDeg));

      final curves = RoutingService.detectSharpCurves(points, const []);

      expect(curves, isEmpty);
    });
  });

  group('B — 합성 급커브 (짧은 구간 내 90도 좌회전)', () {
    test('90도 좌회전 → zone 1개, direction left', () {
      // 동쪽으로 가다가(위도 고정, 경도 증가) 정확히 90도 꺾어 북쪽으로
      // (경도 고정, 위도 증가) 진행하는 합성 경로. 각 구간 ~15-20m.
      final points = <LatLng>[
        LatLng(37.0000000, 127.0000000),
        LatLng(37.0000000, 127.0002000), // 동쪽 진행 (bearing ~90)
        LatLng(37.0000000, 127.0004000),
        LatLng(37.0002000, 127.0004000), // 급격히 북쪽으로 (bearing ~0)
        LatLng(37.0004000, 127.0004000),
      ];

      final curves = RoutingService.detectSharpCurves(points, const []);

      expect(curves.length, 1);
      expect(curves[0].direction, CurveDirection.left);
    });

    test('90도 우회전 → zone 1개, direction right', () {
      final points = <LatLng>[
        LatLng(37.0000000, 127.0000000),
        LatLng(37.0002000, 127.0000000), // 북쪽 진행 (bearing ~0)
        LatLng(37.0004000, 127.0000000),
        LatLng(37.0004000, 127.0002000), // 급격히 동쪽으로 (bearing ~90)
        LatLng(37.0004000, 127.0004000),
      ];

      final curves = RoutingService.detectSharpCurves(points, const []);

      expect(curves.length, 1);
      expect(curves[0].direction, CurveDirection.right);
    });
  });

  group('C — 실측 고덕갈평로 fixture (필드 리포트 회귀 테스트)', () {
    test('9포인트 실측 shape → 정확히 1개의 left 커브 zone', () {
      final points = <LatLng>[
        LatLng(37.055012, 127.049800),
        LatLng(37.055015, 127.050322),
        LatLng(37.055029, 127.050521),
        LatLng(37.055093, 127.050664),
        LatLng(37.055267, 127.050752),
        LatLng(37.055485, 127.050796),
        LatLng(37.055821, 127.050849),
        LatLng(37.056095, 127.050858),
        LatLng(37.056199, 127.050856),
      ];

      // 실제 Valhalla 응답의 maneuver 목록 — type 1(출발/직진 필러)이 경로
      // 전체(0~8)를 덮고, type 5(도착)가 마지막 지점만 덮는다. 이런 "직진
      // 유지" 필러 maneuver가 감지된 커브 범위와 겹친다고 해서 억제되면 안
      // 된다(회귀 테스트 — 실제 필드 리포트 버그의 원인이었다).
      final maneuvers = [
        ManeuverStep(
          type: 1,
          instruction: 'Drive east on 고덕갈평로',
          distanceKm: 0.203,
          beginShapeIdx: 0,
          endShapeIdx: 8,
        ),
        ManeuverStep(
          type: 5,
          instruction: 'Your destination is on the right',
          distanceKm: 0.0,
          beginShapeIdx: 8,
          endShapeIdx: 8,
        ),
      ];
      final curves = RoutingService.detectSharpCurves(points, maneuvers);

      expect(curves.length, 1);
      expect(curves[0].direction, CurveDirection.left);
    });
  });

  group('D — maneuver 범위와 겹치는 커브는 제외', () {
    test('Valhalla maneuver가 이미 커버하는 shape 인덱스 범위와 겹치면 억제된다', () {
      final points = <LatLng>[
        LatLng(37.0000000, 127.0000000),
        LatLng(37.0000000, 127.0002000),
        LatLng(37.0000000, 127.0004000),
        LatLng(37.0002000, 127.0004000),
        LatLng(37.0004000, 127.0004000),
      ];

      // 위 fixture는 (B)와 동일하게 index 0~1 부근에서 left curve 1개를
      // 감지한다. 그 범위를 포함하는 maneuver를 주면 억제되어야 한다.
      final withoutManeuver =
          RoutingService.detectSharpCurves(points, const []);
      expect(withoutManeuver, isNotEmpty);
      final curve = withoutManeuver.first;

      final maneuvers = [
        ManeuverStep(
          type: 14, // sharp_turn_left
          instruction: '좌회전',
          distanceKm: 0.02,
          beginShapeIdx: curve.beginShapeIdx,
          endShapeIdx: curve.endShapeIdx,
        ),
      ];

      final curves = RoutingService.detectSharpCurves(points, maneuvers);
      expect(curves, isEmpty);
    });
  });

  group('E — 경계값 방어', () {
    test('포인트 2개 이하 → 크래시 없이 빈 리스트', () {
      final points = <LatLng>[
        LatLng(37.0, 127.0),
        LatLng(37.0001, 127.0001),
      ];
      expect(
          () => RoutingService.detectSharpCurves(points, const []),
          returnsNormally);
      expect(RoutingService.detectSharpCurves(points, const []), isEmpty);
    });
  });
}
