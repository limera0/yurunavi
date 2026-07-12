import 'package:latlong2/latlong.dart';

enum PoiType {
  cafe,
  convenienceStore,
  gasStation,
  supermarket,
  restaurant,
}

extension PoiTypeX on PoiType {
  String get label {
    switch (this) {
      case PoiType.cafe:
        return '카페';
      case PoiType.convenienceStore:
        return '편의점';
      case PoiType.gasStation:
        return '주유소';
      case PoiType.supermarket:
        return '마트';
      case PoiType.restaurant:
        return '식당';
    }
  }

  /// 슬라이드 7 가이드: 카페=주황, 편의점=파랑, 주유소=빨강, 마트=보라, 식당=노랑
  int get colorValue {
    switch (this) {
      case PoiType.cafe:
        return 0xFFFF7700;
      case PoiType.convenienceStore:
        return 0xFF2196F3;
      case PoiType.gasStation:
        return 0xFFE53935;
      case PoiType.supermarket:
        return 0xFF8E24AA;
      case PoiType.restaurant:
        return 0xFFFFB300;
    }
  }
}

class Poi {
  final String id;
  final String name;
  final PoiType type;
  final LatLng location;
  final double? rating;
  final String? address;

  const Poi({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    this.rating,
    this.address,
  });
}
