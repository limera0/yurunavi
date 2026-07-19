import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/services/routing_service.dart';

// 위도 37.0(한국) 근방 고정 — Vincenty 계산기가 적도(위도 0) 부근 대량의 점쌍
// 비교에서 수치적으로 불안정해지는 경우가 있어(cosSqAlpha→0 근방), 실제 서비스
// 위도대와 비슷한 값을 사용한다. 위도 37도에서 경도 1도 ≈ 111320*cos(37°)m.
const _baseLat = 37.0;
final _metersPerDegreeLon = 111320.0 * math.cos(_baseLat * math.pi / 180);

List<LatLng> _eastward(double startLonDeg, double totalM, double stepM) {
  final steps = (totalM / stepM).round();
  return List<LatLng>.generate(
    steps + 1,
    (i) => LatLng(_baseLat, startLonDeg + (i * stepM) / _metersPerDegreeLon),
  );
}

void main() {
  group('A — 직선 경로 (진행만, 되돌아옴 없음)', () {
    test('30km 직진 → 루프 없음', () {
      final points = _eastward(127.0, 30000, 200);

      final loop = RoutingService.findLoopCenter(points);

      expect(loop, isNull);
    });
  });

  group('B — 합성 제자리 루프 (6km 나갔다가 출발점 근처로 복귀)', () {
    test('신갈JC형 루프 → loopCenter가 진행 방향 시작점 근처에서 검출됨', () {
      final outbound = _eastward(127.0, 6100, 200); // 0 → +6.1km 동쪽
      final startLon = outbound.first.longitude;
      final peakLon = outbound.last.longitude;
      // 복귀: 출발점에서 400m 지점까지만 돌아옴(루프 인접 임계치 1500m 이내).
      final returnEndLon = startLon + 400 / _metersPerDegreeLon;
      final returnSteps =
          ((peakLon - returnEndLon) * _metersPerDegreeLon / 200).round();
      final inbound = List<LatLng>.generate(
        returnSteps,
        (i) => LatLng(
          _baseLat,
          peakLon - (i + 1) * (peakLon - returnEndLon) / returnSteps,
        ),
      );
      // 복귀 후 목적지 방향으로 계속 진행(실제 사례처럼 "루프 후 재개" 모양).
      final resume = _eastward(returnEndLon, 10000, 200).skip(1);

      final points = [...outbound, ...inbound, ...resume];

      final loop = RoutingService.findLoopCenter(points);

      expect(loop, isNotNull);
      // loopCenter는 나중에 근처로 되돌아오게 되는 "더 이른 지점"을 반환하는
      // 알고리즘 설계이므로 outbound 시작 구간(출발점 근방)에서 나와야 한다.
      expect(loop!.longitude, closeTo(outbound.first.longitude, 0.01));
    });
  });

  group('C — 완만한 굽이길 (지속적으로 전진, 제자리로 돌아오지 않음)', () {
    test('사인파형 좌우 흔들림 + 단조 전진 30km → 루프 없음(정당한 스위치백 보존)', () {
      // 경도는 단조 증가(전진), 위도는 사인파로 좌우 흔들림 — 산길 곡선처럼
      // 방향은 계속 바뀌지만 결코 "훨씬 이전 지점 근처로" 되돌아오지 않는다.
      const totalM = 30000.0;
      const stepM = 100.0;
      const amplitudeDeg = 0.003; // 위도 흔들림 진폭(약 300m 상당)
      const periodM = 2000.0;
      final steps = (totalM / stepM).round();
      final points = List<LatLng>.generate(steps + 1, (i) {
        final progressedM = i * stepM;
        final lonDeg = 127.0 + progressedM / _metersPerDegreeLon;
        final latDeg = _baseLat +
            amplitudeDeg * math.sin(2 * math.pi * progressedM / periodM);
        return LatLng(latDeg, lonDeg);
      });

      final loop = RoutingService.findLoopCenter(points);

      expect(loop, isNull);
    });
  });

  group('D — 경계값 방어', () {
    test('점 0~1개 → 크래시 없이 null', () {
      expect(RoutingService.findLoopCenter(const []), isNull);
      expect(RoutingService.findLoopCenter([const LatLng(0, 0)]), isNull);
    });
  });
}
