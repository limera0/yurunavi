import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// 오프라인 지명 인덱스 1건 (assets/data/kr_places.json 레코드).
class ExitLandmarkPlace {
  final String name;
  final int classPriority; // city=0, town=1, village=2, 그외=9
  final double lat;
  final double lon;
  const ExitLandmarkPlace({
    required this.name,
    required this.classPriority,
    required this.lat,
    required this.lon,
  });
}

/// OSM `sign.exit_name_elements`가 없는 출구 maneuver에서 발화할 인근 지명을
/// 오프라인 데이터(assets/data/kr_places.json, korea.mbtiles place 레이어에서
/// 빌드 시점 추출됨 — scripts/build_place_index.py)에서 찾는다.
class ExitLandmarkService {
  final List<ExitLandmarkPlace> places;
  static const _distance = Distance();
  static const _classPriority = {'city': 0, 'town': 1, 'village': 2};

  const ExitLandmarkService(this.places);

  static Future<ExitLandmarkService> load(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final data = jsonDecode(raw) as List<dynamic>;
    final places = data.map((e) {
      final m = e as Map<String, dynamic>;
      return ExitLandmarkPlace(
        name: m['name'] as String,
        classPriority: _classPriority[m['class'] as String] ?? 9,
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
      );
    }).toList();
    return ExitLandmarkService(places);
  }

  /// [point] 기준 [radiusKm] 이내 후보 중 class 우선(city>town>village),
  /// 동급이면 최근접 지명을 반환. 후보 없으면 null.
  String? nearestLandmark(LatLng point, {double radiusKm = 3.0}) {
    ExitLandmarkPlace? best;
    double bestDistKm = double.infinity;
    for (final p in places) {
      final d = _distance.as(LengthUnit.Kilometer, point, LatLng(p.lat, p.lon));
      if (d > radiusKm) continue;
      final better = best == null ||
          p.classPriority < best.classPriority ||
          (p.classPriority == best.classPriority && d < bestDistKm);
      if (better) {
        best = p;
        bestDistKm = d;
      }
    }
    return best?.name;
  }
}
