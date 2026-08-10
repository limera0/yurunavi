import 'dart:convert';

/// 카테고리를 지정하지 않았거나(구버전 데이터 포함) 삭제된 카테고리를 가리키던
/// 즐겨찾기의 기본 카테고리명. 설정 화면의 사용자 카테고리 목록과 별개로 항상
/// 선택 가능한 값으로 취급한다.
const String kUncategorizedFavoriteCategory = '미분류';

/// 위경도 비교 시 "같은 장소"로 볼 오차 범위(도 단위, 약 5m).
const double _kFavoriteLocationEpsilon = 0.00005;

/// 사용자가 저장한 즐겨찾기 장소 (예: 집).
class FavoritePlace {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String category;

  const FavoritePlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.category = kUncategorizedFavoriteCategory,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'lat': lat, 'lng': lng, 'category': category};

  factory FavoritePlace.fromJson(Map<String, dynamic> j) => FavoritePlace(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        // 필드 추가 이전에 저장된 데이터에는 category 키가 없으므로 누락 시
        // 미분류로 취급해 크래시 없이 로드되도록 한다.
        category: (j['category'] as String?) ?? kUncategorizedFavoriteCategory,
      );

  String toJsonString() => jsonEncode(toJson());
  factory FavoritePlace.fromJsonString(String s) =>
      FavoritePlace.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// [favorites] 중 (lat, lng)와 같은 장소로 볼 수 있는 항목을 찾는다. 검색
  /// 결과 카드의 ☆/★ 표시 여부를 판단하는 데 사용 — 두 좌표가 부동소수점
  /// 오차 없이 정확히 일치할 필요는 없으므로 작은 허용오차로 비교한다.
  static FavoritePlace? findByLocation(
    Iterable<FavoritePlace> favorites,
    double lat,
    double lng,
  ) {
    for (final f in favorites) {
      if ((f.lat - lat).abs() < _kFavoriteLocationEpsilon &&
          (f.lng - lng).abs() < _kFavoriteLocationEpsilon) {
        return f;
      }
    }
    return null;
  }
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

/// 검색 이력 항목.
class SearchHistoryItem {
  final String query;      // 검색어 또는 선택된 장소명
  final double? lat;       // 선택된 결과 좌표 (null이면 검색어만 저장)
  final double? lng;
  final String type;       // 'address' | 'poi'
  final DateTime timestamp;

  const SearchHistoryItem({
    required this.query,
    this.lat,
    this.lng,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'query': query,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
      };

  factory SearchHistoryItem.fromJson(Map<String, dynamic> j) => SearchHistoryItem(
        query: j['query'] as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        type: (j['type'] as String?) ?? 'address',
        timestamp: DateTime.parse(j['timestamp'] as String),
      );

  String toJsonString() => jsonEncode(toJson());
  factory SearchHistoryItem.fromJsonString(String s) =>
      SearchHistoryItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
