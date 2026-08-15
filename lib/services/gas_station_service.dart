import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' show pi, sin, cos, sqrt, asin;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
    distanceM: (j['distance_m'] as num?)?.toDouble() ?? 0.0,
    price: j['price'] as int?,
    premiumPrice: j['premium_price'] as int?,
  );
}

class GasStationService {
  static String get _nearbyUrl => '${AppConfig.instance.naviBaseUrl}/gasstations/nearby';

  static const String _localFileName = 'gasstations.json';
  static const Duration _freshnessDuration = Duration(hours: 25);

  static Future<File> _localFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_localFileName');
  }

  static Future<bool> _isLocalDataFresh() async {
    final file = await _localFile();
    if (!await file.exists()) return false;
    final age = DateTime.now().difference(await file.lastModified());
    return age < _freshnessDuration;
  }

  static Future<bool> _downloadBulk() async {
    try {
      final uri = Uri.parse('${AppConfig.instance.naviBaseUrl}/gasstations/bulk');
      final resp = await http
          .get(uri, headers: {'X-Api-Key': AppConfig.instance.naviApiKey})
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return false;
      final file = await _localFile();
      await file.writeAsBytes(resp.bodyBytes);
      return true;
    } catch (e) {
      debugPrint('YNAV_GASSTATION_ERR bulk download failed: $e');
      return false;
    }
  }

  static Future<List<GasStation>?> _loadFromLocal({
    required double lat,
    required double lon,
    required String fuel,
    required double radiusM,
  }) async {
    final file = await _localFile();
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      final results = <(int, double, GasStation)>[];
      for (final e in raw) {
        final m = e as Map<String, dynamic>;
        final sLat = (m['lat'] as num).toDouble();
        final sLon = (m['lon'] as num).toDouble();
        final dist = _haversineM(lat, lon, sLat, sLon);
        if (dist > radiusM) continue;
        final gasoline = m['price'] as int?;
        final premium = m['premium_price'] as int?;
        if (fuel == 'B034' && premium == null) continue;
        final sortPrice = fuel == 'B034' ? (premium ?? 999999) : (gasoline ?? 999999);
        results.add((sortPrice, dist, GasStation(
          name: m['name'] as String? ?? '',
          brand: m['brand'] as String? ?? '',
          address: m['address'] as String? ?? '',
          lat: sLat,
          lon: sLon,
          distanceM: dist,
          price: gasoline,
          premiumPrice: premium,
        )));
      }
      results.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
      return results.take(20).map((r) => r.$3).toList();
    } catch (e) {
      debugPrint('YNAV_GASSTATION_ERR local load failed: $e');
      return null;
    }
  }

  static double _haversineM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(sqrt(a));
  }

  static Future<List<GasStation>> fetchNearby({
    required double lat,
    required double lon,
    String fuel = 'B027',
    double radiusM = 5000,
  }) async {
    // 1. 신선한 로컬 파일 있으면 로컬에서 필터링해 반환
    if (await _isLocalDataFresh()) {
      final local = await _loadFromLocal(lat: lat, lon: lon, fuel: fuel, radiusM: radiusM);
      if (local != null) return local;
    }

    // 2. 로컬 파일이 없거나 만료됨 — bulk 다운로드 시도
    final downloaded = await _downloadBulk();
    if (downloaded) {
      final local = await _loadFromLocal(lat: lat, lon: lon, fuel: fuel, radiusM: radiusM);
      if (local != null) return local;
    }

    // 3. 다운로드 실패 + 파일 있으면 stale 파일로 graceful degradation
    final file = await _localFile();
    if (await file.exists()) {
      final local = await _loadFromLocal(lat: lat, lon: lon, fuel: fuel, radiusM: radiusM);
      if (local != null) return local;
    }

    // 4. 로컬 파일 없음 — 기존 Opinet API 방식 폴백
    final uri = Uri.parse(_nearbyUrl).replace(queryParameters: {
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
        debugPrint('YNAV_GASSTATION_ERR status=${resp.statusCode}');
        return [];
      }
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.map((e) => GasStation.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('YNAV_GASSTATION_ERR error=$e');
      return [];
    }
  }
}
