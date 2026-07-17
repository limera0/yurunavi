import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // 적도 위 경도 방향 10m 간격 포인트 — Distance()가 실제로 계산하는 값과
  // 맞아떨어지도록 다른 route_progress 테스트들과 동일한 변환 사용.
  const metersPerDegreeLon = 111320.0;
  const lat = 0.0;
  const baseLon = 127.0;
  const stepM = 10.0;
  final stepDeg = stepM / metersPerDegreeLon;
  final points =
      List<LatLng>.generate(101, (i) => LatLng(lat, baseLon + i * stepDeg));
  const distance = Distance();

  group('A — 기본 전방 샘플링', () {
    test('fromIdx=0, 기본 설정(500m/150m)이면 0,150,300,450m 지점 4개', () {
      final samples = RoutingService.forwardSamplePoints(points, 0);

      expect(samples.length, 4);
      expect(samples[0], points[0]); // 0m 지점(자기 자신) 포함
      for (var i = 0; i < samples.length; i++) {
        final expectedM = i * 150.0;
        final actualM = distance(points[0], samples[i]);
        expect(actualM, closeTo(expectedM, 0.5));
      }
    });

    test('maxForwardM=300, stepM=100이면 0,100,200,300m 지점 4개', () {
      final samples = RoutingService.forwardSamplePoints(points, 0,
          maxForwardM: 300, stepM: 100);

      expect(samples.length, 4);
      for (var i = 0; i < samples.length; i++) {
        final actualM = distance(points[0], samples[i]);
        expect(actualM, closeTo(i * 100.0, 0.5));
      }
    });
  });

  group('B — 뒤쪽은 절대 포함하지 않는다', () {
    test('fromIdx가 중간이면 그 이전 포인트는 샘플에 나타나지 않는다', () {
      final samples = RoutingService.forwardSamplePoints(points, 50,
          maxForwardM: 300, stepM: 100);

      expect(samples[0], points[50]);
      // 모든 샘플이 fromIdx 지점으로부터 전방(양의 거리)에 있어야 한다 —
      // points 배열은 인덱스 증가=경도 증가 방향으로 단조 배치돼 있으므로,
      // 샘플의 경도가 points[50]의 경도보다 작아지면(뒤로 갔으면) 실패.
      for (final s in samples) {
        expect(s.longitude, greaterThanOrEqualTo(points[50].longitude));
      }
    });
  });

  group('C — 경로가 maxForwardM보다 짧으면 남은 만큼만', () {
    test('경로 끝이 200m 지점에 있으면 그 이상은 샘플링하지 않는다', () {
      final shortPoints = points.sublist(0, 21); // 0~200m (10m*20)
      final samples = RoutingService.forwardSamplePoints(shortPoints, 0,
          maxForwardM: 500, stepM: 150);

      expect(samples.length, 2); // 0m, 150m만 (300m는 경로 밖)
    });
  });

  group('D — 경계값 방어', () {
    test('빈 리스트 → 빈 리스트', () {
      expect(RoutingService.forwardSamplePoints(const [], 0), isEmpty);
    });

    test('fromIdx가 범위 밖(음수/초과) → 빈 리스트', () {
      expect(RoutingService.forwardSamplePoints(points, -1), isEmpty);
      expect(
          RoutingService.forwardSamplePoints(points, points.length), isEmpty);
    });

    test('fromIdx가 마지막 인덱스 → 자기 자신 1개만', () {
      final samples =
          RoutingService.forwardSamplePoints(points, points.length - 1);
      expect(samples, [points.last]);
    });
  });
}
