import 'dart:convert';
import '../models/saved_route.dart';

class RouteShareService {
  static String encodeRoute(SavedRoute route) {
    if (route.points.isEmpty) return '';

    final first = route.points.first;
    final last = route.points.last;

    final wpsJson = jsonEncode([
      {
        'n': '',
        'la': double.parse(first.lat.toStringAsFixed(5)),
        'lo': double.parse(first.lng.toStringAsFixed(5)),
      },
      {
        'n': '',
        'la': double.parse(last.lat.toStringAsFixed(5)),
        'lo': double.parse(last.lng.toStringAsFixed(5)),
      },
    ]);

    final wps = base64Url.encode(utf8.encode(wpsJson));
    return 'yurunavi://route?type=${route.type.index}&wps=$wps';
  }

  static SavedRoute? decodeRoute(String url) {
    try {
      if (!url.startsWith('yurunavi://route')) return null;

      final uri = Uri.parse(url);
      final typeStr = uri.queryParameters['type'];
      final wpsStr = uri.queryParameters['wps'];

      if (typeStr == null || wpsStr == null) return null;

      final typeIndex = int.tryParse(typeStr);
      if (typeIndex == null || typeIndex < 0 || typeIndex >= RouteType.values.length) {
        return null;
      }

      final decoded = utf8.decode(base64Url.decode(wpsStr));
      final list = jsonDecode(decoded) as List<dynamic>;

      final points = list.map((e) {
        final m = e as Map<String, dynamic>;
        return RoutePoint(
          (m['la'] as num).toDouble(),
          (m['lo'] as num).toDouble(),
        );
      }).toList();

      return SavedRoute(
        id: '',
        name: '',
        points: points,
        type: RouteType.values[typeIndex],
        savedAt: DateTime.now(),
        distanceKm: 0,
      );
    } catch (_) {
      return null;
    }
  }
}
