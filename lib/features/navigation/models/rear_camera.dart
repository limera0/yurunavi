import 'dart:convert';

import 'package:flutter/services.dart';

/// 후면단속카메라 1건 (assets/data/rear_cameras.json 레코드).
///
/// 오토바이는 앞번호판이 없어 전방카메라엔 잡히지 않고 후면단속카메라에만
/// 잡힌다 — 이 앱은 후면단속카메라만 선별해 안내한다(18번 기능).
class RearCamera {
  final double lat;
  final double lng;
  final int speedKmh; // 해당 구간 제한속도
  final int postZoneM; // 카메라 통과 후 단속 사후구간 범위(기본 90m 다수)

  const RearCamera({
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.postZoneM,
  });

  factory RearCamera.fromJson(Map<String, dynamic> json) => RearCamera(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        speedKmh: (json['speedKmh'] as num).toInt(),
        postZoneM: (json['postZoneM'] as num).toInt(),
      );

  /// 앱/내비 시작 시 1회 asset을 읽어 전체 카메라 목록을 로드한다
  /// (GuidanceProfile.load / VoicePackService.load와 동일한 정적 로더 패턴).
  static Future<List<RearCamera>> loadAll(
      [String assetPath = 'assets/data/rear_cameras.json']) async {
    final raw = await rootBundle.loadString(assetPath);
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => RearCamera.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
