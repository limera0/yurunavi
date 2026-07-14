import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';

/// 공공데이터포털 소상공인시장진흥공단 상가(상권)정보 API(storeListInRadius)를 통해
/// 5종 POI를 실시간 수집하고 오모테나시 목적지 스냅 로직을 수행하는 서비스.
class PoiService {
  static const _semasBaseUrl =
      'https://apis.data.go.kr/B553077/api/open/sdsc2/storeListInRadius';

  /// 컴파일타임 주입 서비스키 (--dart-define-from-file=env.json).
  /// analyze/test 시에는 빈 문자열이 되는 게 정상 동작 — fallback/에러처리 추가하지 말 것.
  static const _serviceKey = String.fromEnvironment('SEMAS_SERVICE_KEY');

  /// 카테고리 → 업종코드(대/중/소분류) 매핑. restaurant는 indsMclsCd 없이
  /// 대분류(I2) 전체를 받아 클라이언트에서 필터링한다 (API가 중분류 다중선택 미지원).
  static const Map<PoiType, Map<String, String>> _categoryCodes = {
    PoiType.cafe: {
      'indsLclsCd': 'I2',
      'indsMclsCd': 'I212',
      'indsSclsCd': 'I21201',
    },
    PoiType.convenienceStore: {
      'indsLclsCd': 'G2',
      'indsMclsCd': 'G204',
      'indsSclsCd': 'G20405',
    },
    PoiType.gasStation: {
      'indsLclsCd': 'G2',
      'indsMclsCd': 'G214',
      'indsSclsCd': 'G21401',
    },
    PoiType.supermarket: {
      'indsLclsCd': 'G2',
      'indsMclsCd': 'G204',
      'indsSclsCd': 'G20404',
    },
    PoiType.restaurant: {
      'indsLclsCd': 'I2',
    },
  };

  /// restaurant(I2 대분류) 응답 중 "식당"으로 취급하지 않는 중분류
  /// (구내식당/출장음식/이동음식/기타간이/주점/카페).
  static const Set<String> _restaurantExcludeMcls = {
    'I207', 'I208', 'I209', 'I210', 'I211', 'I212',
  };

  /// 소상공인시장진흥공단 원본 데이터가 업종을 잘못 분류해 넣은 케이스를 걸러내는
  /// 업소명 키워드 휴리스틱(2026-07-14 실주행 피드백: 카페 소분류에 "할매국물닭발",
  /// 주유소/카페 소분류에 "OO협동조합" 등이 섞여 나옴 — API 자체 재확인 결과 우리
  /// 쪽 쿼리 코드는 정확했고 원본 데이터의 오분류로 확인됨). 완벽하게 걸러내진
  /// 못하는 휴리스틱이지만("아예 안 거르는 것보단 낫다") 명백한 오분류는 줄여준다.
  ///
  /// 어떤 카테고리든 실제 소비자 대상 매장이 아닌 행정/사업체성 명칭.
  /// 감사에서 "'조합'이 '영농조합법인' 같은 정식 법인명에 포함돼 시골 특산물
  /// 식당까지 걸러낼 수 있다"는 우려가 제기됐으나, 실제로 그런 정식 법인명
  /// 자체를 간판/상호로 쓰는 식당은 없다는 사용자 확인(2026-07-14)에 따라
  /// '조합'을 그대로 포함한다. '연구소'는 "OO커피연구소"류 카페 브랜딩에 실제
  /// 흔히 쓰이는 표현이라 계속 제외.
  static const List<String> _nonStorefrontKeywords = [
    '협동조합', '협회', '조합', '컨설팅', '사무소', '재단',
  ];

  /// 카페(cafe) 소분류에 섞여 들어오는 식당류 업소명 키워드.
  static const List<String> _cafeRestaurantKeywords = [
    '닭발', '곱창', '국밥', '삼겹살', '갈비', '냉면', '순대', '족발', '보쌈',
    '횟집', '참치', '감자탕', '해장국', '추어탕', '매운탕', '닭갈비', '곰탕',
    '설렁탕', '육개장', '삼계탕', '육회',
  ];

  /// [name]이 [type] 카테고리로 분류되기엔 업소명상 명백히 어색한지 판정한다.
  static bool looksMisclassified(String name, PoiType type) {
    for (final kw in _nonStorefrontKeywords) {
      if (name.contains(kw)) return true;
    }
    if (type == PoiType.cafe) {
      for (final kw in _cafeRestaurantKeywords) {
        if (name.contains(kw)) return true;
      }
    }
    return false;
  }

