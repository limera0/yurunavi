import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// OSRM public-demo routing client.
///
/// Calls the project-osrm `driving` profile with `alternatives=true` so the
/// three course cards (시골길·지방도로·국도) can each render a distinct
/// road-snapped polyline. Returns an empty list on any network / parse error
/// — callers decide whether to render nothing or fall back.
class RoutingService {
  static const _osrmBase = 'https://router.project-osrm.org/route/v1/driving';

  /// Returns up to N alternative polylines (each road-snapped) for the given
  /// origin → waypoints → destination sequence. Index 0 is the OSRM primary
  /// route; subsequent entries are alternatives when OSRM provides them.
  static Future<List<List<LatLng>>> fetchRoutes({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    // OSRM coord format is lon,lat (not lat,lon).
    final coords = [origin, ...waypoints, destination]
        .map((p) =>
            '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');
    final uri = Uri.parse(
      '$_osrmBase/$coords'
      '?overview=full&geometries=geojson&alternatives=true&steps=false',
    );

    try {
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        dev.log('OSRM ${resp.statusCode}: ${resp.body}',
            name: 'RoutingService');
        return const [];
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = (body['routes'] as List?) ?? const [];
      return routes.map<List<LatLng>>((r) {
        final geom = r['geometry'] as Map<String, dynamic>;
        final coords = (geom['coordinates'] as List).cast<List>();
        return coords
            .map<LatLng>((c) => LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ))
            .toList(growable: false);
      }).toList();
    } catch (e) {
      dev.log('OSRM fetch failed: $e', name: 'RoutingService');
      return const [];
    }
  }
}
