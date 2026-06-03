import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_place.dart';

/// 즐겨찾기 장소 + 최근 경로 로컬 저장소 (SharedPreferences 기반).
class PlacesService {
  static const _favKey = 'favorite_places_v1';
  static const _recentKey = 'recent_routes_v1';
  static const _maxRecent = 5;

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
}