  /// 카테고리 표시 우선순위: 주유소>편의점>카페>대형마트>식당 (요청 원문의 "전통시장"은
  /// 이 API에 대응 카테고리가 없어 스코프 밖 — 식당을 최하위로 대체).
  static const List<PoiType> displayPriority = [
    PoiType.gasStation,
    PoiType.convenienceStore,
    PoiType.cafe,
    PoiType.supermarket,
    PoiType.restaurant,
  ];

  // ── 공공데이터포털 API 헬퍼 ────────────────────────────────────

  /// LatLng 중심, 반경(m)에 해당하는 특정 타입들의 POI를 가져온다.
  ///
  /// 호출부 기본값은 1500m(2000m 미만 여유있게) 권장 — 이 API는 결과를 거리순으로
  /// 정렬해주지 않고, 반경을 넓게+필터 없이 잡으면 서울 도심에서 500m만으로도
  /// 800건대가 나올 만큼 조밀해서 정말 가까운 곳이 응답 앞쪽에 없을 수 있다(API 자체 한계,
  /// numOfRows=500과의 조합으로 완화만 가능, 완전 해결 불가).
  Future<List<Poi>> fetchPois({
    required LatLng center,
    required double radiusMeters,
    required List<PoiType> types,
  }) async {
    // API 최대 반경은 2000m.
    final clampedRadius = radiusMeters.clamp(0, 2000).toDouble();

    final results = await Future.wait(
      types.map((t) => _fetchOne(center: center, radiusMeters: clampedRadius, type: t)),
    );

    return results.expand((list) => list).toList();
  }

  Future<List<Poi>> _fetchOne({
    required LatLng center,
    required double radiusMeters,
    required PoiType type,
  }) async {
    final codes = _categoryCodes[type] ?? const {};
    final query = <String, String>{
      'serviceKey': _serviceKey,
      'radius': radiusMeters.toStringAsFixed(0),
      'cx': center.longitude.toString(),
      'cy': center.latitude.toString(),
      'type': 'json',
      'numOfRows': '500',
      'pageNo': '1',
      ...codes,
    };

    final uri = Uri.parse(_semasBaseUrl).replace(queryParameters: query);

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        debugPrint('YNAV_POI fetch failed type=$type status=${resp.statusCode}');
        return [];
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final header = json['header'] as Map<String, dynamic>?;
      if (header != null && header['resultCode'] != '00') return [];

      final body = json['body'] as Map<String, dynamic>?;
      final rawItems = body?['items'];
      if (rawItems == null) return [];
      final items = rawItems is List ? rawItems : [rawItems];

      return items
          .map((e) => _parseItem(e as Map<String, dynamic>, type))
          .whereType<Poi>()
          .toList();
    } catch (e) {
      // 네트워크 단절 시 "이 지역엔 POI가 없음"과 구분 불가능해 실기기 디버깅이 매우
      // 어려웠음(2026-07-13 확인) — 최소한의 로그로 향후 진단 가능하게 함.
      debugPrint('YNAV_POI fetch failed type=$type error=$e');
      return [];
    }
  }

  Poi? _parseItem(Map<String, dynamic> item, PoiType type) {
    final indsMclsCd = item['indsMclsCd'] as String?;

    // restaurant는 대분류(I2) 전체를 받아왔으므로 카페 등 제외 중분류를 걸러낸다.
    if (type == PoiType.restaurant &&
        indsMclsCd != null &&
        _restaurantExcludeMcls.contains(indsMclsCd)) {
      return null;
    }

    final lat = item['lat'];
    final lon = item['lon'];
    if (lat == null || lon == null) return null;

    final id = item['bizesId'] as String?;
    if (id == null) return null;

    final name = (item['bizesNm'] as String?) ?? '이름 없음';
    if (looksMisclassified(name, type)) return null;
    // rdnmAdr가 null이 아니라 빈 문자열로 오는 업소도 있어 isNotEmpty까지 확인해야 지번주소로
    // 정상 폴백한다.
    final rdnmAdr = item['rdnmAdr'] as String?;
    final address = (rdnmAdr != null && rdnmAdr.isNotEmpty)
        ? rdnmAdr
        : item['lnoAdr'] as String?;

    return Poi(
      id: id,
      name: name,
      type: type,
      location: LatLng((lat as num).toDouble(), (lon as num).toDouble()),
      address: address,
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

    final cells = <int, List<Poi>>{};
    for (final poi in candidates) {
      final row = ((poi.location.latitude - south) / latSpan * gridSize)
          .floor()
          .clamp(0, gridSize - 1);
      final col = ((poi.location.longitude - west) / lonSpan * gridSize)
          .floor()
          .clamp(0, gridSize - 1);
      final key = row * gridSize + col;
      (cells[key] ??= []).add(poi);
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
