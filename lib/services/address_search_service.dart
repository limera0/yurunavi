import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/config/app_config.dart';

import '../models/address_result.dart';

/// 자체 호스팅 백엔드(navi.westinx.com)의 `/geocode/search` 엔드포인트를 통해
/// 도로명주소/지번주소 텍스트를 좌표로 변환하는 서비스. 서버가 V-World 지오코더를
/// 서버사이드에서 프록시하므로 클라이언트는 API 키를 다루지 않는다.
///
/// [PoiService.fetchPois]는 네트워크 실패와 "결과 0건"을 구분하지 못해(둘 다 빈
/// 리스트 반환) 실기기 디버깅이 어려웠던 기지 결함(2026-07-13 확인)이 있다. 이
/// 서비스는 그 결함을 반복하지 않도록 실패 시 빈 리스트 대신 [AddressSearchException]을
/// 던져 호출부가 "검색 결과 없음"과 "오류 발생"을 구분해 서로 다른 안내를 보여줄 수
/// 있게 한다.
class AddressSearchService {
  static String get _baseUrl => '${AppConfig.instance.naviBaseUrl}/geocode/search';

  static final Map<String, List<AddressResult>> _cache = {};

  Future<List<AddressResult>> search(String query) async {
    final trimmed = query.trim();
    // 빈 질의는 서버도 곧바로 빈 배열을 반환하므로, 왕복 없이 바로 반환한다.
    if (trimmed.isEmpty) return [];

    if (_cache.containsKey(trimmed)) return _cache[trimmed]!;

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {'q': trimmed});

    try {
      final resp = await http
          .get(uri, headers: {'X-Api-Key': AppConfig.instance.naviApiKey})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        debugPrint('YNAV_ADDR search failed status=${resp.statusCode}');
        throw AddressSearchException('status=${resp.statusCode}');
      }

      final rawList = jsonDecode(resp.body) as List<dynamic>;
      final result = rawList
          .map((e) => _parseItem(e as Map<String, dynamic>))
          .whereType<AddressResult>()
          .toList();
      _cache[trimmed] = result;
      return result;
    } on AddressSearchException {
      rethrow;
    } catch (e) {
      debugPrint('YNAV_ADDR search failed error=$e');
      throw AddressSearchException(e.toString());
    }
  }

  AddressResult? _parseItem(Map<String, dynamic> item) {
    final address = item['address'] as String?;
    final lat = item['lat'];
    final lon = item['lon'];
    if (address == null || lat == null || lon == null) return null;

    return AddressResult(
      address: address,
      location: LatLng((lat as num).toDouble(), (lon as num).toDouble()),
    );
  }
}

class AddressSearchException implements Exception {
  final String message;
  const AddressSearchException(this.message);

  @override
  String toString() => 'AddressSearchException: $message';
}
