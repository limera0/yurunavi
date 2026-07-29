import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';

class GasStation {
  final String name;
  final String brand;
  final String address;
  final double lat;
  final double lon;
  final double distanceM;
  final int? price;         // 휘발유(B027) 가격, 원
  final int? premiumPrice;  // 고급휘발유(B034) 가격, 원

  const GasStation({
    required this.name,
    required this.brand,
    required this.address,
    required this.lat,
    required this.lon,
    required this.distanceM,
    this.price,
    this.premiumPrice,
  });

  factory GasStation.fromJson(Map<String, dynamic> j) => GasStation(
    name: j['name'] as String? ?? '',
    brand: j['brand'] as String? ?? '',
    address: j['address'] as String? ?? '',
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    distanceM: (j['distance_m'] as num).toDouble(),
    price: j['price'] as int?,
    premiumPrice: j['premium_price'] as int?,
  );
}

class GasStationService {
  static String get _baseUrl => '${AppConfig.instance.naviBaseUrl}/gasstations/nearby';

  static Future<List<GasStation>> fetchNearby({
    required double lat,
    required double lon,
    String fuel = 'B027',
    double radiusM = 5000,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'fuel': fuel,
      'radius_m': radiusM.toStringAsFixed(0),
    });
    try {
      final resp = await http
          .get(uri, headers: {'X-Api-Key': AppConfig.instance.naviApiKey})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        debugPrint('[GasStation] HTTP ${resp.statusCode}');
        return [];
      }
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.map((e) => GasStation.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[GasStation] 오류: $e');
      return [];
    }
  }
}
