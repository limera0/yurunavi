import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/config/app_config.dart';

import '../models/poi.dart';

/// 자체 호스팅 백엔드(navi.westinx.com)의 `/poi/nearby` 엔드포인트를 통해 5종 POI를
/// 조회하고 오모테나시 목적지 스냅 로직을 수행하는 서비스. 카테고리 필터링 및 원본
/// 데이터 오분류 필터링은 서버(데이터 적재 시점)에서 이미 처리되어 온다.
///
/// [fetchPois] / [fetchPoisInBounds]는 실패(비200 응답·네트워크 예외·서킷 오픈)
/// 시 빈 리스트가 아니라 [PoiFetchException]을 던진다 — 네트워크 실패와 "결과
/// 0건"을 구분하지 못해 실기기 디버깅이 어려웠던 기지 결함(2026-07-13 확인) 해결.
/// 빈 리스트 반환은 이제 "진짜로 결과 0건"만 의미한다.
///
/// 이 인스턴스는 `map_providers.dart`의 `poiServiceProvider`를 통해 앱 전역에 1개만
/// 존재한다(Provider 캐시) — 429 서킷브레이커 상태를 인스턴스 필드로 두는 이유.
class PoiService {
  PoiService({
    http.Client Function()? clientFactory,
    DateTime Function()? now,
  })  : _clientFactory = clientFactory ?? (() => http.Client()),
        _now = now ?? DateTime.now;

  static String get _poiBaseUrl => '${AppConfig.instance.naviBaseUrl}/poi/nearby';

  final http.Client Function() _clientFactory;
  final DateTime Function() _now;

  /// 요청 타임아웃 — 주행 중 10초 지난 POI 응답은 이미 무가치하고, 라디오
  /// 점유 시간을 줄이기 위해 기존 30초에서 단축(2026-08-05 S2).
  static const Duration _timeout = Duration(seconds: 10);

  // ── in-flight 취소(태그별 client) ────────────────────────────────
  // 같은 태그로 새 요청이 시작되면 직전 요청의 HTTP client를 강제로 close()해
  // 응답이 stale이 됐는데도 대역폭·라디오를 계속 점유하는 걸 막는다. 태그 없는
  // 호출(tag: null)은 매번 새 client를 쓰고 저장하지 않는다(전역 취소 사고 방지).
  final Map<String, _CancelToken> _taggedClients = {};

  // ── 429/5xx 서킷브레이커 ────────────────────────────────────────
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenUntil;
  static const int _maxBackoffSeconds = 60;
  static const int _maxRetryAfterSeconds = 300; // 5분 상한

  bool _circuitOpen(DateTime now) {
    final openUntil = _circuitOpenUntil;
    return openUntil != null && now.isBefore(openUntil);
  }

  void _onFailure(DateTime now, {int? retryAfterSeconds}) {
    final wasClosed = _consecutiveFailures == 0;
    _consecutiveFailures++;
    final int backoffSeconds;
    if (retryAfterSeconds != null) {
      backoffSeconds = min(retryAfterSeconds, _maxRetryAfterSeconds);
    } else {
      // 1 → 2 → 4 → 8 → 16 → 32 → 60(상한) 초.
      final exp = _consecutiveFailures - 1;
      final raw = exp >= 6 ? 1 << 6 : 1 << exp; // 오버플로 방지용 상한 클램프
      backoffSeconds = min(raw, _maxBackoffSeconds);
    }
    _circuitOpenUntil = now.add(Duration(seconds: backoffSeconds));
    // 상태 전이(닫힘→열림) 시에만 로그 — 매 실패마다 찍으면 S1에서 겪은 로그
    // 폭주(발열·배터리)를 반복한다.
    if (wasClosed) {
      debugPrint('YNAV_POI circuit open backoff=${backoffSeconds}s');
    }
  }

  void _onSuccess() {
    final wasOpen = _consecutiveFailures > 0;
    _consecutiveFailures = 0;
    _circuitOpenUntil = null;
    if (wasOpen) {
      debugPrint('YNAV_POI circuit closed');
    }
  }

