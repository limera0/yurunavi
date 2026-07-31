import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_place.dart';

/// 즐겨찾기 장소 + 최근 경로 로컬 저장소 (SharedPreferences 기반).
class PlacesService {
  static const _favKey = 'favorite_places_v1';
  static const _recentKey = 'recent_routes_v1';
  static const _catKey = 'favorite_categories_v1';
  static const _maxRecent = 5;

  /// 카테고리 화면을 한 번도 연 적 없는 사용자에게 보여줄 기본 예시 목록.
  /// 사용자가 전부 삭제하면(키는 존재하되 빈 리스트) 그 상태를 그대로 존중한다.
  static const List<String> _defaultCategories = ['집', '회사', '맛집'];

  // ── Favorites ─────────────────────────────────────────────────────────────

  Future<List<FavoritePlace>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favKey) ?? [];
    return raw
        .map((s) => FavoritePlace.fromJsonString(s))
        .toList()
        .reversed
        .toList();
  }

  Future<void> addFavorite(FavoritePlace place) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favKey) ?? [];
    raw.add(place.toJsonString());
    await prefs.setStringList(_favKey, raw);
  }

  Future<void> removeFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favKey) ?? [];
    raw.removeWhere((s) {
      try {
        return FavoritePlace.fromJsonString(s).id == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_favKey, raw);
  }

  /// [from] 카테고리로 저장된 즐겨찾기를 전부 [to]로 재배정한다(카테고리 삭제
  /// 시 미분류로 이동시키는 용도). `loadFavorites()`와 달리 저장 순서를
  /// 뒤집지 않고 raw 문자열 리스트를 그대로 순회·재저장해 원본 저장 순서를
  /// 보존한다 — 표시용으로 뒤집힌 리스트를 다시 저장하면 순서가 오염된다.
  Future<void> reassignFavoriteCategory(String from, String to) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favKey) ?? [];
    final updated = raw.map((s) {
      try {
        final place = FavoritePlace.fromJsonString(s);
        if (place.category != from) return s;
        return FavoritePlace(
          id: place.id,
          name: place.name,
          lat: place.lat,
          lng: place.lng,
          category: to,
        ).toJsonString();
      } catch (_) {
        return s;
      }
    }).toList();
    await prefs.setStringList(_favKey, updated);
  }

  // ── Recent routes ─────────────────────────────────────────────────────────

  Future<List<RecentRoute>> loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_recentKey) ?? [];
    return raw.map((s) => RecentRoute.fromJsonString(s)).toList().reversed.toList();
  }

  Future<void> addRecent(RecentRoute route) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_recentKey) ?? [];
    raw.add(route.toJsonString());
    // 최근 _maxRecent 개만 유지
    final trimmed = raw.length > _maxRecent ? raw.sublist(raw.length - _maxRecent) : raw;
    await prefs.setStringList(_recentKey, trimmed);
  }

  // ── Favorite categories (설정 > 즐겨찾기 카테고리) ───────────────────────────

  Future<List<String>> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_catKey)) {
      return List<String>.from(_defaultCategories);
    }
    return prefs.getStringList(_catKey) ?? [];
  }

  Future<void> saveCategories(List<String> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_catKey, categories);
  }
}
