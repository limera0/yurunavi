import 'dart:convert';

/// 사용자가 저장한 즐겨찾기 장소 (예: 집).
class FavoritePlace {
  final String id;
  final String name;
  final double lat;
  final double lng;

  const FavoritePlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'lat': lat, 'lng': lng};

  factory FavoritePlace.fromJson(Map<String, dynamic> j) => FavoritePlace(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );

  String toJsonString() => jsonEncode(toJson());
  factory FavoritePlace.fromJsonString(String s) =>
      FavoritePlace.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// 최근 주행 경로 (출발-도착 쌍).
class RecentRoute {
  final String id;
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;
  final String? destName;
  final DateTime at;

  const RecentRoute({
    required this.id,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    this.destName,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'originLat': originLat,
        'originLng': originLng,
        'destLat': destLat,
        'destLng': destLng,
        if (destName != null) 'destName': destName,
        'at': at.toIso8601String(),
      };

  factory RecentRoute.fromJson(Map<String, dynamic> j) => RecentRoute(
        id: j['id'] as String,
        originLat: (j['originLat'] as num).toDouble(),
        originLng: (j['originLng'] as num).toDouble(),
        destLat: (j['destLat'] as num).toDouble(),
        destLng: (j['destLng'] as num).toDouble(),
        destName: j['destName'] as String?,
        at: DateTime.parse(j['at'] as String),
      );

  String toJsonString() => jsonEncode(toJson());
  factory RecentRoute.fromJsonString(String s) =>
      RecentRoute.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
