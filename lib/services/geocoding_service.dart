import 'package:geocoding/geocoding.dart';

/// 좌표 → 사람이 읽을 수 있는 주소 문자열 역지오코딩 서비스.
class GeocodingService {
  /// `Placemark` 조회 공통 로직 — [reverseGeocode]/[reverseGeocodeCoarse]가
  /// 공유한다. 실패/타임아웃 시 null(호출부가 각자 폴백 처리).
  Future<Placemark?> _fetchPlacemark(double lat, double lng) async {
    try {
      // `Geocoding()` 생성자 자체가 플랫폼 구현체가 없으면 동기적으로 throw할 수
      // 있으므로(예: 순수 `flutter test` 환경) try 블록 안에서 지연 생성한다.
      final geocoding = Geocoding();
      final placemarks = await geocoding
          .placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 4));
      if (placemarks.isEmpty) return null;
      return placemarks.first;
    } catch (_) {
      return null;
    }
  }

  /// Reverse-geocodes a coordinate to a human-readable address string.
  /// Returns null on any failure/timeout (some AOSP-based devices have no
  /// native Geocoder backend at all) — callers must handle null gracefully.
  Future<String?> reverseGeocode(double lat, double lng) async {
    final p = await _fetchPlacemark(lat, lng);
    if (p == null) return null;

    // Coarse-to-fine 순서로 조합 (예: "경기도 평택시 서정동").
    final parts = <String>[
      if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
        p.administrativeArea!,
      if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
      if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
      if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty) p.thoroughfare!,
      if (p.subThoroughfare != null && p.subThoroughfare!.isNotEmpty)
        p.subThoroughfare!,
    ];

    // 연속 중복 제거 (일부 기기에서 locality/subLocality가 같은 값으로 겹치는 경우 방지).
    final deduped = <String>[];
    for (final part in parts) {
      if (deduped.isEmpty || deduped.last != part) {
        deduped.add(part);
      }
    }

    if (deduped.isEmpty) {
      return (p.name != null && p.name!.isNotEmpty) ? p.name : null;
    }
    return deduped.join(' ');
  }

  /// 시/군/구 수준만 반환하는 저해상도 역지오코딩 (예: "경기도 평택시").
  /// 내비 하단 카드의 "현위치" 표시처럼 도로명까지 필요 없는 자리에서 쓴다 —
  /// [reverseGeocode]와 달리 subLocality/thoroughfare는 포함하지 않는다.
  /// 호출측에서 빈번한 GPS 틱마다 부르지 않도록 디바운스는 각자 책임진다
  /// (기기 내장 geocoder라 네트워크 요청은 아니지만 기기 API 호출 폭주는
  /// 마찬가지로 피해야 함).
  Future<String?> reverseGeocodeCoarse(double lat, double lng) async {
    final p = await _fetchPlacemark(lat, lng);
    if (p == null) return null;

    final parts = <String>[
      if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
        p.administrativeArea!,
      if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
    ];

    final deduped = <String>[];
    for (final part in parts) {
      if (deduped.isEmpty || deduped.last != part) {
        deduped.add(part);
      }
    }

    return deduped.isEmpty ? null : deduped.join(' ');
  }
}
