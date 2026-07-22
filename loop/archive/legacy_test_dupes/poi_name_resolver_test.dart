import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/map/poi_name_resolver.dart';
import 'package:yurunavi/models/map_language.dart';

void main() {
  group('PoiNameResolver', () {
    test('korean → name:nonlatin', () {
      expect(PoiNameResolver(MapLanguage.korean)
          .resolve({'name:nonlatin': '오산역', 'name:latin': 'Osan', 'name': 'Osan'}), '오산역');
    });
    test('english → name:latin', () {
      expect(PoiNameResolver(MapLanguage.english)
          .resolve({'name:nonlatin': '오산역', 'name:latin': 'Osan'}), 'Osan');
    });
    test('선택 토큰 없음 → name 폴백', () {
      expect(PoiNameResolver(MapLanguage.korean).resolve({'name': 'Osan'}), 'Osan');
    });
    test('빈 문자열은 값 없음 취급 → name 폴백', () {
      expect(PoiNameResolver(MapLanguage.korean)
          .resolve({'name:nonlatin': '', 'name': 'Osan'}), 'Osan');
    });
    test('어떤 name도 없음 → null (호출측이 좌표 폴백)', () {
      expect(PoiNameResolver(MapLanguage.korean).resolve({'class': 'restaurant'}), isNull);
    });
  });
}