const _ko = {
  'restaurant': '음식점',
  'cafe': '카페',
  'fast_food': '패스트푸드',
  'fuel': '주유소',
  'parking': '주차장',
  'bank': '은행',
  'hospital': '병원',
  'pharmacy': '약국',
  'convenience': '편의점',
  'supermarket': '마트',
  'hotel': '숙박',
  'attraction': '명소',
  'viewpoint': '전망대',
  'station': '역',
  'bus_stop': '버스정류장',
};

String? poiCategoryKo(Map<String, dynamic> props) {
  final sub = props['subclass'];
  final cls = props['class'];
  final key = (sub is String && sub.isNotEmpty) ? sub : (cls is String && cls.isNotEmpty ? cls : null);
  if (key == null) return null;
  return _ko[key] ?? key;
}
