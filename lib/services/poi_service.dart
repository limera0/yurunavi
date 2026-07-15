import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';

/// 자체 호스팅 백엔드(navi.westinx.com)의 `/poi/nearby` 엔드포인트를 통해 5종 POI를
/// 조회하고 오모테나시 목적지 스냅 로직을 수행하는 서비스. 카테고리 필터링 및 원본
/// 데이터 오분류 필터링은 서버(데이터 적재 시점)에서 이미 처리되어 온다.
class PoiService {
  static const _poiBaseUrl = 'https://navi.westinx.com/poi/nearby';

  /// PoiType ↔ 서버 카테고리 문자열(snake_case) 매핑.
  static const Map<PoiType, String> _typeToCategory = {
    PoiType.cafe: 'cafe',
    PoiType.convenienceStore: 'convenience_store',
    PoiType.gasStation: 'gas_station',
    PoiType.supermarket: 'supermarket',
    PoiType.restaurant: 'restaurant',
  };

  static final Map<String, PoiType> _categoryToType = {
    for (final entry in _typeToCategory.entries) entry.value: entry.key,
  };

  /// 카테고리 표시 우선순위: 주유소>편의점>카페>대형마트>식당 (요청 원문의 "전통시장"은
  /// 이 API에 대응 카테고리가 없어 스코프 밖 — 식당을 최하위로 대체).
  static const List<PoiType> displayPriority = [
    PoiType.gasStation,
    PoiType.convenienceStore,
    PoiType.cafe,
    PoiType.supermarket,
    PoiType.restaurant,
  ];

  // ── POI API 헬퍼 ────────────────────────────────────────────

  /// LatLng 중심, 반경(m)에 해당하는 특정 타입들의 POI를 가져온다.
  ///
  /// 서버가 거리순 정렬·반경 필터링을 이미 처리해 응답하므로 요청 타입들을 한 번의
  /// HTTP GET으로 모아 보낸다.
  Future<List<Poi>> fetchPois({
    required LatLng center,
    required double radiusMeters,
    required List<PoiType> types,
  }) async {
    if (types.isEmpty) return [];

    final clampedRadius = max(0.0, radiusMeters);
    final categories = types.map((t) => _typeToCategory[t]).whereType<String>().toList();

    final query = <String, String>{
      'lat': center.latitude.toString(),
      'lon': center.longitude.toString(),
      'radius_m': clampedRadius.toStringAsFixed(0),
      'types': categories.join(','),
    };

    final uri = Uri.parse(_poiBaseUrl).replace(queryParameters: query);

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        debugPrint('YNAV_POI fetch failed status=${resp.statusCode}');
        return [];
      }

