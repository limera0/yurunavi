import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  group('A — RoundaboutDirectionLabel.labelKo', () {
    test('left → 좌측', () {
      expect(RoundaboutDirection.left.labelKo, '좌측');
    });
    test('straight → 직진', () {
      expect(RoundaboutDirection.straight.labelKo, '직진');
    });
    test('right → 우측', () {
      expect(RoundaboutDirection.right.labelKo, '우측');
    });
  });

  group('B — classifyRoundaboutDirection 경계값', () {
    // CurveDirection과 동일 부호 관례(delta < 0 → left, delta >= 0 → right)를
    // 그대로 좌/직/우 3분류로 확장한 것 — 임계값은 ±45°.
    test('정확히 -45도 → left (경계 포함)', () {
      expect(RoutingService.classifyRoundaboutDirection(-45),
          RoundaboutDirection.left);
    });
    test('-44.999도 → straight (경계 바로 안쪽)', () {
      expect(RoutingService.classifyRoundaboutDirection(-44.999),
          RoundaboutDirection.straight);
    });
    test('정확히 45도 → right (경계 포함)', () {
      expect(RoutingService.classifyRoundaboutDirection(45),
          RoundaboutDirection.right);
    });
    test('44.999도 → straight (경계 바로 안쪽)', () {
      expect(RoutingService.classifyRoundaboutDirection(44.999),
          RoundaboutDirection.straight);
    });
    test('0도 → straight', () {
      expect(RoutingService.classifyRoundaboutDirection(0),
          RoundaboutDirection.straight);
    });
    test('+180도(wrap-around 근처) → right', () {
      expect(RoutingService.classifyRoundaboutDirection(180),
          RoundaboutDirection.right);
    });
    test('-180도(wrap-around 근처) → left', () {
      expect(RoutingService.classifyRoundaboutDirection(-180),
          RoundaboutDirection.left);
    });
    test('-179.9도 → left', () {
      expect(RoutingService.classifyRoundaboutDirection(-179.9),
          RoundaboutDirection.left);
    });
  });

  group('C — HANDOFF_0807_S6 검단 회전교차로 실측 프로브 5건', () {
    // signedBearingDiff 결과값(PoiService.signedBearingDiff로 별도 검증됨,
    // test/services/poi_service_test.dart 참조)을 그대로 넣어 최종 3분류
    // 판정까지 기대와 일치하는지 확인한다.
    const cases = [
      (label: 'S→E', signedTurn: 8.4, expected: RoundaboutDirection.straight),
      (label: 'S→W', signedTurn: -150.9, expected: RoundaboutDirection.left),
      (label: 'N→S', signedTurn: -17.5, expected: RoundaboutDirection.straight),
      (label: 'E→W', signedTurn: 10.9, expected: RoundaboutDirection.straight),
      (label: 'W→N', signedTurn: -101.1, expected: RoundaboutDirection.left),
    ];

    for (final c in cases) {
      test('${c.label}: signedTurn=${c.signedTurn} → ${c.expected}', () {
        expect(
          RoutingService.classifyRoundaboutDirection(c.signedTurn),
          c.expected,
        );
      });
    }
  });
}
