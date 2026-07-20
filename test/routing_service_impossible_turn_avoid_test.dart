import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/services/routing_service.dart';

// 회귀 가드: loop/RECON_impossible_left_turns.md에서 마스터가 실주행으로 확인한
// "불가능한 좌회전" 2개 지점 좌표가 실수로 바뀌거나 삭제되지 않도록 고정한다.
void main() {
  group('RoutingService.knownImpossibleTurnAvoids', () {
    test('정확히 2개 지점, 실측 좌표와 일치', () {
      final avoids = RoutingService.knownImpossibleTurnAvoids;

      expect(avoids.length, 2);
      expect(avoids[0], {'lat': 37.09172, 'lon': 127.09205}); // 삼봉로/삼남로
      expect(avoids[1], {'lat': 37.13696, 'lon': 127.07838}); // 동부대로/남부대로
    });
  });
}