      final rawList = jsonDecode(resp.body) as List<dynamic>;
      return rawList
          .map((e) => _parseItem(e as Map<String, dynamic>))
          .whereType<Poi>()
          .toList();
    } catch (e) {
      // 네트워크 단절 시 "이 지역엔 POI가 없음"과 구분 불가능해 실기기 디버깅이 매우
      // 어려웠음(2026-07-13 확인) — 최소한의 로그로 향후 진단 가능하게 함.
      debugPrint('YNAV_POI fetch failed error=$e');
      return [];
    }
  }

  /// 뷰포트 사각형(south/west/north/east)에 해당하는 특정 타입들의 POI를 가져온다.
  ///
  /// 서버가 정확히 이 사각형 안의 결과만(반경 필터링 없이) 사각형 중심 기준
  /// 거리순으로 정렬해 응답하므로, 호출부는 반경으로 근사할 필요 없이 실제
  /// 화면 뷰포트를 그대로 넘기면 된다.
  Future<List<Poi>> fetchPoisInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
    required List<PoiType> types,
  }) async {
    if (types.isEmpty) return [];

    final categories = types.map((t) => _typeToCategory[t]).whereType<String>().toList();

    final query = <String, String>{
      'south': south.toString(),
      'west': west.toString(),
      'north': north.toString(),
      'east': east.toString(),
      'types': categories.join(','),
    };

    final uri = Uri.parse(_poiBaseUrl).replace(queryParameters: query);

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        debugPrint('YNAV_POI fetchInBounds failed status=${resp.statusCode}');
        return [];
      }

      final rawList = jsonDecode(resp.body) as List<dynamic>;
      return rawList
          .map((e) => _parseItem(e as Map<String, dynamic>))
          .whereType<Poi>()
          .toList();
    } catch (e) {
      debugPrint('YNAV_POI fetchInBounds failed error=$e');
      return [];
    }
  }

  Poi? _parseItem(Map<String, dynamic> item) {
    final id = item['id'] as String?;
    final name = item['name'] as String?;
    final categoryStr = item['category'] as String?;
    final lat = item['lat'];
    final lon = item['lon'];
    if (id == null || name == null || lat == null || lon == null) return null;

    final type = categoryStr == null ? null : _categoryToType[categoryStr];
    if (type == null) return null;

    return Poi(
      id: id,
      name: name,
      type: type,
      location: LatLng((lat as num).toDouble(), (lon as num).toDouble()),
      address: item['address'] as String?,
    );
  }

  // ── 거리 계산 ─────────────────────────────────────────────────

  static double haversineMeters(LatLng a, LatLng b) {
    const toRad = pi / 180.0;
    final dLat = (b.latitude - a.latitude) * toRad;
    final dLon = (b.longitude - a.longitude) * toRad;
    final sinHLat = sin(dLat / 2);
    final sinHLon = sin(dLon / 2);
    final h =
        sinHLat * sinHLat + cos(a.latitude * toRad) * cos(b.latitude * toRad) * (sinHLon * sinHLon);
    return 6371000 * 2 * asin(sqrt(h));
  }

  /// 두 점이 이루는 방위각(bearing) 계산 (degree)
  static double bearing(LatLng from, LatLng to) {
    const toRad = pi / 180.0;
    final dLon = (to.longitude - from.longitude) * toRad;
    final lat1 = from.latitude * toRad;
    final lat2 = to.latitude * toRad;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  /// 두 방위각의 절대 차이 (0~180)
  static double bearingDiff(double a, double b) {
    final diff = ((a - b).abs()) % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  // ── 상시(ambient) 표시 선정 로직 ─────────────────────────────────

  /// ambient POI 레이어(홈 지도 위 상시 점) 및 검색 시트의 지도 핀 레이어에서 공용으로
  /// 쓰는 "화면에 보여줄 N개 고르기" 로직.
  ///
  /// 단순 거리순 정렬만 쓰면(과거 방식) 화면 중심 근처에 우연히 몰려 있는 후보가
  /// 캡을 다 채워버려 사용자 눈엔 "랜덤하게" 보이고, 정작 화면 가장자리엔 아무 것도
  /// 안 뜨는 문제가 있었다(실주행 피드백). 이를 뷰포트를 grid로 나눠 라운드로빈으로
  /// 골고루 뽑는 방식으로 바꾸되, 각 grid cell 안에서는 카테고리 우선순위(주유소 >
  /// 편의점 > 카페 > 대형마트 > 식당)를 최우선, 거리를 tie-break로 적용해 "우선순위가
  /// 있어 보이면서도 화면 전체에 고르게 분포"하는 두 요구를 동시에 만족시킨다.
  // 1-2-5 시퀀스 "nice" 스텝 — [rawSizeDeg] 이상인 가장 작은 스텝으로 스냅한다.
  // 뷰포트 span이 팬으로 미세하게 달라져도(같은 줌 레벨이면 보통 같은 구간
  // 안에 머무름) 동일한 스텝으로 떨어져 셀 크기가 안정적으로 유지된다.
  static const List<double> _kCellSizeStepsDeg = [
    0.0005, 0.001, 0.002, 0.005,
    0.01, 0.02, 0.05,
    0.1, 0.2, 0.5,
    1.0, 2.0, 5.0,
  ];

  static double _snapCellSizeDeg(double rawSizeDeg) {
    for (final step in _kCellSizeStepsDeg) {
      if (rawSizeDeg <= step) return step;
    }
    return _kCellSizeStepsDeg.last;
  }

  static List<Poi> selectForAmbientDisplay({
    required List<Poi> candidates,
    required double south,
    required double north,
    required double west,
    required double east,
    required LatLng center,
    int maxCount = 20,
    int gridSize = 4,
  }) {
    if (candidates.isEmpty) return const [];

    int priorityIndex(Poi p) {
      final idx = displayPriority.indexOf(p.type);
      return idx < 0 ? displayPriority.length : idx;
    }

    int comparePriorityThenDistance(Poi a, Poi b) {
      final pa = priorityIndex(a);
      final pb = priorityIndex(b);
      if (pa != pb) return pa.compareTo(pb);
      return haversineMeters(center, a.location)
          .compareTo(haversineMeters(center, b.location));
    }

    final latSpan = (north - south).abs();
    final lonSpan = (east - west).abs();
    if (latSpan <= 0 || lonSpan <= 0) {
      final sorted = List<Poi>.from(candidates)
        ..sort(comparePriorityThenDistance);
      return sorted.take(maxCount).toList();
    }

    // 셀 "크기"는 현재 뷰포트 span에서 뽑아 줌 레벨에 맞게 적응시키되, "nice"
    // 스텝값(1-2-5 시퀀스)으로 스냅해 팬으로 span이 소수점 아래에서 미세하게
    // 흔들려도(부동소수점 오차 포함) 같은 줌 레벨에서는 항상 동일한 셀
    // 크기가 나오게 한다. 셀 "경계"도 뷰포트(south/west) 상대가 아니라
    // 절대 좌표를 셀 크기로 나눈 몫으로 고정한다. 뷰포트 상대 좌표+비스냅
    // 크기를 쓰면 팬만 해도 매 호출마다 그리드 원점/크기가 같이 흔들려,
    // 동일한 POI 집합인데도 어느 셀에 속하는지 매번 달라지고 그 결과
    // 라운드로빈에서 살아남는 POI가 뒤바뀐다 — 팬/줌 시 편의점이 사라지고
    // 없던 식당이 뜨는 현상으로 리포트됨(2026-07-15 밤 라이딩).
    final cellLatSize = _snapCellSizeDeg(latSpan / gridSize);
    final cellLonSize = _snapCellSizeDeg(lonSpan / gridSize);
    final cells = <(int, int), List<Poi>>{};
    for (final poi in candidates) {
      final row = (poi.location.latitude / cellLatSize).floor();
      final col = (poi.location.longitude / cellLonSize).floor();
      (cells[(row, col)] ??= []).add(poi);
    }
    for (final cell in cells.values) {
      cell.sort(comparePriorityThenDistance);
    }

    final result = <Poi>[];
    var round = 0;
    while (result.length < maxCount) {
      var pickedAny = false;
      for (final cell in cells.values) {
        if (round >= cell.length) continue;
        result.add(cell[round]);
        pickedAny = true;
        if (result.length >= maxCount) break;
      }
      if (!pickedAny) break;
      round++;
    }

    return result.take(maxCount).toList();
  }

  // ── 오모테나시 스냅 로직 ───────────────────────────────────────

  /// 반환값: (스냅된 POI 또는 null, 사용된 반경km, 모든 POI 목록)
  Future<SnapResult> snapDestination({
    required LatLng origin,
    required LatLng tapped,
    double radiusKm = 1.0,
  }) async {
    final radiusM = radiusKm * 1000;

    // 1. 반경 내 모든 POI 수집
    final allPois = await fetchPois(
      center: tapped,
      radiusMeters: radiusM,
      types: PoiType.values,
    );

    // Step A: 반경 내 카페 중 가장 평점 높은 것
    final cafes = allPois.where((p) => p.type == PoiType.cafe).toList()
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

    if (cafes.isNotEmpty) {
      return SnapResult(
        snappedPoi: cafes.first,
        allPois: allPois,
        radiusKm: radiusKm,
      );
    }

    // Step B: 현재 주행 방향에 인접(±45°)한 편의점 탐색
    final headingBearing = bearing(origin, tapped);
    final convStores = allPois.where((p) => p.type == PoiType.convenienceStore).toList();

    final sameSide = convStores
        .where((p) => bearingDiff(bearing(tapped, p.location), headingBearing) <= 45)
        .toList()
      ..sort((a, b) => haversineMeters(tapped, a.location).compareTo(haversineMeters(tapped, b.location)));

    if (sameSide.isNotEmpty) {
      return SnapResult(
        snappedPoi: sameSide.first,
        allPois: allPois,
        radiusKm: radiusKm,
      );
    }

    // Step C: 반대편(길 건너) 편의점 - 방향차 > 45°인 가장 가까운 편의점
    final otherSide = convStores
        .where((p) => bearingDiff(bearing(tapped, p.location), headingBearing) > 45)
        .toList()
      ..sort((a, b) => haversineMeters(tapped, a.location).compareTo(haversineMeters(tapped, b.location)));

    if (otherSide.isNotEmpty) {
      return SnapResult(
        snappedPoi: otherSide.first,
        allPois: allPois,
        radiusKm: radiusKm,
      );
    }

    // 카페/편의점 없음 -> null 반환 (팝업 트리거)
    return SnapResult(
      snappedPoi: null,
      allPois: allPois,
      radiusKm: radiusKm,
    );
  }
}

class SnapResult {
  final Poi? snappedPoi;
  final List<Poi> allPois;
  final double radiusKm;

  const SnapResult({
    required this.snappedPoi,
    required this.allPois,
    required this.radiusKm,
  });
}

/// [PoiRegionCache]가 보관하는 단일 조회 결과. "어느 사각형+타입 조합을,
/// 언제, 어떤 결과로" 가져왔는지를 담는다.
class _PoiRegionCacheEntry {
  final double south;
  final double west;
  final double north;
  final double east;
  final Set<PoiType> types;
  final DateTime fetchedAt;
  final List<Poi> pois;

  _PoiRegionCacheEntry({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.types,
    required this.fetchedAt,
    required this.pois,
  });
}

/// "이 사각형 영역+타입 조합의 POI를 이미 최근에 가져왔는가"를 판단해
/// 불필요한 네트워크 재조회(뷰포트를 벗어났다가 금방 되돌아오는 패닝 등)를
/// 막기 위한 화면(State) 소유 캐시. 전역 싱글톤이 아니며, 각 화면이 자신의
/// 인스턴스를 필드로 들고 있는다.
///
/// 캐시 적중 조건: 만료(TTL) 전이고, 저장된 항목의 타입 집합이 요청 타입의
/// 상위집합(superset)이며, 저장된 항목의 영역이 요청 영역을 완전히 포함할 때.
/// 적중 시 저장된(더 넓을 수 있는) 결과를 요청 영역/타입으로 다시 필터링해
/// 반환한다 — 서버가 좁은 요청에 응답했을 결과와 동일한 모양을 보장한다.
///
/// ⚠️ 이 "포함 관계면 재사용 가능" 전제는 저장된 응답이 해당 영역의 *전체*
/// 결과일 때만 성립한다. 서버(`native/src/main.rs`의 `MAX_POI_RESULTS`, 현재
/// 500)가 거리순 상위 N개로 응답을 자르므로, 잘렸을 가능성이 있는 응답을
/// 그대로 캐싱해 더 좁은 영역에 재사용하면 원래 영역 중심에서 먼 가장자리
/// 쪽 POI가 실제로는 있는데도 조용히 빠질 수 있다(2026-07-15 감사에서 발견 —
/// 서버 응답 개수가 [_serverCapHeuristic] 이상이면 잘렸을 수 있다고 보고 아예
/// 캐싱하지 않는다: 이 경우 매번 새로 조회하게 되어 캐시 이득은 줄지만
/// 정확성이 더 중요하다).
class PoiRegionCache {
  PoiRegionCache({int capacity = 8, DateTime Function()? now})
      : _capacity = capacity,
        _now = now ?? DateTime.now;

  static const Duration ttl = Duration(minutes: 5);

  /// 서버 `MAX_POI_RESULTS`(native/src/main.rs)와 반드시 일치시켜야 하는 값.
  /// 응답 개수가 이 값 이상이면 "거리순 상위 N개로 잘렸을 수 있다"로 간주해
  /// 캐싱을 건너뛴다(완전한 응답이라는 보장이 없는 걸 재사용하지 않기 위함).
  static const int _serverCapHeuristic = 500;

  final int _capacity;
  final DateTime Function() _now;
  final List<_PoiRegionCacheEntry> _entries = [];

  List<Poi>? tryGet({
    required double south,
    required double west,
    required double north,
    required double east,
    required Set<PoiType> types,
  }) {
    final nowTs = _now();
    // 가장 최근에 추가된 항목부터 살펴본다 — 여러 항목이 조건을 만족하면
    // 최신 것을 우선한다(entries는 항상 추가 순 = 시간순으로 쌓인다).
    for (final entry in _entries.reversed) {
      if (nowTs.difference(entry.fetchedAt) >= ttl) continue;
      if (!types.every(entry.types.contains)) continue;
      final containsRegion = entry.south <= south &&
          entry.north >= north &&
          entry.west <= west &&
          entry.east >= east;
      if (!containsRegion) continue;

      return entry.pois
          .where((p) =>
              types.contains(p.type) &&
              p.location.latitude >= south &&
              p.location.latitude <= north &&
              p.location.longitude >= west &&
              p.location.longitude <= east)
          .toList();
    }
    return null;
  }

  void put({
    required double south,
    required double west,
    required double north,
    required double east,
    required Set<PoiType> types,
    required List<Poi> pois,
  }) {
    // 잘렸을 수 있는 응답은 이 영역의 "전체 결과"라고 보장할 수 없으므로
    // 캐싱하지 않는다 — 다음 요청은 그냥 네트워크로 다시 나간다.
    if (pois.length >= _serverCapHeuristic) return;

    if (_entries.length >= _capacity) {
      _entries.removeAt(0); // 가장 오래된(맨 앞) 항목을 제거
    }
    _entries.add(_PoiRegionCacheEntry(
      south: south,
      west: west,
      north: north,
      east: east,
      types: types,
      fetchedAt: _now(),
      pois: pois,
    ));
  }
}
