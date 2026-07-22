import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/map/poi_category.dart';

void main() {
  group('poiCategoryKo', () {
    test('restaurant → 음식점', () => expect(poiCategoryKo({'class': 'restaurant'}), '음식점'));
    test('subclass 우선(더 구체적)', () =>
        expect(poiCategoryKo({'class': 'restaurant', 'subclass': 'cafe'}), '카페'));
    test('미매핑 class → 원문 그대로', () => expect(poiCategoryKo({'class': 'xyz'}), 'xyz'));
    test('class 없음 → null (호출측이 좌표 폴백)', () => expect(poiCategoryKo({'name': 'A'}), isNull));
    test('빈 문자열 → null', () => expect(poiCategoryKo({'class': ''}), isNull));
  });
}