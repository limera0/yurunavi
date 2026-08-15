import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_route.dart';
import 'native_engine.dart';

class RouteService {
  static const _key = 'saved_routes_v1';

  Future<List<SavedRoute>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.map((s) => SavedRoute.fromJsonString(s)).toList();
  }

  Future<void> saveAll(List<SavedRoute> routes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, routes.map((r) => r.toJsonString()).toList());
  }

  Future<void> add(SavedRoute route) async {
    final all = await loadAll();
    all.add(route);
    await saveAll(all);
  }

  Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((r) => r.id == id);
    await saveAll(all);
  }

  // ── 경로 유사도: NativeEngine (Rust fallback Dart 구현) ───

  static SimilarityResult checkSimilarity(SavedRoute a, SavedRoute b) {
    final ptsA = a.points.map((p) => GpsPoint(p.lat, p.lng)).toList();
    final ptsB = b.points.map((p) => GpsPoint(p.lat, p.lng)).toList();
    return NativeEngine.checkRouteSimilarity(ptsA, ptsB);
  }

  static List<({SavedRoute route, double sim})> findSimilar(
    SavedRoute candidate,
    List<SavedRoute> existing, {
    double threshold = 0.70,
  }) {
    final results = <({SavedRoute route, double sim})>[];
    for (final r in existing) {
      final result = checkSimilarity(candidate, r);
      if (result.score >= threshold) {
        results.add((route: r, sim: result.score));
      }
    }
    results.sort((a, b) => b.sim.compareTo(a.sim));
    return results;
  }

}
