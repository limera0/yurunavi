import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/map/poi_feature_picker.dart';

PickFeature f(String layer, double dpx, [Map<String,dynamic>? p]) =>
    PickFeature(layerId: layer, screenDist: dpx, props: p ?? const {});

void main() {
  group('PoiFeaturePicker', () {
    test('후보 없음 → null', () {
      expect(PoiFeaturePicker.pick([]), isNull);
    });
    test('레이어 우선순위가 거리보다 우선 (먼 level-1 > 가까운 place)', () {
      final r = PoiFeaturePicker.pick([f('place-city', 2), f('poi-level-1', 40)]);
      expect(r!.layerId, 'poi-level-1');
    });
    test('동순위 → 화면거리 최소', () {
      final r = PoiFeaturePicker.pick([f('poi-level-2', 30), f('poi-level-2', 8)]);
      expect(r!.screenDist, 8);
    });
    test('railway는 poi-level-3보다 하위', () {
      final r = PoiFeaturePicker.pick([f('poi-railway', 2), f('poi-level-3', 50)]);
      expect(r!.layerId, 'poi-level-3');
    });
    test('미지의 레이어 id → 최하위 (다른 후보 있으면 탈락)', () {
      final r = PoiFeaturePicker.pick([f('building', 1), f('place-town', 60)]);
      expect(r!.layerId, 'place-town');
    });
    test('미지 레이어만 있으면 그중 최소거리 반환', () {
      final r = PoiFeaturePicker.pick([f('building', 9), f('water', 3)]);
      expect(r!.screenDist, 3);
    });
  });
}