  int? _parseRetryAfterSeconds(String? headerValue) {
    if (headerValue == null) return null;
    final parsed = int.tryParse(headerValue.trim());
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  /// GET 요청 1회를 서킷브레이커·in-flight 취소·타임아웃 정책과 함께 수행하고
  /// 성공 시 응답 바디(JSON 문자열)를 반환한다. 실패 시 항상 [PoiFetchException]을
  /// 던진다(빈 리스트로 뭉개지 않는다).
  Future<String> _getJson(Uri uri, {String? tag}) async {
    final startedAt = _now();
    if (_circuitOpen(startedAt)) {
      // 서킷이 열린 동안은 HTTP 요청을 아예 만들지 않는다 — 폭주를 막는
      // 마지막 물리적 벽. 여기선 상태 전이가 아니므로 로그를 남기지 않는다.
      throw const PoiFetchException(circuitOpen: true, message: 'circuit open');
    }

    _CancelToken? myToken;
    final http.Client client;
    if (tag != null) {
      _taggedClients[tag]?.cancel();
      myToken = _CancelToken(_clientFactory());
      _taggedClients[tag] = myToken;
      client = myToken.client;
    } else {
      client = _clientFactory();
    }

    try {
      final resp = await client
          .get(uri, headers: {'X-Api-Key': AppConfig.instance.naviApiKey})
          .timeout(_timeout);

      if (resp.statusCode != 200) {
        if (resp.statusCode == 429 || resp.statusCode >= 500) {
          final retryAfter = _parseRetryAfterSeconds(resp.headers['retry-after']);
          _onFailure(_now(), retryAfterSeconds: retryAfter);
        }
        debugPrint('YNAV_POI fetch failed status=${resp.statusCode}');
        throw PoiFetchException(
          statusCode: resp.statusCode,
          message: 'status=${resp.statusCode}',
        );
      }

      _onSuccess();
      return resp.body;
    } on PoiFetchException {
      rethrow;
    } catch (e) {
      if (myToken?.cancelled ?? false) {
        // 취소는 정상 동작(더 최신 요청이 이 요청을 대체함) — 로그를 남기지 않는다.
        throw const PoiFetchException(message: 'cancelled');
      }
      _onFailure(_now());
      debugPrint('YNAV_POI fetch failed error=$e');
      throw PoiFetchException(message: e.toString());
    } finally {
      // 태그 없는 호출의 client는 여기서 직접 닫아야 한다(아무도 재사용/취소하지
      // 않으므로). 태그 있는 호출은 다음 같은 태그 요청이 cancel()로 닫거나,
      // 이 인스턴스가 계속 살아있는 한 재사용 가능하도록 열어둔다.
      if (tag == null) client.close();
    }
  }

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
  ///
  /// [tag]를 넘기면 같은 태그의 직전 미완료 요청을 강제로 취소(client.close())한다
  /// — 겹친 요청이 응답만 버려진 채 대역폭·라디오를 계속 점유하는 걸 막는다.
  /// 실패 시(비200·네트워크 예외·서킷 오픈) [PoiFetchException]을 던진다.
  Future<List<Poi>> fetchPois({
    required LatLng center,
    required double radiusMeters,
    required List<PoiType> types,
    String? tag,
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
    final body = await _getJson(uri, tag: tag);

    try {
      final rawList = jsonDecode(body) as List<dynamic>;
      return rawList
          .map((e) => _parseItem(e as Map<String, dynamic>))
          .whereType<Poi>()
          .toList();
    } catch (e) {
      debugPrint('YNAV_POI fetch parse failed error=$e');
      throw PoiFetchException(message: e.toString());
    }
  }

  /// 뷰포트 사각형(south/west/north/east)에 해당하는 특정 타입들의 POI를 가져온다.
  ///
  /// 서버가 정확히 이 사각형 안의 결과만(반경 필터링 없이) 사각형 중심 기준
  /// 거리순으로 정렬해 응답하므로, 호출부는 반경으로 근사할 필요 없이 실제
  /// 화면 뷰포트를 그대로 넘기면 된다.
  ///
  /// [tag]는 [fetchPois]와 동일하게 in-flight 취소용. 실패 시
  /// [PoiFetchException]을 던진다.
  Future<List<Poi>> fetchPoisInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
    required List<PoiType> types,
    String? tag,
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
    final body = await _getJson(uri, tag: tag);

    try {
      final rawList = jsonDecode(body) as List<dynamic>;
      return rawList
          .map((e) => _parseItem(e as Map<String, dynamic>))
          .whereType<Poi>()
          .toList();
    } catch (e) {
      debugPrint('YNAV_POI fetchInBounds parse failed error=$e');
      throw PoiFetchException(message: e.toString());
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

  // `value / step`이 정수에 아주 가까우면(부동소수점 표현 오차, 보통 1e-13
  // 스케일) 그 정수로 취급한다 — 그렇지 않으면 "수학적으로는 정확히 격자선
  // 위"인 값이 이진 부동소수점 표현 탓에 격자선 바로 아래/위로 미끄러져,
  // 거의 같은 두 중심점이 서로 다른 셀로 스냅되는 문제가 생긴다(예: 37.48을
  // 37.5-0.02로 계산하면 37.48/0.02가 1873.9999999999998로 나와 floor가
  // 한 칸 아래로 미끄러짐 — snapBoundsOutward 단위 테스트에서 실측됨).
  static const double _gridSnapTolerance = 1e-6;

  static int _floorGridIndex(double value, double step) {
    final q = value / step;
    final nearest = q.roundToDouble();
    if ((q - nearest).abs() < _gridSnapTolerance) return nearest.toInt();
    return q.floor();
  }

  static int _ceilGridIndex(double value, double step) {
    final q = value / step;
    final nearest = q.roundToDouble();
    if ((q - nearest).abs() < _gridSnapTolerance) return nearest.toInt();
    return q.ceil();
  }

  /// 요청 bbox를 바깥쪽으로(south/west는 floor, north/east는 ceil) "nice" 격자에
  /// 스냅해 반환한다 — [PoiRegionCache.tryGet]이 "저장 영역 ⊇ 요청 영역"일 때만
  /// 적중하는데, 내비 자동추종처럼 bbox가 GPS 위치를 중심으로 매 틱 미세하게
  /// 흔들리면(1m만 움직여도) 캐시가 사실상 항상 미스하기 때문이다.
  ///
  /// 스텝은 [selectForAmbientDisplay]가 쓰는 것과 같은 1-2-5 "nice" 시퀀스
  /// (`_snapCellSizeDeg`)를 재사용해 `span / 4`로 잡는다 — 같은 줌 레벨이면 항상
  /// 같은 스텝이 나와 스냅 격자가 안정적이다. span 대비 과도하게 셀을 키우면 서버
  /// cap(`PoiRegionCache._serverCapHeuristic`)에 걸려 캐싱 자체가 스킵될 수 있어
  /// span/4로 제한한다.
  ///
  /// ⚠️ 호출부는 스냅된 bbox로 네트워크 요청·캐시 put/get을 하되, 화면 표시는
  /// 스냅 bbox가 아니라 실제 뷰포트로 후보를 필터링한 뒤 넘겨야 한다(안 그러면
  /// 화면 밖 POI가 그려진다).
  static ({double south, double west, double north, double east}) snapBoundsOutward({
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    final latSpan = (north - south).abs();
    final lonSpan = (east - west).abs();
    final latStep = _snapCellSizeDeg(latSpan > 0 ? latSpan / 4 : _kCellSizeStepsDeg.first);
    final lonStep = _snapCellSizeDeg(lonSpan > 0 ? lonSpan / 4 : _kCellSizeStepsDeg.first);

    // ⚠️ 부동소수점 특성상 "항상 원본을 포함한다"는 절대(0 오차) 보장은 하지
    // 않는다 — 위 `_gridSnapTolerance` 라운딩이 반대 방향(정수 그대로 곱했을 때
    // 원본보다 극미하게, ~1e-13도 수준으로 작아지는 쪽)으로 미끄러지는 극단
    // 케이스가 이론상 존재한다. 이 값 자체가 network/cache 조회에만 쓰이고
    // 실제 화면 표시 필터링은 항상 원본(unsnapped) bounds로 다시 하므로(§2-5
    // 경고 참고) 이 정도 오차는 기능적으로 무해하다 — 캐시가 그 순간 딱 한 번
    // 미스하고 네트워크로 폴백할 뿐이다.
    final snappedSouth = _floorGridIndex(south, latStep) * latStep;
    final snappedNorth = _ceilGridIndex(north, latStep) * latStep;
    final snappedWest = _floorGridIndex(west, lonStep) * lonStep;
    final snappedEast = _ceilGridIndex(east, lonStep) * lonStep;

    return (
      south: snappedSouth,
      west: snappedWest,
      north: snappedNorth,
      east: snappedEast,
    );
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
  ///
  /// ⚠️ 현재 이 리포 어디에서도 호출되지 않는 죽은 코드다(2026-08-05 S2 조사 —
  /// `grep -rn snapDestination lib/` 결과 정의만 있고 호출부 없음). [fetchPois]가
  /// 이제 실패 시 예외를 던지므로 이 메서드도 그대로 전파하지만, 실제 호출부가
  /// 생기면 try/catch로 감싸 목적지 스냅 실패를 팝업 경로로 흘려보내야 한다.
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

/// 태그별 in-flight 취소용 client 래퍼. `cancel()`이 호출된 뒤 그 client에서
/// 발생하는 예외는 "정상적인 취소"로 간주해 [PoiService._getJson]이 로그를
/// 남기지 않고 조용히 [PoiFetchException]으로 감싼다.
class _CancelToken {
  _CancelToken(this.client);

  final http.Client client;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    client.close();
  }
}

/// [PoiService.fetchPois] / [fetchPoisInBounds]가 실패 시 던지는 예외.
/// 네트워크 실패·비200 응답·서킷 오픈을 "결과 0건"과 명확히 구분하기 위함
/// (`AddressSearchException`과 동일한 패턴, `address_search_service.dart` 참고).
class PoiFetchException implements Exception {
  const PoiFetchException({
    this.statusCode,
    this.circuitOpen = false,
    required this.message,
  });

  /// HTTP 상태코드. 네트워크 예외(타임아웃·연결 끊김 등)나 서킷 오픈이면 null.
  final int? statusCode;

  /// 서킷브레이커가 열려 있어 HTTP 요청 자체를 보내지 않은 경우 true.
  final bool circuitOpen;

  final String message;

  @override
  String toString() {
    final parts = <String>[message];
    if (statusCode != null) parts.add('status=$statusCode');
    if (circuitOpen) parts.add('circuitOpen');
    return 'PoiFetchException(${parts.join(', ')})';
  }
}

/// ambient/search POI 재조회를 시간·거리·타입변경 기준으로 억제하는 소형 디바운스
/// 정책. `main_map_screen`·`nav_screen`이 거의 동일한 디바운스 로직을 각자 복제하지
/// 않도록 공용화했다(`feedback_prefer_simple_reuse` 메모리 참고).
///
/// ⚠️ 반드시 [shouldFetch]가 true를 반환한 그 즉시(네트워크 await 이전)
/// [markStarted]를 호출해야 한다. 응답이 돌아온 뒤(await 이후)에만 커밋하면,
/// 응답이 1개 디바운스 주기 안에 안 돌아올 때 이 상태가 영원히 갱신되지 않아
/// 재시도가 무한 반복되는 결함이 생긴다 — 2026-08-05 S2 조사에서 발견된, 실측
/// 429 폭주(초당 ~10회)의 진짜 원인이 정확히 이 패턴이었다.
class PoiFetchThrottle {
  PoiFetchThrottle({
    required this.minInterval,
    required this.minMoveMeters,
    this.typeChangeMinInterval = const Duration(seconds: 3),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration minInterval;
  final double minMoveMeters;

  /// [types]가 직전 커밋 시점과 달라졌을 때 시간/거리 조건을 우회하되, 완전
  /// 무제한 우회는 금지하고 이 하한만큼은 반드시 기다리게 한다.
  final Duration typeChangeMinInterval;

  final DateTime Function() _now;

  DateTime? _lastAt;
  LatLng? _lastCenter;
  Set<PoiType> _lastTypes = const {};

  /// 새 요청을 시작해도 되는지 판단한다.
  ///
  /// [types]를 넘기면(노출 카테고리가 줌에 따라 바뀌는 화면용) 직전 커밋과
  /// 타입 집합이 다를 때 시간/거리 조건을 건너뛰되 [typeChangeMinInterval]
  /// 하한은 유지한다. [types]를 생략하면(예: 검색 프리페치처럼 항상 전체
  /// 타입을 쓰는 화면) 시간/거리 조건만 본다.
  bool shouldFetch({required LatLng center, Set<PoiType>? types}) {
    final nowTs = _now();
    final lastAt = _lastAt;

    if (types != null) {
      final sameTypes =
          types.length == _lastTypes.length && types.every(_lastTypes.contains);
      if (!sameTypes) {
        return lastAt == null || nowTs.difference(lastAt) >= typeChangeMinInterval;
      }
    }

    final lastCenter = _lastCenter;
    final movedEnough =
        lastCenter == null || PoiService.haversineMeters(lastCenter, center) >= minMoveMeters;
    final staleEnough = lastAt == null || nowTs.difference(lastAt) >= minInterval;
    return movedEnough || staleEnough;
  }

  /// [shouldFetch]가 true를 반환해 요청을 시작하기로 확정한 바로 그 자리에서
  /// (네트워크 await 전에) 호출해야 한다.
  void markStarted({required LatLng center, Set<PoiType>? types}) {
    _lastAt = _now();
    _lastCenter = center;
    if (types != null) _lastTypes = Set<PoiType>.from(types);
  }

  /// 노출 대상 타입이 없어져(줌아웃 등) 이번 틱엔 fetch 자체를 하지 않은 경우
  /// 호출한다. 다음에 타입이 다시 생기면 "타입 변경"으로 간주돼
  /// [typeChangeMinInterval]만 기다리면 된다(매번 [minInterval] 전체를
  /// 기다리지 않아도 됨).
  void clearTypes() {
    _lastTypes = const {};
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
