import 'package:latlong2/latlong.dart';

/// V-World 지오코더(백엔드 `/geocode/search` 프록시) 검색 결과 1건. `Poi`와는 완전히
/// 별개 모델 — `PoiType`에 "주소" 카테고리를 추가하지 않고(카테고리 색상/줌레벨/상시표시
/// 우선순위 로직에 영향 없이) 도로명주소 검색을 얹기 위함.
class AddressResult {
  final String address;
  final LatLng location;
  const AddressResult({required this.address, required this.location});
}
