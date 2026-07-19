import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yurunavi/models/saved_place.dart';
import 'package:yurunavi/services/places_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlacesService favorites (category 포함)', () {
    test('addFavorite/loadFavorites가 category를 보존한다', () async {
      final service = PlacesService();
      await service.addFavorite(const FavoritePlace(
        id: '1',
        name: '우리집',
        lat: 37.5,
        lng: 127.0,
        category: '집',
      ));

      final all = await service.loadFavorites();

      expect(all, hasLength(1));
      expect(all.first.category, '집');
    });

    test('removeFavorite가 id로 정확히 제거한다', () async {
      final service = PlacesService();
      await service.addFavorite(
          const FavoritePlace(id: '1', name: 'A', lat: 1, lng: 1));
      await service.addFavorite(
          const FavoritePlace(id: '2', name: 'B', lat: 2, lng: 2));

      await service.removeFavorite('1');
      final all = await service.loadFavorites();

      expect(all.map((p) => p.id), ['2']);
    });
  });

  group('PlacesService categories', () {
    test('한 번도 저장한 적 없으면 기본 예시 카테고리를 반환한다', () async {
      final service = PlacesService();
      final categories = await service.loadCategories();
      expect(categories, isNotEmpty);
    });

    test('저장 후 그대로 불러온다', () async {
      final service = PlacesService();
      await service.saveCategories(['헬멧샵', '주유소']);

      final categories = await service.loadCategories();

      expect(categories, ['헬멧샵', '주유소']);
    });

    test('사용자가 전부 삭제하면(빈 리스트 저장) 기본값으로 되돌아가지 않는다', () async {
      final service = PlacesService();
      await service.saveCategories([]);

      final categories = await service.loadCategories();

      expect(categories, isEmpty);
    });
  });
}
