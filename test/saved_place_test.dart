import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/models/saved_place.dart';

void main() {
  group('FavoritePlace 직렬화', () {
    test('category 포함 toJson/fromJson 왕복', () {
      const place = FavoritePlace(
        id: '1',
        name: '우리집',
        lat: 37.5,
        lng: 127.0,
        category: '집',
      );

      final restored = FavoritePlace.fromJsonString(place.toJsonString());

      expect(restored.id, '1');
      expect(restored.name, '우리집');
      expect(restored.lat, 37.5);
      expect(restored.lng, 127.0);
      expect(restored.category, '집');
    });

    test('category 없이 저장된 구버전 JSON을 읽으면 미분류로 채워진다', () {
      const legacyJson = '{"id":"2","name":"옛날즐겨찾기","lat":36.0,"lng":128.0}';

      final restored = FavoritePlace.fromJsonString(legacyJson);

      expect(restored.category, kUncategorizedFavoriteCategory);
    });

    test('category 기본값은 미분류', () {
      const place = FavoritePlace(id: '3', name: 'X', lat: 0, lng: 0);
      expect(place.category, kUncategorizedFavoriteCategory);
    });
  });

  group('FavoritePlace.findByLocation', () {
    const favorites = [
      FavoritePlace(id: 'a', name: 'A', lat: 37.12345, lng: 127.12345),
      FavoritePlace(id: 'b', name: 'B', lat: 35.0, lng: 129.0),
    ];

    test('허용오차 내 좌표는 같은 장소로 찾는다', () {
      final found = FavoritePlace.findByLocation(favorites, 37.123451, 127.123449);
      expect(found?.id, 'a');
    });

    test('허용오차를 벗어나면 매치하지 않는다', () {
      final found = FavoritePlace.findByLocation(favorites, 37.2, 127.2);
      expect(found, isNull);
    });

    test('빈 목록이면 null', () {
      final found = FavoritePlace.findByLocation(const [], 0, 0);
      expect(found, isNull);
    });
  });
}
