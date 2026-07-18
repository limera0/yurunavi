import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/presentation/nav_screen.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  group('turnStepLabelForType — exit(20/21) 카드 라벨', () {
    test('구조물 없음 → 기존 일반 라벨 유지 (우측으로 진출)', () {
      expect(turnStepLabelForType(20), '우측으로 진출');
    });

    test('구조물 없음 → 기존 일반 라벨 유지 (좌측으로 진출)', () {
      expect(turnStepLabelForType(21), '좌측으로 진출');
    });

    test('type 20 + tunnel 인접 → "터널 우측 옆길"', () {
      expect(
        turnStepLabelForType(20, nearbyStructure: StructureType.tunnel),
        '터널 우측 옆길',
      );
    });

    test('type 21 + tunnel 인접 → "터널 좌측 옆길"', () {
      expect(
        turnStepLabelForType(21, nearbyStructure: StructureType.tunnel),
        '터널 좌측 옆길',
      );
    });

    test('type 20 + bridge 인접 → "고가도로 우측 옆길"', () {
      expect(
        turnStepLabelForType(20, nearbyStructure: StructureType.bridge),
        '고가도로 우측 옆길',
      );
    });

    test('type 21 + bridge 인접 → "고가도로 좌측 옆길"', () {
      expect(
        turnStepLabelForType(21, nearbyStructure: StructureType.bridge),
        '고가도로 좌측 옆길',
      );
    });

    test('type 20 + underpass 인접 → "지하차도 우측 옆길"', () {
      expect(
        turnStepLabelForType(20, nearbyStructure: StructureType.underpass),
        '지하차도 우측 옆길',
      );
    });

    test('type 21 + underpass 인접 → "지하차도 좌측 옆길"', () {
      expect(
        turnStepLabelForType(21, nearbyStructure: StructureType.underpass),
        '지하차도 좌측 옆길',
      );
    });

    test('다른 maneuver 타입은 구조물 인접 여부와 무관하게 영향받지 않는다', () {
      expect(
        turnStepLabelForType(10, nearbyStructure: StructureType.tunnel),
        '우회전',
      );
      expect(
        turnStepLabelForType(15, nearbyStructure: StructureType.bridge),
        '좌회전',
      );
    });
  });
}
